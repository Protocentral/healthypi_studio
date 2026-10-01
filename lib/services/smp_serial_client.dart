// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

import '../protocol/hpi_command.dart';
import '../protocol/hpi_group64.g.dart';
import 'smp/byte_stream_transport.dart';
import 'smp/serial_transport.dart';
import 'smp/tcp_transport.dart';

/// MCUmgr control and firmware session for the HealthyPi 6, over USB CDC 1 or
/// the ESP32's Wi-Fi passthrough.
///
/// The protocol itself — SMP framing, CBOR, sequence matching, the image and os
/// groups — lives in `mcumgr_dart`; the `uart_mcumgr` encapsulation both links
/// carry is in its `UartMcumgrCodec`, wrapped by the transports in `smp/`. What
/// remains here is HealthyPi's own surface: the **group-64** control commands,
/// whose ids, request maps and replies are generated from the firmware catalog
/// (`lib/protocol/hpi_group64.g.dart`), and the update sequence.
///
/// Every group-64 command goes through the same `SmpClient` as the img and os
/// groups and its reply is read: the device answers each one, and an error
/// such as NO_MEDIA or a locked device is reported by name instead of the UI
/// assuming success.
class SmpSerialClient {
  ByteStreamSmpTransport? _transport;
  SmpClient? _client;
  ImgMgmt? _img;
  OsMgmt? _os;

  /// HealthyPi's vendor management group.
  static const int controlGroup = hpiGroupId;

  /// Data bytes per upload request. Kept for callers that display it; the value
  /// now comes from `ImgMgmt`, sized by the transport's `maxWriteLength`.
  static const int otaChunk = 128;

  bool get isOpen => _transport?.state == SmpConnectionState.connected;

  /// Frames the link corrupted — a non-zero value means bytes are being lost.
  int get badFrames => _transport?.badFrames ?? 0;

  /// Data bytes per upload request in steady state, for diagnostics.
  int get uploadChunkSize => _img?.steadyChunkSize ?? otaChunk;

  /// Open a TCP control link to the ESP32 SMP passthrough (Wi-Fi OTA).
  /// [host] is typically `healthypi.local`, [port] the gateway port (9000).
  Future<bool> openTcp(
    String host, {
    int port = TcpSmpTransport.defaultPort,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    close();
    return _attach(TcpSmpTransport(host, port: port, timeout: timeout));
  }

  /// Open the control port (CDC 1). Baud is irrelevant over USB CDC ACM.
  ///
  /// Stays synchronous, as `UsbSerialService` expects: opening a serial port
  /// does no I/O that can block, so the transport offers a synchronous open.
  bool open(String portName, {int baudRate = 115200}) {
    close();
    final SerialSmpTransport transport =
        SerialSmpTransport(portName, baudRate: baudRate);
    try {
      transport.connectSync();
      _bind(transport);
      return true;
    } on SmpTransportException catch (e) {
      debugPrint('❌ SMP control open failed: ${e.message}');
      return false;
    }
  }

  Future<bool> _attach(ByteStreamSmpTransport transport) async {
    try {
      await transport.connect();
      _bind(transport);
      return true;
    } on SmpTransportException catch (e) {
      debugPrint('❌ SMP open failed: ${e.message}');
      return false;
    }
  }

  void _bind(ByteStreamSmpTransport transport) {
    final SmpClient client = SmpClient(transport);
    _transport = transport;
    _client = client;
    _img = ImgMgmt(client, maxWriteLength: () => transport.maxWriteLength);
    _os = OsMgmt(client);
  }

  void close() {
    final ByteStreamSmpTransport? transport = _transport;
    final SmpClient? client = _client;
    _transport = null;
    _client = null;
    _img = null;
    _os = null;
    unawaited(client?.dispose());
    unawaited(transport?.disconnect());
  }

  // ---- group 64 control commands ----

  /// Send [command] and read its reply. [write] picks the SMP op for a command
  /// that supports both; otherwise the command's only op is used.
  Future<HpiResult<Map<String, Object?>>> request(
    HpiCommand command, {
    Map<String, Object?> payload = const {},
    bool? write,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final SmpClient? client = _client;
    if (client == null || !isOpen) {
      return HpiResult.failed(HpiFailure.notConnected(command));
    }
    final bool useWrite = write ?? !command.read;
    if (useWrite ? !command.write : !command.read) {
      throw ArgumentError('$command has no ${useWrite ? "write" : "read"} op');
    }
    client.timeout = timeout;
    try {
      final SmpMessage rsp = await client.send(
        op: useWrite ? SmpOp.writeReq : SmpOp.readReq,
        group: controlGroup,
        id: command.id,
        payload: payload,
      );
      final int? rc = rsp.rc;
      if (rc != null) {
        final failure = HpiFailure.fromReply(command, rc, rsp.errGroup);
        debugPrint('⚠️ $command: ${failure.label}');
        return HpiResult.failed(failure);
      }
      return HpiResult.ok(rsp.payload);
    } on SmpException catch (e) {
      debugPrint('❌ $command: $e');
      return HpiResult.failed(HpiFailure.transport(command, e));
    }
  }

  Future<HpiResult<T>> _typed<T>(
    HpiCommand command,
    T Function(Map<Object?, Object?>) parse, {
    Map<String, Object?> payload = const {},
    bool? write,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final r = await request(command,
        payload: payload, write: write, timeout: timeout);
    return r.map(parse);
  }

  /// Start the CDC0 stream. Fails with CHANNEL_NOT_AVAILABLE (258) when the
  /// device cannot produce a requested channel.
  Future<HpiResult<void>> streamStart({int ch = 0x03, int ann = 0x00}) =>
      request(Hpi.streamStart, payload: streamStartRequest(ch: ch, ann: ann));

  Future<HpiResult<void>> streamStop(
          {Duration timeout = const Duration(seconds: 3)}) =>
      request(Hpi.streamStop, timeout: timeout);

  Future<HpiResult<StreamStatusReply>> streamStatus() =>
      _typed(Hpi.streamStatus, StreamStatusReply.fromMap);

  /// Start an SD recording. The reply carries the file path; NOT_READY (256)
  /// means already recording or no card — [sdStatus] tells them apart.
  Future<HpiResult<SdRecordStartReply>> sdRecordStart({String? name}) => _typed(
        Hpi.sdRecordStart,
        SdRecordStartReply.fromMap,
        payload: sdRecordStartRequest(
            name: (name == null || name.isEmpty) ? null : name),
      );

  Future<HpiResult<void>> sdRecordStop() => request(Hpi.sdRecordStop);

  Future<HpiResult<SdStatusReply>> sdStatus() =>
      _typed(Hpi.sdStatus, SdStatusReply.fromMap);

  /// Arm or disarm USB Transfer Mode. Arming re-enumerates USB, so the reply
  /// may be the last thing this link carries.
  Future<HpiResult<TransferModeWriteReply>> transferMode(bool on) => _typed(
        Hpi.transferMode,
        TransferModeWriteReply.fromMap,
        payload: transferModeWriteRequest(on: on),
        write: true,
      );

  // ---- firmware update ----

  /// Upload [image] into the device's secondary slot for MCUboot image index
  /// [imageIndex] (0 = M7, 1 = M4). Chunks are driven by the offset the device
  /// returns, so a device that jumps the offset resumes correctly.
  /// [onProgress] reports (bytesSent, total).
  Future<bool> imageUpload(
    Uint8List image, {
    int imageIndex = 0,
    void Function(int sent, int total)? onProgress,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final ImgMgmt? img = _img;
    final SmpClient? client = _client;
    if (img == null || client == null || !isOpen) return false;
    client.timeout = timeout;
    try {
      await img.upload(image, imageIndex: imageIndex, onProgress: onProgress);
      return true;
    } on SmpException catch (e) {
      debugPrint('❌ OTA upload failed: $e');
      return false;
    }
  }

  /// Mark the uploaded image pending — MCUboot installs it on next boot.
  /// [sha] is the SHA-256 of the full image.
  Future<bool> imageTest(
    List<int> sha, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final ImgMgmt? img = _img;
    final SmpClient? client = _client;
    if (img == null || client == null || !isOpen) return false;
    client.timeout = timeout;
    try {
      await img.test(sha);
      return true;
    } on SmpException catch (e) {
      debugPrint('❌ OTA image test failed: $e');
      return false;
    }
  }

  /// Read the device's image slots — version, hash and the bootable / pending
  /// / confirmed / active flags. Returns an empty list if the read fails, so a
  /// caller can treat "could not read" and "nothing staged" alike.
  Future<List<ImageSlot>> imageList({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final ImgMgmt? img = _img;
    final SmpClient? client = _client;
    if (img == null || client == null || !isOpen) return const <ImageSlot>[];
    client.timeout = timeout;
    try {
      return await img.list();
    } on SmpException catch (e) {
      debugPrint('❌ image list failed: $e');
      return const <ImageSlot>[];
    }
  }

  /// Verify that the image the device has staged is the one we just uploaded.
  ///
  /// Without this an upload that silently truncated, or landed in the wrong
  /// slot, is only discovered when the board fails to boot.
  Future<bool> verifyStaged(List<int> sha, {int imageIndex = 0}) async {
    final List<ImageSlot> slots = await imageList();
    if (slots.isEmpty) return false;
    for (final ImageSlot slot in slots) {
      if (slot.image == imageIndex &&
          !slot.active &&
          _sameHash(slot.hash, sha)) {
        return true;
      }
    }
    return false;
  }

  static bool _sameHash(List<int> a, List<int> b) {
    if (a.length != b.length || a.isEmpty) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Confirm the running image, so MCUboot stops treating it as on trial and
  /// keeps it across the next reboot. Run this **after** the device has come
  /// back up on the new firmware — confirming before the swap defeats the
  /// revert-on-failure the test/confirm flow exists to provide.
  Future<bool> imageConfirm(
    List<int> sha, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final ImgMgmt? img = _img;
    final SmpClient? client = _client;
    if (img == null || client == null || !isOpen) return false;
    client.timeout = timeout;
    try {
      await img.confirm(sha);
      return true;
    } on SmpException catch (e) {
      debugPrint('❌ image confirm failed: $e');
      return false;
    }
  }

  /// The running image, if the device reports one.
  Future<ImageSlot?> runningImage() async {
    for (final ImageSlot slot in await imageList()) {
      if (slot.active) return slot;
    }
    return null;
  }

  /// SHA-256 of an image (host-side; matches what `image test` expects).
  List<int> sha256(Uint8List image) => crypto.sha256.convert(image).bytes;

  /// os reset — reboot into MCUboot to install pending images.
  Future<bool> osReset({Duration timeout = const Duration(seconds: 3)}) async {
    final OsMgmt? os = _os;
    final SmpClient? client = _client;
    if (os == null || client == null || !isOpen) return false;
    client.timeout = timeout;
    try {
      await os.reset();
      return true;
    } catch (_) {
      // The device usually resets before it can reply; a timeout here means the
      // reset happened, not that it failed.
      return true;
    }
  }
}

/// Why a group-64 request did not succeed.
class HpiFailure {
  const HpiFailure._(this.command, this.message, {this.rc, this.group});

  factory HpiFailure.notConnected(HpiCommand command) =>
      HpiFailure._(command, 'control port not open');

  factory HpiFailure.transport(HpiCommand command, SmpException e) =>
      HpiFailure._(command,
          e.message.contains('timed out') ? 'no reply from the device' : e.message);

  factory HpiFailure.fromReply(HpiCommand command, int rc, int? group) =>
      HpiFailure._(command, 'rc $rc', rc: rc, group: group);

  final HpiCommand command;
  final String message;

  /// The device's result code, when it answered with an error.
  final int? rc;

  /// The group that raised [rc] (SMP v2), when reported.
  final int? group;

  /// The catalog entry for a group-64 error code.
  HpiErrorCode? get code =>
      rc != null && (group == null || group == hpiGroupId) ? hpiErrors[rc] : null;

  /// A short, user-facing description, e.g. `NO_MEDIA — no SD card present`.
  String get label {
    final c = code;
    if (c != null) return c.hint.isEmpty ? c.name : '${c.name} — ${c.hint}';
    if (rc != null) {
      final stock = hpiStockErrors[group ?? -1]?[rc];
      if (stock != null) return stock;
      if (rc == 8) return 'not supported by this firmware';
      return 'error $rc';
    }
    return message;
  }

  @override
  String toString() => '$command: $label';
}

/// The outcome of a group-64 request: the parsed reply, or why it failed.
class HpiResult<T> {
  const HpiResult.ok(T this.value) : failure = null;
  const HpiResult.failed(HpiFailure this.failure) : value = null;

  final T? value;
  final HpiFailure? failure;

  bool get ok => failure == null;

  HpiResult<R> map<R>(R Function(Map<Object?, Object?>) parse) {
    final f = failure;
    if (f != null) return HpiResult.failed(f);
    return HpiResult.ok(parse(value as Map<Object?, Object?>));
  }
}
