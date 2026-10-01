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

  test('device_info and telemetry decode to typed replies', () async {
    device.onRequest = (r) => switch (r.id) {
          0x01 => {'sn': '3233511900370042', 'fw': '1.0.2', 'br': 'v5', 'up': 42},
          0x30 => {'vbat_mv': 3987, 'soc': 81, 'usb': true, 'batt': true, 'ok': true},
          _ => smpErr(8),
        };
    final info = (await client.deviceInfo()).value!;
    expect(info.sn, '3233511900370042');
    expect(info.br, 'v5');
    expect(info.up, 42);
    final t = (await client.telemetry()).value!;
    expect(t.soc, 81);
    expect(t.vbatMv, 3987);
    expect(t.ibatMa, isNull); // not sent, so not invented
  });

  test('lock_state 0 is locked, as the firmware defines it', () async {
    device.onRequest = (r) => {'state': 0};
    expect((await client.lockState()).value!.state, 0);
    expect(Hpi.lockState.id, 0x13);
  });

  test('a locked device refusing a command is named', () async {
    device.onRequest = (r) => {'rc': 13};
    final r = await client.streamStart();
    expect(r.failure!.label, 'the device is locked');
  });

  test('RTC_NOT_SET is read as os rc 4, and the clock is written with an offset',
      () async {
    device.onRequest = (SmpMessage r) =>
        r.op == SmpOp.readReq ? smpErr(4, group: 0) : <String, Object?>{};
    final read = await client.readDatetime();
    expect(read.failure!.rc, 4);
    expect(read.failure!.label, 'RTC_NOT_SET');

    expect((await client.writeDatetime(DateTime(2026, 10, 1, 16, 20, 5))).ok,
        isTrue);
    final sent = device.requests.last;
    expect(sent.group, 0);
    expect(sent.id, 4);
    expect(sent.payload['datetime'],
        matches(RegExp(r'^2026-10-01T16:20:05[+-]\d\d:\d\d$')));
  });
}
