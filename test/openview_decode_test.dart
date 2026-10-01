import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/data_parser.dart';
import 'package:healthypi_studio/services/openview_parser.dart';

/// One v2 data frame, byte for byte as healthypi-6-fw `openview/protocol.py`
/// `pack()` builds it.
List<int> frame({
  int seq = 1,
  int ecg1 = 0,
  int ecg2 = 0,
  int ecg3 = 0,
  int resp = 0,
  int red = 0,
  int ir = 0,
  bool ppgValid = true,
  int hr = 0,
  int spo2 = 0,
  int rr = 0,
  int tempCc = 0,
  int version = 0x02,
  List<int> footer = const [0x00, 0x0B],
}) {
  final b = ByteData(43)
    ..setUint32(0, seq, Endian.little)
    ..setInt32(4, ecg1, Endian.little)
    ..setInt32(8, ecg2, Endian.little)
    ..setInt32(12, ecg3, Endian.little)
    ..setInt32(16, resp, Endian.little)
    ..setInt32(20, red, Endian.little)
    ..setInt32(24, ir, Endian.little)
    ..setUint8(28, ppgValid ? 0xFF : 0x00)
    ..setUint16(29, hr, Endian.little)
    ..setUint8(31, spo2)
    ..setUint8(32, rr)
    ..setUint16(33, tempCc, Endian.little)
    ..setInt32(35, 11, Endian.little)
    ..setInt32(39, -12, Endian.little);
  return [0x0A, 0xFA, 0x2B, version, 0x02, ...b.buffer.asUint8List(), ...footer];
}

void main() {
  test('a v2 data frame decodes field by field', () {
    final p = OpenViewParser();
    final out = p.add(frame(
      seq: 7,
      ecg1: 1000,
      ecg2: -2000,
      ecg3: 3000,
      resp: -4,
      red: 123456,
      ir: -654321,
      hr: 72,
      spo2: 98,
      rr: 16,
      tempCc: 3655,
    ));
    final d = out.single;
    expect(d.sequenceNumber, 7);
    expect([d.ecg1, d.ecg2, d.ecg3, d.respiration], [1000, -2000, 3000, -4]);
    expect([d.ppgRed, d.ppgIr], [123456, -654321]);
    expect(d.ppgValid, isTrue);
    expect([d.heartRate, d.spo2, d.respirationRate], [72, 98, 16]);
    expect(d.temperature, closeTo(36.55, 1e-9));
    expect([d.adcChannel1, d.adcChannel2], [11, -12]);
    // OpenView carries no vitals flags: the HR source is unknown, not ECG.
    expect(d.hasVitalsFlags, isFalse);
  });

  test('frames split across reads and preceded by noise are recovered', () {
    final p = OpenViewParser();
    final bytes = [1, 2, 0x0A, 3, ...frame(seq: 1), ...frame(seq: 2)];
    final out = [
      ...p.add(bytes.sublist(0, 30)),
      ...p.add(bytes.sublist(30, 61)),
      ...p.add(bytes.sublist(61)),
    ];
    expect(out.map((d) => d.sequenceNumber), [1, 2]);
    expect(p.sequenceGaps, 0);
  });

  test('HRV and EEG frames are stepped over by their length', () {
    final p = OpenViewParser();
    final hrv = [0x0A, 0xFA, 0x14, 0x02, 0x03, ...List.filled(20, 0x0A), 0x00, 0x0B];
    // 51 bytes in all, per the reference's EEG_PACKET_LEN.
    final eeg = [0x0A, 0xFA, 0x2E, 0x02, 0x04, ...List.filled(44, 0xFA), 0x00, 0x0B];
    final out = p.add([...hrv, ...frame(seq: 5), ...eeg, ...frame(seq: 6)]);
    expect(out.map((d) => d.sequenceNumber), [5, 6]);
    expect(p.skipped, 2);
  });

  test('a v1 frame is counted, not decoded as v2', () {
    final p = OpenViewParser();
    expect(p.add(frame(version: 0x00)), isEmpty);
    expect(p.legacyV1, 1);
  });

  test('a bad footer is dropped and the stream resyncs', () {
    final p = OpenViewParser();
    final out = p.add([...frame(seq: 1, footer: [0x00, 0x00]), ...frame(seq: 2)]);
    expect(out.map((d) => d.sequenceNumber), [2]);
    expect(p.dropped, greaterThan(0));
  });

  test('a sequence gap is counted', () {
    final p = OpenViewParser();
    p.add([...frame(seq: 1), ...frame(seq: 4)]);
    expect(p.sequenceGaps, 1);
  });

  test('DataParser routes Wi-Fi bytes through the OpenView decoder', () {
    final parser = DataParser();
    parser.parseOpenViewBytes([...frame(seq: 1, ecg1: 5), ...frame(seq: 2, ecg1: 6)]);
    expect(parser.consumePackets().map((d) => d.ecg1), [5, 6]);
    expect(parser.packetsDropped, 0);
    parser.dispose();
  });
}
