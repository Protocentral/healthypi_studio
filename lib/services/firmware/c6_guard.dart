import '../../protocol/hpi_group64.g.dart';
import '../smp_serial_client.dart';

/// Keeps resets away from an ESP32-C6 update.
///
/// The M7 holds the C6 in reset from boot, so resetting the M7 (os reset,
/// entering recovery) or the C6 (`conn_disable`) while a C6 update is in
/// flight abandons it. Worse, after commit, while the C6's new image is still
/// proving itself, it rolls that image back. The firmware refuses such a
/// reset with ESP_UPDATE_ACTIVE (274); this asks first, so Studio can say why
/// instead of sending a command that will be refused.
///
/// A port of healthypi-6-fw `tools/healthypi/src/healthypi/fw/esp32c6.py`
/// (`busy_reason`, `explain_busy`).

/// Why a reset must wait, from an `espfw_status` reply with `busy` set.
String explainEspBusy(EspfwStatusReply s) {
  final st = s.st ?? -1;
  final String what;
  if (st >= HpiEspfwState.preparing && st <= HpiEspfwState.verifying) {
    final name = (hpiEspfwStates[st] ?? 'state $st').toLowerCase();
    what = 'An ESP32-C6 firmware update is in progress '
        '($name, ${s.rx ?? 0}/${s.len ?? 0} B)';
  } else {
    final ver = s.ver;
    what = "The ESP32-C6's new firmware "
        '(${ver == null || ver.isEmpty ? 'version unknown' : ver}) is running '
        'but still proving itself';
  }
  return '$what. Resetting the device now, or putting the C6 back into '
      'reset, would roll that update back, so the device refuses. Wait about a '
      'minute, then try again.';
}

/// For a 274 refusal seen without a status to hand.
const String espUpdateActiveText = 'The device refused: an ESP32-C6 firmware '
    'update is in progress, or its new image is still proving itself, and a '
    'reset now would roll it back. Wait about a minute, then try again.';

/// Text explaining why a reset must wait, or null when it need not.
///
/// Null also when the firmware has no C6 update service (it cannot be
/// mid-update) or the status cannot be read: the device still refuses an
/// unsafe reset itself, and [resetRefusalText] explains that refusal.
Future<String?> espBusyReason(SmpSerialClient client) async {
  final r = await client.espfwStatus();
  final s = r.value;
  if (s == null || s.busy != true) return null;
  return explainEspBusy(s);
}

/// User-facing text for a refused reset-type command.
String resetRefusalText(HpiFailure failure) => failure.isEspUpdateActive
    ? espUpdateActiveText
    : 'The device refused: ${failure.label}';
