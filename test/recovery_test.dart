// Recovery and USB identity: a fake bootloader on one link, a fake recovered
// application on another.

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/models/usb_device_info.dart';
import 'package:healthypi_studio/services/firmware/firmware_updater.dart';
import 'package:healthypi_studio/services/firmware/recovery.dart';
import 'package:healthypi_studio/services/smp_serial_client.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import 'support/fake_smp_device.dart';
import 'support/test_bundles.dart';

UsbDeviceInfo _port(int vid, int pid, {String? product}) => UsbDeviceInfo(
      portName: '/dev/cu.usbmodem1',
      productDescription: product,
      vendorId: vid,
      productId: pid,
      isHealthyPi: HealthyPiUsb.isHealthyPi6(vid, pid),
      displayName: UsbDeviceDetector.classifyDeviceType(vid, pid, product),
    );

void main() {
  group('USB identity', () {
    test('HealthyPi 6 is matched on the VID, release or dev', () {
      expect(HealthyPiUsb.isHealthyPi6(0x1209, 0xFF91), isTrue);
      expect(HealthyPiUsb.isHealthyPi6(0x2FE3, 0x0100), isTrue);
      expect(HealthyPiUsb.isHealthyPi6(0x10C4, 0xEA60), isFalse); // CP210x
    });

    test('1209:FF90 is a HealthyPi 5, not a 6', () {
      expect(HealthyPiUsb.isHealthyPi6(0x1209, 0xFF90), isFalse);
      expect(_port(0x1209, 0xFF90).displayName, 'HealthyPi 5');
    });

    test('recovery is told by the product string, same VID/PID', () {
      final rec = _port(0x1209, 0xFF91, product: HealthyPiUsb.recoveryProduct);
      final app = _port(0x1209, 0xFF91, product: 'HealthyPi 6');
      expect(rec.isRecovery, isTrue);
      expect(app.isRecovery, isFalse);
      expect(rec.displayName, contains('recovery'));
    });
  });

  group('recover', () {
    late FakeSmpDevice bootloader;
    late FakeSmpDevice application;
    late List<String> log;
    final m7 = buildMcuImage(version: (1, 0, 2));
    var uploaded = 0;
    var resets = 0;
    var m4Reads = 0;

    Future<SmpSerialClient?> open(String port) async {
      final dev = port == 'rec' ? bootloader : application;
      final c = SmpSerialClient();
      return await c.openTcp('127.0.0.1', port: dev.port) ? c : null;
    }

    FirmwareRecovery recovery() => FirmwareRecovery(
          openClient: open,
          applicationPorts: () async => ['app'],
          log: (l) => log.add(l),
          appReturn: const Duration(seconds: 5),
          m4Bind: const Duration(milliseconds: 300),
          poll: const Duration(milliseconds: 50),
        );

    setUp(() async {
      log = [];
      uploaded = 0;
      resets = 0;
      m4Reads = 0;
      bootloader = await FakeSmpDevice.bind();
      application = await FakeSmpDevice.bind();
      // MCUboot serial recovery: img and os groups only.
      bootloader.onRequest = (SmpMessage r) {
        if (r.group == 1 && r.id == 1) {
          final data = r.payload['data'] as List;
          uploaded += data.length;
          return {'off': (r.payload['off'] as int) + data.length};
        }
        if (r.group == 0 && r.id == 5) {
          resets++;
          return {};
        }
        return smpErr(8, group: r.group);
      };
      application.onRequest = (SmpMessage r) {
        if (r.group != 64) return smpErr(8, group: r.group);
        if (r.id == 0x01) return {'sn': 'X', 'fw': '1.0.2'};
        if (r.id == 0x31) {
          // The M4 binds a moment after the M7 comes up.
          m4Reads++;
          return {'m7fw': '1.0.2', 'm4fw': m4Reads < 2 ? '' : '1.0.1', 'espfw': ''};
        }
        return smpErr(8);
      };
    });

    tearDown(() async {
      await bootloader.close();
      await application.close();
    });

    test('writes the M7, resets, and confirms the application runs it',
        () async {
      final out = await recovery().recover(
          recoveryPort: 'rec', m7: m7, m7Version: '1.0.2', m4Version: '1.0.2');
      expect(uploaded, m7.length);
      expect(resets, 1);
      expect(out.m7, '1.0.2');
      expect(out.m4, '1.0.1'); // waited for the M4 to bind
      expect(out.m4Behind, isTrue); // recovery never touches the M4
    });

    test('refuses a port that is the running application', () async {
      await expectLater(
        recovery().recover(recoveryPort: 'app', m7: m7, m7Version: '1.0.2'),
        throwsA(isA<UpdateException>()
            .having((e) => e.message, 'message', contains('application'))),
      );
      expect(uploaded, 0);
    });

    test('says so when the application comes back on another version',
        () async {
      await expectLater(
        recovery().recover(recoveryPort: 'rec', m7: m7, m7Version: '1.0.3'),
        throwsA(isA<UpdateException>()
            .having((e) => e.message, 'message', contains('reports 1.0.2'))),
      );
    });
  });

  group('enter recovery', () {
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

    test('arms and resets when the firmware supports it', () async {
      device.onRequest = (r) => r.op == SmpOp.readReq
          ? {'av': true, 'armed': false}
          : {'armed': true, 'rst': true};
      expect(await FirmwareRecovery.enterRecovery(client), isNull);
      expect(device.requests.last.payload, {'arm': true, 'rst': true});
    });

    test('a build without a bootloader says so and writes nothing', () async {
      device.onRequest = (r) => {'av': false, 'armed': false};
      expect(await FirmwareRecovery.enterRecovery(client),
          contains('without a bootloader'));
      expect(device.requests.where((r) => r.op == SmpOp.writeReq), isEmpty);
    });
  });
}
