// HealthyPi Core detection: it shares 1209:FF90 with the HealthyPi 5, so the
// product string decides, and a HealthyPi 6 is never taken for either.

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/models/usb_device_info.dart';

UsbDeviceInfo port(int vid, int pid, String? product) => UsbDeviceInfo(
      portName: '/dev/cu.usbmodem1101',
      productDescription: product,
      vendorId: vid,
      productId: pid,
      isHealthyPi: HealthyPiUsb.isHealthyPi6(vid, pid),
      displayName: UsbDeviceDetector.classifyDeviceType(vid, pid, product),
    );

void main() {
  test('1209:FF90 with the Core product string is a Core', () {
    final p = port(0x1209, 0xFF90, 'HealthyPi Core');
    expect(p.isCore, isTrue);
    expect(p.isHealthyPi, isFalse, reason: 'not a HealthyPi 6');
    expect(p.isRecovery, isFalse);
    expect(p.displayName, 'HealthyPi Core');
  });

  test('1209:FF90 with any other product string stays a HealthyPi 5', () {
    for (final product in [null, '', 'HealthyPi 5', 'HealthyPi Core 2', 'Pico']) {
      final p = port(0x1209, 0xFF90, product);
      expect(p.isCore, isFalse, reason: 'product $product');
      expect(p.isHealthyPi, isFalse);
      expect(p.displayName, 'HealthyPi 5', reason: 'product $product');
    }
  });

  test('the product string alone is not enough', () {
    // Right name, wrong ids: another RP2350 board, or the HealthyPi 6 PID.
    expect(port(0x2E8A, 0x000A, 'HealthyPi Core').isCore, isFalse);
    expect(port(0x1209, HealthyPiUsb.releasePid, 'HealthyPi Core').isCore,
        isFalse);
    expect(port(0x2FE3, 0x0100, 'HealthyPi Core').isCore, isFalse);
  });

  test('surrounding whitespace in the descriptor is tolerated', () {
    expect(port(0x1209, 0xFF90, ' HealthyPi Core ').isCore, isTrue);
  });

  test('HealthyPi 6 detection is unchanged', () {
    final app = port(0x1209, HealthyPiUsb.releasePid, 'HealthyPi 6');
    expect(app.isHealthyPi, isTrue);
    expect(app.isCore, isFalse);
    expect(app.displayName, 'HealthyPi 6');
    final rec = port(0x1209, HealthyPiUsb.releasePid, 'HealthyPi 6 Recovery');
    expect(rec.isRecovery, isTrue);
    expect(rec.isCore, isFalse);
    expect(port(0x2FE3, 0x0001, null).displayName,
        'HealthyPi 6 (development build)');
  });

  test('the Core PIDs are one named list, shared with the HealthyPi 5 today',
      () {
    expect(HealthyPiCoreUsb.productIds, contains(HealthyPiUsb.healthyPi5Pid));
    expect(HealthyPiCoreUsb.vendorId, 0x1209);
    expect(HealthyPiCoreUsb.bootromVendorId, 0x2E8A);
    expect(HealthyPiCoreUsb.bootromProductId, 0x000F);
  });
}
