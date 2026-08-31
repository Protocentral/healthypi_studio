# HealthyPi Studio — Design System

Source of truth for the UI: the tokens, components and rules every screen is
built from, and how they are implemented in code.

Code entry points:

| Layer | File |
|---|---|
| Tokens (colour, type, metrics, trace ramp) | [lib/theme/hpi_tokens.dart](../lib/theme/hpi_tokens.dart) |
| `ThemeData` for both themes | [lib/theme/app_theme.dart](../lib/theme/app_theme.dart) |
| Chrome (app bar, rail, status line) | [lib/shell/studio_shell.dart](../lib/shell/studio_shell.dart) |
| Screen frame (header, columns, toolbar) | [lib/shell/screen_frame.dart](../lib/shell/screen_frame.dart) |
| Navigation model | [lib/shell/studio_nav.dart](../lib/shell/studio_nav.dart) |
| Preferences + session metadata | [lib/shell/studio_settings.dart](../lib/shell/studio_settings.dart) |
| Components | [lib/widgets/hpi/](../lib/widgets/hpi/) |
| Screens | [lib/screens/studio/](../lib/screens/studio/) |

---

## 1. The five rules

Everything below follows from these. If a change breaks one of them, it is
wrong even if it looks fine in isolation.

1. **One chrome.** Top device bar + labelled rail + one status line. Screens are
   content inside it and never push their own `Scaffold` — that is what used to
   make the rail vanish on two screens.
2. **Amber is the primary action.** Signal Amber `#FBBF24` is reserved for the
   single primary action per screen and the active-nav indicator. Nothing else
   gets an amber fill. Brand blue `#6FB3CC` is selection and navigation.
3. **Traces are a semantic ramp, not primaries.** The three ECG leads share the
   amber family so they read as one modality. Nothing is saturated RGB; nothing
   is pure black.
4. **Every number is JetBrains Mono.** Saira caps for titles, Jost for
   nav/labels/buttons, Montserrat for body copy.
5. **A value the device has not reported reads as an em dash.** Never a
   plausible-looking zero. Where a metric is not implemented, the UI says so.

---

## 2. Colour

Read colours from the theme, never as literals:

```dart
final p = context.hpi;      // HpiPalette for the active theme
Container(color: p.card, ...);
Text('72', style: HpiText.vital(p.textPrimary));
```

`HpiPalette` is a `ThemeExtension`, so both themes carry the full set and
`Theme.of(context)` resolves it. `context.hpi` is the accessor.

### Dark ramp (default)

| Token | Hex | Use |
|---|---|---|
| `canvas` | `#0E1418` | page background behind cards |
| `chrome` / `card` | `#14191E` | app bar, rail, status line, cards |
| `cardInner` | `#1C2228` | raised tiles (vitals, metrics, counters) |
| `well` | `#111619` | recessed plot wells, table headers, gutters |
| `outline` | `#2C363E` | control outlines |
| `outlineSoft` | `#232B32` | card outlines |
| `divider` | `#1B2228` | hairline row separators |
| `brand` | `#6FB3CC` | selection, navigation, informational |
| `accent` | `#FBBF24` | the one primary action; active nav |
| `success` / `warning` / `error` | `#4ADE80` / `#FB923C` / `#F87171` | state |
| `textPrimary` … `textFaint` | `#ECEFF1` `#B9C2C8` `#8D99A1` `#6B767E` | four text levels |

### Light ramp

Same tokens, inverted: surfaces `#FAFBFC → #FFF → #F1F4F5`, brand blue drops to
`#2C6E84`, amber to `#F59E0B`, and every trace darkens one step so it holds on
white. Switch lives in the top bar and in Settings → Appearance.

### Trace ramp

`p.trace.forChannel(channelId)` resolves a channel id to its colour, so a screen
never picks one by hand.

| Channel | Dark | Light |
|---|---|---|
| `ecg1` Lead I | `#FBBF24` | `#B45309` |
| `ecg2` Lead II | `#F59E0B` | `#92400E` |
| `ecg3` V1 | `#D97706` | `#7C2D12` |
| `respiration` | `#4CC38A` | `#15803D` |
| `ppg` | `#6FB3CC` | `#2C6E84` |
| `eeg1` / `eeg2` | `#8B84F0` / `#A78BFA` | `#4338CA` / `#6D28D9` |
| `temperature` | `#FB923C` | `#C2410C` |

---

## 3. Type

Four families, bundled as static instances in `assets/fonts` so the app renders
identically offline. Use `HpiText.*` rather than raw `TextStyle`.

| Role | Style | Spec |
|---|---|---|
| Screen title | `HpiText.screenTitle` | Saira 600 / 19 / +0.06em caps |
| Card section title | `HpiText.sectionTitle` | Saira 600 / 12 caps |
| Context line | `HpiText.screenSubtitle` | Montserrat 400 / 12 |
| Field label | `HpiText.label` | Jost 600 / 10 / +0.12em caps |
| Control / chip | `HpiText.control` | Jost 500 / 11 |
| Nav row, list title | `HpiText.uiTitle` | Jost 500 / 12.5 |
| Primary button | `HpiText.button` | Jost 600 / 12.5 / +0.04em |
| Rail label | `HpiText.railLabel` | Jost 600 / 9.5 caps |
| Body | `HpiText.body` | Montserrat 400 / 12 / 1.5 |
| Closing note | `HpiText.note` | Montserrat 400 / 11 |
| Vital number | `HpiText.vital` | JetBrains Mono 500 / 34 |
| Unit | `HpiText.unit` | Jost 600 / 10 caps |
| Any number | `HpiText.mono` | JetBrains Mono, size to taste |

---

## 4. Chrome and metrics

```
┌────────────────────────────────────────────────── 60px app bar ──┐
│ wordmark · STUDIO │ link chip · rate chip · storage │ session pill · theme · ACTION │
├──────┬──────────────────────────────────────────────────────────┤
│ rail │ ScreenHeader  (title · badge · context line · quiet action)│
│ 96px │ [ScreenToolbar 44px — acquisition screens only]           │
│      │ content, 18px gutter, 12px card gap, 14px column gap      │
├──────┴──────────────────────────────────────────────────────────┤
│ status line 34px: items … clock                     (always on) │
└─────────────────────────────────────────────────────────────────┘
```

`HpiMetrics` holds every number above. Window is 1600×1000 by default and must
still work at the 1200×800 minimum: below `HpiMetrics.compactBreakpoint` the app
bar drops its rate and storage chips, side columns narrow, and the toolbar and
status line scroll horizontally instead of overflowing.

### The rail

Eight destinations in `StudioDestination`: six above the spacer
(Live, HRV, EEG, Records, Filters, Link), two below (Device, Settings). The
active one takes a 3px amber left edge and an 8%-amber wash — the only amber in
the rail. In the Connect state the rail dims destinations that need a source
rather than hiding them, so the app never looks like a different program.

### Display modes on Live

Focus mode is a display mode, not a separate shell. It collapses the vitals
strip and inspector dock, runs traces full-bleed, and floats the vitals HUD and
a control capsule over the canvas. Chrome never changes. `Esc` leaves focus
mode first, then closes the dock.

### Keyboard

`Space` freeze/resume · `R` start/stop recording · `F` focus mode ·
`M` drop marker · `1–8` jump to destination · `Esc` exit focus / close dock.
Documented on Settings → Shortcuts; handled in
[studio_home.dart](../lib/screens/studio/studio_home.dart).

---

## 5. Components

All in `lib/widgets/hpi/`. Compose these; do not hand-roll equivalents.

**Surfaces** — `HpiCard` (chrome-level card), `HpiTile` (raised inner tile),
`HpiWell` (recessed plot/table well), `HpiRule`.

**Text** — `HpiLabel`, `HpiSectionTitle`, `HpiMono`, `HpiBody`, `HpiNote`.

**Chips and badges** — `HpiChip` (app-bar chip), `HpiStatusDot` (optionally
pulsing), `HpiBadge` (LIVE / DISPLAY ONLY / UPDATING), `HpiTag` (normal/low/high).

**Buttons** — `HpiPrimaryButton` (the one amber action), `HpiGhostButton`
(everything else), `HpiToolButton` (toolbar; `active` outlines amber, never
fills), `HpiSegmented<T>`, `HpiToggle`, `HpiCheckbox`, `HpiOptionRow`.

**Rows and meters** — `HpiKeyValue`, `HpiSettingRow`, `HpiMeter`, `HpiMeterRow`,
`HpiParamSlider`, `HpiKeyCap`.

**Tables** — `HpiTable` + `HpiColumnSpec` + `HpiTableRow` + `HpiCell` +
`HpiStatusCell`, plus `HpiLogLine` and `HpiActionRow`.

**Plots** — `HpiTimeGrid`, `HpiLinePlot`, `HpiSparkline`, `HpiPlotWell`,
`HpiVitalCard`, `HpiPoincarePlot`, `HpiGapTimeline`, and `HpiWaveTrace`.

`HpiWaveTrace` is the live-signal painter: it reads a `ChannelData` circular
buffer in place and decimates to the canvas width, so a seven-channel 500 Hz
canvas costs no per-frame list copies. Repaint keys off the buffer write cursor.

**Frame** — `ScreenHeader`, `ScreenBody`, `ScreenColumns`, `ScreenToolbar`,
`ScreenEmptyState`.

---

## 6. Logo use

Five assets in `assets/brand/`, each with exactly one job. `HpiWordmark` and
`HpiMonoMark` pick the theme-correct file, so screens never reference a path.

| Asset | Where |
|---|---|
| `hpi6-wordmark-dark.png` | app bar on the dark ramp (light ink + amber “6”) |
| `hpi6-wordmark-light.png` | app bar on the light ramp (dark ink + amber “6”) |
| `hpi6-mono-blue.png` | Device screen identity tile |
| `hpi6-mono-white.png` | Connect empty state, dimmed to 50% |
| `logo-round.png` | Settings → About, and the app/window icon |

The wordmark appears **once**, in the app bar, followed by a divider and the
uppercase `STUDIO` qualifier in Jost. No screen draws its own header lockup.

---

## 7. Screens

| Design | Screen | File |
|---|---|---|
| 1a / 2a | Live signals (+ Focus mode) | [live_screen.dart](../lib/screens/studio/live_screen.dart), [live_inspector.dart](../lib/screens/studio/live_inspector.dart) |
| 2b | HRV analysis | [hrv_screen.dart](../lib/screens/studio/hrv_screen.dart) |
| 2c | EEG | [eeg_screen.dart](../lib/screens/studio/eeg_screen.dart) |
| 2d | Recordings & export | [recordings_screen.dart](../lib/screens/studio/recordings_screen.dart) |
| 2e | Filters | [filters_screen.dart](../lib/screens/studio/filters_screen.dart) |
| 2f | Link health | [link_health_screen.dart](../lib/screens/studio/link_health_screen.dart) |
| 2g | Device & firmware | [device_screen.dart](../lib/screens/studio/device_screen.dart) |
| 2h | Connect (Live's empty state) | [connect_screen.dart](../lib/screens/studio/connect_screen.dart) |
| 2i | Settings | [settings_screen.dart](../lib/screens/studio/settings_screen.dart) |
| 1d | Light theme | same screens, `HpiPalette.light` |

Each screen owns two contributions to the chrome: its primary action and its
status-line items. `StudioHome` collects both via a `GlobalKey` per screen, so
the shell stays the single place chrome is assembled.

---

## 8. Honesty rules in the UI

The design is explicit about not overstating what the device reports. Current
cases, each visible in the UI rather than hidden:

* **HRV `pNN50` and mean R-R** — the firmware's HRV packet carries the fields but
  reports zero, so the tiles read `not reported by firmware`.
* **EEG electrode contact** — the packet reports lead-off per electrode as a
  bitmask, not impedance in kΩ, so the panel reports contact, not a fake kΩ.
  `Impedance check` is present and disabled: no firmware command exists.
* **Filtered export** — no code path bakes the display filter chain into an
  exported file, so the export panel's switch is disabled and labelled, and the
  matching **Keep raw signal in exports** setting says exports are always raw.
  Both used to be live switches that the exporter ignored.
* **BLE** — `BleService` connects but never assigns its data or command
  characteristics, so nothing flows over it. Rather than offer a connection that
  does nothing, Connect does not list BLE at all: the source filter is
  `All / USB / WiFi` and opens on **USB**. The service and its provider stay
  registered, so re-enabling it is a change to `connect_screen.dart` alone.
* **Sensor inventory** — the Device screen used to table part numbers, buses and
  sample rates for front-ends that are not on a HealthyPi 6. None of it came off
  the wire and group 64 has no device-info command, so the card is now an empty
  state that says the firmware does not report an inventory. A table of invented
  hardware reads as a probe result, which makes a wrong row look like a fault.
* **Device identity** — the firmware version is read over MCUmgr when the
  control port opens and shown as reported; serial and MAC are in neither the
  stream nor the MCUmgr surface, so they render as em dashes rather than
  invented values.
* **No device attached** — Live runs the built-in generator and the badge reads
  `Demo data`, with the status line saying `Demo data · no device attached`.

When one of these is fixed in firmware or in a service, remove the note in the
same change.

---

## 9. Adding a screen

1. Add a `StudioDestination` value with its label, title and both icons.
2. Build the screen with `ScreenBody` + `ScreenHeader` (+ `ScreenColumns`).
   Never a `Scaffold`.
3. If it needs its own primary action or status items, expose
   `buildPrimaryAction(context)` / `buildStatusItems(context)` from its `State`
   and wire a `GlobalKey` in `StudioHome`.
4. Use `context.hpi`, `HpiText.*` and the components above — no literal hex, no
   bare `TextStyle`.
5. Add the destination to the rail-order assertion in
   [test/shell_test.dart](../test/shell_test.dart).
