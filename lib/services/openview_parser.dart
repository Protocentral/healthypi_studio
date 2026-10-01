import 'dart:typed_data';

import 'data_parser.dart';

/// Decoder for OpenView v2, the Wi-Fi stream format.
///
/// The M7 speaks only `.HP6` DBLK, on USB. The ESP32-C6 co-processor repacks
/// samples into OpenView frames for Wi-Fi consumers and sends them on TCP port
/// 5000 (and UDP broadcast 5001). Layout from healthypi-6-fw
/// `tools/healthypi/src/healthypi/openview/protocol.py`, which transcribes the
/// co-processor's `openview_pack_packet()`:
///
/// ```
///  0  0A FA        sync
///  2  len          0x2B for a v2 data frame
///  3  version      0x02 (0x00 = legacy v1, emitted by nothing current)
///  4  type         0x02 data, 0x03 HRV (27 B), 0x04 EEG (51 B)
///  5  seq u32 | ecg1 ecg2 ecg3 resp ppg_red ppg_ir (6 x i32) | ppg_valid u8
///     | hr u16 | spo2 u8 | resp_rate u8 | temp_cc u16 | adc1 adc2 (2 x i32)
/// 48  00 0B        footer
/// ```
///
/// Only data frames are decoded. HRV and EEG frames are stepped over by their
/// length. Not yet verified against hardware: the co-processor's OpenView path
/// has not been run on a board.
class OpenViewParser {
  static const int sync0 = 0x0A;
  static const int sync1 = 0xFA;
  static const int versionV1 = 0x00;
  static const int versionV2 = 0x02;
  static const int typeData = 0x02;
  static const int typeHrv = 0x03;
  static const int typeEeg = 0x04;
  static const int dataLen = 50;
  static const int hrvLen = 27;
  static const int eegLen = 51;

  final List<int> _buf = [];

  /// Frames rejected for a bad footer or an unknown version.
  int dropped = 0;

  /// v1 frames seen — pre-v2 co-processor firmware, which Studio does not
  /// decode.
  int legacyV1 = 0;

  /// HRV and EEG frames stepped over.
  int skipped = 0;

  int? _lastSeq;
  int sequenceGaps = 0;

  /// Feed received bytes; returns every complete data frame decoded.
  List<OpenViewData> add(List<int> bytes) {
    _buf.addAll(bytes);
    final out = <OpenViewData>[];
    var pos = 0;
    while (true) {
      final i = _findSync(pos);
      if (i < 0) {
        // Keep a trailing 0x0A: it may be the first half of a sync.
        pos = _buf.isNotEmpty && _buf.last == sync0 ? _buf.length - 1 : _buf.length;
        break;
      }
      if (_buf.length - i < 5) {
        pos = i;
        break;
      }
      final version = _buf[i + 3];
      final type = _buf[i + 4];
      final len = switch (type) {
        typeHrv => hrvLen,
        typeEeg => eegLen,
        _ => dataLen,
      };
      if (_buf.length - i < len) {
        pos = i;
        break;
      }
      if (_buf[i + len - 2] != 0x00 || _buf[i + len - 1] != 0x0B) {
        dropped++;
        pos = i + 1; // not a frame after all; resync
        continue;
      }
      if (type != typeData) {
        skipped++;
      } else if (version == versionV1) {
        legacyV1++;
      } else if (version != versionV2) {
        dropped++;
      } else {
        out.add(_decode(i));
      }
      pos = i + len;
    }
    _buf.removeRange(0, pos);
    return out;
  }

  int _findSync(int from) {
    for (var i = from; i + 1 < _buf.length; i++) {
      if (_buf[i] == sync0 && _buf[i + 1] == sync1) return i;
    }
    return -1;
  }

  OpenViewData _decode(int at) {
    final b = ByteData.sublistView(
        Uint8List.fromList(_buf.sublist(at + 5, at + dataLen - 2)));
    int i32(int o) => b.getInt32(o, Endian.little);
    final seq = b.getUint32(0, Endian.little);
    if (_lastSeq != null && seq != ((_lastSeq! + 1) & 0xFFFFFFFF)) {
      sequenceGaps++;
    }
    _lastSeq = seq;
    final tempCc = b.getUint16(33, Endian.little);
    return OpenViewData(
      rawPayload: const [],
      protocolVersion: 2,
      sequenceNumber: seq,
      ecg1: i32(4),
      ecg2: i32(8),
      ecg3: i32(12),
      respiration: i32(16),
      ppgRed: i32(20),
      ppgIr: i32(24),
      ppgValid: b.getUint8(28) == 0xFF,
      heartRate: b.getUint16(29, Endian.little),
      spo2: b.getUint8(31),
      respirationRate: b.getUint8(32),
      temperature: tempCc / 100.0, // 0 = not reported, rendered as a dash
      adcChannel1: i32(35),
      adcChannel2: i32(39),
    );
  }

  void reset() {
    _buf.clear();
    _lastSeq = null;
    dropped = 0;
    legacyV1 = 0;
    skipped = 0;
    sequenceGaps = 0;
  }
}
