import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/protocol/hp6_formats.dart';
import 'package:healthypi_studio/services/data_parser.dart';

// Fixed byte vectors for every DBLK channel the live stream carries, in format
// 0x0300 (firmware app_m7/src/core/sample_formats.h). The frames are built
// here byte by byte so the layout under test is visible in the test itself.

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// One DBLK frame: 28-byte header, [payload], CRC-32 over everything before it.
List<int> dblk({
  required int channel,
  required int sampleCount,
  required List<int> payload,
  int seq = 1,
  int tMs = 1000,
  bool corruptCrc = false,
}) {
  final len = dblkOverhead + payload.length;
  final b = ByteData(len);
  b.setUint8(0, 0x44); // D
  b.setUint8(1, 0x42); // B
  b.setUint8(2, 0x4C); // L
  b.setUint8(3, 0x4B); // K
  b.setUint32(4, len, Endian.little);
  b.setUint32(8, seq, Endian.little);
  b.setUint64(12, tMs, Endian.little);
  b.setUint8(20, channel);
  b.setUint8(21, 0);
  b.setUint16(22, sampleCount, Endian.little);
  b.setUint32(24, 0, Endian.little);
  final bytes = b.buffer.asUint8List();
  bytes.setRange(dblkHeaderLen, dblkHeaderLen + payload.length, payload);
  final crc = _crc32(bytes.sublist(0, len - dblkCrcLen));
  b.setUint32(len - dblkCrcLen, corruptCrc ? crc ^ 1 : crc, Endian.little);
  return bytes;
}

List<int> ecgSample(
    {int resp = 0, int leadI = 0, int leadII = 0, int v1 = 0, int leadOff = 0}) {
  final b = ByteData(20);
  b.setInt32(0, resp, Endian.little);
  b.setInt32(4, leadI, Endian.little);
  b.setInt32(8, leadII, Endian.little);
  b.setInt32(12, v1, Endian.little);
  b.setUint8(16, leadOff);
  return b.buffer.asUint8List();
}

List<int> ppgSample(int red, int ir) {
  final b = ByteData(12);
  b.setInt32(0, red, Endian.little);
  b.setInt32(4, ir, Endian.little);
  return b.buffer.asUint8List();
}

List<int> vitalsSample({
  int hr = 0,
  int spo2x10 = 0,
  int rr = 0,
  int tempX100 = 0,
  int sdnn = 0,
  int rmssd = 0,
  int lfHfX10 = 0,
  int flags = 0,
}) {
  final b = ByteData(16);
  b.setUint16(0, hr, Endian.little);
  b.setUint16(2, spo2x10, Endian.little);
  b.setUint16(4, rr, Endian.little);
  b.setInt16(6, tempX100, Endian.little);
  b.setUint16(8, sdnn, Endian.little);
  b.setUint16(10, rmssd, Endian.little);
  b.setUint16(12, lfHfX10, Endian.little);
  b.setUint8(14, flags);
  return b.buffer.asUint8List();
}

List<int> inferSample({
  int tsMs = 0,
  int model = 0,
  int cls = 0,
  int conf = 0,
  List<int> scores = const [0, 0, 0, 0, 0],
  int flags = 0,
}) {
  final b = ByteData(16);
  b.setUint32(0, tsMs, Endian.little);
  b.setUint16(4, model, Endian.little);
  b.setUint8(6, cls);
  b.setUint8(7, conf);
  for (var k = 0; k < 5; k++) {
    b.setInt8(8 + k, scores[k]);
  }
  b.setUint8(13, flags);
  return b.buffer.asUint8List();
}

void main() {
  late DataParser parser;

  setUp(() => parser = DataParser());
  tearDown(() => parser.dispose());

  test('frame helper matches the parser CRC (sanity)', () {
    // "123456789" is the CRC-32/ISO-HDLC check value.
    expect(_crc32('123456789'.codeUnits), 0xCBF43926);
  });

  group('ECG (channel 1)', () {
    test('decodes leads, respiration and lead-off per sample', () {
      parser.parseBinaryData(dblk(channel: Hp6Channel.ecg, sampleCount: 2, payload: [
        ...ecgSample(resp: -7, leadI: 1000, leadII: -2000, v1: 3000),
        ...ecgSample(leadI: 1, leadOff: Hp6LeadOff.ra | Hp6LeadOff.ll),
      ]));

      final packets = parser.consumePackets();
      expect(packets, hasLength(2));
      expect(packets[0].respiration, -7);
      expect(packets[0].ecg1, 1000);
      expect(packets[0].ecg2, -2000);
      expect(packets[0].ecg3, 3000);
      expect(packets[0].ecgLeadOff, 0);
      expect(packets[1].ecgLeadOff, Hp6LeadOff.ra | Hp6LeadOff.ll);
      expect(packets[1].ecgLeadsOff, isTrue);
      expect(parser.packetsDropped, 0);
    });
  });

  group('PPG (channel 2)', () {
    test('is paced out 2:1 against ECG samples', () {
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.ppg,
          sampleCount: 2,
          payload: [...ppgSample(11, 12), ...ppgSample(21, 22)]));
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.ecg,
          sampleCount: 4,
          seq: 2,
          payload: [for (var i = 0; i < 4; i++) ...ecgSample()]));

      final packets = parser.consumePackets();
      expect(packets.map((p) => p.ppgRed), [0, 11, 11, 21]);
      expect(packets.map((p) => p.ppgIr), [0, 12, 12, 22]);
    });
  });

  group('VITALS (channel 4)', () {
    test('decodes the 16-byte 0x0300 layout, including SDNN above 255', () async {
      final hrv = parser.hrvStream.first;
      parser.parseBinaryData(dblk(
        channel: Hp6Channel.vitals,
        sampleCount: 1,
        payload: vitalsSample(
          hr: 72,
          spo2x10: 975,
          rr: 16,
          tempX100: 3655,
          sdnn: 312, // would have read as 56 under the old u8 layout
          rmssd: 41,
          lfHfX10: 23,
          flags: Hp6VitalsFlag.hrFromPpg | Hp6VitalsFlag.ppgWeak,
        ),
      ));

      final v = await hrv;
      expect(v.heartRate, 72);
      expect(v.sdnnMs, 312);
      expect(v.rmssdMs, 41);
      expect(v.lfHf, closeTo(2.3, 1e-9));
      expect(v.hrFromPpg, isTrue);
      expect(v.ppgWeak, isTrue);
      expect(v.ecgLeadOff, isFalse);
      // R-R is not on the wire and must not be synthesized from HR.
      expect(v.rrIntervalMs, 0);
    });

    test('vitals and flags ride on the following ECG samples', () {
      parser.parseBinaryData(dblk(
        channel: Hp6Channel.vitals,
        sampleCount: 1,
        payload: vitalsSample(
            hr: 64,
            spo2x10: 981,
            rr: 14,
            tempX100: -125,
            flags: Hp6VitalsFlag.ecgLeadOff),
      ));
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.ecg, sampleCount: 1, seq: 2, payload: ecgSample()));

      final p = parser.consumePackets().single;
      expect(p.heartRate, 64);
      expect(p.spo2, 98);
      expect(p.respirationRate, 14);
      expect(p.temperature, closeTo(-1.25, 1e-9));
      expect(p.hrFromPpg, isFalse);
      expect(p.ecgLeadsOff, isTrue);
    });

    test('LF/HF of 0 means not computed', () async {
      final hrv = parser.hrvStream.first;
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.vitals,
          sampleCount: 1,
          payload: vitalsSample(hr: 60)));
      expect((await hrv).lfHf, isNull);
    });

    test('every sample in a batched block is emitted', () async {
      final all = parser.hrvStream.take(3).toList();
      parser.parseBinaryData(dblk(
        channel: Hp6Channel.vitals,
        sampleCount: 3,
        payload: [
          ...vitalsSample(hr: 60),
          ...vitalsSample(hr: 61),
          ...vitalsSample(hr: 62),
        ],
      ));
      expect((await all).map((v) => v.heartRate), [60, 61, 62]);
    });
  });

  group('EEG (channel 5)', () {
    test('decodes eight channels and the lead-off mask', () async {
      final eeg = parser.eegStream.first;
      final b = ByteData(36);
      for (var c = 0; c < 8; c++) {
        b.setInt32(c * 4, (c + 1) * (c.isEven ? 10 : -10), Endian.little);
      }
      b.setUint8(32, 0x05); // channels 1 and 3 off
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.eeg,
          sampleCount: 1,
          payload: b.buffer.asUint8List()));

      final e = await eeg;
      expect(e.channels, [10, -20, 30, -40, 50, -60, 70, -80]);
      expect(e.isChannelConnected(0), isFalse);
      expect(e.isChannelConnected(1), isTrue);
      expect(e.isChannelConnected(2), isFalse);
    });
  });

  group('INFER (channel 8)', () {
    test('a real inference is emitted with its scores', () async {
      final infer = parser.inferStream.first;
      parser.parseBinaryData(dblk(
        channel: Hp6Channel.infer,
        sampleCount: 1,
        payload: inferSample(
          tsMs: 123456,
          model: 7,
          cls: 2,
          conf: 200,
          scores: [-5, 3, 90, -128, 127],
          flags: Hp6InferFlag.lowConf,
        ),
      ));

      final s = await infer;
      expect(s.tsMs, 123456);
      expect(s.modelId, 7);
      expect(s.classId, 2);
      expect(s.confidence, 200);
      expect(s.scores, [-5, 3, 90, -128, 127]);
      expect(s.lowConfidence, isTrue);
      expect(parser.inferSamplesReceived, 1);
    });

    test('a stub inference is never presented as a result', () async {
      final seen = <InferSample>[];
      final sub = parser.inferStream.listen(seen.add);
      parser.parseBinaryData(dblk(
        channel: Hp6Channel.infer,
        sampleCount: 1,
        payload: inferSample(cls: 0, conf: 255, flags: Hp6InferFlag.stub),
      ));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, isEmpty);
      expect(parser.inferStubsDropped, 1);
      expect(parser.packetsDropped, 0);
    });
  });

  group('EVENT (channel 6)', () {
    test('is counted, not dropped', () {
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.event,
          sampleCount: 1,
          payload: List<int>.filled(8, 0)));
      expect(parser.eventsReceived, 1);
      expect(parser.packetsDropped, 0);
    });
  });

  group('framing errors', () {
    test('a bad CRC is dropped and the next block still decodes', () {
      parser.parseBinaryData([
        ...dblk(
            channel: Hp6Channel.ecg,
            sampleCount: 1,
            payload: ecgSample(leadI: 1),
            corruptCrc: true),
        ...dblk(
            channel: Hp6Channel.ecg,
            sampleCount: 1,
            seq: 2,
            payload: ecgSample(leadI: 2)),
      ]);
      expect(parser.consumePackets().map((p) => p.ecg1), [2]);
      expect(parser.packetsDropped, 1);
    });

    test('a block split across reads is reassembled', () {
      final frame =
          dblk(channel: Hp6Channel.ecg, sampleCount: 1, payload: ecgSample(leadI: 9));
      parser.parseBinaryData(frame.sublist(0, 10));
      parser.parseBinaryData(frame.sublist(10));
      expect(parser.consumePackets().single.ecg1, 9);
    });

    test('leading noise is skipped', () {
      parser.parseBinaryData([
        1, 2, 3, 0x44, 0x42, // includes a false partial magic
        ...dblk(channel: Hp6Channel.ecg, sampleCount: 1, payload: ecgSample(leadI: 5)),
      ]);
      expect(parser.consumePackets().single.ecg1, 5);
    });

    test('the old 12-byte VITALS layout is rejected, not misread', () {
      final seen = <HRVPacketData>[];
      final sub = parser.hrvStream.listen(seen.add);
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.vitals,
          sampleCount: 1,
          payload: List<int>.filled(12, 0x11)));
      sub.cancel();
      expect(seen, isEmpty);
      expect(parser.packetsDropped, 1);
    });

    test('a payload that does not divide into samples is rejected', () {
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.ecg,
          sampleCount: 3,
          payload: [...ecgSample(), ...ecgSample()])); // 40 B for 3 samples
      expect(parser.consumePackets(), isEmpty);
      expect(parser.packetsDropped, 1);
    });

    test('an unknown channel is skipped without counting a drop', () {
      parser.parseBinaryData(
          dblk(channel: 42, sampleCount: 1, payload: List<int>.filled(4, 0)));
      parser.parseBinaryData(dblk(
          channel: Hp6Channel.ecg, sampleCount: 1, seq: 2, payload: ecgSample(leadI: 3)));
      expect(parser.consumePackets().single.ecg1, 3);
      expect(parser.packetsDropped, 0);
    });

    test('a sequence gap is counted', () {
      parser.parseBinaryData(
          dblk(channel: Hp6Channel.ecg, sampleCount: 1, seq: 1, payload: ecgSample()));
      parser.parseBinaryData(
          dblk(channel: Hp6Channel.ecg, sampleCount: 1, seq: 5, payload: ecgSample()));
      expect(parser.sequenceGaps, 1);
    });
  });
}
