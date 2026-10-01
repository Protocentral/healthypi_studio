import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:mcumgr_dart/mcumgr_dart.dart';

import '../smp_serial_client.dart';
import 'bundle.dart';

/// Applies a firmware bundle (zip) to a HealthyPi 6 over its control link.
///
/// A port of the reference updater, healthypi-6-fw
/// `tools/healthypi/src/healthypi/fw/update.py` (`apply_bundle`). The device
/// facts it depends on:
///
///  * **M7**: single-image, overwrite-only MCUboot with downgrade prevention.
///    Upload to image 0, then mark it pending by its MCUboot hash (the SHA-256
///    TLV, never the file's SHA-256). There is no trial boot and no revert.
///  * **M4**: not an MCUboot image. It goes through group 64 `m4fw_*`, staged
///    in QSPI and written to bank 2 by the M7 at commit, after the M7 checks
///    the digest and ECDSA signature.
///  * Installing an M7 delays its boot (MCUboot copies the image first), so it
///    misses the M4's one-shot IPC bind and comes up with no vitals. A second
///    reset, with nothing left to copy, pairs the cores again.
class FirmwareUpdater {
  FirmwareUpdater({
    required this.client,
    required this.resetAndReconnect,
    this.log,
    this.onProgress,
  });

  /// The control client. Read on every use: a reset may reopen it.
  final SmpSerialClient Function() client;

  /// Reset the device and wait until the control link answers again. False
  /// if it did not come back.
  final Future<bool> Function() resetAndReconnect;

  final void Function(String line)? log;
  final void Function(UpdateProgress progress)? onProgress;

  // enum hpi_m4fw_state (app_m7/src/services/m4_update_service.h)
  static const int m4Receiving = 1;
  static const int m4Committed = 3;
  static const int m4Failed = 4;

  /// Bytes an `m4fw_chunk` request spends on framing before any payload.
  static const int m4ChunkOverhead = 48;

  void _log(String line) => log?.call(line);

  void _stage(UpdateStage stage, [int sent = 0, int total = 0]) =>
      onProgress?.call(UpdateProgress(stage, sent, total));

  /// Apply [bundle]. Images already at the bundle's version are skipped unless
  /// [force]. Throws [UpdateException] where continuing would be unsafe or
  /// misleading; the message says what state the device is in.
  Future<UpdateOutcome> applyBundle(FirmwareBundle bundle,
      {bool force = false}) async {
    _stage(UpdateStage.checking);
    _log('Bundle ${bundle.release} (signed: ${bundle.signer.label})');
    final installed = await _versions();
    for (final name in FirmwareBundle.applyOrder) {
      final img = bundle.images[name];
      if (img != null) {
        _log('  $name: installed ${installed[name] ?? '?'}, bundle ${img.version}');
      }
    }

    final wanted = [
      for (final n in FirmwareBundle.applyOrder)
        if (bundle.images.containsKey(n)) n,
    ];
    await _checkSupport(wanted);

    final plan = <String>[];
    final skipped = <String>[];
    for (final name in wanted) {
      final img = bundle.images[name]!;
      if (name == 'm7') {
        final refusal = m7Downgrade(installed['m7'] ?? '', img.version);
        if (refusal != null) throw UpdateException(refusal);
      }
      if (name == 'esp32c6') {
        _log('  esp32c6: skipped — Studio cannot update the Wi-Fi co-processor');
        skipped.add(name);
        continue;
      }
      if (!force && sameVersion(installed[name] ?? '', img.version)) {
        _log('  $name: already at ${img.version} — skipped');
        skipped.add(name);
        continue;
      }
      plan.add(name);
    }
    if (plan.isEmpty) {
      _stage(UpdateStage.done);
      return UpdateOutcome(
          ok: true, applied: const [], skipped: skipped, versionsAfter: installed);
    }
    _log('Plan: ${plan.join(' → ')}');

    final stop = await client().streamStop();
    if (!stop.ok) _log('  stream_stop refused (${stop.failure!.label}) — continuing');

    Uint8List? m7Hash;
    for (final name in plan) {
      final img = bundle.images[name]!;
      if (name == 'm4') await _applyM4(img.data, img.signature);
      if (name == 'm7') m7Hash = await _applyM7(img.data);
    }

    final after = await _resetAndVerify(
      m7Installed: plan.contains('m7'),
      m4Expected: plan.contains('m4')
          ? bundle.images['m4']!.version
          : (installed['m4'] ?? ''),
    );

    var ok = true;
    for (final name in plan) {
      final want = bundle.images[name]!.version;
      final got = after[name] ?? '';
      final match = sameVersion(got, want);
      ok &= match;
      _log('  $name: ${got.isEmpty ? '?' : got} '
          '${match ? 'OK' : '— expected $want'}');
    }
    if (m7Hash != null) ok &= await _m7Running(m7Hash);
    _stage(ok ? UpdateStage.done : UpdateStage.failed);
    return UpdateOutcome(
        ok: ok, applied: plan, skipped: skipped, versionsAfter: after);
  }

  /// Install a single raw M7 image (a development build outside a bundle).
  /// No manifest signature is checked here; MCUboot still verifies the image
  /// signature at boot.
  Future<UpdateOutcome> applyM7Image(Uint8List image) async {
    _stage(UpdateStage.checking);
    final info = _imageInfo(image);
    final installed = await _versions();
    await _checkSupport(const ['m7']);
    final refusal = m7Downgrade(installed['m7'] ?? '', info.version.toString());
    if (refusal != null) throw UpdateException(refusal);
    await client().streamStop();
    final hash = await _applyM7(image);
    final after = await _resetAndVerify(
        m7Installed: true, m4Expected: installed['m4'] ?? '');
    final ok = await _m7Running(hash);
    _stage(ok ? UpdateStage.done : UpdateStage.failed);
    return UpdateOutcome(
        ok: ok, applied: const ['m7'], skipped: const [], versionsAfter: after);
  }

  // ---- steps ---------------------------------------------------------------

  Future<Map<String, String>> _versions() async {
    final r = await client().fwVersions();
    final v = r.value;
    if (v == null) {
      throw UpdateException('Could not read firmware versions: ${r.failure!.label}');
    }
    return {'m7': v.m7fw ?? '', 'm4': v.m4fw ?? '', 'esp32c6': v.espfw ?? ''};
  }

  /// A development build has no bootloader, no img group and no M4-update
  /// service. Say that, rather than comparing versions that cannot change.
  Future<void> _checkSupport(List<String> wanted) async {
    final missing = <String>[];
    if (wanted.contains('m7') && await client().imageStates() == null) {
      missing.add('M7: no MCUboot image group (no bootloader)');
    }
    if (wanted.contains('m4') && !(await client().m4fwStatus()).ok) {
      missing.add('M4: no M4-update service');
    }
    if (missing.isEmpty) return;
    throw UpdateException(
        'This unit cannot be updated over USB — it is running a development '
        'build:\n  ${missing.join('\n  ')}\n'
        'Program a signed factory image over SWD first; after that, updates '
        'work over USB.');
  }

  McuImageInfo _imageInfo(Uint8List image) {
    try {
      final info = McuImageInfo.parse(image);
      if (info.sha256 == null) throw const FormatException('no SHA-256 TLV');
      if (!info.verifyHash(image)) {
        throw const FormatException('its SHA-256 TLV does not match its content');
      }
      return info;
    } on FormatException catch (e) {
      throw UpdateException('The M7 image is not a usable imgtool-signed '
          'MCUboot image (${e.message}).');
    }
  }

  Future<Uint8List> _applyM7(Uint8List image) async {
    final info = _imageInfo(image);
    final hash = info.hash;
    final before = await client().imageStates() ?? const <ImageSlot>[];
    if (_slotHash(before, 0) case final h? when _same(h, hash)) {
      _log('  M7: the device already runs this exact image; MCUboot will '
          'decline it and nothing will change');
    }

    _log('M7: uploading ${info.version}, ${image.length} B');
    _stage(UpdateStage.uploadingM7, 0, image.length);
    final err = await client().imageUpload(image,
        onProgress: (sent, total) =>
            _stage(UpdateStage.uploadingM7, sent, total));
    if (err != null) {
      throw UpdateException('M7 upload failed: $err. Nothing was installed; '
          'the device still runs its old firmware. Re-run the update.');
    }

    _stage(UpdateStage.markingM7);
    final staged = await client().imageStates() ?? const <ImageSlot>[];
    if (_slotHash(staged, 1) case final h? when !_same(h, hash)) {
      throw UpdateException('M7: the staged image does not match the one '
          'uploaded. Nothing was installed; re-run the update.');
    }
    final mark = await client().imageMarkPending(hash);
    if (mark != null) {
      throw UpdateException('M7: marking the uploaded image for install failed '
          '($mark). It is in slot 1 but not pending, so MCUboot will ignore it '
          'and the device keeps its old firmware. Re-run the update.');
    }
    _log('  M7: marked pending — MCUboot installs it on the next boot');
    return hash;
  }

  Future<void> _applyM4(Uint8List image, Uint8List? signature) async {
    final c = client();
    final status = await c.m4fwStatus();
    final st = status.value;
    if (st == null) {
      throw UpdateException('M4 status failed: ${status.failure!.label}');
    }
    if (st.sig == true && signature == null) {
      throw const UpdateException('M4: this device requires a signed image, '
          'and the bundle carries no signature for it.');
    }
    if (st.st == m4Receiving || st.st == m4Failed) {
      // An interrupted run leaves the service here, and begin then answers
      // BUSY until something clears it. Nothing else writes the M4 staging
      // area, so a stale upload is ours to discard.
      _log('  M4: discarding a stale upload (state ${st.st}, '
          '${st.rx}/${st.len} B)');
      final abort = await c.m4fwAbort();
      if (!abort.ok) {
        throw UpdateException(
            'M4: abort of the stale upload failed: ${abort.failure!.label}');
      }
    } else if (st.st == m4Committed) {
      throw const UpdateException('M4: a committed image is waiting for a '
          'reset. Reboot the device, then run the update again.');
    }

    final digest = crypto.sha256.convert(image).bytes;
    _log('M4: uploading ${image.length} B${signature == null ? '' : ' (signed)'}');
    final begin =
        await c.m4fwBegin(len: image.length, sha: digest, sig: signature);
    if (!begin.ok) {
      throw UpdateException('M4 begin failed: ${begin.failure!.label}');
    }

    final chunk = c.uploadChunkSize;
    var off = 0;
    _stage(UpdateStage.uploadingM4, 0, image.length);
    while (off < image.length) {
      final end = off + chunk < image.length ? off + chunk : image.length;
      final r = await c.m4fwChunk(off, Uint8List.sublistView(image, off, end));
      final next = r.value?.off;
      if (next == null) {
        throw UpdateException('M4 chunk at +$off failed: '
            '${r.failure?.label ?? 'no offset in reply'}. Bank 2 is untouched; '
            're-run the update.');
      }
      if (next != end) {
        throw UpdateException('M4: device expects +$next after sending '
            '+$off..$end. Bank 2 is untouched; re-run the update.');
      }
      off = next;
      _stage(UpdateStage.uploadingM4, off, image.length);
    }

    _stage(UpdateStage.committingM4);
    _log('  M4: commit (digest, signature, erase and write bank 2)…');
    final commit = await c.m4fwCommit();
    if (!commit.ok) {
      throw UpdateException('M4 commit refused: ${commit.failure!.label}. '
          'Bank 2 was not modified; the M4 still runs its old image.');
    }
    _log('  M4: committed');
  }

  Future<Map<String, String>> _resetAndVerify({
    required bool m7Installed,
    required String m4Expected,
  }) async {
    _stage(UpdateStage.resetting);
    _log('Resetting…');
    if (!await resetAndReconnect()) {
      throw const UpdateException('The device did not come back after the '
          'reset. Reconnect it, then check the versions on the Device screen.');
    }
    var after = await _versions();

    // The M7 install delays its boot past the M4's one-shot IPC bind. An empty
    // M4 version is that unbound state; a second reset pairs the cores.
    if (m7Installed) {
      final m4 = after['m4'] ?? '';
      if (m4.isEmpty || (m4Expected.isNotEmpty && !sameVersion(m4, m4Expected))) {
        _log('M4 did not bind after the M7 install (expected). Resetting once '
            'more to pair the cores…');
        _stage(UpdateStage.resetting);
        if (!await resetAndReconnect()) {
          throw const UpdateException('The device did not come back after the '
              'second reset. Reconnect it, then check the versions.');
        }
        after = await _versions();
      }
    }
    _stage(UpdateStage.verifying);
    return after;
  }

  /// A matching version string does not prove an install; the slot-0 hash
  /// does.
  Future<bool> _m7Running(Uint8List want) async {
    final live = _slotHash(await client().imageStates() ?? const [], 0);
    if (live == null) {
      _log('  M7: could not read the running image hash');
      return false;
    }
    final ok = _same(live, want);
    _log(ok
        ? '  M7: running image hash matches the bundle'
        : '  M7: running image hash does NOT match — MCUboot did not install it');
    return ok;
  }

  static List<int>? _slotHash(List<ImageSlot> slots, int slot) {
    for (final s in slots) {
      if (s.image == 0 && s.slot == slot && s.hash.isNotEmpty) return s.hash;
    }
    return null;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// `2.0.1-dev` → `[2, 0, 1]`. Suffixes are a build flavour, not an ordering.
List<int> versionTuple(String v) {
  final core = v.split('-').first.split('+').first;
  final out = <int>[];
  for (final piece in core.split('.')) {
    final n = int.tryParse(piece);
    if (n == null) break;
    out.add(n);
  }
  return out.isEmpty ? const [0] : out;
}

int compareVersions(String a, String b) {
  final x = versionTuple(a), y = versionTuple(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p.compareTo(q);
  }
  return 0;
}

/// Is the device already at the bundle's version? Unknown never matches.
bool sameVersion(String device, String bundle) =>
    device.isNotEmpty && compareVersions(device, bundle) == 0;

/// Refusal text if [bundle] is an older M7 than [installed], else null.
/// MCUboot would refuse it at boot anyway, after a ~40 s upload.
String? m7Downgrade(String installed, String bundle) {
  if (installed.isEmpty || compareVersions(bundle, installed) >= 0) return null;
  return 'The M7 image ($bundle) is older than the installed M7 ($installed). '
      'MCUboot refuses older images, so uploading it would change nothing. To '
      'install an older M7 deliberately, use recovery.';
}

enum UpdateStage {
  idle,
  checking,
  uploadingM4,
  committingM4,
  uploadingM7,
  markingM7,
  resetting,
  verifying,
  done,
  failed,
}

class UpdateProgress {
  const UpdateProgress(this.stage, this.sent, this.total);
  final UpdateStage stage;
  final int sent;
  final int total;
  double? get fraction => total == 0 ? null : sent / total;
}

class UpdateOutcome {
  const UpdateOutcome({
    required this.ok,
    required this.applied,
    required this.skipped,
    required this.versionsAfter,
  });

  /// Every applied image reports the expected version and, for the M7, the
  /// expected image hash.
  final bool ok;
  final List<String> applied;
  final List<String> skipped;
  final Map<String, String> versionsAfter;
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}
