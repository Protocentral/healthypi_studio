// HealthyPi Core stream: DBLK blocks arrive inside unsolicited SMP frames
// (op 3, group 64, id 0xC0, {"b": <block>}) on the one CDC port, and must
// reach DataParser.parseBinaryData() exactly as HealthyPi 6 CDC0 bytes do.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/protocol/hp6_formats.dart';
import 'package:healthypi_studio/protocol/hpi_core.dart';
import 'package:healthypi_studio/protocol/hpi_group64.g.dart';
import 'package:healthypi_studio/services/core_stream_router.dart';
import 'package:healthypi_studio/services/data_parser.dart';
import 'package:healthypi_studio/services/smp_serial_client.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import 'support/fake_smp_device.dart';

/// CRC-32/ISO-HDLC (zlib), bit by bit — independent of the parser's table.
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// One DBLK block, as the Core's hpi_dblk.c builds it.
Uint8List dblk(int channel, int seq, List<List<int>> samples, {int tMs = 0}) {
  final payload = [for (final s in samples) ...s];
  final len = dblkOverhead + payload.length;
  final b = ByteData(len);
  b.setUint32(0, 0x4B4C4244, Endian.little); // "DBLK"
  b.setUint32(4, len, Endian.little);
  b.setUint32(8, seq, Endian.little);
  b.setUint64(12, tMs, Endian.little);
  b.setUint8(20, channel);
  b.setUint8(21, 0);
  b.setUint16(22, samples.length, Endian.little);
  b.setUint32(24, 0, Endian.little);
  final bytes = b.buffer.asUint8List();
  bytes.setRange(dblkHeaderLen, dblkHeaderLen + payload.length, payload);
  b.setUint32(len - dblkCrcLen, crc32(bytes.sublist(0, len - dblkCrcLen)),
      Endian.little);
  return bytes;
}

/// ECG sample: {resp, ecg1, ecg2, ecg3 (i32), lead_off, flags, pad2}. The
/// Core has one lead: ecg2 and ecg3 are 0.
List<int> ecg(int resp, int lead) {
  final b = ByteData(20);
  b.setInt32(0, resp, Endian.little);
  b.setInt32(4, lead, Endian.little);
  return b.buffer.asUint8List();
}

List<int> ppg(int red, int ir) {
  final b = ByteData(12);
  b.setInt32(0, red, Endian.little);
  b.setInt32(4, ir, Endian.little);
  return b.buffer.asUint8List();
}

/// The stream notification as the Core sends it.
SmpMessage note(Uint8List block) => SmpMessage(
      op: SmpOp.writeRsp,
      group: 64,
      id: HpiCore.streamData,
      seq: 0,
      payload: {'b': block},
    );

/// Through the SMP wire encoding and back, so `b` is whatever CBOR decoding
/// makes of a byte string.
SmpMessage overTheWire(SmpMessage m) => SmpMessage.fromBytes(m.toBytes());

void main() {
  test('CRC helper matches the zlib check value', () {
    expect(crc32('123456789'.codeUnits), 0xCBF43926);
  });

  group('CoreStreamRouter', () {
    late DataParser parser;
    late CoreStreamRouter router;

    setUp(() {
      parser = DataParser();
      router = CoreStreamRouter(parser.parseBinaryData);
    });
    tearDown(() => parser.dispose());

    test('an ECG block in a notification becomes samples', () {
      final block = dblk(Hp6Channel.ecg, 1,
          [for (var i = 0; i < 25; i++) ecg(1000 + i, -200 + i)]);
      expect(router.add(overTheWire(note(block))), isTrue);

      expect(router.blocks, 1);
      expect(parser.packetsReceived, 25);
      expect(parser.packetsDropped, 0);
      final packets = parser.consumePackets();
      expect(packets.first.ecg1, -200);
      expect(packets.first.respiration, 1000);
      expect(packets.last.ecg1, -176);
      expect(packets.first.ecg2, 0);
      expect(packets.first.ecg3, 0);
    });

    test('PPG rides the ECG cadence, as on a HealthyPi 6', () {
      router.add(overTheWire(note(dblk(Hp6Channel.ppg, 1,
          [for (var i = 0; i < 16; i++) ppg(50000 + i, 60000 + i)]))));
      router.add(overTheWire(note(dblk(Hp6Channel.ecg, 2,
          [for (var i = 0; i < 4; i++) ecg(0, i)]))));
      final packets = parser.consumePackets();
      expect(packets, hasLength(4));
      expect(packets.last.ppgValid, isTrue);
      expect(packets.last.ppgRed, 50001); // two real PPG samples popped at 2:1
      expect(parser.sequenceGaps, 0);
    });

    test('a lost block shows up as a sequence gap', () {
      router.add(overTheWire(note(dblk(Hp6Channel.ecg, 10, [ecg(0, 1)]))));
      router.add(overTheWire(note(dblk(Hp6Channel.ecg, 12, [ecg(0, 2)]))));
      expect(parser.sequenceGaps, 1);
      expect(parser.packetsReceived, 2);
    });

    test('a corrupted block is counted as a drop, not plotted', () {
      final block = dblk(Hp6Channel.ecg, 1, [ecg(0, 5)]);
      block[dblkHeaderLen] ^= 0xFF; // payload no longer matches the CRC
      router.add(overTheWire(note(block)));
      expect(parser.packetsReceived, 0);
      expect(parser.packetsDropped, 1);
    });

    test('other unsolicited frames are ignored, never parsed', () {
      // A late reply to stream_status, and a group-64 frame with another id.
      expect(
          router.add(SmpMessage(
              op: SmpOp.readRsp, group: 64, id: 0x22, seq: 7, payload: {})),
          isFalse);
      expect(
          router.add(SmpMessage(
              op: SmpOp.writeRsp,
              group: 64,
              id: 0x21,
              seq: 0,
              payload: {'b': dblk(Hp6Channel.ecg, 1, [ecg(0, 1)])})),
          isFalse);
      // Right id, wrong group.
      expect(
          router.add(SmpMessage(
              op: SmpOp.writeRsp,
              group: 0,
              id: HpiCore.streamData,
              seq: 0,
              payload: {'b': dblk(Hp6Channel.ecg, 1, [ecg(0, 1)])})),
          isFalse);
      expect(router.ignored, 3);
      expect(parser.packetsReceived, 0);
    });

    test('a notification without a byte string is counted as malformed', () {
      expect(router.add(note(Uint8List(0))), isFalse);
      expect(
          router.add(SmpMessage(
              op: SmpOp.writeRsp,
              group: 64,
              id: HpiCore.streamData,
              seq: 0,
              payload: {'x': 1})),
          isFalse);
      expect(router.malformed, 2);
      expect(router.blocks, 0);
    });
  });

  group('over an SMP link', () {
    late FakeSmpDevice device;
    late SmpSerialClient client;
    late DataParser parser;
    late CoreStreamRouter router;
    late StreamSubscription<SmpMessage> sub;

    setUp(() async {
      device = await FakeSmpDevice.bind();
      client = SmpSerialClient();
      expect(await client.openTcp('127.0.0.1', port: device.port), isTrue);
      await device.waitConnected();
      parser = DataParser();
      router = CoreStreamRouter(parser.parseBinaryData);
      sub = client.notifications.listen(router.add);
    });

    tearDown(() async {
      await sub.cancel();
      client.close();
      await device.close();
      parser.dispose();
    });

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('stream_start, then framed notifications reach the parser', () async {
      device.onRequest = (_) => {};
      final r = await client.streamStart(ch: HpiCore.chAll);
      expect(r.ok, isTrue);
      expect(device.requests.single.id, Hpi.streamStart.id);
      expect(device.requests.single.payload, {'ch': 7, 'ann': 0});

      for (var seq = 1; seq <= 3; seq++) {
        device.notify(note(dblk(Hp6Channel.ecg, seq,
            [for (var i = 0; i < 25; i++) ecg(0, seq * 100 + i)])));
      }
      await until(() => parser.packetsReceived == 75);
      expect(parser.packetsReceived, 75);
      expect(parser.sequenceGaps, 0);
      expect(router.blocks, 3);
    });

    test('a reply still finds its request while the stream runs', () async {
      device.onRequest = (req) {
        // The device interleaves a stream block ahead of the reply.
        device.notify(note(dblk(Hp6Channel.ecg, 1, [ecg(0, 9)])));
        return {'active': true, 'ch': 7, 'ann': 0, 'sent': 10, 'dropped': 0};
      };
      final st = await client.streamStatus();
      expect(st.ok, isTrue);
      expect(st.value!.active, isTrue);
      await until(() => parser.packetsReceived == 1);
      expect(parser.packetsReceived, 1);
    });

    test('notifications follow a reopened link', () async {
      client.close();
      expect(await client.openTcp('127.0.0.1', port: device.port), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      device.notify(note(dblk(Hp6Channel.ecg, 1, [ecg(0, 1)])));
      await until(() => parser.packetsReceived == 1);
      expect(parser.packetsReceived, 1);
    });
  });

  group('Core-only commands', () {
    late FakeSmpDevice device;
    late SmpSerialClient client;

    setUp(() async {
      device = await FakeSmpDevice.bind();
      client = SmpSerialClient();
      expect(await client.openTcp('127.0.0.1', port: device.port), isTrue);
    });

    tearDown(() async {
      client.close();
      await device.close();
    });

    test('reset_bootsel is a group-64 write to 0xB0', () async {
      device.onRequest = (_) => {};
      final r = await client.resetBootsel();
      expect(r.ok, isTrue);
      final req = device.requests.single;
      expect((req.op, req.group, req.id), (SmpOp.writeReq, 64, 0xB0));
    });

    test('reset_bootsel with no reply counts as done (the board reset)',
        () async {
      device.onRequest = (_) => null; // held, never answered
      final r =
          await client.resetBootsel(timeout: const Duration(milliseconds: 100));
      expect(r.ok, isTrue);
    });

    test('a refused reset_bootsel is reported', () async {
      device.onRequest = (_) => smpErr(8);
      final r = await client.resetBootsel();
      expect(r.ok, isFalse);
      expect(r.failure!.rc, 8);
    });

    test('c6_flash_mode is a group-64 write to 0xB1', () async {
      device.onRequest = (_) => {};
      expect((await client.c6FlashMode()).ok, isTrue);
      final req = device.requests.single;
      expect((req.op, req.group, req.id), (SmpOp.writeReq, 64, 0xB1));
    });

    test('lock_state ENOTSUP leaves the lock unknown', () async {
      device.onRequest = (_) => smpErr(8, group: 0);
      final r = await client.lockState();
      expect(r.ok, isFalse);
      expect(r.failure!.rc, 8);
    });
  });

  test('fw_versions: the Core application version is read by key order', () {
    expect(HpiCoreVersions.firmware({'fw': '0.2.0', 'm7fw': 'x'}), '0.2.0');
    expect(HpiCoreVersions.firmware({'m7fw': '0.2.0'}), '0.2.0');
    expect(HpiCoreVersions.firmware({'fw': ''}), isNull);
    expect(HpiCoreVersions.firmware(null), isNull);
    expect(HpiCoreVersions.coprocessor({'espfw': '1.0.0'}), '1.0.0');
  });
}
