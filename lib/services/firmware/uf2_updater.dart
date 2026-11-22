import '../smp_serial_client.dart';
import 'firmware_updater.dart';
import 'picotool.dart';

/// Firmware update for a HealthyPi Core: no MCUboot, so no SMP image upload.
///
///  1. `reset_bootsel` (group 64, 0xB0) reboots the RP2350 into its ROM
///     bootloader (USB 2E8A:000F "RP2350 Boot").
///  2. Studio lets go of the serial port and waits for picotool to see the
///     board in BOOTSEL.
///  3. `picotool load -x file.uf2` writes the image over PICOBOOT and runs it.
///     Copying to the BOOTSEL drive is avoided on purpose: on macOS it
///     sometimes never mounts.
///  4. Studio waits for the Core to enumerate again, reconnects, and reads
///     `fw_versions`.
///
/// Every board-facing step is injected, so the control flow is tested without
/// hardware.
class Uf2Updater {
  Uf2Updater({
    required this.picotool,
    required this.resetBootsel,
    required this.detach,
    required this.reattach,
    required this.readVersion,
    this.log,
    this.onProgress,
    this.bootromWait = const Duration(seconds: 20),
    this.appReturn = const Duration(seconds: 30),
    this.poll = const Duration(seconds: 1),
  });

  /// Null when picotool could not be found.
  final Picotool? picotool;

  /// Send `reset_bootsel`; returns the failure, or null.
  final Future<HpiFailure?> Function() resetBootsel;

  /// Close Studio's hold on the Core's port, so nothing re-opens it during
  /// the update.
  final Future<void> Function() detach;

  /// Find the Core again and reconnect to it; true once it answers.
  final Future<bool> Function() reattach;

  /// The running firmware version, as `fw_versions` reports it.
  final Future<String?> Function() readVersion;

  final void Function(String line)? log;
  final void Function(UpdateProgress progress)? onProgress;

  final Duration bootromWait;
  final Duration appReturn;
  final Duration poll;

  /// What [missingPicotool] says when picotool is absent; set by the caller
  /// from [PicotoolLocator.missingMessage].
  String missingPicotool = 'picotool was not found.';

  void _log(String line) => log?.call(line);
  void _stage(UpdateStage s) => onProgress?.call(UpdateProgress(s, 0, 0));

  /// Install [uf2Path] on the connected Core. When [alreadyInBootsel] (a board
  /// held in BOOTSEL by hand, or left there by a failed update), skip the
  /// reset and load straight away. Throws [UpdateException] with what state
  /// the board is in when it cannot finish.
  Future<UpdateOutcome> install(String uf2Path,
      {String? versionBefore, bool alreadyInBootsel = false}) async {
    _stage(UpdateStage.checking);
    final tool = picotool;
    // Before touching the board: without picotool, a board sent to BOOTSEL
    // would be stranded there.
    if (tool == null) throw UpdateException(missingPicotool);
    _log('picotool: ${tool.executable}');

    if (!alreadyInBootsel) {
      _stage(UpdateStage.resetting);
      _log('Rebooting into the RP2350 boot ROM (reset_bootsel)…');
      final f = await resetBootsel();
      if (f != null) {
        throw UpdateException('The Core refused reset_bootsel: ${f.label}. '
            'Nothing was changed.');
      }
      await detach();
    }

    _stage(UpdateStage.waitingBootrom);
    if (!await _until(tool.bootromPresent, bootromWait)) {
      throw UpdateException(alreadyInBootsel
          ? 'No RP2350 in BOOTSEL was found. Hold BOOTSEL while plugging the '
              'board in, then try again.'
          : 'The Core did not appear in BOOTSEL within '
              '${bootromWait.inSeconds} s. If it is in BOOTSEL now (a drive '
              'named RP2350), install again with "already in BOOTSEL".');
    }
    _log('Board in BOOTSEL.');

    _stage(UpdateStage.loadingUf2);
    _log('picotool load -x $uf2Path');
    final why = await tool.loadAndRun(uf2Path);
    if (why != null) {
      throw UpdateException('picotool could not load the image: $why. The '
          'board is still in BOOTSEL; install again.');
    }
    _log('Loaded; the Core is restarting.');

    _stage(UpdateStage.verifying);
    if (!await _until(reattach, appReturn)) {
      throw UpdateException('The image was written, but the Core did not come '
          'back within ${appReturn.inSeconds} s. Unplug and replug it; if it '
          'still does not enumerate, it is not running the new image.');
    }
    final after = await readVersion();
    _log('Running ${after ?? '— (fw_versions did not answer)'}'
        '${versionBefore == null ? '' : ' (was $versionBefore)'}');
    _stage(UpdateStage.done);
    return UpdateOutcome(
      ok: after != null,
      applied: const ['uf2'],
      skipped: const [],
      versionsAfter: {'fw': ?after},
    );
  }

  Future<bool> _until(Future<bool> Function() check, Duration budget) async {
    final deadline = DateTime.now().add(budget);
    while (true) {
      if (await check()) return true;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(poll);
    }
  }
}
