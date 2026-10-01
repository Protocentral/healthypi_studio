import 'dart:typed_data';

import '../smp_serial_client.dart';
import 'firmware_updater.dart';

/// MCUboot serial recovery: the floor beneath a failed update.
///
/// A port of healthypi-6-fw `tools/healthypi/src/healthypi/fw/recovery.py`.
/// Overwrite-only MCUboot has no revert, so a unit whose M7 will not boot is
/// rescued from the bootloader, which exposes its own SMP img group on a
/// single CDC port ("HealthyPi 6 Recovery", same VID/PID as the application).
///
/// Recovery writes the **M7 only**, straight to slot 0. It bypasses downgrade
/// prevention, and the M4 is untouched: bring it into line afterwards with a
/// normal update from the recovered application.
class FirmwareRecovery {
  FirmwareRecovery({
    required this.openClient,
    required this.applicationPorts,
    this.log,
    this.onProgress,
    this.appReturn = const Duration(seconds: 45),
    this.m4Bind = const Duration(seconds: 15),
    this.poll = const Duration(seconds: 2),
  });

  /// Open an SMP client on [port], or null if it cannot be opened.
  final Future<SmpSerialClient?> Function(String port) openClient;

  /// Ports that could be the recovered application's control port, most
  /// likely first. Called repeatedly while waiting for it to enumerate.
  final Future<List<String>> Function() applicationPorts;

  final void Function(String line)? log;
  final void Function(int sent, int total)? onProgress;

  /// How long the application gets to boot and enumerate after the reset.
  final Duration appReturn;

  /// How long to wait for the M4 to bind IPC and report its version.
  final Duration m4Bind;
  final Duration poll;

  void _log(String line) => log?.call(line);

  /// Ask a running application to reboot into serial recovery. Returns null
  /// once it is rebooting, or why it will not.
  static Future<String?> enterRecovery(SmpSerialClient client) async {
    final state = await client.recoveryState();
    if (!state.ok) {
      return 'Recovery state read failed: ${state.failure!.label}. Only the '
          'signed build supports recovery.';
    }
    if (state.value!.av != true) {
      return 'This firmware cannot enter recovery: it was built without a '
          'bootloader, so there is nothing to reboot into.';
    }
    final r = await client.enterRecovery();
    // The device may reset before its reply gets out; no reply is expected
    // as often as a reply.
    if (!r.ok && r.failure!.rc != null) {
      return 'Enter recovery failed: ${r.failure!.label}';
    }
    return null;
  }

  /// Write [m7] to the unit in recovery on [recoveryPort], reset it, then find
  /// the application and check it runs [m7Version]. [m4Version] (from the
  /// bundle, if any) is only compared and reported.
  Future<RecoveryOutcome> recover({
    required String recoveryPort,
    required Uint8List m7,
    required String m7Version,
    String? m4Version,
  }) async {
    final c = await openClient(recoveryPort);
    if (c == null) {
      throw UpdateException('Could not open $recoveryPort.');
    }
    try {
      // The application answers group 64; MCUboot's recovery does not. USB
      // ids cannot tell them apart, so ask the protocol before writing.
      final probe = await c.deviceInfo(timeout: const Duration(seconds: 3));
      if (probe.ok) {
        throw UpdateException('$recoveryPort is the running application, not '
            'the bootloader. Use Install firmware to update normally, or '
            'Enter recovery mode first.');
      }
      _log('Recovery: writing M7 $m7Version (${m7.length} B) to slot 0');
      final err = await c.imageUpload(m7, onProgress: onProgress);
      if (err != null) {
        throw UpdateException('Recovery upload failed: $err. The unit is '
            'still in recovery; retry.');
      }
      await c.osReset();
    } finally {
      c.close();
    }
    _log('  reset sent; waiting for the application to come back…');
    return _confirm(m7Version, m4Version);
  }

  Future<RecoveryOutcome> _confirm(String wantM7, String? wantM4) async {
    final deadline = DateTime.now().add(appReturn);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(poll);
      for (final port in await applicationPorts()) {
        final c = await openClient(port);
        if (c == null) continue;
        try {
          if (!(await c.deviceInfo(timeout: const Duration(seconds: 2))).ok) {
            continue;
          }
          var v = (await c.fwVersions()).value;
          // The M7 learns the M4's version over IPC, which binds ~7-10 s
          // after boot; judge the M4 only once it has had that long.
          final m4Deadline = DateTime.now().add(m4Bind);
          while ((v?.m4fw ?? '').isEmpty && DateTime.now().isBefore(m4Deadline)) {
            await Future<void>.delayed(poll);
            v = (await c.fwVersions()).value;
          }
          final m7 = v?.m7fw ?? '';
          final m4 = v?.m4fw ?? '';
          _log('  application is back on $port: '
              'M7 ${m7.isEmpty ? '?' : m7}, M4 ${m4.isEmpty ? '?' : m4}');
          if (!sameVersion(m7, wantM7)) {
            throw UpdateException('Recovery wrote M7 $wantM7, but the '
                'application reports ${m7.isEmpty ? 'no version' : m7}. The '
                'image may not have been accepted; enter recovery and retry.');
          }
          final m4Behind = wantM4 != null && !sameVersion(m4, wantM4);
          if (m4Behind) {
            _log('  The M4 is not at $wantM4 — recovery writes the M7 only. '
                'Install the bundle again to bring the M4 into line.');
          }
          return RecoveryOutcome(port: port, m7: m7, m4: m4, m4Behind: m4Behind);
        } finally {
          c.close();
        }
      }
    }
    throw UpdateException('The image was written, but no application answered '
        'within ${appReturn.inSeconds} s. If the unit came back as '
        '"HealthyPi 6 Recovery", MCUboot did not accept the image; retry.');
  }
}

class RecoveryOutcome {
  const RecoveryOutcome({
    required this.port,
    required this.m7,
    required this.m4,
    required this.m4Behind,
  });

  /// The recovered application's control port.
  final String port;
  final String m7;
  final String m4;

  /// The M4 is not at the bundle's version; a normal update fixes it.
  final bool m4Behind;
}
