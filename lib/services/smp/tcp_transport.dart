// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import 'byte_stream_transport.dart';

/// SMP over the ESP32-C6's TCP passthrough — the Wi-Fi route to the same
/// control and firmware session USB reaches on CDC 1.
///
/// The passthrough is transparent: it forwards the identical `uart_mcumgr`
/// lines, so nothing above [ByteStreamSmpTransport] can tell the two apart.
class TcpSmpTransport extends ByteStreamSmpTransport {
  TcpSmpTransport(
    this.host, {
    this.port = defaultPort,
    this.timeout = const Duration(seconds: 5),
  });

  /// The SMP port on the board. Port 5000 alongside it carries the DBLK sample
  /// stream, which is a different service on the same radio.
  static const int defaultPort = 9000;

  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;

  @override
  String? get deviceLabel => '$host:$port';

  @override
  Future<void> connect() async {
    if (state == SmpConnectionState.connected) return;
    setState(SmpConnectionState.connecting);
    try {
      final Socket socket = await Socket.connect(host, port, timeout: timeout);
      // Control traffic is small and latency-sensitive; Nagle would coalesce
      // an upload request with the next and stall the offset-driven loop.
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      resetDecoder();
      _sub = socket.listen(
        onBytes,
        onError: (Object e) {
          debugPrint('⚠️ SMP TCP read error: $e');
          unawaited(disconnect());
        },
        onDone: () => unawaited(disconnect()),
        cancelOnError: false,
      );
      setState(SmpConnectionState.connected);
      debugPrint('📡 SMP control over TCP: $host:$port');
    } catch (e) {
      setState(SmpConnectionState.disconnected);
      throw SmpTransportException('could not connect to $host:$port: $e');
    }
  }

  @override
  void sendBytes(Uint8List bytes) {
    final Socket? socket = _socket;
    if (socket == null) throw SmpTransportException('$deviceLabel is closed');
    socket.add(bytes);
  }

  @override
  Future<void> disconnect() async {
    if (state == SmpConnectionState.disconnected) return;
    setState(SmpConnectionState.disconnecting);
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    setState(SmpConnectionState.disconnected);
    await closeStreams();
  }
}
