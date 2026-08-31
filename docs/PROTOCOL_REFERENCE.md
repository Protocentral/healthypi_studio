# HealthyPi Studio — Protocol Reference

**Status:** Canonical · **Last verified against code:** 2026-07-23
**Supersedes:** OPENVIEW_PROTOCOL.md, OPENVIEW_HRV_PACKET_SPEC.md, OPENVIEW_EEG_PACKET_SPEC.md, and the protocol sections of DEVICE_DATA_FLOW_CHECKLIST.md / DEVICE_INTEGRATION_QUICKSTART.md / ESP32_C6_WIFI_SERVER.md / STUDIO_INTEGRATION_NOTES.md.

This document is the single source of truth for the HealthyPi 6 wire formats that Studio parses and produces. Where the older docs disagreed, the values here were confirmed by reading the shipping parser ([lib/services/data_parser.dart](../lib/services/data_parser.dart)) and SMP client ([lib/services/smp_serial_client.dart](../lib/services/smp_serial_client.dart)).

---

## 0. TL;DR — what actually runs today

| Concern | Current truth | Where |
|---|---|---|
| **Streaming format** | `.HP6` **DBLK** blocks (channel-batched, CRC32). | [data_parser.dart:671](../lib/services/data_parser.dart#L671) |
| **Legacy OpenView** (38/46/50-byte packets, types 0x02/0x03/0x04) | **Dead code**, retained for reference behind `// ignore: dead_code`. Not parsed. | [data_parser.dart:673](../lib/services/data_parser.dart#L673) |
| **USB data link (CDC0)** | **921600 baud**, 8N1, event-driven (`SerialPortReader`). | [usb_serial_service.dart:198](../lib/services/usb_serial_service.dart#L198) |
| **USB control (CDC1)** | MCUmgr SMP over Zephyr serial framing. | [smp_serial_client.dart](../lib/services/smp_serial_client.dart) |
| **WiFi data** | TCP **:5000** on the ESP32-C6, same byte stream as CDC0. | [wifi_serial_service.dart](../lib/services/wifi_serial_service.dart) |
| **WiFi control / OTA** | TCP **:9000** SMP passthrough on the ESP32-C6. | [smp_serial_client.dart:48](../lib/services/smp_serial_client.dart#L48) |
| **BLE** | Connect + time-sync only; **no data, no control, no DFU**. | [ble_service.dart](../lib/services/ble_service.dart) |

> **Baud-rate note (resolves a long-standing doc conflict):** older docs variously claimed 115200 or 921600, and one flagged that 115200 cannot carry 19 KB/s. The shipping code uses **921600** (`_lastBaudRate = 921600`, `connect(..., baudRate = 921600)`). Treat any "115200" in archived docs as stale.

---

## 1. `.HP6` DBLK streaming format (CURRENT)

Since the 2026-06-08 firmware/Studio rewrite, the device streams the same canonical `.HP6` "DBLK" block format on the wire (CDC0 / WiFi TCP) that Studio also writes to disk — one parser serves both file and stream. Reference: firmware `services/hp6_frame.h`; Studio decoder [data_parser.dart:818-1021](../lib/services/data_parser.dart#L818).

### 1.1 Block frame (little-endian)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | Magic | ASCII `"DBLK"` = `44 42 4C 4B` |
| 4 | 4 | `block_len` | uint32, **whole frame including CRC**. Valid range: `[32, 4096]` |
| 8 | 4 | `seq` | uint32 monotonic block sequence (gap → `_sequenceGaps++`) |
| 12 | 8 | `t_ms` | uint64 device-monotonic milliseconds (low 32 bits used as HRV timestamp) |
| 20 | 1 | `channel` | `1`=ECG, `2`=PPG, `4`=VITALS, `5`=EEG (reserved) |
| 21 | 1 | `flags` | reserved |
| 22 | 2 | `sample_count` | uint16 samples in this block |
| 24 | 4 | reserved | — |
| 28 | N | `samples[]` | channel-specific structs (below) |
| 28+N | 4 | `crc32` | zlib/IEEE CRC-32 over bytes `[0, block_len-4)` |

Header is 28 bytes; CRC trailer is 4 bytes. Parser resyncs on bad magic, out-of-range `block_len`, or CRC mismatch (each increments `packetsDropped`).

### 1.2 Channel sample structs

**Channel 1 — ECG @ 500 Hz — 20 bytes/sample**

| Off | Size | Field |
|---|---|---|
| 0 | 4 | `respiration` (int32, bio-Z) |
| 4 | 4 | `ecg1` / Lead I (int32) |
| 8 | 4 | `ecg2` / Lead II (int32) |
| 12 | 4 | `ecg3` / V1 / Lead III (int32) |
| 16 | 1 | `lead_off` bitmask |
| 17 | 1 | `flags` |
| 18 | 2 | padding |

**Channel 2 — PPG @ 250 Hz — 12 bytes/sample** (arrives in 16-sample blocks)

| Off | Size | Field |
|---|---|---|
| 0 | 4 | `ppgRed` (int32) |
| 4 | 4 | `ppgIr` (int32) |
| 8 | 1 | `lead_off` |
| 9 | 3 | padding |

**Channel 4 — VITALS (on change) — 12 bytes**

| Off | Size | Field | Units |
|---|---|---|---|
| 0 | 2 | `hr` (uint16) | BPM |
| 2 | 2 | `spo2x10` (uint16) | % ×10 |
| 4 | 2 | `rr` (uint16) | breaths/min |
| 6 | 2 | `temp` (int16) | °C ×100 |
| 8 | 1 | `sdnn` (uint8) | ms |
| 9 | 1 | `rmssd` (uint8) | ms |
| 10 | 2 | padding | — |

**Channel 5 — EEG — reserved.** Not streamed by the device yet; blocks are ignored ([data_parser.dart:1018](../lib/services/data_parser.dart#L1018)). See §4 for the proposed EEG spec if/when it ships.

### 1.3 ECG↔PPG synchronization (implementation contract)

ECG is 500 Hz, PPG is 250 Hz. The parser keeps a PPG FIFO and pops one real PPG sample every 2nd ECG sample (2:1 lock), emitting exactly one `OpenViewData` per ECG sample so downstream consumers (`packetStream`, recording, charts) see a coherent, per-sample record with a real (non-interpolated) PPG value. FIFO is bounded at 512 samples (~2 s) to prevent unbounded growth if ECG stalls.

### 1.4 Known limitations to fix before "clinical" claims

- **VITALS-derived HRV is partly stubbed:** `pnn50`, `signalQuality`, `arrhythmiaFlags`, `meanRr` are hardcoded to `0` ([data_parser.dart:1007-1011](../lib/services/data_parser.dart#L1007)); `rrInterval` is derived from HR, not measured. The HRV Analysis screen therefore shows zeros for those fields.
- **No DBLK unit tests** exist; the only packet tests exercise the now-dead legacy path.

---

## 2. Legacy OpenView packets (ARCHIVED — not parsed today)

Retained for historical reference and for any old firmware/ESP images still in the field. **The current parser does not decode these** — they are counted as sync-skip bytes. If you need to re-enable them, the decoders still live in `data_parser.dart` (dead-code region) and in the archived specs.

Summary of the legacy family (full byte tables are preserved in git history, in the pre-2026-07-23 `OPENVIEW_PROTOCOL.md` and `OPENVIEW_HRV_PACKET_SPEC.md`):

| Type | Name | Size | Rate | Header (meta bytes) |
|---|---|---|---|---|
| `0x02` | Waveform v1 | 38 B | 500 Hz | `0A FA 1F 00 02` |
| `0x02` | Waveform v2 | 50 B | 250 Hz | `0A FA` + len + `02 02` (adds uint32 seq) |
| `0x03` | HRV | 27 B | ~0.2 Hz | `0A FA 14 02 03` |
| `0x04` | EEG | 51 B | 250 Hz | `0A FA 2E 02 04` |

> The old OPENVIEW_PROTOCOL.md stated the header as `0A FA 0C BF 1F`. That was **wrong** — real RX logs and every other doc show `0A FA 1F 00 02`. Corrected here for the record.

---

## 3. MCUmgr SMP control & OTA surface (CURRENT)

Studio talks to the device's control plane over MCUmgr **Simple Management Protocol (SMP)**. The exact same request/response and OTA logic runs over two transports; only the byte pipe differs:

- **USB CDC1** — Zephyr `uart_mcumgr` serial framing.
- **WiFi TCP :9000** — ESP32-C6 SMP passthrough (`SmpSerialClient.openTcp(host, port: 9000)`, default host `healthypi.local`).

### 3.1 Serial framing (Zephyr shell SMP transport)

```
0x06 0x09  <base64( 2-byte big-endian length  ||  SMP header+payload  ||  CRC16-XMODEM )>  0x0A
```
Continuation lines use the `0x04 0x14` start marker. CBOR body; the hand-rolled encoder/decoder handles map-of-{int,text,bool,bytes}. (See [smp_serial_client.dart](../lib/services/smp_serial_client.dart).)

### 3.2 SMP commands implemented in Studio today

| Group | ID | Command | Studio method | Response used? |
|---|---|---|---|---|
| 0 (OS) | 5 | reset (reboot to MCUboot) | `osReset()` | timeout treated as success |
| 1 (Image) | 1 | image upload (chunked) | `imageUpload()` | yes — device returns next offset |
| 1 (Image) | 0 | image test / mark-pending (`confirm:false`) | `imageTest(sha)` | yes |
| 64 (vendor `hpi`) | 0x20/0x21 | stream start/stop (`ch`,`ann`) | `streamStart()/streamStop()` | fire-and-forget |
| 64 | 0x61/0x62 | SD record start/stop | — | fire-and-forget |
| 64 | 0x69 | USB MSC transfer mode | `transferMode(on)` | fire-and-forget |

**OTA flow:** upload (128-byte chunks, first chunk carries `image`/`len`/`sha`) → `imageTest` (mark pending) → `osReset` (reboot into MCUboot, which swaps). Dual-image supported (image index 0/1; M7 required, M4 optional).

### 3.3 Firmware-defined but NOT yet in Studio

The firmware host-interface contract (STUDIO_INTEGRATION_NOTES / DUAL_CDC plan) reserves a broader group-64 surface tied to firmware phases. Studio has **not** implemented these; they are release backlog:

| IDs | Feature | FW phase |
|---|---|---|
| `0x0001` | device_info (sn, fw, channels) | 2 |
| `0x0022` | stream_status | 2 |
| `0x0030/0x0031` | telemetry / fw_versions | 2 |
| `0x0010–0x0013` | unlock/lock (security) | 11 |
| `0x0050–0x0052` | HealthyLink modules | 4 |
| `0x0060–0x0068` | SD recordings browser | 5 |
| `0x0070–0x0073` | WiFi provisioning | 6 |
| `0x0080–0x0082` | diagnostics/self-test | 7 |
| `0x0090–0x0092` | log streaming | 8 |

**OTA hardening gaps (OTA is beta):** no `image confirm` (confirm:true) after reboot, no `image list`/version read-back to verify the swap, no per-chunk retry, `osReset` timeout masks failures, CBOR/CRC16 code is hand-rolled and untested. Error codes 256+ (`HPI_ERR_NOT_READY`, `HW_FAULT`, `CHANNEL_NOT_AVAILABLE`, `INSUFFICIENT_STORAGE`, …) are defined by firmware but not surfaced in the UI.

---

## 4. USB topology & port pairing

The HealthyPi 6 enumerates as a **composite dual-CDC** device:

- **CDC 0** — sample stream (device→host). Opens on connect; the device auto-streams once CDC0 opens.
- **CDC 1** — bidirectional MCUmgr SMP (control + events + OTA). Async events arrive as SMP responses with `seq = 0`.

**Port pairing** (Studio picks CDC1 as the sibling of the opened CDC0 by longest-common-prefix):

| OS | Pattern | Example |
|---|---|---|
| macOS | adjacent `usbmodem…` suffixes | `…1` (CDC0) + `…3` (CDC1) |
| Linux | consecutive `ttyACM` | `ttyACM0` + `ttyACM1` |
| Windows | consecutive `COM` | `COMn` + `COMn+1` |

**Lifecycle rules of the road:** keep CDC1 open for the whole "connected" session; open CDC0 only while streaming and always keep a reader draining it; always send `stream_stop` before closing CDC0.

VID/PID: Zephyr dev pair `0x2FE3 / 0x0100` (will move to a registered pair before mass production). Older HealthyPi generations used bridge chips (CH340 `1A86:7523`, CP210x `10C4:EA60`, FT232 `0403:6001`) — relevant only for legacy hardware.

> **Known risk:** the longest-common-prefix CDC1 heuristic can select the wrong port on a multi-device host. The robust fix is an `os echo` identification probe, which the firmware supports.

---

## 5. Data-rate & performance envelope

| Metric | Target |
|---|---|
| ECG rate | 500 Hz |
| PPG rate | 250 Hz |
| Sustained data rate | ~19 KB/s |
| Visualization latency | < 5 ms typical, < 200 ms max |
| Packet loss | 0% target (< 0.1% acceptable) |
| Frame rate | 60 FPS (> 30 acceptable) |

WiFi is expected to match USB within ±5% throughput.

---

## 6. `OpenViewData` — the in-app canonical record

Regardless of wire format, the parser emits `OpenViewData` (one per ECG sample), consumed by charts, recording, and export:

`ecg1, ecg2, ecg3, respiration, ppgRed, ppgIr, ppgValid, heartRate, spo2, respirationRate, temperature, sequenceNumber, protocolVersion` (+ `adcChannel1/2`). `toHealthyPiData()` yields the vitals-only legacy view. **Always call `DataParser.parseBinaryData()`** — never the deprecated `parseData(String)`.

---

## 7. `.HP6` on-disk recording format

Studio records to `.hpd`/`.HP6` files via [biosignal_file_writer.dart](../lib/services/biosignal_file_writer.dart) / [biosignal_file_reader.dart](../lib/services/biosignal_file_reader.dart): a header block, repeated 64 KB data blocks with `DATA`/`EVNT`/`INDX` markers, per-block CRC, an index section for fast seek, and a footer. Because the stream and file share the DBLK block model, the same decode path applies. Full field-level spec lives in the DEVELOPER_GUIDE recording chapter.
