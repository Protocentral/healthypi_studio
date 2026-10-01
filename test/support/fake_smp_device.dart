// A loopback stand-in for the board's SMP control port, for tests.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcumgr_dart/mcumgr_dart.dart';

/// Decodes the uart_mcumgr lines Studio writes over TCP; a test answers each request
/// from [onRequest], or holds it in [held] to answer later and out of order.
class FakeSmpDevice {
  FakeSmpDevice(this._server) {
    _server.listen((Socket socket) {
      _socket = socket;
      final decoder = UartMcumgrDecoder();
      socket.listen((Uint8List chunk) {
        for (final frame in decoder.add(chunk)) {
          final req = SmpMessage.fromBytes(frame);
          requests.add(req);
          final reply = onRequest?.call(req);
          if (reply != null) {
            respond(req, reply);
          } else {
            held.add(req);
            _heldChanged.add(null);
          }
        }
      });
    });
  }

  static Future<FakeSmpDevice> bind() async =>
      FakeSmpDevice(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  Socket? _socket;
  final requests = <SmpMessage>[];
  final held = <SmpMessage>[];
  final _heldChanged = StreamController<void>.broadcast();
  Map<String, Object?>? Function(SmpMessage req)? onRequest;

  int get port => _server.port;

  Future<void> waitHeld(int n) async {
    while (held.length < n) {
      await _heldChanged.stream.first;
    }
  }

  void respond(SmpMessage req, Map<String, Object?> payload) {
    final frame = SmpMessage(
      op: req.op == SmpOp.readReq ? SmpOp.readRsp : SmpOp.writeRsp,
      group: req.group,
      id: req.id,
      seq: req.seq,
      payload: payload,
    ).toBytes();
    for (final line in UartMcumgrCodec.encode(frame)) {
      _socket?.add(line);
    }
  }

  Future<void> close() async {
    _socket?.destroy();
    await _server.close();
    await _heldChanged.close();
  }
}

/// An SMP v2 error reply.
Map<String, Object?> smpErr(int rc, {int group = 64}) => {
      'err': {'group': group, 'rc': rc},
    };
