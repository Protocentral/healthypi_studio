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

  /// A HealthyPi Core candidate: its USB ids and product string match
  /// ([HealthyPiCoreUsb.matches]). Only a candidate until it answers an SMP
  /// echo; its one CDC port carries both control and the sample stream.
  bool get isCore =>
      HealthyPiCoreUsb.matches(vendorId, productId, productDescription);

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

/// USB identity of a HealthyPi Core (RP2350B), and of the RP2350 ROM
/// bootloader it reboots into for a firmware update.
///
/// For now the Core shares 1209:FF90 with the HealthyPi 5, so the ids alone
/// do not say which board is plugged in: the product string does. A port is a
/// Core only if both match, and Studio still confirms it with an SMP echo
/// before using it. When the Core gets its own PID, add it to [productIds]
/// (and, if no HealthyPi 5 shares it, the product check becomes a formality).
abstract final class HealthyPiCoreUsb {
  static const int vendorId = 0x1209;

  /// PIDs a Core may enumerate with. 0xFF90 is shared with the HealthyPi 5.
  static const Set<int> productIds = {HealthyPiUsb.healthyPi5Pid};

  /// The USB product string the Core firmware reports.
  static const String product = 'HealthyPi Core';
  static const String manufacturer = 'ProtoCentral';

  /// The RP2350 ROM bootloader (BOOTSEL), which `reset_bootsel` reboots into.
  /// It has no serial port: it shows up as a USB drive and a PICOBOOT
  /// interface, which picotool talks to.
  static const int bootromVendorId = 0x2E8A;
  static const int bootromProductId = 0x000F;

  static bool matches(int vid, int pid, String? productString) =>
      vid == vendorId &&
      productIds.contains(pid) &&
      (productString?.trim() == product);
}

/// Utility class for identifying and categorizing USB devices
class UsbDeviceDetector {
  /// Check if a device is a HealthyPi 6 by its USB ids.
  static bool isHealthyPiDevice(int vid, int pid) =>
      HealthyPiUsb.isHealthyPi6(vid, pid);

  /// A display name for a port, from what the USB descriptors report.
  static String classifyDeviceType(int vid, int pid, String? product) {
    // Before the HealthyPi 5 check: the two boards share 1209:FF90.
    if (HealthyPiCoreUsb.matches(vid, pid, product)) return 'HealthyPi Core';
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
