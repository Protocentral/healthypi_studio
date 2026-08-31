import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'data_parser.dart';

/// Helper class for platform-specific socket configuration
class _SocketHelper {
  /// Configure socket for macOS to work around platform-specific issues
  static void configurePlatformSocket(Socket socket) {
    try {
      // Set TCP_NODELAY to disable Nagle's algorithm for lower latency
      socket.setOption(SocketOption.tcpNoDelay, true);
      
      // Additional platform-specific config can be added here if needed
    } catch (e) {
      debugPrint('⚠️ Could not configure socket options: $e (non-critical)');
    }
  }
}

/// WiFi-based serial communication service for HealthyPi 6 device
/// Provides TCP socket connection to remote HealthyPi 6 over WiFi
class WifiSerialService extends ChangeNotifier {
  /// Active TCP socket connection
  Socket? _socket;

  /// Stream subscription for incoming data
  StreamSubscription<List<int>>? _socketSubscription;

  /// Currently connected device IP address
  String? _connectedDevice;

  /// Port number for TCP connection
  int _port = 5000;

  /// Connection timeout duration
  static const Duration _connectionTimeout = Duration(seconds: 10);

  /// Retry logic
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  Timer? _reconnectTimer;

  /// Broadcast stream for incoming data (matches USB architecture)
  final StreamController<List<int>> _dataStreamController = StreamController<List<int>>.broadcast();

  /// Legacy listener list for backward compatibility
  /// Note: Internally converted to stream subscriptions
  final List<StreamSubscription<List<int>>> _listenerSubscriptions = [];

  /// DataParser for direct binary data parsing (matches USB architecture)
  DataParser? _dataParser;

  /// Set the DataParser for direct data parsing (same API as UsbSerialService)
  void setDataParser(DataParser parser) {
    _dataParser = parser;
    debugPrint('✅ WiFi: DataParser connected');
  }

  // ============= GETTERS =============

  /// Currently connected device IP
  String? get connectedDevice => _connectedDevice;

  /// Connection status
  bool get isConnected => _socket != null;

  /// Port number
  int get port => _port;

  /// Data stream (matches USB service API)
  Stream<List<int>> get dataStream => _dataStreamController.stream;

  // ============= CONNECTION MANAGEMENT =============

  /// Connect to HealthyPi 6 device over WiFi
  /// 
  /// [ipAddress] - IP address of the device (e.g., "192.168.1.100")
  /// [port] - TCP port (default: 5000)
  /// 
  /// Returns true if connection successful, false otherwise
  Future<bool> connect(String ipAddress, {int port = 5000}) async {
    // Disconnect if already connected
    if (isConnected) {
      await disconnect();
    }

    _port = port;
    _reconnectAttempts = 0;

    try {
      debugPrint('🔌 Connecting to HealthyPi 6 at $ipAddress:$port...');

      // Try direct string address first (let Dart resolve)
      debugPrint('🔌 Attempting TCP connection (direct string)...');
      
      // Ensure clean state by yielding to the event loop
      await Future.delayed(Duration.zero);
      
      final socket = await Socket.connect(
        ipAddress,
        port,
        timeout: _connectionTimeout,
      );

      _socket = socket;
      _connectedDevice = ipAddress;
      _setupSocket();
      
      // Try sending a keep-alive/handshake byte to activate the stream
      try {
        debugPrint('📡 Sending handshake to device...');
        _socket!.add([0xFF]);  // Send a dummy byte as handshake
        await _socket!.flush();
        debugPrint('✅ Handshake sent');
      } catch (e) {
        debugPrint('⚠️ Failed to send handshake: $e');
      }
      
      debugPrint('✅ Connected to HealthyPi 6 at $ipAddress:$port');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Failed to connect to $ipAddress:$port');
      debugPrint('   Error type: ${e.runtimeType}');
      debugPrint('   Error message: $e');
      
      // Additional debugging for socket-specific errors
      if (e is SocketException) {
        debugPrint('   OS Error: ${e.osError}');
        debugPrint('   Errno: ${e.osError?.errorCode}');
        debugPrint('   Address: ${e.address}');
        debugPrint('   Port: ${e.port}');
        
        // Provide specific guidance based on errno
        if (e.osError?.errorCode == 1) {
          debugPrint('   ℹ️  Errno 1 (EPERM) typically indicates:');
          debugPrint('       - Device/firewall refusing connections');
          debugPrint('       - Check ESP32 logs for "Client connected"');
          debugPrint('       - Verify device is still listening');
          debugPrint('       - Try: nc -zv $ipAddress $port');
        }
      }
      
      _socket = null;
      _connectedDevice = null;
      notifyListeners();
      return false;
    }
  }

  /// Setup socket after successful connection
  void _setupSocket() {
    if (_socket == null) return;

    // Configure socket for this platform
    _SocketHelper.configurePlatformSocket(_socket!);

    debugPrint('📡 Setting up socket listener...');

    // Listen for incoming data
    _socketSubscription = _socket!.listen(
      (List<int> data) {
        if (data.isEmpty) {
          // Silently ignore empty packets (no logging for performance)
          return;
        }
        // Removed excessive per-packet logging for performance
        // Use ThroughputMonitor for metrics instead
        _handleDataReceived(data);
      },
      onError: (error, stackTrace) {
        debugPrint('⚠️ WiFi socket error: $error');
        // Don't print full stack trace, just the error
        _handleConnectionError(error);
      },
      onDone: () {
        debugPrint('❌ WiFi connection closed by device (remote)');
        _handleConnectionClosed();
      },
      cancelOnError: false,  // Don't cancel on error, keep listening
    );
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    try {
      _reconnectTimer?.cancel();
      _reconnectAttempts = 0;

      await _socketSubscription?.cancel();
      await _socket?.close();

      _socket = null;
      _connectedDevice = null;

      debugPrint('✅ Disconnected from device');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ Error during disconnect: $e');
    }
  }

  /// Test if device accepts TCP connections at the kernel level
  Future<void> testDeviceResponsiveness(String ipAddress, {int port = 5000}) async {
    debugPrint('🔍 Testing device TCP responsiveness...');
    
    try {
      // Test 1: Try connecting with explicit source port binding disabled
      debugPrint('   Test 1: Standard connection...');
      final testSocket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 3),
      );
      
      // If we get here, device accepted the connection
      debugPrint('   ✅ Device accepted connection');
      
      // Test 2: Try sending a single byte
      debugPrint('   Test 2: Sending test byte...');
      testSocket.add([0xFF]);
      await testSocket.flush();
      
      debugPrint('   ✅ Test byte sent');
      
      // Listen for response
      testSocket.listen(
        (data) {
          debugPrint('   ✅ Device responded with ${data.length} bytes');
        },
        onError: (e) {
          debugPrint('   ❌ Error receiving from device: $e');
        },
        onDone: () {
          debugPrint('   ℹ️ Device closed connection after test');
        },
      );
      
      // Close after 1 second
      await Future.delayed(const Duration(seconds: 1));
      await testSocket.close();
      
    } catch (e) {
      debugPrint('   ❌ Device is NOT responsive: $e');
      if (e is SocketException) {
        debugPrint('      errno: ${e.osError?.errorCode}');
        debugPrint('      message: ${e.osError?.message}');
      }
    }
  }

  // ============= DATA HANDLING =============

  /// Register a listener for incoming data
  /// Internally converts to stream subscription for efficiency
  void addDataListener(Function(List<int>) listener) {
    final subscription = _dataStreamController.stream.listen(
      (data) {
        try {
          listener(data);
        } catch (e) {
          debugPrint('⚠️ Error in data listener: $e');
        }
      },
      onError: (e) {
        debugPrint('⚠️ Stream error in listener: $e');
      },
    );
    _listenerSubscriptions.add(subscription);
  }

  /// Remove a data listener (not supported with stream-based approach)
  /// For fine-grained control, use dataStream.listen() directly
  void removeDataListener(Function(List<int>) listener) {
    debugPrint('⚠️ removeDataListener not supported with stream architecture');
    debugPrint('   Use dataStream.listen() and cancel the subscription instead');
  }

  /// Handle received data - emit to broadcast stream AND parse directly
  /// All listeners automatically receive data via stream subscriptions
  void _handleDataReceived(List<int> data) {
    // Emit to broadcast stream (for any stream subscribers)
    if (!_dataStreamController.isClosed) {
      _dataStreamController.add(data);
    }

    // Wire directly to DataParser (same as USB service)
    // This ensures consistent data flow regardless of listener setup timing
    if (_dataParser != null) {
      _dataParser!.parseBinaryData(data);
    }
  }

  // ============= ERROR HANDLING =============

  /// Handle connection errors
  void _handleConnectionError(dynamic error) {
    debugPrint('⚠️ Connection error: $error');
    _socket = null;

    // Attempt reconnection
    _attemptReconnect();
  }

  /// Handle connection closed
  void _handleConnectionClosed() {
    _socket = null;
    _socketSubscription?.cancel();

    // Attempt reconnection
    _attemptReconnect();
  }

  /// Attempt to reconnect to device
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('❌ Max reconnection attempts reached');
      _connectedDevice = null;
      notifyListeners();
      return;
    }

    _reconnectAttempts++;
    final delaySeconds = _reconnectAttempts * 2; // Exponential backoff

    debugPrint('🔄 Reconnecting (attempt $_reconnectAttempts/$_maxReconnectAttempts) in ${delaySeconds}s...');

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_connectedDevice != null) {
        final success = await connect(_connectedDevice!, port: _port);
        if (!success) {
          _attemptReconnect();
        }
      }
    });

    notifyListeners();
  }

  // ============= DIAGNOSTICS =============

  /// Test connectivity to a device without establishing persistent connection
  /// Useful for debugging network issues
  Future<String> diagnosticTest(String ipAddress, {int port = 5000}) async {
    final buffer = StringBuffer();
    buffer.writeln('═══ WiFi Connectivity Diagnostic ═══');
    buffer.writeln('Target: $ipAddress:$port');
    
    try {
      // Test 1: Parse the IP address
      buffer.write('1️⃣ IP Address Parsing: ');
      late InternetAddress address;
      try {
        address = InternetAddress(ipAddress);
        buffer.writeln('✅ OK (${address.type})');
      } catch (e) {
        buffer.writeln('❌ FAILED: $e');
        return buffer.toString();
      }

      // Test 2: Attempt connection with detailed timeout
      buffer.write('2️⃣ TCP Connection: ');
      try {
        final socket = await Socket.connect(
          address,
          port,
          timeout: const Duration(seconds: 10),
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw SocketException('Timeout'),
        );

        // Test 3: Check socket properties
        buffer.writeln('✅ Connected');
        buffer.writeln('3️⃣ Socket Properties:');
        buffer.writeln('   • Address: ${socket.remoteAddress}');
        buffer.writeln('   • Port: ${socket.remotePort}');
        
        // Close the diagnostic socket
        await socket.close();
        buffer.writeln('✅ All tests passed - connection working');
      } catch (e) {
        buffer.writeln('❌ FAILED: $e');
        if (e is SocketException) {
          buffer.writeln('   OS Error: ${e.osError}');
          buffer.writeln('   Errno: ${e.osError?.errorCode}');
        }
      }
    } catch (e) {
      buffer.writeln('❌ Unexpected error: $e');
    }
    
    return buffer.toString();
  }

  /// Print detailed diagnostic information
  Future<void> runDiagnostics(String ipAddress, {int port = 5000}) async {
    final results = await diagnosticTest(ipAddress, port: port);
    debugPrint(results);
  }

  /// Advanced socket debugging - returns detailed error information
  Future<Map<String, dynamic>> advancedDiagnostics(String ipAddress, {int port = 5000}) async {
    final diagnostics = <String, dynamic>{};
    
    try {
      // 1. Address Resolution
      debugPrint('🔍 Advanced Diagnostics for $ipAddress:$port');
      final address = InternetAddress(ipAddress);
      diagnostics['addressResolution'] = {
        'input': ipAddress,
        'resolved': address.address,
        'type': address.type.name,  // 'IPv4' or 'IPv6'
        'success': true,
      };
      debugPrint('✅ Address resolved: ${address.address} (${address.type.name})');

      // 2. Network connectivity check
      debugPrint('📡 Checking network connectivity...');
      try {
        final socket = await Socket.connect(
          address,
          port,
          timeout: const Duration(seconds: 5),
        );
        
        diagnostics['networkConnectivity'] = {
          'canConnect': true,
          'remoteAddress': socket.remoteAddress.address,
          'remotePort': socket.remotePort,
          'localAddress': socket.address.address,
          'localPort': socket.port,
        };
        
        await socket.close();
        debugPrint('✅ Network connectivity OK');
      } catch (e) {
        diagnostics['networkConnectivity'] = {
          'canConnect': false,
          'error': '$e',
        };
        
        if (e is SocketException) {
          debugPrint('❌ Socket Error: ${e.message}');
          debugPrint('   OS Error Code: ${e.osError?.errorCode}');
          debugPrint('   OS Error: ${e.osError?.message}');
          
          diagnostics['socketError'] = {
            'message': e.message,
            'osErrorCode': e.osError?.errorCode,
            'osErrorMessage': e.osError?.message,
            'errno1_interpretation': _getErrno1Help(e.osError?.errorCode),
          };
        }
      }

      // 3. System socket state
      debugPrint('🔗 Checking system socket state...');
      // Note: Can only simulate on Dart, actual netstat would need Process execution
      diagnostics['systemState'] = {
        'timestamp': DateTime.now().toIso8601String(),
        'platform': Platform.isWindows ? 'Windows' : 
                   Platform.isMacOS ? 'macOS' : 
                   Platform.isLinux ? 'Linux' : 'Unknown',
      };
      
      return diagnostics;
    } catch (e) {
      diagnostics['error'] = '$e';
      return diagnostics;
    }
  }

  /// Get interpretation text for errno 1
  String _getErrno1Help(int? errorCode) {
    if (errorCode != 1) return '';
    
    return '''
ERRNO 1 (EPERM - Operation not Permitted) Likely Causes:
1. ✋ Device rejecting the connection (check ESP32 logs)
2. 📊 Device has max active connections (restart device)
3. 🔌 TCP backlog is full (restart device)
4. 🚫 Device firewall or connection limiter active
5. 🔄 Previous connections not cleaned up (restart device)

IMMEDIATE FIX: Restart ESP32 and try again immediately.
INVESTIGATION: Check device logs for "Client connected from" message.
''';
  }

  // ============= LIFECYCLE =============

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    _socket?.close();

    // Cancel all listener subscriptions
    for (final subscription in _listenerSubscriptions) {
      subscription.cancel();
    }
    _listenerSubscriptions.clear();

    // Close stream controller
    _dataStreamController.close();

    super.dispose();
  }

  /// Get connection status info
  String getStatusString() {
    if (!isConnected) {
      return 'Not connected';
    }
    return 'Connected to $_connectedDevice:$_port';
  }
}
