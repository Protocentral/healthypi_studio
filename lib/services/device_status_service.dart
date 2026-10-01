import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/hpi_group64.g.dart';
import 'firmware_update_service.dart';
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
  TelemetryReply? _telemetry;
  StreamStatusReply? _stream;
  SdStatusReply? _sd;
  int? _lockState;
  String? _clock;
  bool _clockSetByStudio = false;
  String? _clockError;

  DeviceInfoReply? get info => _info;
  FwVersionsReply? get versions => _versions;
  TelemetryReply? get telemetry => _telemetry;
  StreamStatusReply? get stream => _stream;
  SdStatusReply? get sd => _sd;

  /// The device's RTC as it reports it, or null if unread / unset.
  String? get clock => _clock;

  /// Studio set the RTC on connect because it had never been set.
  bool get clockSetByStudio => _clockSetByStudio;
  String? get clockError => _clockError;

  /// Known only once read; null means not reported.
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
    _telemetry = null;
    _stream = null;
    _sd = null;
    _lockState = null;
    _clock = null;
    _clockSetByStudio = false;
    _clockError = null;
    notifyListeners();
  }

  Future<void> refreshIdentity() async {
    if (_fw.busy || !_usb.controlConnected) return;
    final c = _usb.control;
    _info = (await c.deviceInfo()).value ?? _info;
    _versions = (await c.fwVersions()).value ?? _versions;
    _lockState = (await c.lockState()).value?.state ?? _lockState;
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
      _lockState = (await c.lockState()).value?.state ?? _lockState;
      // The M4 version arrives over IPC a few seconds after boot.
      if ((_versions?.m4fw ?? '').isEmpty) {
        _versions = (await c.fwVersions()).value ?? _versions;
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
    if (!_usb.controlConnected) return;
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

  @override
  void dispose() {
    _poll?.cancel();
    _usb.removeListener(_onUsb);
    super.dispose();
  }
}
