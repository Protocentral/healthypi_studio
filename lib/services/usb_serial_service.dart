import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart' show ImageSlot;
import '../models/usb_device_info.dart';
import 'data_parser.dart';
import 'smp_serial_client.dart';

class UsbSerialService extends ChangeNotifier {
  List<String> _availablePorts = [];
  SerialPort? _port;
  String? _connectedPortName;

  // CDC 1 control pipe (MCUmgr SMP). Opened alongside the CDC 0 data port so we
  // can issue group-64 stream_start/stop. Best-effort: failures here never
  // affect the data path (the device also auto-streams when CDC 0 opens).
  final SmpSerialClient _control = SmpSerialClient();
  String? _controlPortName;
  bool _transferArmed = false;
  bool _deviceRecording = false;
  bool get controlConnected => _control.isOpen;
  String? get controlPortName => _controlPortName;
  /// The MCUmgr/SMP control client (CDC 1) -- used by the firmware OTA screen.
  SmpSerialClient get control => _control;
  bool get transferArmed => _transferArmed;
  bool get deviceRecording => _deviceRecording;

  StreamSubscription<Uint8List>? _dataSubscription;
  final StreamController<String> _dataStreamController = StreamController<String>.broadcast();
  final StreamController<Uint8List> _binaryDataStreamController = StreamController<Uint8List>.broadcast();
  
  // Reference to DataParser for wiring USB data to packet parsing
  DataParser? _dataParser;
  
  // Auto-reconnection state
  Timer? _reconnectTimer;
  String? _lastConnectedPortName;
  int _lastBaudRate = 921600;
  bool _autoReconnectEnabled = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 2);
  
  List<String> get availablePorts => List.unmodifiable(_availablePorts);
  bool get isConnected => _port != null && _port!.isOpen;
  String? get connectedPortName => _connectedPortName;
  Stream<String> get dataStream => _dataStreamController.stream;
  Stream<Uint8List> get binaryDataStream => _binaryDataStreamController.stream;
  bool get autoReconnectEnabled => _autoReconnectEnabled;
  bool get isReconnecting => _reconnectTimer != null && _reconnectTimer!.isActive;
  int get reconnectAttempts => _reconnectAttempts;
  
  UsbSerialService() {
    _init();
  }
  
  Future<void> _init() async {
    try {
      debugPrint('✅ USB Serial Service initialized with flutter_libserialport');
      // Initial port refresh
      await refreshDevices();
    } catch (e) {
      debugPrint('⚠️  Error initializing USB Serial: $e');
    }
  }
  
  /// The running firmware's version, read over MCUmgr once the control port is
  /// open, or null when it is closed or the board did not answer.
  ///
  /// It lives here rather than on a screen because it belongs to the
  /// connection: the Device screen displays it, and `RecordingEngine` stamps it
  /// into every `.hpd` header, which is why neither should be reading it for
  /// itself.
  String? _firmwareVersion;
  String? get firmwareVersion => _firmwareVersion;

  /// Whether opening the control port should also send `stream_start`.
  ///
  /// Mirrors the **Auto-start streaming on connect** setting, pushed in from
  /// `main.dart` rather than read here, so the service keeps no dependency on
  /// the shell. When it is off the control port still opens — it carries
  /// firmware update and the group-64 commands — and the user starts the stream
  /// from Device → Maintenance.
  bool autoStartStreaming = true;

  /// Enable or disable auto-reconnection
  void setAutoReconnect(bool enabled) {
    _autoReconnectEnabled = enabled;
    if (!enabled) {
      _cancelReconnectTimer();
    }
  }
  
  /// Set the DataParser to automatically parse incoming USB data
  void setDataParser(DataParser parser) {
    _dataParser = parser;
  }
  
  /// Get statistics: packets received and dropped
  Map<String, int> getPacketStats() {
    return {
      'packetsReceived': _dataParser?.packetsReceived ?? 0,
      'packetsDropped': _dataParser?.packetsDropped ?? 0,
    };
  }
  UsbDeviceInfo getPortInfo(String portName) {
    try {
      // IMPORTANT: Don't access port properties without opening
      // On macOS, accessing vendorId, productId, etc. on unopened ports
      // requires special permissions and can fail with "Operation not permitted"
      // Instead, we just use basic port info without needing to open it
      
      String displayName = portName;
      
      // Return basic info without accessing closed port properties
      // Only use port name to avoid permission issues
      return UsbDeviceInfo(
        portName: portName,
        manufacturerName: null,
        productDescription: null,
        serialNumber: null,
        vendorId: 0,
        productId: 0,
        isHealthyPi: false,
        displayName: displayName,
      );
    } catch (e) {
      debugPrint('Error getting port info for $portName: $e');
      return UsbDeviceInfo(
        portName: portName,
        manufacturerName: null,
        productDescription: 'Unknown Device',
        serialNumber: null,
        vendorId: 0,
        productId: 0,
        isHealthyPi: false,
        displayName: portName,
      );
    }
  }
  
  /// Get all ports with their information
  List<UsbDeviceInfo> getAllPortsInfo() {
    final infos = <UsbDeviceInfo>[];
    for (final portName in _availablePorts) {
      infos.add(getPortInfo(portName));
    }
    return infos;
  }
  
  /// Refresh available serial ports
  Future<void> refreshDevices() async {
    try {
      var ports = SerialPort.availablePorts;
      
      // On macOS, prefer /dev/cu.* (call) over /dev/tty.* (terminal)
      // If both exist, filter to only show /dev/cu.* variants
      if (ports.any((p) => p.startsWith('/dev/cu.'))) {
        ports = ports.where((p) => p.startsWith('/dev/cu.') || !p.startsWith('/dev/tty.')).toList();
      }
      
      _availablePorts = ports;
      debugPrint('Found ${_availablePorts.length} serial ports: $_availablePorts');
      notifyListeners();
    } catch (e) {
      debugPrint('Error listing serial ports: $e');
      _availablePorts = [];
      notifyListeners();
    }
  }
  
  /// Check if a port can be opened (diagnostic helper)
  Future<Map<String, dynamic>> diagnosePort(String portName) async {
    final diagnosis = <String, dynamic>{
      'portName': portName,
      'exists': false,
      'isOpen': false,
      'canOpen': false,
      'error': null,
    };
    
    try {
      // Check if port is in available ports
      final available = SerialPort.availablePorts;
      diagnosis['exists'] = available.contains(portName);
      debugPrint('🔍 Port $portName exists: ${diagnosis['exists']}');
      debugPrint('   Available ports: $available');
      
      if (!diagnosis['exists']) {
        diagnosis['error'] = 'Port not found in available ports';
        return diagnosis;
      }
      
      // Try to open it
      final testPort = SerialPort(portName);
      if (testPort.openReadWrite()) {
        diagnosis['canOpen'] = true;
        diagnosis['isOpen'] = testPort.isOpen;
        debugPrint('✅ Port can be opened');
        testPort.close();
        testPort.dispose();
      } else {
        final error = SerialPort.lastError;
        diagnosis['error'] = error?.message ?? 'Unknown error';
        diagnosis['errorCode'] = error?.errorCode ?? 'unknown';
        debugPrint('❌ Port cannot be opened: ${diagnosis['error']}');
      }
    } catch (e) {
      diagnosis['error'] = e.toString();
      debugPrint('❌ Diagnostic error: $e');
    }
    
    return diagnosis;
  }
  
  /// Connect to a serial port
  Future<bool> connect(String portName, {int baudRate = 921600}) async {
    try {
      // Ensure any previous connection is cleaned up
      if (_port != null) {
        await disconnect();
        // Add a small delay to ensure port is fully released
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      // On macOS, ensure we're using the /dev/cu.* variant, not /dev/tty.*
      String actualPortName = portName;
      if (portName.startsWith('/dev/tty.')) {
        actualPortName = portName.replaceFirst('/dev/tty.', '/dev/cu.');
        debugPrint('   - Converted tty to cu: $actualPortName');
      }
      
      // Create port object
      _port = SerialPort(actualPortName);
      
      debugPrint('📍 Attempting to open port: $actualPortName');
      debugPrint('   - Port exists: ${SerialPort.availablePorts.contains(actualPortName)}');
      
      // Try to open the port
      bool opened = false;
      try {
        // Try openReadWrite (read and write access)
        opened = _port!.openReadWrite();
        if (!opened) {
          final error = SerialPort.lastError;
          debugPrint('❌ Failed to open port: ${error?.message}');
          debugPrint('   - Error code: ${error?.errorCode}');
          
          _port?.dispose();
          _port = null;
          return false;
        }
      } catch (e) {
        debugPrint('❌ Error opening port: $e');
        _port?.dispose();
        _port = null;
        return false;
      }
      
      debugPrint('✅ Port opened successfully');
      
      // Configure port
      try {
        final config = SerialPortConfig();
        config.baudRate = baudRate;
        config.bits = 8;
        config.stopBits = 1;
        config.parity = SerialPortParity.none;
        config.setFlowControl(SerialPortFlowControl.none);
        
        _port!.config = config;
        debugPrint('✅ Port configured: $baudRate baud, 8N1');
      } catch (e) {
        debugPrint('⚠️  Error configuring port: $e');
        // Continue anyway - config might not be critical
      }
      
      _connectedPortName = actualPortName;
      
      // Save connection parameters for auto-reconnection
      _lastConnectedPortName = actualPortName;
      _lastBaudRate = baudRate;
      _reconnectAttempts = 0;
      _cancelReconnectTimer();
      
      // Start reading data
      _startDataStream();

      // Open the CDC 1 control sibling and explicitly start the stream
      // (ECG+PPG). Best-effort; the device auto-streams on CDC 0 open anyway.
      _openControlAndStart(actualPortName);

      debugPrint('✅ Connected to $actualPortName at $baudRate baud');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Outer error connecting to port: $e');
      _port?.dispose();
      _port = null;
      return false;
    }
  }
  
  /// Start reading data stream from serial port
  /// flutter_libserialport provides event-based streaming (no polling needed!)
  void _startDataStream() {
    if (_port == null || !_port!.isOpen) return;
    
    try {
      final reader = SerialPortReader(_port!);
      _dataSubscription = reader.stream.listen(
        (data) {
          try {
            // Emit binary data for OpenView protocol parsing
            if (!_binaryDataStreamController.isClosed) {
              _binaryDataStreamController.add(data);
            }
            
            // Wire to DataParser if set
            if (_dataParser != null) {
              _dataParser!.parseBinaryData(data.toList());
            }
            
            // Also emit as text for legacy support (optional)
            // Skip text conversion for binary protocols to avoid errors
            if (data.length < 100 && data.every((b) => b >= 32 && b < 127)) {
              try {
                final text = String.fromCharCodes(data);
                if (!_dataStreamController.isClosed) {
                  _dataStreamController.add(text);
                }
              } catch (e) {
                // Ignore if data is not valid text
              }
            }
          } catch (e) {
            debugPrint('Error processing serial data: $e');
          }
        },
        onError: (error) {
          debugPrint('Serial port read error: $error');
          // Schedule auto-reconnection attempt
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('Serial port stream closed');
          // Notify listeners that connection was lost
          _connectedPortName = null;
          notifyListeners();
          // Schedule auto-reconnection attempt
          _scheduleReconnect();
        },
        cancelOnError: false, // Don't cancel subscription on error, allow recovery
      );
    } catch (e) {
      debugPrint('Error starting data stream: $e');
      disconnect();
    }
  }
  
  /// Disconnect from port
  /// Set [intentional] to true when user explicitly disconnects (won't trigger reconnect)
  Future<void> disconnect({bool intentional = true}) async {
    if (intentional) {
      // User-initiated disconnect - cancel any pending reconnection
      _cancelReconnectTimer();
      _lastConnectedPortName = null;
    }
    
    try {
      await _dataSubscription?.cancel();
    } catch (e) {
      debugPrint('Error cancelling data subscription: $e');
    }
    _dataSubscription = null;

    // Stop the stream on the control pipe, then close it.
    try {
      if (_control.isOpen) {
        _control.streamStop();
      }
    } catch (e) {
      debugPrint('Error sending stream_stop: $e');
    }
    _control.close();
    _controlPortName = null;
    // The version belonged to the board that just went away.
    _firmwareVersion = null;

    if (_port != null) {
      try {
        if (_port!.isOpen) {
          _port!.close();
        }
        _port!.dispose();
      } catch (e) {
        debugPrint('Error closing/disposing port: $e');
      }
      _port = null;
    }

    _connectedPortName = null;
    notifyListeners();
  }

  /// Find the CDC 1 control sibling of the just-opened CDC 0 data port, open it,
  /// and send stream_start. The two HealthyPi CDC ACM interfaces enumerate as a
  /// pair sharing a long common prefix (macOS …1/…3, Linux ttyACM0/ttyACM1,
  /// Windows sequential COMn); we pick the available port with the longest
  /// common prefix that isn't the data port. All best-effort.
  void _openControlAndStart(String dataPort) {
    try {
      final candidates = SerialPort.availablePorts
          .where((p) => p != dataPort)
          .toList();
      if (candidates.isEmpty) {
        debugPrint('ℹ️ No control-port sibling found; relying on device auto-stream');
        return;
      }
      int commonLen(String a, String b) {
        final n = a.length < b.length ? a.length : b.length;
        int i = 0;
        while (i < n && a[i] == b[i]) {
          i++;
        }
        return i;
      }
      candidates.sort((a, b) => commonLen(b, dataPort).compareTo(commonLen(a, dataPort)));
      final controlPort = candidates.first;
      if (_control.open(controlPort)) {
        _controlPortName = controlPort;
        if (autoStartStreaming) {
          _control.streamStart(ch: 0x03, ann: 0x00); // ECG + PPG (+ vitals)
          debugPrint('✅ Control pipe $controlPort: stream_start sent (ECG+PPG)');
        } else {
          debugPrint(
              'ℹ️ Control pipe $controlPort open; auto-start off, no stream_start');
        }
        unawaited(_readFirmwareVersion());
      } else {
        debugPrint('⚠️ Could not open control sibling $controlPort; using auto-stream');
      }
    } catch (e) {
      debugPrint('⚠️ Control-port setup error (non-fatal): $e');
    }
  }

  /// Read the running image's version over MCUmgr, once per control session.
  ///
  /// Best-effort and quiet: a board that does not answer leaves the field null,
  /// and every consumer renders that as unknown rather than as a guess.
  Future<void> _readFirmwareVersion() async {
    try {
      final ImageSlot? running = await _control.runningImage();
      if (running == null) return;
      _firmwareVersion =
          running.version.isEmpty ? running.shortHash : running.version;
      debugPrint('✅ Firmware version: $_firmwareVersion');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Could not read firmware version: $e');
    }
  }

  /// Arm/disarm USB MSC Transfer Mode via the CDC1 control pipe (group 64
  /// 0x0069). Arming re-enumerates the device, so the data/control ports will
  /// briefly drop and the host mounts the SD as a USB drive; disarming restores
  /// streaming. Returns true if the command was written.
  bool setTransferMode(bool on) {
    if (!_control.isOpen) {
      debugPrint('⚠️ Transfer Mode: control port not open');
      return false;
    }
    final ok = _control.transferMode(on);
    if (ok) {
      _transferArmed = on;
      debugPrint('📦 Transfer Mode ${on ? "ARM" : "DISARM"} sent on $_controlPortName');
      notifyListeners();
    }
    return ok;
  }

  /// Start/stop recording to the device's SD card via the CDC1 control pipe
  /// (group 64 0x0061/0x0062). Independent of host-side recording. Returns true
  /// if the command was written.
  bool setDeviceRecording(bool on, {String? name}) {
    if (!_control.isOpen) {
      debugPrint('⚠️ Device recording: control port not open');
      return false;
    }
    final ok = on ? _control.sdRecordStart(name: name) : _control.sdRecordStop();
    if (ok) {
      _deviceRecording = on;
      debugPrint('💾 Device SD recording ${on ? "START" : "STOP"} sent');
      notifyListeners();
    }
    return ok;
  }
  
  /// Cancel any pending reconnection timer
  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  /// Schedule a reconnection attempt
  void _scheduleReconnect() {
    // Don't reconnect if intentionally disconnected or max attempts reached
    if (_lastConnectedPortName == null) {
      debugPrint('🔄 Not reconnecting: no previous connection');
      return;
    }
    
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('🔄 Max reconnection attempts ($_maxReconnectAttempts) reached');
      _lastConnectedPortName = null;
      return;
    }
    
    // Cancel any existing timer
    _cancelReconnectTimer();
    
    debugPrint('🔄 Scheduling reconnection attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts in ${_reconnectDelay.inSeconds}s');
    
    _reconnectTimer = Timer(_reconnectDelay, _attemptReconnect);
  }
  
  /// Attempt to reconnect to the last connected port
  Future<void> _attemptReconnect() async {
    if (_lastConnectedPortName == null) return;
    
    _reconnectAttempts++;
    debugPrint('🔄 Reconnection attempt $_reconnectAttempts/$_maxReconnectAttempts to $_lastConnectedPortName');
    
    // Refresh device list first
    await refreshDevices();
    
    // Check if the port is available
    if (!_availablePorts.contains(_lastConnectedPortName)) {
      debugPrint('🔄 Port $_lastConnectedPortName not available, will retry...');
      _scheduleReconnect();
      return;
    }
    
    // Attempt connection
    final success = await connect(_lastConnectedPortName!, baudRate: _lastBaudRate);
    
    if (success) {
      debugPrint('✅ Reconnected successfully to $_lastConnectedPortName');
    } else {
      debugPrint('❌ Reconnection failed, scheduling retry...');
      _scheduleReconnect();
    }
  }
  
  /// Write string to port
  Future<void> write(String data) async {
    if (_port == null || !_port!.isOpen) {
      debugPrint('Cannot write: port not open');
      return;
    }
    
    try {
      final bytes = Uint8List.fromList(data.codeUnits);
      final bytesWritten = _port!.write(bytes);
      if (bytesWritten != bytes.length) {
        debugPrint('Warning: Only wrote $bytesWritten of ${bytes.length} bytes');
      }
    } catch (e) {
      debugPrint('Error writing to port: $e');
    }
  }
  
  /// Write bytes to port
  Future<void> writeBytes(Uint8List data) async {
    if (_port == null || !_port!.isOpen) {
      debugPrint('Cannot write: port not open');
      return;
    }
    
    try {
      final bytesWritten = _port!.write(data);
      if (bytesWritten != data.length) {
        debugPrint('Warning: Only wrote $bytesWritten of ${data.length} bytes');
      }
    } catch (e) {
      debugPrint('Error writing bytes to port: $e');
    }
  }
  
  @override
  void dispose() {
    _cancelReconnectTimer();
    disconnect();
    _dataStreamController.close();
    _binaryDataStreamController.close();
    super.dispose();
  }
}
