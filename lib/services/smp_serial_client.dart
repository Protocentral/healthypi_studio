// Copyright (c) 2025 ProtoCentral
// SPDX-License-Identifier: MIT

import 'dart:async';

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

  Future<HpiResult<DeviceInfoReply>> deviceInfo(
          {Duration timeout = const Duration(seconds: 3)}) =>
      _typed(Hpi.deviceInfo, DeviceInfoReply.fromMap, timeout: timeout);

  /// Versions of every processor, as the M7 reports them. An empty `m4fw`
  /// means the M4 has not bound IPC to the M7 (no vitals until it does).
  Future<HpiResult<FwVersionsReply>> fwVersions(
          {Duration timeout = const Duration(seconds: 3)}) =>
      _typed(Hpi.fwVersions, FwVersionsReply.fromMap, timeout: timeout);

  Future<HpiResult<TelemetryReply>> telemetry() =>
      _typed(Hpi.telemetry, TelemetryReply.fromMap);

  /// 0 = unlocked. A locked device rejects stream_start, sd_record_start and
  /// transfer_mode.
  Future<HpiResult<LockStateReply>> lockState() =>
      _typed(Hpi.lockState, LockStateReply.fromMap);

  // ---- connectivity (ESP32-C6 co-processor) ----

  /// Radio state as the M7 sees it. `link`: 0 off by request, 1 starting,
  /// 2 up, 3 fault.
  Future<HpiResult<ConnStatusReply>> connStatus() =>
      _typed(Hpi.connStatus, ConnStatusReply.fromMap);

  /// Power the co-processor and bring up [radios] (bit 0 Wi-Fi, bit 1 BLE).
  /// The reply means "accepted", not "radio up": poll [connStatus].
  Future<HpiResult<ConnEnableReply>> connEnable({int radios = 0x01}) => _typed(
      Hpi.connEnable, ConnEnableReply.fromMap,
      payload: connEnableRequest(radios: radios));

  /// Radios down and the co-processor back into reset.
  Future<HpiResult<ConnDisableReply>> connDisable() =>
      _typed(Hpi.connDisable, ConnDisableReply.fromMap);

  Future<HpiResult<WifiStatusReply>> wifiStatus() =>
      _typed(Hpi.wifiStatus, WifiStatusReply.fromMap);

  /// Store network credentials. Unlock-gated.
  Future<HpiResult<WifiSetReply>> wifiSet(String ssid, String password) =>
      _typed(Hpi.wifiSet, WifiSetReply.fromMap,
          payload: wifiSetRequest(ssid: ssid, pw: password));

  Future<HpiResult<WifiForgetReply>> wifiForget() =>
      _typed(Hpi.wifiForget, WifiForgetReply.fromMap);

  /// Start the provisioning access point. Not unlock-gated: it is how a
  /// locked device gets online.
  Future<HpiResult<WifiSoftapReply>> wifiSoftap() =>
      _typed(Hpi.wifiSoftap, WifiSoftapReply.fromMap);

  // ---- RTC (stock os group) ----

  static const int _osGroup = 0;
  static const int _osDatetime = 4;

  /// Read the device clock. RTC_NOT_SET (os rc 4) means it has never been
  /// written, and recordings are stamped with time 0 until it is.
  Future<HpiResult<String?>> readDatetime() async {
    final r = await _os0(SmpOp.readReq, const {});
    return r.ok ? HpiResult.ok(hpiStr(r.value!['datetime'])) : HpiResult.failed(r.failure!);
  }

  /// Set the device clock to [when], as local time with an explicit offset —
  /// the form the firmware's own host tool writes.
  Future<HpiResult<void>> writeDatetime(DateTime when) =>
      _os0(SmpOp.writeReq, {'datetime': isoWithOffset(when)});

  Future<HpiResult<Map<String, Object?>>> _os0(
      SmpOp op, Map<String, Object?> payload) async {
    const cmd = HpiCommand(_osDatetime, 'os datetime', read: true, write: true);
    final SmpClient? client = _client;
    if (client == null || !isOpen) {
      return HpiResult.failed(HpiFailure.notConnected(cmd));
    }
    client.timeout = const Duration(seconds: 3);
    try {
      final rsp = await client.send(
          op: op, group: _osGroup, id: _osDatetime, payload: payload);
      final rc = rsp.rc;
      if (rc != null) {
        return HpiResult.failed(
            HpiFailure.fromReply(cmd, rc, rsp.errGroup ?? _osGroup));
      }
      return HpiResult.ok(rsp.payload);
    } on SmpException catch (e) {
      return HpiResult.failed(HpiFailure.transport(cmd, e));
    }
  }

  /// `2026-10-01T16:20:05+05:30`.
  static String isoWithOffset(DateTime when) {
    final t = when.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final off = t.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final mins = off.inMinutes.abs();
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
        'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
        '$sign${two(mins ~/ 60)}:${two(mins % 60)}';
  }

  // ---- M4 update (group 64, signed builds only) ----

  /// Call first: the M4 update service's state, and whether it requires a
  /// signature. Fails with rc 8 (ENOTSUP) on a build without the service.
  Future<HpiResult<M4fwStatusReply>> m4fwStatus() =>
      _typed(Hpi.m4fwStatus, M4fwStatusReply.fromMap);

  /// Discard a stale upload (state RECEIVING or FAILED).
  Future<HpiResult<void>> m4fwAbort() => request(Hpi.m4fwAbort);

  /// Start an upload. There is no resume: an interrupted upload restarts at 0.
  Future<HpiResult<void>> m4fwBegin(
          {required int len, required List<int> sha, List<int>? sig}) =>
      request(Hpi.m4fwBegin,
          payload: m4fwBeginRequest(len: len, sha: sha, sig: sig));

  /// One chunk; the reply's `off` is the next offset the device expects.
  Future<HpiResult<M4fwChunkReply>> m4fwChunk(int off, List<int> data) =>
      _typed(Hpi.m4fwChunk, M4fwChunkReply.fromMap,
          payload: m4fwChunkRequest(off: off, data: data));

  /// Verify the digest and signature, then erase and write bank 2. Takes
  /// several seconds before the device replies; a short timeout would report
  /// failure for an update that succeeded.
  Future<HpiResult<M4fwCommitReply>> m4fwCommit(
          {Duration timeout = const Duration(seconds: 30)}) =>
      _typed(Hpi.m4fwCommit, M4fwCommitReply.fromMap, timeout: timeout);

  /// Whether this firmware can reboot into MCUboot serial recovery (`av`).
  Future<HpiResult<EnterRecoveryReply>> recoveryState() =>
      _typed(Hpi.enterRecovery, EnterRecoveryReply.fromMap);

  /// Arm recovery and reset: the device comes back as a single CDC port named
  /// "HealthyPi 6 Recovery", and group 64 is gone until it is reflashed.
  Future<HpiResult<EnterRecoveryWriteReply>> enterRecovery() => _typed(
        Hpi.enterRecovery,
        EnterRecoveryWriteReply.fromMap,
        payload: enterRecoveryWriteRequest(arm: true, rst: true),
        write: true,
      );

  /// Arm or disarm USB Transfer Mode. Arming re-enumerates USB, so the reply
  /// may be the last thing this link carries.
  Future<HpiResult<TransferModeWriteReply>> transferMode(bool on) => _typed(
        Hpi.transferMode,
        TransferModeWriteReply.fromMap,
        payload: transferModeWriteRequest(on: on),
        write: true,
      );

  // ---- firmware update (M7, MCUboot img group) ----

  /// Upload [image] to MCUboot image 0. The device routes it to that image's
  /// secondary slot; there is no image 1 on this board. Chunks are driven by
  /// the offset the device returns. [onProgress] reports (bytesSent, total).
  /// Returns null on success, or why it failed.
  Future<String?> imageUpload(
    Uint8List image, {
    void Function(int sent, int total)? onProgress,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final ImgMgmt? img = _img;
    final SmpClient? client = _client;
    if (img == null || client == null || !isOpen) return 'control port not open';
    client.timeout = timeout;
    try {
      await img.upload(image, imageIndex: 0, onProgress: onProgress);
      return null;
    } on SmpException catch (e) {
      debugPrint('❌ OTA upload failed: $e');
      return e.message;
    }
  }

  /// Mark the uploaded image pending, so MCUboot installs it on the next boot.
  /// [hash] is the MCUboot image hash (`McuImageInfo.hash`), not the file's
  /// SHA-256. Returns null on success, or why it failed.
  Future<String?> imageMarkPending(
    List<int> hash, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final ImgMgmt? img = _img;
    final SmpClient? client = _client;
    if (img == null || client == null || !isOpen) return 'control port not open';
    client.timeout = timeout;
    try {
      await img.test(hash);
      return null;
    } on SmpException catch (e) {
      debugPrint('❌ OTA mark pending failed: $e');
      return e.message;
    }
  }

  /// Read the device's image slots, or null if the img group did not answer
  /// (a development build has no bootloader and no img group).
  Future<List<ImageSlot>?> imageStates({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final ImgMgmt? img = _img;
    final SmpClient? client = _client;
    if (img == null || client == null || !isOpen) return null;
    client.timeout = timeout;
    try {
      return await img.list();
    } on SmpException catch (e) {
      debugPrint('❌ image list failed: $e');
      return null;
    }
  }

  /// Read the device's image slots — version, hash and the bootable / pending
  /// / confirmed / active flags. Empty if the read fails.
  Future<List<ImageSlot>> imageList({
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      await imageStates(timeout: timeout) ?? const <ImageSlot>[];

  /// The running image, if the device reports one.
  Future<ImageSlot?> runningImage() async {
    for (final ImageSlot slot in await imageList()) {
      if (slot.active) return slot;
    }
    return null;
  }

  /// `os echo`. CDC1 (and MCUboot recovery) answers; CDC0 never does, which
  /// is how the control port is told apart from the data port.
  Future<bool> echo({Duration timeout = const Duration(milliseconds: 1500)}) async {
    final OsMgmt? os = _os;
    final SmpClient? client = _client;
    if (os == null || client == null || !isOpen) return false;
    client.timeout = timeout;
    try {
      return await os.echo('hpi') == 'hpi';
    } on SmpException {
      return false;
    }
  }

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
      if (rc == 13) return 'the device is locked';
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
