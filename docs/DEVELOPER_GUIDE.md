# HealthyPi Studio — Developer Guide

Companion docs: **[PROTOCOL_REFERENCE.md](PROTOCOL_REFERENCE.md)** (wire formats) and **[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)** (the UI).

This guide describes how the shipping app is actually wired. Where the docs and the code disagree, the code wins.

---

## 1. Architecture at a glance

```
Device (HealthyPi 6)
  │  .HP6 DBLK blocks
  ├── USB CDC0 ────► UsbSerialService ─┐
  ├── WiFi TCP:5000 ► WifiSerialService ┼─► DataParser.parseBinaryData()
  └── (BLE: connect + time-sync only)  │       │ emits OpenViewData / HRVPacketData
                                        │       ▼
  USB CDC1 / WiFi TCP:9000 (SMP) ◄──────┘   ChannelController.addDataPointsSync()
        │ MCUmgr control + OTA                   │ circular buffers
        ▼                                        ├──► MultiChannelWaveformChart (Canvas)
  SmpSerialClient                                └──► RecordingDataBridge ─► RecordingEngine ─► .hpd
```

**State management:** services extend `ChangeNotifier` and are provided via `MultiProvider` in [main.dart](../lib/main.dart). Mutate via `context.read<T>()`. Do **not** use `Consumer<T>`/`Provider.of<T>` in new code (some legacy screens still do — a cleanup item). WiFi/USB→DataParser wiring is deferred to `addPostFrameCallback` so all providers exist first.

**Not Provider-managed (instantiate directly):** `EegBandPowerService`. `ChannelController` is owned by `LiveDataPump` — read it as `pump.controller`, never construct a second one.

**Theme:** Material 3, primary `#0D1B2A`, secondary `#1B263B`, accent `#FF6B35`, dark-first.

**Platform support:** desktop (macOS/Windows/Linux) is the primary target and fully functional; Android is BLE-only and currently **connect-only for live data** (see §7); iOS is framework-ready but unconfigured; Web is out of scope.

---

## 2. Connectivity services

### 2.1 USB serial ([usb_serial_service.dart](../lib/services/usb_serial_service.dart))
- `flutter_libserialport` with `SerialPortReader` (event-driven, no polling). **Not** `usb_serial` — the old USB_PORT_SELECTION_ARCHITECTURE.md described the pre-migration `usb_serial` plugin and is retired.
- `connect(portName, baudRate = 921600)`, 8N1. Auto-reconnect (10 tries / 2 s).
- On connect, opens the CDC1 SMP sibling (`control` getter → `SmpSerialClient`) and sends `stream_start`. CDC1 also drives OTA, SD record, and MSC transfer mode.
- Always call `refreshDevices()` before showing a device picker.

### 2.2 WiFi ([wifi_serial_service.dart](../lib/services/wifi_serial_service.dart))
- TCP client to the ESP32-C6, default port **5000**, `TCP_NODELAY`. Same DBLK byte stream as USB → same parser.
- `connect()`, `runDiagnostics(ip, port:)`, `diagnosticTest(ip, port:)`. Always check `isConnected` before touching `connectedDevice`.
- Control/OTA over WiFi uses a **separate** TCP port **9000** (SMP passthrough), not 5000.
- `removeDataListener` is a documented no-op under the stream architecture.
- **macOS "Operation not permitted (errno=1)":** almost always the app firewall or an IPv4/IPv6 mismatch. Diagnose with `nc -zv <ip> 5000`, `lsof -i :5000`, `tcpdump -i en0 port 5000`. errno map: 1=EPERM(firewall), 111=ECONNREFUSED, 113=EHOSTUNREACH, 110=ETIMEDOUT. A healthy stream logs `Binary data received: … starts with 0x0A, 0xFA`.

### 2.3 BLE ([ble_service.dart](../lib/services/ble_service.dart))
- Scan, connect, and post-connect time-sync (`setTime`) only. `_commandCharacteristic`/`_dataCharacteristic` are never assigned, so `_sendCommand` is a silent no-op and **no data flows into DataParser over BLE**. Treat BLE as connect-only; streaming and BLE DFU are not implemented. Check `FlutterBluePlus.adapterState` before scanning.
- **Not reachable from the UI.** Connect lists USB and WiFi only, and defaults to USB; `BleService` and its `main.dart` provider are still registered but nothing reads them. Re-enabling BLE means restoring the rows and the filter segment in [connect_screen.dart](../lib/screens/studio/connect_screen.dart) — and it should not happen before the characteristics are actually wired.

---

## 3. Parsing & the data pipeline

`DataParser.parseBinaryData(List<int>)` is the only entry point. It buffers, finds DBLK magic, CRC-checks, and emits `OpenViewData` (one per ECG sample) plus `HRVPacketData` from VITALS blocks. Stats: `packetsReceived`, `packetsDropped`, `_sequenceGaps`, `getStats()`/`getPacketStats()`. Full byte layout in [PROTOCOL_REFERENCE.md §1](PROTOCOL_REFERENCE.md).

**Channel keys** used by `ChannelController.addDataPointsSync()`: `ecg1, ecg2, ecg3, respiration, ppg_red, ppg_ir, heart_rate, spo2, temperature`.

**Debugging the pipeline** (from the retired DEBUG_LOGGING_GUIDE, still useful): check in order — port open → bytes arriving → `packetsReceived > 0` → drop rate < 1% → `totalSamplesRecorded > 0` → UI redraw. Garbled data ranked causes: baud mismatch, sync loss, cable, buffer overflow, disconnect. Use `debugPrint()` with emoji prefixes (✅ ❌ ⚠️ 🔌 📡 📊 🔄), never `print()`.

---

## 4. Multi-channel waveform display

- **Models** ([waveform_models.dart](../lib/models/waveform_models.dart)): `ChannelConfiguration` (id, label, unit, color, min/max, autoScale, showGrid, lineWidth…), `ChannelData` (circular buffer), `ChartSettings` (timeWindow 1/5/10/30/60 s, gridDensity, interpolation, zoom 0.5×–10×), `DataPoint`.
- **Controller** ([channel_controller.dart](../lib/controllers/channel_controller.dart)): `extends ChangeNotifier`, **instantiate directly (NOT via Provider)**. `addDataPointsSync(Map)`, visibility/scale/pause/timeWindow/zoom, `exportAsCSV`, `getChannelStats`, `startRecording/stopRecording`.
- **Buffer size:** the code is the source of truth for the default capacity; configure via `maxBufferSize`/`bufferSize` on `ChannelData`.
- **Rendering:** Canvas `CustomPainter` in [hpi_wave.dart](../lib/widgets/hpi/hpi_wave.dart), reading the ring buffer in place and decimating to canvas width. Each trace repaints off its own `Ticker` when the write cursor moves — never off a parent rebuild. No chart library is involved (or depended on).
- Channel presets: ECG (red, ±5 mV), respiration (green), pulse (blue, 40–200 BPM), temperature (orange, 35–40 °C), SpO₂ (yellow, 90–100%).

---

## 5. Digital filters

- **Design:** `FilterDesign(type, cutoff…, order, samplingRate, qFactor)` — types highpass/lowpass/bandpass/notch. **Order must be even**; always call `design.validate()` (returns error string or null) before building. Parameter names are authoritative in [filter_models.dart](../lib/models/filter_models.dart).
- **Real-time:** `DigitalFilter(coefficients).processSample()/processBatch()/reset()` (cascaded second-order sections, bilinear transform).
- **Offline:** `OfflineFilter.apply(data, design, zeroPhase: true)` for zero-phase (forward+reverse) batch filtering.
- **Presets:** `FilterPresetManager.getPresetsByCategory('ECG'|'EMG'|'EEG'|'General')`. About a dozen presets ship (ECG Cleanup, ECG Standard, EMG Noise Reduction, EEG Standard, Alpha/Beta band, Low-Pass Only, …); the Filters screen exposes four of them.
- **Live filtering** ([filter_integration_service.dart](../lib/services/filter_integration_service.dart)) is created with `filteringEnabled: false` (off by default) but is **user-enableable at runtime** from the channel control panel — it is not dead. Contains a legacy `FilterSupport` static extension and an unused `FilteredDataBridge`.
- 39 filter unit tests in [test/filter_test.dart](../test/filter_test.dart).

---

## 6. Recording engine & files

**Pipeline (auto-wired in Desktop Lab):** Record button → `ChannelController.startRecording()` → builds `RecordingConfig` from visible channels → `RecordingEngine.startRecording(config)` → `RecordingDataBridge` forwards live samples → `BiosignalFileWriter` writes `.hpd` → appears in the unified **Recordings & Export** screen.

- **State machine:** `idle → recording ↔ paused → stopped → (reset) idle`; ERROR reachable on exception. Check `RecordingEngine.state` before transitions.
- **Config:** `RecordingConfig(channels: List<ChannelInfo>, sessionName, subjectMetadata?, sessionMetadata?, enablePreBuffer, preBufferDuration, autoSaveInterval)`. `ChannelInfo(id, name, unit, samplingRate, gainFactor, minValue, maxValue)`.
- **File format:** header + repeated 64 KB blocks (`DATA`/`EVNT`/`INDX` markers, per-block CRC), index for seek, footer. `BiosignalFileWriter.finalize()` **must** be called or the file corrupts. Reader: `open/readHeader/readSamples/readEvents/close`.
- **Extension:** current code writes **`.hpd`** (older RECORDING_ENGINE_GUIDE/QUICK_START said `.biosig` — stale).
- **Storage:** `~/Documents/HealthyPi_Recordings/`, exports `~/Documents/HealthyPi_Exports/`. (The onboarding quickstart's `~/.healthypi_studio/Sessions/` path referred to the unwired session subsystem — see §8.)
- **Export:** CSV via `RecordingExportService.exportToCSV`, which streams the `.hpd` through `BiosignalFileReader.readSamples()` and writes one row per sample, honouring delimiter, precision, timestamps, time range, downsampling and markers. CSV is the only export format; EDF+/HDF5/MATLAB were removed before v1.0 rather than shipped as disabled promises. Filtered export does not exist — exports are always the raw recorded signal.
- **`.hpd` round trip, fixed 2026-08-30.** The writer and reader had never been tested against each other and disagreed three ways: block markers (`DATA`/`EVNT`/`INDX`) were written 16 bits wide and compared 32, so `readSamples()` matched nothing and every recording read back **empty**; subject metadata was read in a different field order than written; and strings were stored UTF-8 but decoded with `String.fromCharCodes`, mangling `Ω` and `°C`. Files written before that fix are not readable.
- 21 recording tests in [test/recording_test.dart](../test/recording_test.dart), 7 file round-trip tests in [test/biosignal_file_test.dart](../test/biosignal_file_test.dart), 6 export tests in [test/csv_export_test.dart](../test/csv_export_test.dart). `exportToCSV` takes an `outputDirectory` override so tests need no `path_provider` channel.

---

## 7. Firmware update (OTA) — how it works today

Screen: the **Firmware update** panel on the Device screen ([device_screen.dart](../lib/screens/studio/device_screen.dart)), reached from `DEVICE` in the left rail.

- **Transports:** USB CDC1 (default) or WiFi TCP :9000 (`healthypi.local`, ESP32 SMP passthrough) via a UI toggle. **No BLE DFU.**
- **Flow:** pick `.bin` → `imageUpload` (128-byte chunks) → `imageTest` (mark pending) → `osReset` (reboot into MCUboot). Dual-image (M7 required, M4 optional).
- **Current limitations (OTA is beta — harden before GA):** no `image confirm` after reboot, no version/hash read-back to confirm the swap ("verify the version after it comes back" is left to the user), no per-chunk retry, `osReset` timeout is treated as success, hand-rolled CBOR/CRC16 with no tests, CDC1 auto-detect uses a fragile longest-common-prefix heuristic.

Full SMP surface: [PROTOCOL_REFERENCE.md §3](PROTOCOL_REFERENCE.md).

---

## 8. Subsystems that were removed, and what is left

Everything this section used to list as "exists but unwired" has been deleted.
The UI revamp removed the orphaned screens, widgets, `lib/examples/`
and `connection_panel.dart.bak`, and wired `ThroughputMonitor` from the
acquisition path. On **2026-08-03** the remaining unwired services were deleted
outright rather than quarantined:

`session_manager.dart`, `session_validator.dart`, `subject_database.dart`,
`quality_monitor.dart`, `quality_assessor.dart`, `recording_file_manager.dart`,
`eeg_filter_service.dart`, `filtered_export_service.dart`, all of
`services/ecg_analysis/`, their exclusive models (`quality_metrics.dart`,
`session_models.dart`, `subject.dart`) and `assets/templates/`.

**None of it is in this repository's history** — it was removed during private
 development, before the first public commit. The `sqflite`,
`json_serializable` and `universal_io` dependencies went with them, along with
`fl_chart` and `syncfusion_flutter_charts`, which nothing had imported since the
waveforms became Canvas painters.

**Removed before v1.0:** `edf_exporter.dart`, `EDFExportOptions` and the
`ExportFormat` enum's EDF+/HDF5/MATLAB entries. Studio exports CSV and says so,
rather than listing three formats it cannot write. They were removed before the
first public commit, so EDF is a fresh implementation if it is ever picked up.

**EEG decode is present but inert.** `_decodeDblk()` handles DBLK channel 5
(36 B/sample, `ch[8]` int32 µV, `lead_off`, 3 pad bytes, 16 samples/block at
250 Hz — matching `struct hp6_eeg_sample`). It has **never produced a sample
from a board**, and cannot today:

- `app_m7/src/services/stream_service.c` `hpi_stream_enable()` returns
  `-ENOTSUP` for any `ch_mask` carrying `HPI_STREAM_CH_EEG`, with the comment
  *"EEG requested but no module/driver yet"*.
- `app_m7/src/healthylink/mod_eeg.c` guards its whole acquisition path on
  `DT_NODE_HAS_STATUS(ads1299, okay) && IS_ENABLED(CONFIG_SENSOR_ADS1299)`;
  that Kconfig is set nowhere in `app_m7`, so the provider `start()`s and
  no-ops.
- Studio's own auto-start sends `stream_start(ch: 0x03)` — `HPI_STREAM_CH_ECG |
  HPI_STREAM_CH_PPG`. EEG is `0x08` and is never requested.

The decode stays because it is written against the documented struct and costs
nothing when no channel-5 block arrives. Do not describe it as working EEG.

**Still unreferenced, deliberately kept:** `csv_exporter.dart`. Nothing imports
`CSVExporter` — `RecordingExportService.exportToCSV` does today's export itself,
streaming the `.hpd` instead of taking a fully materialised
`RecordingDataForExport`. Decide in v1.1 whether to wire or drop it.

**Consequence worth knowing:** `ecg_analysis/` was the only code that could have
derived real `pNN50` / `meanRr` from the ECG stream. With it gone, those fields
stay whatever the DBLK VITALS decoder reports (hardcoded 0), and the UI omits
them rather than showing a fabricated zero. Real HRV now needs a fresh
implementation, not a wiring job.

---

## 9. Getting started (device bring-up)

1. `flutter pub get`; run desktop: `flutter run -d macos` (or `windows`/`linux`).
2. Connect HealthyPi 6 over USB. Studio logs `USB Serial Service initialized with flutter_libserialport`, then RX bytes.
3. Verify streaming: `packetsReceived` climbs, drop rate < 1%, waveforms move.
4. Record: Record button → stop → file in `~/Documents/HealthyPi_Recordings/` → export CSV from Recordings & Export.
5. OTA: control panel → Update Firmware → pick `.bin` → USB or WiFi.

Platform notes: macOS needs location permission for serial; Linux user must be in `dialout`; Windows needs the USB-CDC driver. Ports: macOS `/dev/cu.*`, Linux `/dev/ttyACM*`, Windows `COM*`.

---

## 10. Testing

`flutter test` runs 138 tests: filter (39), recording (21), legacy EEG packet (15), legacy HRV packet (15), SMP transport (12), file round trip (7), CSV export (6), PPG decimation (3), listener (2), widget smoke (1), plus the shell suite. 113 pass; the 25 failures are all in the legacy packet tests and predate this work. **Coverage gaps:** DBLK parsing (the live path — the packet tests cover the dead legacy path), the OTA sequence itself (`imageUpload`/`verifyStaged`/`imageTest`; the SMP tests cover the transport under it), and the connectivity services.
