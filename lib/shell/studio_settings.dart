import 'package:flutter/material.dart';

/// How dense the time grid behind a trace is drawn.
enum GridDensityPref { fine, standard, off }

/// Mains frequency drives every notch stage on every modality — set once per
/// region rather than per filter.
enum MainsFrequency {
  fifty(50),
  sixty(60);

  const MainsFrequency(this.hz);
  final int hz;
}

/// Session metadata, lightweight by design: a subject/session pill set once in
/// the top bar and stamped into every recording and export. No wizard, no modal.
class StudioSession extends ChangeNotifier {
  String _sessionId = 'S-001';
  String _subject = '';
  String _protocolNote = '';

  String get sessionId => _sessionId;
  String get subject => _subject;
  String get protocolNote => _protocolNote;

  /// The pill text in the app bar: session id, then subject when one is set.
  String get pillLabel => _subject.isEmpty ? _sessionId : '$_sessionId · $_subject';

  bool get hasSubject => _subject.isNotEmpty;

  set sessionId(String value) {
    if (_sessionId == value) return;
    _sessionId = value;
    notifyListeners();
  }

  set subject(String value) {
    if (_subject == value) return;
    _subject = value;
    notifyListeners();
  }

  set protocolNote(String value) {
    if (_protocolNote == value) return;
    _protocolNote = value;
    notifyListeners();
  }
}

/// App preferences that the chrome and every screen read.
///
/// Held in memory for this release — the app ships no preferences store yet, and
/// the Settings screen states that preferences apply immediately.
class StudioSettings extends ChangeNotifier {
  // Appearance
  ThemeMode _themeMode = ThemeMode.dark;
  GridDensityPref _gridDensity = GridDensityPref.standard;
  double _traceThickness = 1.8;
  bool _reduceMotion = false;

  // Acquisition
  double _sweepSpeedMmPerSec = 25;
  double _windowSeconds = 10;
  bool _autoStartOnConnect = true;
  MainsFrequency _mains = MainsFrequency.fifty;
  bool _metricUnits = true;

  // Data & storage
  /// Describes what `RecordingEngine.generateDefaultFilename()` actually
  /// produces. It is shown read-only in Settings, so it has to track the engine
  /// rather than describe a scheme nothing implements.
  String _fileNamePattern = 'recording_{session}_{date}_{time}.hpd';
  bool _autoExportAfterRecording = false;
  bool _keepRawInExports = true;

  ThemeMode get themeMode => _themeMode;
  GridDensityPref get gridDensity => _gridDensity;
  double get traceThickness => _traceThickness;
  bool get reduceMotion => _reduceMotion;

  double get sweepSpeedMmPerSec => _sweepSpeedMmPerSec;
  double get windowSeconds => _windowSeconds;
  bool get autoStartOnConnect => _autoStartOnConnect;
  MainsFrequency get mains => _mains;
  bool get metricUnits => _metricUnits;

  String get fileNamePattern => _fileNamePattern;
  bool get autoExportAfterRecording => _autoExportAfterRecording;
  bool get keepRawInExports => _keepRawInExports;

  /// Grid divisions across the visible window for the current density.
  int get gridDivisions => switch (_gridDensity) {
        GridDensityPref.fine => 20,
        GridDensityPref.standard => 10,
        GridDensityPref.off => 0,
      };

  /// The device reports temperature in °C; this is the only quantity in the app
  /// whose unit the Units setting changes. Value and label are read together so
  /// a converted number can never be drawn under the wrong unit.
  double temperature(double celsius) =>
      _metricUnits ? celsius : celsius * 9 / 5 + 32;

  String get temperatureUnit => _metricUnits ? '°C' : '°F';

  set themeMode(ThemeMode value) => _set(() => _themeMode = value, _themeMode == value);
  set gridDensity(GridDensityPref value) =>
      _set(() => _gridDensity = value, _gridDensity == value);
  set traceThickness(double value) =>
      _set(() => _traceThickness = value, _traceThickness == value);
  set reduceMotion(bool value) =>
      _set(() => _reduceMotion = value, _reduceMotion == value);
  set sweepSpeedMmPerSec(double value) =>
      _set(() => _sweepSpeedMmPerSec = value, _sweepSpeedMmPerSec == value);
  set windowSeconds(double value) =>
      _set(() => _windowSeconds = value, _windowSeconds == value);
  set autoStartOnConnect(bool value) =>
      _set(() => _autoStartOnConnect = value, _autoStartOnConnect == value);
  set mains(MainsFrequency value) => _set(() => _mains = value, _mains == value);
  set metricUnits(bool value) =>
      _set(() => _metricUnits = value, _metricUnits == value);
  set fileNamePattern(String value) =>
      _set(() => _fileNamePattern = value, _fileNamePattern == value);
  set autoExportAfterRecording(bool value) =>
      _set(() => _autoExportAfterRecording = value,
          _autoExportAfterRecording == value);
  set keepRawInExports(bool value) =>
      _set(() => _keepRawInExports = value, _keepRawInExports == value);

  void _set(VoidCallback apply, bool unchanged) {
    if (unchanged) return;
    apply();
    notifyListeners();
  }
}
