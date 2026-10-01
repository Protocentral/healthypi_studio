/// Extended information about a USB serial port
/// Contains rich metadata from libserialport for HealthyPi detection and display
class UsbDeviceInfo {
  /// Serial port path (COM3, /dev/ttyUSB0, /dev/cu.usbserial-*, etc.)
  final String portName;

  /// Manufacturer name if available
  final String? manufacturerName;

  /// Product description from device
  final String? productDescription;

  /// Serial number of the device
  final String? serialNumber;

  /// Vendor ID
  final int vendorId;

  /// Product ID
  final int productId;

  /// Whether this is identified as a HealthyPi 6 (application or recovery)
  final bool isHealthyPi;

  /// A HealthyPi 6 in MCUboot serial recovery: one CDC port, no data stream.
  /// Never open it as a data port.
  bool get isRecovery =>
      isHealthyPi && (productDescription?.contains('Recovery') ?? false);

  /// Human-readable display name
  final String displayName;

  /// Vendor ID as hex string
  String get vidHex => vendorId.toRadixString(16).padLeft(4, '0').toUpperCase();

  /// Product ID as hex string
  String get pidHex => productId.toRadixString(16).padLeft(4, '0').toUpperCase();

  UsbDeviceInfo({
    required this.portName,
    this.manufacturerName,
    this.productDescription,
    this.serialNumber,
    required this.vendorId,
    required this.productId,
    required this.isHealthyPi,
    required this.displayName,
  });

  /// Create a display string with all device information
  String get fullInfo {
    final parts = [
      displayName,
      'Port: $portName',
      'VID: $vidHex',
      'PID: $pidHex',
    ];
    if (manufacturerName != null) {
      parts.add('Mfr: $manufacturerName');
    }
    if (productDescription != null) {
      parts.add('Desc: $productDescription');
    }
    if (serialNumber != null) {
      parts.add('SN: $serialNumber');
    }
    return parts.join('\n');
  }

  /// Get a concise one-line description
  String get shortInfo => '$displayName - $portName';

  @override
  String toString() => shortInfo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsbDeviceInfo &&
          runtimeType == other.runtimeType &&
          productId == other.productId &&
          vendorId == other.vendorId &&
          portName == other.portName;

  @override
  int get hashCode => Object.hash(productId, vendorId, portName);
}

/// USB identity of a HealthyPi 6.
///
/// Match on the vendor id only. The application and the MCUboot recovery mode
/// share one PID, and which of the two composite CDC ports carries control is
/// a protocol question (the control port answers SMP), not a USB-id one.
abstract final class HealthyPiUsb {
  /// pid.codes VID (release builds) and Zephyr's development VID (dev builds).
  static const Set<int> vendorIds = {0x1209, 0x2FE3};

  /// Release PID under the pid.codes VID.
  static const int releasePid = 0xFF91;

  /// 0x1209:0xFF90 is a HealthyPi 5, not a 6.
  static const int healthyPi5Pid = 0xFF90;

  /// Product string while in MCUboot serial recovery.
  static const String recoveryProduct = 'HealthyPi 6 Recovery';

  static bool isHealthyPi6(int vid, int pid) =>
      vendorIds.contains(vid) && !(vid == 0x1209 && pid == healthyPi5Pid);
}

/// Utility class for identifying and categorizing USB devices
class UsbDeviceDetector {
  /// Check if a device is a HealthyPi 6 by its USB ids.
  static bool isHealthyPiDevice(int vid, int pid) =>
      HealthyPiUsb.isHealthyPi6(vid, pid);

  /// A display name for a port, from what the USB descriptors report.
  static String classifyDeviceType(int vid, int pid, String? product) {
    if (HealthyPiUsb.isHealthyPi6(vid, pid)) {
      if (product?.contains('Recovery') ?? false) {
        return 'HealthyPi 6 — recovery mode';
      }
      return vid == 0x2FE3 ? 'HealthyPi 6 (development build)' : 'HealthyPi 6';
    }
    if (vid == 0x1209 && pid == HealthyPiUsb.healthyPi5Pid) return 'HealthyPi 5';
    if (product != null && product.isNotEmpty) return product;
    return 'Serial port';
  }
}
