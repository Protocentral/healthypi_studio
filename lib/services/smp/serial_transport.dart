// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import 'byte_stream_transport.dart';

/// SMP over the board's control port — CDC 1 of the composite USB device.
///
/// CDC 0 carries the DBLK sample stream and is opened separately by
/// `UsbSerialService`; this is the second interface, which carries the group-64
/// control commands and the MCUmgr firmware session.
class SerialSmpTransport extends ByteStreamSmpTransport {
  SerialSmpTransport(this.portName, {this.baudRate = 115200});

  /// Port as the OS names it. On macOS a `/dev/tty.*` name is rewritten to its
  /// `/dev/cu.*` callout twin: opening the tty side blocks until DCD asserts,
  /// which a CDC ACM device never does.
  final String portName;

  /// Irrelevant over USB CDC ACM — the device ignores it — but libserialport
  /// still wants a valid configuration.
  final int baudRate;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _sub;

  @override
  String? get deviceLabel => portName;

  @override
  Future<void> connect() async => connectSync();

  /// Open the port synchronously.
  ///
  /// Opening a serial port does no I/O that can block, so unlike a socket there
  /// is nothing to await — and `UsbSerialService` opens the control pipe from a
  /// synchronous path. Throws [SmpTransportException] on failure, like
  /// [connect].
  void connectSync() {
    if (state == SmpConnectionState.connected) return;
    setState(SmpConnectionState.connecting);

    final String name = portName.startsWith('/dev/tty.')
        ? portName.replaceFirst('/dev/tty.', '/dev/cu.')
        : portName;

    final SerialPort port = SerialPort(name);
    try {
      if (!port.openReadWrite()) {
        port.dispose();
        setState(SmpConnectionState.disconnected);
        throw SmpTransportException('could not open $name');
      }
      port.config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);

      final SerialPortReader reader = SerialPortReader(port);
      _port = port;
      _reader = reader;
      resetDecoder();
      _sub = reader.stream.listen(
        onBytes,
        onError: (Object e) => debugPrint('⚠️ SMP serial read error: $e'),
      );
      setState(SmpConnectionState.connected);
      debugPrint('🔌 SMP control port open: $name');
    } on SmpTransportException {
      rethrow;
    } catch (e) {
      try {
        port.dispose();
      } catch (_) {}
      setState(SmpConnectionState.disconnected);
      throw SmpTransportException('could not open $name: $e');
    }
  }

  @override
  void sendBytes(Uint8List bytes) {
    final SerialPort? port = _port;
    if (port == null) throw SmpTransportException('$portName is closed');
    final int written = port.write(bytes);
    if (written != bytes.length) {
      throw SmpTransportException(
        'short write on $portName ($written/${bytes.length} bytes)',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    setState(SmpConnectionState.disconnecting);
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    // The reader owns a native read loop; dropping the reference alone leaks it.
    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;
    try {
      final SerialPort? port = _port;
      if (port != null) {
        if (port.isOpen) port.close();
        port.dispose();
      }
    } catch (_) {}
    _port = null;
    setState(SmpConnectionState.disconnected);
    await closeStreams();
  }
}
