// Group-64 control commands: every one is answered by the device and its reply
// is read. Exercised over the TCP transport against a loopback fake device.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/protocol/hpi_group64.g.dart';
import 'package:healthypi_studio/services/smp_serial_client.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import 'support/fake_smp_device.dart';

void main() {
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

  test('stream_start goes out as a group-64 write with ch and ann', () async {
    device.onRequest = (_) => {};
    final r = await client.streamStart(ch: 0x03, ann: 0x00);
    expect(r.ok, isTrue);
    final req = device.requests.single;
    expect(req.group, 64);
    expect(req.id, Hpi.streamStart.id);
    expect(req.op, SmpOp.writeReq);
    expect(req.payload, {'ch': 3, 'ann': 0});
  });

  test('sd_record_start returns the path the device reports', () async {
    device.onRequest = (_) => {'path': '/SD:/REC0007.HP6'};
    final r = await client.sdRecordStart(name: 'bench');
    expect(r.ok, isTrue);
    expect(r.value!.path, '/SD:/REC0007.HP6');
    expect(device.requests.single.payload, {'name': 'bench'});
  });

  test('an empty session name is left out of the request', () async {
    device.onRequest = (_) => {'path': '/SD:/REC0008.HP6'};
    await client.sdRecordStart(name: '');
    expect(device.requests.single.payload, isEmpty);
  });

  test('a group-64 error is reported by its catalog name', () async {
    device.onRequest = (_) => smpErr(258);
    final r = await client.streamStart(ch: 0x10);
    expect(r.ok, isFalse);
    expect(r.failure!.rc, 258);
    expect(r.failure!.code!.name, 'CHANNEL_NOT_AVAILABLE');
    expect(r.failure!.label, startsWith('CHANNEL_NOT_AVAILABLE'));
  });

  test('transfer_mode reports NO_MEDIA rather than arming', () async {
    device.onRequest = (_) => smpErr(267);
    final r = await client.transferMode(true);
    expect(r.failure!.code!.name, 'NO_MEDIA');
    expect(device.requests.single.payload, {'on': true});
  });

  test('transfer_mode state comes from the reply', () async {
    device.onRequest = (_) => {'armed': true};
    final r = await client.transferMode(true);
    expect(r.value!.armed, isTrue);
  });

  test('no reply is a failure, not a success', () async {
    device.onRequest = (_) => null; // hold forever
    final r = await client.request(Hpi.streamStop,
        timeout: const Duration(milliseconds: 100));
    expect(r.ok, isFalse);
    expect(r.failure!.label, 'no reply from the device');
  });

  test('interleaved img and group-64 requests each get their own reply',
      () async {
    device.onRequest = (_) => null; // hold both, answer out of order
    final slots = client.imageList();
    final rec = client.sdRecordStart();
    await device.waitHeld(2);

    final img = device.held.firstWhere((r) => r.group == 1);
    final g64 = device.held.firstWhere((r) => r.group == 64);
    expect(img.seq, isNot(g64.seq));

    device.respond(g64, {'path': '/SD:/REC0009.HP6'});
    device.respond(img, {
      'images': [
        {
          'image': 0,
          'slot': 0,
          'version': '1.0.2',
          'hash': Uint8List(32),
          'active': true,
          'confirmed': true,
        },
      ],
    });

    expect((await rec).value!.path, '/SD:/REC0009.HP6');
    expect((await slots).single.version, '1.0.2');
  });

  test('a stock os-group error is named too', () {
    final f = HpiFailure.fromReply(Hpi.deviceInfo, 4, 0);
    expect(f.code, isNull);
    expect(f.label, 'RTC_NOT_SET');
  });
}
