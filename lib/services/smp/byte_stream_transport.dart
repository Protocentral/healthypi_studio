// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

/// Base for the two byte-stream SMP transports Studio uses — USB CDC 1 and the
/// ESP32's TCP passthrough.
///
/// `SmpTransport` is shaped for BLE, where the bytes on the characteristic are
/// the SMP frame itself. A byte stream has no packet boundaries, so both of our
/// links carry Zephyr's `uart_mcumgr` encapsulation: a length prefix, a
/// CRC-16/XMODEM, and base64 lines marked `0x06 0x09` / `0x04 0x14`. That codec
/// lives in `mcumgr_dart`, so a subclass here only has to move bytes —
/// [sendBytes] out, [onBytes] in — and manage its own connection.
abstract class ByteStreamSmpTransport implements SmpTransport {
  final StreamController<Uint8List> _rx =
      StreamController<Uint8List>.broadcast();
  final StreamController<SmpConnectionState> _states =
      StreamController<SmpConnectionState>.broadcast();
  final UartMcumgrDecoder _decoder = UartMcumgrDecoder();

  SmpConnectionState _state = SmpConnectionState.disconnected;

  /// Bytes per upload request, chosen so `ImgMgmt`'s steady-state chunk comes
  /// out at 128 — the size this firmware has been flashed with all along.
  /// `ImgMgmt` reserves 28 bytes of header and CBOR overhead after the first
  /// frame, and 90 on the first, which carries the 32-byte SHA as well.
  static const int uploadWriteLength = 156;

  /// Frames dropped by the decoder for a bad length prefix or CRC. Non-zero
  /// means the link is corrupting bytes — worth surfacing on Link health.
  int get badFrames => _decoder.badFrames;

  @override
  int? get maxWriteLength => uploadWriteLength;

  @override
  SmpConnectionState get state => _state;

  @override
  Stream<SmpConnectionState> get stateChanges => _states.stream;

  @override
  Stream<Uint8List> get notifications => _rx.stream;

  @override
  Future<void> write(Uint8List frame) async {
    if (_state != SmpConnectionState.connected) {
      throw SmpTransportException('$deviceLabel is not connected');
    }
    for (final Uint8List line in UartMcumgrCodec.encode(frame)) {
      sendBytes(line);
    }
  }

  /// Write raw bytes to the underlying pipe. Throw [SmpTransportException] on
  /// failure; the SMP client turns that into a failed request rather than a
  /// silent hang.
  @protected
  void sendBytes(Uint8List bytes);

  /// Feed inbound bytes from the pipe. Partial lines, several lines at once and
  /// interleaved console text are all fine.
  @protected
  void onBytes(Uint8List chunk) {
    for (final Uint8List frame in _decoder.add(chunk)) {
      if (!_rx.isClosed) _rx.add(frame);
    }
  }

  @protected
  void setState(SmpConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Drop any half-received packet. Call when the pipe opens, so a truncated
  /// packet from a previous session cannot merge into the next one.
  @protected
  void resetDecoder() => _decoder.reset();

  @protected
  Future<void> closeStreams() async {
    await _rx.close();
    await _states.close();
  }
}
