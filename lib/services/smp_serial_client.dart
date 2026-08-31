// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart';

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
/// which are vendor-specific, and the two-image update sequence.
///
/// Two modes, unchanged from the hand-rolled client this replaces:
///  - Fire-and-forget writes for the group-64 commands (stream / record /
///    transfer-mode). The device does not answer them, so nothing is awaited.
///  - Request/response transactions for **firmware OTA**, which need the
///    device's reply — the next offset it expects, and the result code.
class SmpSerialClient {
  ByteStreamSmpTransport? _transport;
  SmpClient? _client;

  /// Sequence numbers for the fire-and-forget group-64 writes. `SmpClient`
  /// keeps its own counter for the requests it matches replies to; these are
  /// never answered, so the two spaces cannot collide in a way that matters.
  int _controlSeq = 0;
  ImgMgmt? _img;
  OsMgmt? _os;

  /// HealthyPi's vendor management group.
  static const int controlGroup = 64;

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

  // ---- group 64 control commands (fire-and-forget) ----

  /// The device does not answer these, so there is nothing to await. Returns
  /// whether the request reached the wire.
  bool _writeRequest(int id, Map<String, Object?> payload) {
    final ByteStreamSmpTransport? transport = _transport;
    if (transport == null || !isOpen) return false;
    try {
      final SmpMessage req = SmpMessage(
        op: SmpOp.writeReq,
        group: controlGroup,
        id: id,
        seq: _controlSeq = (_controlSeq + 1) & 0xFF,
        payload: payload,
      );
      unawaited(transport.write(req.toBytes()).catchError((Object e) {
        debugPrint('❌ SMP write failed: $e');
      }));
      return true;
    } catch (e) {
      debugPrint('❌ SMP write failed: $e');
      return false;
    }
  }

  bool streamStart({int ch = 0x03, int ann = 0x00}) =>
      _writeRequest(0x20, <String, Object?>{'ch': ch, 'ann': ann});

  bool streamStop() => _writeRequest(0x21, const <String, Object?>{});

  bool sdRecordStart({String? name}) => _writeRequest(
        0x61,
        (name == null || name.isEmpty)
            ? const <String, Object?>{}
            : <String, Object?>{'name': name},
      );

  bool sdRecordStop() => _writeRequest(0x62, const <String, Object?>{});

  bool transferMode(bool on) =>
      _writeRequest(0x69, <String, Object?>{'on': on});

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
