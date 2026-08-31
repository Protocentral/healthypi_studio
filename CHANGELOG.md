# Changelog

All notable changes to the HealthyPi Studio project will be documented in this file.

## [Unreleased] — pre-1.0 fixes

### Fixed

- **A `ProviderNotFoundException` on every launch.** `UsbSerialService`'s
  provider `create` wired the firmware-version listener with
  `context.read<RecordingEngine>()`, but `RecordingEngine` was registered
  *lower down the same `MultiProvider` list* — and `create` gets the
  `MultiProvider`'s own context, which sees only the providers above it. The
  post-frame deferral did not help: position, not timing, was the problem. The
  scheduler caught the throw so the app kept running, which is why it went
  unnoticed; the cost was that `deviceFirmwareVersion` was never wired, so
  every recording header recorded an empty firmware version. `RecordingEngine`
  is now registered before the transports that read it.

### Corrected

- **EEG is not live, and the decode is unverified.** An earlier development
  commit landed the DBLK channel-5 decode under the claim that live EEG reaches
  the UI. That overstates what it did. The DBLK
  channel-5 decode is correct against `struct hp6_eeg_sample` and its in-code
  comments are accurate, but no board can exercise it today:
  `hpi_stream_enable()` returns `-ENOTSUP` for any `stream_start` carrying the
  EEG bit, `mod_eeg.c` compiles its ADS1299 path out without
  `CONFIG_SENSOR_ADS1299` (set nowhere in `app_m7`), and Studio's own
  auto-start requests `ch: 0x03` — ECG and PPG only. A HealthyPi 6 attached
  during this check streamed no channel-5 blocks. The decode stays, documented
  as inert; README and DEVELOPER_GUIDE now say so.

## [Unreleased] — CSV is the only export format

### Removed

- **EDF+, HDF5 and MATLAB export.** They were listed in the export panel and
  disabled as *not yet available* — three promises the code could not keep.
  Gone from the UI, so the panel now states the format (CSV) instead of
  offering a choice of one. With them go `lib/services/edf_exporter.dart`,
  `EDFExportOptions`, `RecordingExportService.exportToEDF` (which only ever
  set `'EDF export not yet fully implemented'` and returned null),
  `EventMarkerForExport.toEDFAnnotation`, and the `ExportFormat` enum with its
  `available` flag. They pre-date the first public commit and are not in this
  repository's history.
- The README's claim that CSV export is validated "raw or filtered". Filtered
  export has never existed; the switch that offered it is disabled and says so.

## [Unreleased] — post-revamp review fixes

Fixes from a code review of the revamp, plus the dead-code decision that had been
left open by the pre-launch review.

### Fixed

- **Global shortcuts no longer fire while you are typing.** `Space`, `R`, `M`,
  `F` and `1`–`8` are bound at shell level, and Flutter hands character keys to
  ancestor handlers even when a `TextField` has the caret — so typing a WiFi host,
  a subject name or an OTA hostname was starting recordings, freezing the trace
  and navigating away mid-word. The handler now stands down for text entry.
- **Waveforms advance at frame rate again.** `ChannelController` deliberately does
  not notify per sample, so each trace only repainted when some unrelated widget
  happened to rebuild — about once a second with no device attached, and in device
  mode only because the status line was watching the parser and rebuilding the
  entire shell on every parse batch. Each trace now repaints off its own `Ticker`
  watching the ring buffer's write cursor, and the status line reads the existing
  1 Hz link snapshot instead of the parser.
- **The SMP serial reader is closed**, not just dereferenced, when the control
  port closes.
- **BLE commands no longer vanish silently** — `_sendCommand` says when it is
  dropping a command for want of a characteristic (BLE is connect-only today).
- `print()` → `debugPrint()` in `recording_file_service.dart` and
  `recording_export_service.dart`.
- The Live HRV card no longer prints `pNN50 0%` for a field the firmware does not
  report; it omits it, as DESIGN_SYSTEM §8 requires.

### Removed

- **Every unwired subsystem**, deleted rather than quarantined: session/subject
  management (`session_manager`, `session_validator`, `subject_database`), quality
  monitoring (`quality_monitor`, `quality_assessor`), `services/ecg_analysis/`,
  `recording_file_manager`, `eeg_filter_service`, `filtered_export_service`, their
  exclusive models, and `assets/templates/`. All of it pre-dates the first
  public commit and is not in this repository's history.
- **Five unused dependencies**: `fl_chart` and `syncfusion_flutter_charts` (nothing
  has imported a chart library since the waveforms became Canvas painters),
  `sqflite`, `json_serializable`, `universal_io`. `intl` was promoted to a direct
  dependency — it had been arriving transitively through Syncfusion.

### Notes

- `flutter analyze`: 0 errors, 0 warnings (was 11 warnings).
- `flutter test`: 87 passing / 25 failing. The 25 pre-date the revamp (verified
  against the pre-revamp tree) and sit on the dead legacy OpenView
  parse path.
- Deleting `ecg_analysis/` means real `pNN50`/`meanRr` now needs a fresh
  implementation rather than a wiring job.

## [Unreleased] — UI revamp

Full rebuild of the interface against the **HealthyPi Studio UI Revamp** design
project. See [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) for the resulting
system.

### Added

- **A design token layer.** `HpiPalette` ships as a `ThemeExtension` for both
  themes, with a semantic trace ramp, a nine-step type scale, and fixed chrome
  metrics. Screens read `context.hpi` and `HpiText.*`; no literal hex, no bare
  `TextStyle`.
- **A light theme**, on the same tokens with an inverted ramp and traces darkened
  one step. Switch in the top bar and in Settings → Appearance.
- **Four bundled type families** — Saira, Jost, Montserrat, JetBrains Mono — as
  static instances, so the app renders identically offline.
- **Brand assets with defined roles** (`assets/brand/`): theme-correct wordmark in
  the app bar, mono-blue lockup on Device, mono-white on Connect, round mark in
  About. `HpiWordmark` / `HpiMonoMark` pick the right file.
- **One shell for every screen** — top device bar, labelled 96px rail, one status
  line — plus a component kit of ~35 widgets in `lib/widgets/hpi/`.
- **Focus mode** on Live: traces full-bleed, vitals as a floating HUD, controls in
  a bottom capsule. A display mode, not a separate shell; `Esc` exits.
- **New screens**: Link health (throughput, gap timeline, per-stream
  expected-vs-actual rate, event log), Connect (USB/BLE/WiFi in one list as
  Live's empty state), and Settings (appearance, acquisition, session metadata,
  shortcuts, about).
- **Global keyboard shortcuts**: `Space` freeze, `R` record, `F` focus, `M`
  marker, `1`–`8` jump to screen, `Esc` exit focus / close dock.
- **A session pill** in the top bar, authored once in Settings and stamped into
  recordings and exports.
- `LiveDataPump` — acquisition (channel controller, transport bridge, vitals
  trends) now lives at shell level, so a running recording survives navigation.
- `HpiWaveTrace` — a trace painter that reads the sample ring buffer in place and
  decimates to canvas width, removing per-frame list copies from the 500 Hz path.
- Shell, navigation and theme tests in `test/shell_test.dart`.

### Changed

- Screens no longer push their own `Scaffold`, so the rail can no longer vanish
  (it did on two screens).
- The 320px control panel is now a 52px inspector dock that expands on demand.
- Vitals moved out of the footer into a strip across the top of the dashboard.
- Trace colours moved from saturated primaries (`#FF0000` / `#00FF00` / `#00FFFF`)
  to the semantic ramp, so the three ECG leads read as one modality.
- `ThroughputMonitor` is now fed from the acquisition path; Link health reported
  zeroes before.
- Firmware update is a card on the Device screen rather than its own screen.
- Bluetooth is no longer probed at startup — it is probed when the user asks for
  it, so launching the app raises no permission prompt.

### Fixed

- The filter screen ran its designs at a hardcoded 1000 Hz sampling rate; each
  modality now uses its real rate (ECG/respiration 500 Hz, EEG 250 Hz, PPG 125 Hz).
- `session_manager.dart` referenced an undefined `path` prefix and did not compile.
- `port_name_resolver.dart` imported a package absent from `pubspec.yaml`; it was
  unreferenced and has been removed.

### Removed

- 13 superseded screens and 24 widgets belonging to them, `lib/examples/`, and
  `connection_panel.dart.bak`.

### Known limits, stated in the UI

CSV is the only implemented export; HRV `pNN50` and mean R-R are reported as zero
by the firmware; EEG reports lead-off, not impedance; BLE connects but does not
yet stream. Each of these says so on screen rather than showing a plausible
number. See [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) §8.

## [1.0.0] - 2025-11-20

### Initial Release

#### Added
- ✅ Complete Flutter 3 application structure for multi-platform support
- ✅ Material 3 design system with custom dark blue and orange theme
- ✅ Multi-platform support: macOS, Windows, Linux, and Android
- ✅ Bottom navigation with three main tabs: Dashboard, Connect, and Settings
- ✅ Bluetooth Low Energy (BLE) service for wireless device connections
  - Device scanning and discovery
  - Connection management with status indicators
  - Service and characteristic discovery
  - Data subscription and notification handling
  - Automatic permission requests
- ✅ USB Serial service for wired device connections
  - USB device detection and listing
  - Serial port configuration with customizable baud rates
  - Data streaming with configurable parameters
  - Device attach/detach event handling
- ✅ Real-time data visualization with animated charts
  - Heart Rate monitoring
  - SpO2 monitoring
  - Temperature monitoring
  - Smooth line charts with fl_chart library
  - Configurable data point limits
- ✅ Connection management UI
  - Tabbed interface for BLE and USB connections
  - Device scanning with visual feedback
  - Connection status indicators
  - Easy device selection and connection
- ✅ Data parsing service
  - Text protocol parsing
  - Binary protocol parsing template
  - Data history management (up to 1000 readings)
  - Real-time data updates via Provider pattern
- ✅ Platform-specific configurations
  - Android: Bluetooth and USB permissions in manifest
  - macOS: Bluetooth and USB entitlements configured
  - iOS: Framework ready (needs testing)
  - Windows & Linux: Full desktop support
- ✅ Comprehensive documentation
  - README.md: Project overview and setup
  - QUICKSTART.md: Getting started guide
  - INTEGRATION.md: Device integration guide
  - ARCHITECTURE.md: Technical architecture overview
  - PROJECT_SUMMARY.md: Complete project summary
- ✅ Development tools
  - Platform detection utilities
  - State management with Provider
  - Widget tests
  - Code analysis configuration

#### Platform Support
- macOS: ✅ Fully tested and working
- Windows: ✅ Framework ready
- Linux: ✅ Framework ready
- Android: ✅ Configured with permissions
- iOS: ⏳ Framework ready (needs device testing)
- Web: ⚠️ Not recommended (BLE/USB limitations)

#### Dependencies
- flutter_blue_plus: ^1.32.12 (Bluetooth LE)
- usb_serial: ^0.5.2 (USB Serial communication)
- fl_chart: ^0.69.2 (Chart visualization)
- syncfusion_flutter_charts: ^27.2.3 (Advanced charts)
- provider: ^6.1.2 (State management)
- permission_handler: ^11.3.1 (Runtime permissions)
- universal_io: ^2.2.2 (Platform detection)

#### Known Issues
- None at initial release
- Sample data displayed (real device integration pending)

#### Future Enhancements
- [ ] Real device protocol implementation
- [ ] Data recording and storage
- [ ] Data export (CSV, JSON)
- [ ] Device configuration settings
- [ ] Alerts and notifications
- [ ] Multi-device support
- [ ] Historical data viewing
- [ ] Customizable chart settings
- [ ] Dark/Light theme toggle
- [ ] iOS platform testing
- [ ] Web platform evaluation

---

## Version History

### Version Numbering
This project uses [Semantic Versioning](https://semver.org/):
- MAJOR version for incompatible API changes
- MINOR version for new functionality in a backward compatible manner
- PATCH version for backward compatible bug fixes

### Release Notes Format
- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security-related changes

---

## Contributing

To contribute to this project:
1. Create a feature branch
2. Make your changes
3. Update this CHANGELOG.md under "Unreleased"
4. Submit a pull request

## Links
- [Project Repository](https://github.com/Protocentral/healthypi_studio)
- [Issue Tracker](https://github.com/Protocentral/healthypi_studio/issues)
- [Flutter Documentation](https://flutter.dev/docs)
