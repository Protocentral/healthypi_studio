# HealthyPi Studio — Documentation

Three canonical documents, plus this index. Start here.

| Doc | What it covers |
|---|---|
| **[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)** | The UI's source of truth: colour and type tokens, the shell (top device bar, labelled rail, status line), the `lib/widgets/hpi/` component kit, the semantic trace ramp, logo use, the nine screens, and the honesty rules for values the device does not report. **Read this before touching any UI file.** |
| **[PROTOCOL_REFERENCE.md](PROTOCOL_REFERENCE.md)** | The source of truth for wire formats: `.HP6` **DBLK** streaming blocks (current), legacy OpenView packets (archived/dead), MCUmgr SMP control & OTA surface, USB dual-CDC topology, `.hpd` file format. Baud, ports, and packet layouts are verified against the shipping parser. |
| **[DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)** | How the app is wired: architecture, connectivity (USB/WiFi/BLE), parsing pipeline, waveform display, filters, recording/export and firmware update. Getting-started + debugging + testing. |

The feature-by-feature status of the app — what is stable, what is beta, what is
experimental and what is not implemented — is in the
[README](../README.md#feature-status).

## Notes for readers
- The **live streaming protocol is DBLK**, not the legacy 38-byte OpenView format. Older docs describing the OpenView packet are archived because the parser no longer decodes it.
- The **USB data baud rate is 921600** (some retired docs said 115200 — that was stale).
- Firmware **OTA works over USB and WiFi (MCUmgr SMP)**; BLE DFU is not yet implemented, and OTA is beta — see the [README](../README.md#firmware-update).
