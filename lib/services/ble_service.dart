import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import '../utils/global.dart';

class BleService extends ChangeNotifier {
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _connectedDevice;
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // The command characteristic, once BLE service discovery assigns it. Nothing
  // assigns it today: BLE is connect-only, and streaming is v1.2 work.
  BluetoothCharacteristic? _commandCharacteristic;


  List<BluetoothDevice> get devices => _devices;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => _isScanning;
  bool get isConnected => _connectedDevice != null;
  
  BleService();

  /// True once the platform has been probed and reported a usable Bluetooth
  /// stack. Stays false in test environments and on platforms with no BLE
  /// implementation, so the Connect screen can offer USB and WiFi instead.
  bool _supported = false;
  bool get isSupported => _supported;

  bool _probed = false;

  /// True once [ensureAvailable] has run, so the UI can tell "not asked yet"
  /// apart from "asked, and unavailable".
  bool get isProbed => _probed;

  /// Probe the Bluetooth stack, once, on first use.
  ///
  /// Deliberately not called from the constructor: on macOS merely touching the
  /// plugin raises the system Bluetooth permission prompt, and USB is this
  /// app's primary transport — asking for Bluetooth before the user has asked
  /// for Bluetooth is the wrong first impression.
  Future<bool> ensureAvailable() async {
    if (_probed) return _supported;
    _probed = true;
    try {
      // The plugin throws rather than returning false where it has no platform
      // implementation at all, so the whole probe has to be guarded.
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint('⚠️ Bluetooth not supported by this device');
      } else {
        _supported = true;
        FlutterBluePlus.adapterState.listen((state) {
          debugPrint('📶 Bluetooth adapter state: $state');
        });
      }
    } catch (e) {
      debugPrint('⚠️ Bluetooth unavailable on this platform: $e');
      _supported = false;
    }
    notifyListeners();
    return _supported;
  }
  
  Future<void> startScan() async {
    if (_isScanning) return;
    if (!await ensureAvailable()) {
      debugPrint('⚠️ Skipping BLE scan — no Bluetooth stack on this platform');
      return;
    }

    // Studio is desktop-only: macOS, Windows and Linux all grant Bluetooth at
    // the OS level (on macOS via the sandbox entitlement), so there is no
    // runtime permission request to make here.

    _devices.clear();
    _isScanning = true;
    notifyListeners();
    
    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      
      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (!_devices.contains(result.device)) {
            _devices.add(result.device);
            notifyListeners();
          }
        }
      });
      
      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 15));
      await stopScan();
    } catch (e) {
      debugPrint('Error during BLE scan: $e');
      _isScanning = false;
      notifyListeners();
    }
  }
  
  Future<void> stopScan() async {
    if (!_supported) return;
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    notifyListeners();
  }
  
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;
      notifyListeners();
      
      // Listen to connection state
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _connectedDevice = null;
          notifyListeners();
        }
      });
      
      return true;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      return false;
    }
  }
  
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      notifyListeners();
    }
  }

  
  Future<List<BluetoothService>> discoverServices() async {
    if (_connectedDevice == null) return [];
    
    try {
      return await _connectedDevice!.discoverServices();
    } catch (e) {
      debugPrint('Error discovering services: $e');
      return [];
    }
  }

  Future<void> sendCurrentDateTime(BluetoothDevice device) async {
    final dt = DateTime.now();
    final cdate = DateFormat("yy").format(dt);

    // Get timezone offset in total minutes (e.g., IST = +330, EST = -300)
    //final offsetMinutes = dt.timeZoneOffset.inMinutes; // signed int

    debugPrint('Syncing device time: ${dt.toString()} (local time)');
    //debugPrint('Timezone: ${dt.timeZoneName}, Offset: ${offsetMinutes} mins');

    List<int> commandDateTimePacket = [];
    ByteData sessionParametersLength = ByteData(6);
    commandDateTimePacket.addAll(hPiGlobal.CMD_SET_DEVICE_TIME);

    sessionParametersLength.setUint8(0, dt.second);
    sessionParametersLength.setUint8(1, dt.minute);
    sessionParametersLength.setUint8(2, dt.hour);
    sessionParametersLength.setUint8(3, dt.day);
    sessionParametersLength.setUint8(4, dt.month);
    sessionParametersLength.setUint8(5, int.parse(cdate));

    // Encode signed offset in minutes as Int16 (2 bytes, big-endian)
    // Range: -840 to +840 minutes covers all real-world timezones
    //sessionParametersLength.setInt16(6, offsetMinutes, Endian.little);

    Uint8List cmdByteList = sessionParametersLength.buffer.asUint8List(0, 6);
    commandDateTimePacket.addAll(cmdByteList);

    debugPrint('Full Cmd: ${commandDateTimePacket.map((b) => '0x${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(' ')}');
    debugPrint('Decoded → ss:${dt.second} mm:${dt.minute} hh:${dt.hour} dd:${dt.day} MM:${dt.month} yy:${int.parse(cdate)}');
    debugPrint('-------------------------------');
    // ──────────────────────────────────────────────────────────

    await _sendCommand(commandDateTimePacket, device);
  }


  Future<void> _sendCommand(List<int> commandList, BluetoothDevice device) async {
    final characteristic = _commandCharacteristic;
    if (characteristic == null) {
      // Silently dropping a command is how this went unnoticed; say so.
      debugPrint('⚠️ BLE command dropped: no command characteristic '
          '(BLE is connect-only in this build)');
      return;
    }
    await characteristic.write(commandList, withoutResponse: true);
  }
  
  Stream<List<int>>? subscribeToCharacteristic(
    BluetoothCharacteristic characteristic,
  ) {
    try {
      characteristic.setNotifyValue(true);
      return characteristic.lastValueStream;
    } catch (e) {
      debugPrint('Error subscribing to characteristic: $e');
      return null;
    }
  }
  
  Future<void> writeToCharacteristic(
    BluetoothCharacteristic characteristic,
    List<int> value,
  ) async {
    try {
      await characteristic.write(value);
    } catch (e) {
      debugPrint('Error writing to characteristic: $e');
    }
  }
  
  @override
  void dispose() {
    stopScan();
    disconnect();
    super.dispose();
  }
}
