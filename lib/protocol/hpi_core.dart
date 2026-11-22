import 'hpi_command.dart';

/// HealthyPi Core additions to the group-64 surface.
///
/// The Core (RP2350B) implements a subset of the HealthyPi 6 catalog in
/// `hpi_group64.g.dart`, with the same ids, and answers rc 8 (ENOTSUP) for the
/// rest. The commands here exist on the Core only, so they are hand-written
/// rather than added to the generated catalog, which mirrors the HealthyPi 6
/// firmware.
abstract final class HpiCore {
  /// Reboot into the RP2350 ROM bootloader (BOOTSEL), where picotool can load
  /// a UF2. The device may reset before its reply leaves.
  static const resetBootsel = HpiCommand(0x00B0, 'reset_bootsel', write: true);

  /// Put the ESP32-C6 co-processor into its ROM flash mode.
  static const c6FlashMode = HpiCommand(0x00B1, 'c6_flash_mode', write: true);

  /// Id of the unsolicited stream notification: op 3 (write rsp), group 64,
  /// seq 0, CBOR `{"b": <one DBLK block>}`, sent after `stream_start` until
  /// `stream_stop` or the port closes.
  static const int streamData = 0x00C0;

  /// Key of the DBLK bytes in a [streamData] payload.
  static const String streamDataKey = 'b';

  /// `stream_start` channel bits the Core accepts; any other bit is refused
  /// with CHANNEL_NOT_AVAILABLE (258).
  static const int chEcg = 0x01;
  static const int chPpg = 0x02;
  static const int chVitals = 0x04;
  static const int chAll = chEcg | chPpg | chVitals;

  /// Group-64 commands from the HealthyPi 6 catalog the Core implements.
  /// Everything else answers ENOTSUP, including `lock_state`, so a Core's lock
  /// state is unknown and treated as unlocked.
  static const Set<int> implemented = {
    0x0001, // device_info
    0x0020, // stream_start
    0x0021, // stream_stop
    0x0022, // stream_status
    0x0030, // telemetry
    0x0031, // fw_versions
    0x0060, // sd_status
    0x0061, // sd_record_start
    0x0062, // sd_record_stop
    0x0077, // conn_status
    0x0081, // diag_lead_off
  };
}

/// Reading a Core's `fw_versions` reply.
///
/// The Core answers the HealthyPi 6 command id, but it has one application
/// processor (the RP2350) rather than an M7 and an M4, and the contract does
/// not pin the reply's key names. Read the application version from `fw`
/// (the key `device_info` uses), then `m7fw` (the HealthyPi 6 key); the C6's
/// from `espfw`. A key the device did not send stays null.
abstract final class HpiCoreVersions {
  static const List<String> firmwareKeys = ['fw', 'm7fw'];
  static const List<String> coprocessorKeys = ['espfw'];

  static String? firmware(Map<Object?, Object?>? reply) =>
      _first(reply, firmwareKeys);

  static String? coprocessor(Map<Object?, Object?>? reply) =>
      _first(reply, coprocessorKeys);

  static String? _first(Map<Object?, Object?>? reply, List<String> keys) {
    if (reply == null) return null;
    for (final k in keys) {
      final v = reply[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }
}
