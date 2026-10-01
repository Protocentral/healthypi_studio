import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mcumgr_dart/mcumgr_dart.dart' show McuImageInfo;

import 'firmware/bundle.dart';
import 'firmware/firmware_updater.dart';
import 'usb_serial_service.dart';

/// What the user picked to install.
enum FirmwareSource { none, bundle, rawM7 }

/// Firmware update over the USB control port (CDC1), for the Device screen.
///
/// Owns the selection, the progress and the log; the update logic itself is
/// [FirmwareUpdater]. Lives at shell level so an update keeps running if the
/// user navigates away from the Device screen.
class FirmwareUpdateService extends ChangeNotifier {
  FirmwareUpdateService(this._usb);

  final UsbSerialService _usb;

  /// MCUboot copies the image and the M4 rebinds IPC ~7-10 s after a reset;
  /// asking before then reads a half-booted device.
  static const Duration resetSettle = Duration(seconds: 12);
  static const Duration reconnectBudget = Duration(seconds: 45);

  FirmwareSource _source = FirmwareSource.none;
  String? _path;
  FirmwareBundle? _bundle;
  Uint8List? _rawImage;
  String? _rawVersion;
  String? _selectionError;

  bool _busy = false;
  UpdateProgress _progress = const UpdateProgress(UpdateStage.idle, 0, 0);
  final List<String> _log = [];
  UpdateOutcome? _outcome;
  String? _error;

  FirmwareSource get source => _source;
  String? get path => _path;
  FirmwareBundle? get bundle => _bundle;
  String? get rawVersion => _rawVersion;
  String? get selectionError => _selectionError;
  bool get busy => _busy;
  UpdateProgress get progress => _progress;
  List<String> get log => List.unmodifiable(_log);
  UpdateOutcome? get outcome => _outcome;
  String? get error => _error;
  bool get canInstall =>
      !_busy && _usb.controlConnected && _source != FirmwareSource.none;

  /// Load [path]: a `.hpifw` bundle (verified now, before anything is sent),
  /// or a raw signed M7 `.bin`.
  Future<void> select(String path) async {
    _path = path;
    _bundle = null;
    _rawImage = null;
    _rawVersion = null;
    _selectionError = null;
    _outcome = null;
    _error = null;
    _source = FirmwareSource.none;
    try {
      final bytes = await File(path).readAsBytes();
      if (path.toLowerCase().endsWith('.hpifw')) {
        _bundle = FirmwareBundle.open(bytes);
        _source = FirmwareSource.bundle;
      } else {
        final info = McuImageInfo.parse(bytes);
        if (info.sha256 == null || !info.verifyHash(bytes)) {
          throw const FormatException('its image hash does not match its content');
        }
        _rawImage = bytes;
        _rawVersion = info.version.toString();
        _source = FirmwareSource.rawM7;
      }
    } on BundleException catch (e) {
      _selectionError = e.message;
    } on FormatException catch (e) {
      _selectionError = 'Not an MCUboot M7 image: ${e.message}';
    } on FileSystemException catch (e) {
      _selectionError = 'Could not read the file: ${e.message}';
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_busy) return;
    _source = FirmwareSource.none;
    _path = null;
    _bundle = null;
    _rawImage = null;
    _rawVersion = null;
    _selectionError = null;
    notifyListeners();
  }

  Future<void> install() async {
    if (!canInstall) return;
    _busy = true;
    _log.clear();
    _outcome = null;
    _error = null;
    notifyListeners();

    final updater = FirmwareUpdater(
      client: () => _usb.control,
      resetAndReconnect: _resetAndReconnect,
      log: (line) {
        debugPrint('🔄 fw: $line');
        _log.add(line);
        notifyListeners();
      },
      onProgress: (p) {
        _progress = p;
        notifyListeners();
      },
    );
    try {
      _outcome = _source == FirmwareSource.bundle
          ? await updater.applyBundle(_bundle!)
          : await updater.applyM7Image(_rawImage!);
    } on UpdateException catch (e) {
      _error = e.message;
      _progress = const UpdateProgress(UpdateStage.failed, 0, 0);
    } catch (e) {
      _error = 'Update error: $e';
      _progress = const UpdateProgress(UpdateStage.failed, 0, 0);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Reset, then wait for the control port to answer again.
  Future<bool> _resetAndReconnect() async {
    _usb.expectReset();
    await _usb.control.osReset();
    await Future<void>.delayed(resetSettle);
    final deadline = DateTime.now().add(reconnectBudget);
    while (DateTime.now().isBefore(deadline)) {
      if (_usb.controlConnected) {
        final r = await _usb.control
            .fwVersions(timeout: const Duration(seconds: 2));
        if (r.ok) return true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }
}
