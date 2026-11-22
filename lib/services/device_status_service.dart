import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/hpi_core.dart';
import '../protocol/hpi_group64.g.dart';
import 'firmware_update_service.dart';
import 'smp_serial_client.dart';
import 'usb_serial_service.dart';

/// What the connected HealthyPi 6 reports about itself, read over the control
/// port (CDC1): identity, firmware versions, telemetry, stream and SD status,
/// lock state, and the RTC.
///
/// Identity is read once when the control port opens; status is polled every
/// few seconds while it stays open, except during a firmware update. Every
/// value is what the device reported — a field it did not send stays null and
/// renders as an em dash.
class DeviceStatusService extends ChangeNotifier {
  DeviceStatusService(this._usb, this._fw) {
    _usb.addListener(_onUsb);
    _onUsb();
  }

  final UsbSerialService _usb;
  final FirmwareUpdateService _fw;

  static const Duration pollInterval = Duration(seconds: 5);

  DeviceInfoReply? _info;
  FwVersionsReply? _versions;
  Map<Object?, Object?>? _versionsRaw;
  TelemetryReply? _telemetry;
  StreamStatusReply? _stream;
  SdStatusReply? _sd;
  int? _lockState;
  ConnStatusReply? _conn;
  WifiStatusReply? _wifi;
  String? _clock;
  bool _clockSetByStudio = false;
  String? _clockError;

  DeviceInfoReply? get info => _info;
  FwVersionsReply? get versions => _versions;

  /// A HealthyPi Core's application firmware version, from `fw_versions`
  /// (see [HpiCoreVersions]), else `device_info`. Null when not reported.
  String? get coreFirmware =>
      HpiCoreVersions.firmware(_versionsRaw) ?? _info?.fw;

  /// A HealthyPi Core's ESP32-C6 version, when `fw_versions` reports one.
  String? get coreCoprocessorFirmware =>
      HpiCoreVersions.coprocessor(_versionsRaw) ?? _info?.espfw;
  TelemetryReply? get telemetry => _telemetry;
  StreamStatusReply? get stream => _stream;
  SdStatusReply? get sd => _sd;

  /// Co-processor link and radios. The radios are off at boot.
  ConnStatusReply? get conn => _conn;
  WifiStatusReply? get wifi => _wifi;

  /// The device's RTC as it reports it, or null if unread / unset.
  String? get clock => _clock;

  /// Studio set the RTC on connect because it had never been set.
  bool get clockSetByStudio => _clockSetByStudio;
  String? get clockError => _clockError;

  /// Known only once read; null means not reported, and is treated as not
  /// locked. `lock_state` 0 is LOCKED and 1 UNLOCKED (HealthyPi 6 firmware
  /// `enum hpi_lock_state`). A HealthyPi Core does not implement it.
  bool? get locked => _lockState == null ? null : _lockState == 0;

  bool _wasOpen = false;
  bool _reading = false;
  Timer? _poll;

  void _onUsb() {
    final open = _usb.controlConnected;
    if (open && !_wasOpen) {
      _wasOpen = true;
      unawaited(_onControlOpened());
      _poll?.cancel();
      _poll = Timer.periodic(pollInterval, (_) => unawaited(refreshStatus()));
    } else if (!open && _wasOpen) {
      _wasOpen = false;
      _poll?.cancel();
      _poll = null;
      _clear();
    }
  }

  Future<void> _onControlOpened() async {
    await refreshIdentity();
    await _syncClock();
    await refreshStatus();
  }

  void _clear() {
    _info = null;
    _versions = null;
    _versionsRaw = null;
    _telemetry = null;
    _stream = null;
    _sd = null;
    _lockState = null;
    _conn = null;
    _wifi = null;
    _clock = null;
    _clockSetByStudio = false;
    _clockError = null;
    notifyListeners();
  }

  Future<void> refreshIdentity() async {
    if (_fw.busy || !_usb.controlConnected) return;
    final c = _usb.control;
    _info = (await c.deviceInfo()).value ?? _info;
    final v = await c.request(Hpi.fwVersions);
    if (v.ok) {
      _versionsRaw = v.value;
      _versions = FwVersionsReply.fromMap(v.value!);
    }
    // A Core answers lock_state with ENOTSUP; don't spend a round trip on it.
    if (!_usb.isCore) {
      _lockState = (await c.lockState()).value?.state ?? _lockState;
    }
    notifyListeners();
  }

  /// Poll the status reads. Skipped during a firmware update, and while a
  /// previous poll is still in flight.
  Future<void> refreshStatus() async {
    if (_reading || _fw.busy || !_usb.controlConnected) return;
    _reading = true;
    try {
      final c = _usb.control;
      _telemetry = (await c.telemetry()).value ?? _telemetry;
      _stream = (await c.streamStatus()).value ?? _stream;
      _sd = (await c.sdStatus()).value ?? _sd;
      _conn = (await c.connStatus()).value ?? _conn;
      // The Core implements none of lock_state, wifi_status or an M4.
      if (!_usb.isCore) {
        _lockState = (await c.lockState()).value?.state ?? _lockState;
        // wifi_status answers HW_FAULT while the co-processor is held in reset.
        final w = await c.wifiStatus();
        _wifi = w.value ?? (w.failure?.rc != null ? null : _wifi);
        // The M4 version arrives over IPC a few seconds after boot.
        if ((_versions?.m4fw ?? '').isEmpty) {
          final v = await c.request(Hpi.fwVersions);
          if (v.ok) {
            _versionsRaw = v.value;
            _versions = FwVersionsReply.fromMap(v.value!);
          }
        }
      }
      notifyListeners();
    } finally {
      _reading = false;
    }
  }

  /// The STM32 RTC reports no time at all until it has been written once, and
  /// until then every recording is stamped with time 0. Set it from this
  /// machine in that case only; a clock that is already set is left alone.
  Future<void> _syncClock() async {
    // The Core's group 0 has echo, reset, params and os info, not datetime;
    // its RTC (RV-3028) is not exposed over SMP yet.
    if (!_usb.controlConnected || _usb.isCore) return;
    final c = _usb.control;
    final read = await c.readDatetime();
    if (read.ok) {
      _clock = read.value;
      notifyListeners();
      return;
    }
    final f = read.failure!;
    if (f.rc != 4) {
      _clockError = f.label;
      notifyListeners();
      return;
    }
    final write = await c.writeDatetime(DateTime.now());
    if (!write.ok) {
      _clockError = 'RTC not set, and setting it failed: ${write.failure!.label}';
    } else {
      _clockSetByStudio = true;
      _clock = (await c.readDatetime()).value;
      debugPrint('🔄 Device RTC was unset; set to $_clock');
    }
    notifyListeners();
  }

  // ---- connectivity actions; each returns the failure, or null ----

  Future<HpiFailure?> _act(Future<HpiResult<Object?>> Function() call) async {
    if (!_usb.controlConnected) return null;
    final r = await call();
    await refreshStatus();
    return r.failure;
  }

  Future<HpiFailure?> enableWifiRadio() =>
      _act(() => _usb.control.connEnable(radios: 0x01));
  Future<HpiFailure?> disableRadios() => _act(_usb.control.connDisable);
  Future<HpiFailure?> setWifiNetwork(String ssid, String password) =>
      _act(() => _usb.control.wifiSet(ssid, password));
  Future<HpiFailure?> forgetWifiNetwork() => _act(_usb.control.wifiForget);
  Future<HpiFailure?> startSoftAp() => _act(_usb.control.wifiSoftap);

  @override
  void dispose() {
    _poll?.cancel();
    _usb.removeListener(_onUsb);
    super.dispose();
  }
}
