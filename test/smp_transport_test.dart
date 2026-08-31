// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthypi_studio/services/smp/byte_stream_transport.dart';
import 'package:healthypi_studio/services/smp/tcp_transport.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

/// A stand-in for the board's SMP passthrough: decodes the request lines Studio
/// writes, and answers with a properly framed response.
class _FakeDevice {
  _FakeDevice(this._server) {
    _server.listen((Socket socket) {
      _socket = socket;
      if (!_accepted.isCompleted) _accepted.complete();
      final UartMcumgrDecoder decoder = UartMcumgrDecoder();
      socket.listen((Uint8List chunk) {
        for (final Uint8List frame in decoder.add(chunk)) {
          final SmpMessage req = SmpMessage.fromBytes(frame);
          requests.add(req);
          final Map<String, Object?>? reply = _replies[req.id];
          if (reply != null) respond(req, reply);
        }
      });
    });
  }

  static Future<_FakeDevice> bind() async =>
      _FakeDevice(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  Socket? _socket;
  final Completer<void> _accepted = Completer<void>();

  /// Completes once the server has accepted the client socket. `connect()`
  /// returns as soon as the *client* side is up, which is a moment earlier.
  Future<void> get accepted => _accepted.future;
  final List<SmpMessage> requests = <SmpMessage>[];
  final Map<int, Map<String, Object?>> _replies = <int, Map<String, Object?>>{};

  int get port => _server.port;

  /// Auto-answer any request with this command [id].
  void autoReply(int id, Map<String, Object?> payload) => _replies[id] = payload;

  void respond(SmpMessage req, Map<String, Object?> payload,
      {int? maxLineLength}) {
    final Uint8List frame = SmpMessage(
      op: SmpOp.writeRsp,
      group: req.group,
      id: req.id,
      seq: req.seq,
      payload: payload,
    ).toBytes();
    for (final Uint8List line
        in UartMcumgrCodec.encode(frame, maxLineLength: maxLineLength)) {
      _socket?.add(line);
    }
  }

  /// Write raw bytes, to simulate console noise.
  void writeRaw(List<int> bytes) => _socket?.add(bytes);

  /// Send a well-formed line whose CRC does not match its body — a bit flipped
  /// on the wire, not a malformed packet.
  void writeCorrupted() {
    final Uint8List frame =
        SmpMessage(op: SmpOp.writeRsp, group: 0, id: 0, seq: 0).toBytes();
    final Uint8List line = UartMcumgrCodec.encode(frame).single;
    final Uint8List pkt = base64.decode(
      String.fromCharCodes(line.sublist(2, line.length - 1)),
    );
    pkt[2] ^= 0xFF; // flip a body byte; the trailing CRC now disagrees
    _socket?.add(<int>[
      UartMcumgrCodec.startMarker0,
      UartMcumgrCodec.startMarker1,
      ...base64.encode(pkt).codeUnits,
      0x0a,
    ]);
  }

  Future<void> close() async {
    _socket?.destroy();
    await _server.close();
  }
}

void main() {
  late _FakeDevice device;
  late TcpSmpTransport transport;

  setUp(() async {
    device = await _FakeDevice.bind();
    transport = TcpSmpTransport('127.0.0.1', port: device.port);
  });

  tearDown(() async {
    await transport.disconnect();
    await device.close();
  });

  group('TcpSmpTransport', () {
    test('connects and reports state transitions', () async {
      expect(transport.state, SmpConnectionState.disconnected);
      final Future<List<SmpConnectionState>> states =
          transport.stateChanges.take(2).toList();

      await transport.connect();

      expect(transport.state, SmpConnectionState.connected);
      expect(await states, <SmpConnectionState>[
        SmpConnectionState.connecting,
        SmpConnectionState.connected,
      ]);
      expect(transport.deviceLabel, '127.0.0.1:${device.port}');
    });

    test('refuses to connect to a closed port', () async {
      final ServerSocket dead =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int deadPort = dead.port;
      await dead.close();

      final TcpSmpTransport t = TcpSmpTransport('127.0.0.1', port: deadPort);
      await expectLater(t.connect(), throwsA(isA<SmpTransportException>()));
      expect(t.state, SmpConnectionState.disconnected);
    });

    test('rejects a write before connect rather than hanging', () async {
      await expectLater(
        transport.write(Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0, 0, 0])),
        throwsA(isA<SmpTransportException>()),
      );
    });

    test('frames a request the device can decode', () async {
      await transport.connect();
      final SmpClient client = SmpClient(transport);
      device.autoReply(0, <String, Object?>{'rc': 0});

      await client.send(
        op: SmpOp.writeReq,
        group: 64,
        id: 0,
        payload: <String, Object?>{'on': true},
      );

      expect(device.requests, hasLength(1));
      expect(device.requests.single.group, 64);
      expect(device.requests.single.payload['on'], true);
    });

    test('round-trips a request and its response through SmpClient', () async {
      await transport.connect();
      final SmpClient client = SmpClient(transport);
      device.autoReply(1, <String, Object?>{'rc': 0, 'off': 128});

      final SmpMessage rsp = await client.send(
        op: SmpOp.writeReq,
        group: 1,
        id: 1,
        payload: <String, Object?>{'off': 0},
      );

      expect(rsp.rc, isNull); // rc 0 normalises to null
      expect(rsp.payload['off'], 128);
    });

    test('matches responses to requests by seq, out of order', () async {
      await transport.connect();
      final SmpClient client = SmpClient(transport);

      final Future<SmpMessage> first =
          client.send(op: SmpOp.readReq, group: 0, id: 0);
      final Future<SmpMessage> second =
          client.send(op: SmpOp.readReq, group: 0, id: 1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(device.requests, hasLength(2));

      // Answer the second request first.
      device.respond(device.requests[1], <String, Object?>{'which': 'second'});
      device.respond(device.requests[0], <String, Object?>{'which': 'first'});

      expect((await first).payload['which'], 'first');
      expect((await second).payload['which'], 'second');
    });

    test('reassembles a response split across continuation lines', () async {
      await transport.connect();
      final SmpClient client = SmpClient(transport);

      final Future<SmpMessage> pending =
          client.send(op: SmpOp.readReq, group: 0, id: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      device.respond(
        device.requests.single,
        <String, Object?>{'d': 'x' * 400},
        maxLineLength: 48,
      );

      expect((await pending).payload['d'], 'x' * 400);
    });

    test('ignores console noise on the same pipe', () async {
      await transport.connect();
      final SmpClient client = SmpClient(transport);

      final Future<SmpMessage> pending =
          client.send(op: SmpOp.readReq, group: 0, id: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      device.writeRaw('*** Booting Zephyr OS ***\r\n'.codeUnits);
      device.respond(device.requests.single, <String, Object?>{'rc': 0});

      await expectLater(pending, completes);
      expect(transport.badFrames, 0);
    });

    test('counts a corrupted packet and stays usable', () async {
      await transport.connect();
      final SmpClient client = SmpClient(transport);

      await device.accepted;
      device.writeCorrupted();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(transport.badFrames, 1);

      device.autoReply(0, <String, Object?>{'rc': 0});
      await expectLater(
        client.send(op: SmpOp.readReq, group: 0, id: 0),
        completes,
      );
    });

    test('reports a maxWriteLength that yields 128-byte upload chunks',
        () async {
      await transport.connect();
      final ImgMgmt img = ImgMgmt(
        SmpClient(transport),
        maxWriteLength: () => transport.maxWriteLength,
      );
      expect(transport.maxWriteLength,
          ByteStreamSmpTransport.uploadWriteLength);
      expect(img.steadyChunkSize, 128);
    });

    test('disconnect is idempotent and closes the socket', () async {
      await transport.connect();
      await transport.disconnect();
      expect(transport.state, SmpConnectionState.disconnected);
      await transport.disconnect(); // must not throw
    });
  });
}
