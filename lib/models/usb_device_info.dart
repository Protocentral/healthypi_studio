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

  /// Whether this is identified as a HealthyPi device
  final bool isHealthyPi;

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

/// Utility class for identifying and categorizing USB devices
class UsbDeviceDetector {
  /// Known HealthyPi device VID/PID combinations
  static const Map<String, (int vid, int pid)> healthyPiDevices = {
    'HealthyPi v1/v2 (CH340)': (0x1A86, 0x7523),
    'HealthyPi v3 (CP210x)': (0x10C4, 0xEA60),
    'HealthyPi (FT232)': (0x0403, 0x6001),
  };

  /// Check if a device matches known HealthyPi VID/PID pairs
  static bool isHealthyPiDevice(int vid, int pid) {
    return healthyPiDevices.values.any((pair) => pair.$1 == vid && pair.$2 == pid);
  }

  /// Get HealthyPi model name for VID/PID pair
  static String? getHealthyPiModelName(int vid, int pid) {
    for (final entry in healthyPiDevices.entries) {
      if (entry.value.$1 == vid && entry.value.$2 == pid) {
        return entry.key;
      }
    }
    return null;
  }

  /// Classify USB device by type based on VID/PID and device name
  static String classifyDeviceType(int vid, int pid, String deviceName) {
    // Check for HealthyPi first
    if (isHealthyPiDevice(vid, pid)) {
      final modelName = getHealthyPiModelName(vid, pid);
      return 'HealthyPi $modelName';
    }

    // Classify by common chip types
    switch ((vid, pid)) {
      case (0x1A86, 0x7523):
        return 'CH340 Serial Adapter';
      case (0x10C4, 0xEA60):
        return 'CP210x Serial Adapter';
      case (0x0403, 0x6001):
        return 'FT232 Serial Adapter';
      default:
        // Use device name if available
        if (deviceName.isNotEmpty) {
          return deviceName;
        }
        return 'Unknown USB Device';
    }
  }
}
