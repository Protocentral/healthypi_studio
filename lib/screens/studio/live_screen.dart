import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/channel_controller.dart';
import '../../models/recording_models.dart';
import '../../models/waveform_models.dart';
import '../../services/data_parser.dart';
import '../../services/eeg_packet_service.dart';
import '../../services/hrv_packet_service.dart';
import '../../services/live_data_pump.dart';
import '../../services/recording_engine.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_settings.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_plots.dart';
import '../../widgets/hpi/hpi_primitives.dart';
import '../../widgets/hpi/hpi_wave.dart';
import 'live_inspector.dart';

/// Live signals — the acquisition console.
///
/// Two display modes over one layout (design 1a and 2a). The default puts a
/// vitals strip above an acquisition toolbar and a channel canvas, with the
/// 320px panel collapsed to a 52px inspector dock. Focus mode collapses the
/// strip and dock, runs the traces full-bleed, and floats the vitals and
/// controls over the canvas. The chrome never changes between them.
class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<StudioNavController>();
    final pump = context.watch<LiveDataPump>();

    return ListenableBuilder(
      listenable: pump.controller,
      builder: (context, _) {
        final controller = pump.controller;
        final visible = controller.visibleChannels;
        if (nav.focusMode) {
          return _FocusLayout(controller: controller, channels: visible);
        }
        return ScreenBody(
          padded: false,
          header: ScreenHeader(
            title: StudioDestination.live.title,
            badge: pump.isSimulated
                ? HpiBadge('Demo data', tone: context.hpi.brand)
                : HpiBadge('Live', tone: context.hpi.success),
            subtitle: '${visible.length} channels · '
                '${controller.settings.samplingRate.toStringAsFixed(0)} Hz · '
                'streaming ${formatClock(pump.streamDuration)}',
          ),
          toolbar: const _AcquisitionToolbar(),
          child: Column(
            children: [
              const _VitalsStrip(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                            left: HpiMetrics.screenPadding),
                        child: _Canvas(controller: controller, channels: visible),
                      ),
                    ),
                    const LiveInspectorDock(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The vitals strip: five cards across the top of the dashboard, out of the
/// footer where they used to live.
class _VitalsStrip extends StatelessWidget {
  const _VitalsStrip();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final pump = context.watch<LiveDataPump>();
    final parser = context.watch<DataParser>();
    final hrv = context.watch<HRVPacketService>();
    final settings = context.watch<StudioSettings>();
    final data = parser.currentOpenViewData;

    // Nothing is invented here: a value the device has not reported reads as an
    // em dash rather than a plausible number.
    String vital(num? value, {int decimals = 0}) {
      if (value == null || value == 0) return '—';
      return decimals == 0
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(decimals);
    }

    final simulated = pump.isSimulated;
    final hr = simulated ? pump.hrTrend.lastOrNull : data?.heartRate.toDouble();
    final spo2 = simulated ? pump.spo2Trend.lastOrNull : data?.spo2.toDouble();
    final resp =
        simulated ? pump.respTrend.lastOrNull : data?.respirationRate.toDouble();
    final tempC = simulated ? pump.tempTrend.lastOrNull : data?.temperature;
    final temp = tempC == null ? null : settings.temperature(tempC);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HpiMetrics.screenPadding, 0, HpiMetrics.screenPadding, 12),
      child: SizedBox(
        height: 108,
        child: Row(
          children: [
            Expanded(
              child: HpiVitalCard(
                icon: Icons.favorite,
                label: 'Heart rate',
                value: vital(hr),
                unit: 'bpm',
                tone: p.trace.ecg1,
                pulse: hr != null && hr > 0,
                spark: pump.hrTrend,
              ),
            ),
            kCardGapH,
            Expanded(
              child: HpiVitalCard(
                icon: Icons.bloodtype_outlined,
                label: 'SpO₂',
                value: vital(spo2),
                unit: '%',
                tone: p.trace.ppg,
                spark: pump.spo2Trend,
              ),
            ),
            kCardGapH,
            Expanded(
              child: HpiVitalCard(
                icon: Icons.air,
                label: 'Respiration',
                value: vital(resp),
                unit: '/ min',
                tone: p.trace.respiration,
                spark: pump.respTrend,
              ),
            ),
            kCardGapH,
            Expanded(
              child: HpiVitalCard(
                icon: Icons.device_thermostat,
                label: 'Temperature',
                value: vital(temp, decimals: 1),
                unit: settings.temperatureUnit,
                tone: p.trace.temperature,
                caption: simulated ? 'simulated probe' : 'skin probe',
              ),
            ),
            kCardGapH,
            Expanded(
              child: HpiVitalCard(
                icon: Icons.ssid_chart,
                label: 'HRV · SDNN',
                value: hrv.sdnn == null ? '—' : '${hrv.sdnn}',
                unit: 'ms',
                tone: p.trace.eeg1,
                tag: hrv.sdnn == null ? null : hrv.latestData?.sdnnLevel,
                tagTone: p.success,
                // pNN50 is in the packet but the firmware does not fill it in,
                // so it is left out rather than reported as a flat 0%. The HRV
                // screen says so in full.
                caption: hrv.rmssd == null
                    ? 'awaiting HRV packets'
                    : 'RMSSD ${hrv.rmssd} ms',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The acquisition toolbar: transport, sweep speed, window, measurement tools,
/// and the two right-aligned canvas controls.
class _AcquisitionToolbar extends StatelessWidget {
  const _AcquisitionToolbar();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    final settings = context.watch<StudioSettings>();
    final pump = context.watch<LiveDataPump>();
    final controller = pump.controller;
    final paused = controller.settings.isPaused;
    final visibleCount = controller.visibleChannels.length;
    final totalCount = controller.channels.length;

    return ScreenToolbar(
      children: [
        HpiToolButton(
          icon: paused ? Icons.play_arrow : Icons.pause,
          active: paused,
          tooltip: paused ? 'Resume (Space)' : 'Freeze (Space)',
          onPressed: controller.togglePause,
        ),
        const SizedBox(width: 10),
        Container(width: 1, height: 20, color: p.outlineSoft),
        const SizedBox(width: 10),
        const HpiLabel('Sweep'),
        const SizedBox(width: 8),
        HpiSegmented<double>(
          segments: const [
            HpiSegment(value: 12.5, label: '12.5'),
            HpiSegment(value: 25, label: '25'),
            HpiSegment(value: 50, label: '50'),
          ],
          value: settings.sweepSpeedMmPerSec,
          trailingNote: 'mm/s',
          onChanged: (v) => settings.sweepSpeedMmPerSec = v,
        ),
        const SizedBox(width: 12),
        const HpiLabel('Window'),
        const SizedBox(width: 8),
        HpiSegmented<double>(
          segments: const [
            HpiSegment(value: 1, label: '1s'),
            HpiSegment(value: 5, label: '5s'),
            HpiSegment(value: 10, label: '10s'),
            HpiSegment(value: 30, label: '30s'),
            HpiSegment(value: 60, label: '60s'),
          ],
          value: settings.windowSeconds,
          onChanged: (v) {
            settings.windowSeconds = v;
            controller.setTimeWindow(v);
          },
        ),
        const SizedBox(width: 10),
        Container(width: 1, height: 20, color: p.outlineSoft),
        const SizedBox(width: 10),
        // No painter reads `showCursors`, so this toggled a flag and drew
        // nothing. Visible and disabled until a measurement tool exists.
        HpiToolButton(
          icon: Icons.straighten,
          label: 'Calipers — not available',
          onPressed: null,
        ),
        const SizedBox(width: 8),
        _MarkerButton(),
        const SizedBox(width: 8),
        HpiToolButton(
          icon: Icons.filter_alt,
          label: 'Filters',
          active: false,
          onPressed: () => nav.go(StudioDestination.filters),
        ),
        const SizedBox(width: 8),
        HpiToolButton(
          icon: Icons.fullscreen,
          label: 'Focus',
          shortcut: 'F',
          onPressed: nav.toggleFocusMode,
        ),
        const SizedBox(width: 18),
        HpiToolButton(
          icon: Icons.tune,
          label: 'Channels $visibleCount / $totalCount',
          onPressed: () => nav.selectTool(InspectorTool.channels),
        ),
        const SizedBox(width: 8),
        HpiToolButton(
          icon: Icons.fit_screen,
          label: 'Auto-scale',
          onPressed: controller.autoScaleAll,
        ),
        const SizedBox(width: HpiMetrics.screenPadding),
      ],
    );
  }
}

/// Drops an event marker into the running recording, or explains why it can't.
class _MarkerButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<RecordingEngine>();
    final recording = engine.state == RecordingState.recording;
    return HpiToolButton(
      icon: Icons.bookmark_add,
      label: 'Mark event',
      shortcut: 'M',
      tooltip: recording
          ? 'Drop a marker at the current sample'
          : 'Markers are written into a recording — start recording first',
      onPressed: recording ? () => dropMarker(context) : null,
    );
  }
}

/// Shared by the toolbar button and the `M` shortcut.
void dropMarker(BuildContext context) {
  final engine = context.read<RecordingEngine>();
  if (engine.state != RecordingState.recording) return;
  engine.addEvent(EventMarker(
    sequenceNumber: engine.samplesRecorded,
    timestampMicros: engine.elapsedTime.inMicroseconds,
    type: 'event',
    description: 'Marker at ${formatClock(engine.elapsedTime)}',
  ));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Marker dropped at ${formatClock(engine.elapsedTime)}'),
      duration: const Duration(seconds: 2),
    ),
  );
}

/// The channel canvas: one row per visible channel, gutter and readout attached.
class _Canvas extends StatelessWidget {
  const _Canvas({required this.controller, required this.channels});

  final ChannelController controller;
  final Map<String, ChannelData> channels;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const ScreenEmptyState(
        icon: Icons.tune,
        title: 'No channels shown',
        message: 'Every channel is hidden. Open the Channels inspector from the '
            'dock on the right to bring one back.',
      );
    }
    final settings = context.watch<StudioSettings>();
    final eeg = context.watch<EEGPacketService>();
    final p = context.hpi;
    final entries = channels.entries.toList();

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          Expanded(
            flex: (entries[i].value.config.heightRatio * 100).round(),
            child: _ChannelRow(
              data: entries[i].value,
              controller: controller,
              windowSeconds: settings.windowSeconds,
              thickness: settings.traceThickness,
              gridDivisions: settings.gridDivisions,
              color: p.trace.forChannel(entries[i].key),
              leadOff: _leadOff(entries[i].key, eeg),
              last: i == entries.length - 1,
            ),
          ),
      ],
    );
  }

  /// Lead-off is only reported by the device for EEG; nothing is inferred for
  /// the other modalities.
  static bool? _leadOff(String channelId, EEGPacketService eeg) {
    if (eeg.latestData == null) return null;
    return switch (channelId) {
      'eeg1' => !eeg.isChannelConnected(0),
      'eeg2' => !eeg.isChannelConnected(1),
      _ => null,
    };
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.data,
    required this.controller,
    required this.windowSeconds,
    required this.thickness,
    required this.gridDivisions,
    required this.color,
    required this.last,
    this.leadOff,
  });

  final ChannelData data;
  final ChannelController controller;
  final double windowSeconds;
  final double thickness;
  final int gridDivisions;
  final Color color;
  final bool last;
  final bool? leadOff;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final readout = ChannelReadout.of(data);
    final config = data.config;

    final (String quality, Color tone) = switch (leadOff) {
      true => ('Lead off', p.error),
      false => ('Contact', p.success),
      null => readout.hasSignal ? ('Signal', p.success) : ('Flat', p.warning),
    };

    return DecoratedBox(
      decoration: last
          ? const BoxDecoration()
          : BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Gutter(
            data: data,
            controller: controller,
            color: color,
          ),
          Expanded(
            child: HpiWaveTrace(
              data: data,
              windowSeconds: windowSeconds,
              color: color,
              strokeWidth: config.lineWidth == 0 ? thickness : config.lineWidth,
              gridDivisions: gridDivisions,
            ),
          ),
          Container(
            width: HpiMetrics.channelReadoutWidth,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: p.well,
              border: Border(left: BorderSide(color: p.divider)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                HpiMono(
                  readout.formatted(config.unit,
                      decimals: config.decimalPlaces.clamp(0, 3)),
                  size: 11.5,
                  color: p.textPrimary,
                ),
                const SizedBox(height: 3),
                HpiMono(readout.span, size: 9.5, color: p.textFaint),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    HpiStatusDot(color: tone, size: 6),
                    const SizedBox(width: 4),
                    HpiLabel(quality, letterSpacing: 0.6),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The channel gutter: name in its trace colour, acquisition detail, gain steps.
class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.data,
    required this.controller,
    required this.color,
  });

  final ChannelData data;
  final ChannelController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final config = data.config;
    final autoScale = config.autoScale;
    return Container(
      width: HpiMetrics.channelGutterWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.well,
        border: Border(right: BorderSide(color: p.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: HpiFonts.ui,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.55,
              color: color,
            ),
          ),
          const SizedBox(height: 5),
          HpiMono(LiveDataPump.channelDetail(config.id),
              size: 9.5, color: p.textFaint),
          const Spacer(),
          Row(
            children: [
              _Step(
                icon: Icons.remove,
                onTap: autoScale ? null : () => _scale(1.25),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: HpiMono(
                  autoScale ? 'auto' : _gainLabel(config),
                  size: 9.5,
                  color: p.textSecondary,
                  align: TextAlign.center,
                ),
              ),
              const SizedBox(width: 4),
              _Step(
                icon: Icons.add,
                onTap: autoScale ? null : () => _scale(0.8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tightening the range magnifies the trace, which is what a gain step means.
  void _scale(double factor) {
    final config = data.config;
    final centre = (config.minValue + config.maxValue) / 2;
    final half = ((config.maxValue - config.minValue) / 2) * factor;
    controller.setChannelScale(config.id, centre - half, centre + half);
  }

  static String _gainLabel(ChannelConfiguration config) {
    final span = (config.maxValue - config.minValue).abs();
    return '±${(span / 2).toStringAsFixed(0)} ${config.unit}';
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: 17,
            height: 17,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.cardInner,
              border: Border.all(color: p.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 12, color: p.textMuted),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Focus mode (design 2a)
// ─────────────────────────────────────────────────────────────────────────────

/// Focus mode: the vitals strip and dock collapse, traces go full-bleed, vitals
/// float top-left, and the controls gather into a bottom capsule. `Esc` or the
/// Focus toggle returns to the default layout.
class _FocusLayout extends StatelessWidget {
  const _FocusLayout({required this.controller, required this.channels});

  final ChannelController controller;
  final Map<String, ChannelData> channels;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final settings = context.watch<StudioSettings>();
    final entries = channels.entries.toList();

    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                Expanded(
                  child: DecoratedBox(
                    decoration: i == entries.length - 1
                        ? const BoxDecoration()
                        : BoxDecoration(
                            border:
                                Border(bottom: BorderSide(color: p.divider)),
                          ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: HpiWaveTrace(
                            data: entries[i].value,
                            windowSeconds: settings.windowSeconds,
                            color: p.trace.forChannel(entries[i].key),
                            strokeWidth: entries[i].value.config.lineWidth,
                            gridDivisions: settings.gridDivisions,
                          ),
                        ),
                        Positioned(
                          left: 20,
                          bottom: 10,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                entries[i].value.config.label.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: HpiFonts.ui,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.38,
                                  color: p.trace.forChannel(entries[i].key),
                                ),
                              ),
                              const SizedBox(width: 9),
                              HpiMono(
                                LiveDataPump.channelDetail(entries[i].key),
                                size: 10,
                                color: p.textFaint,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Positioned(top: 14, left: 20, child: _VitalsHud()),
        const Positioned(bottom: 18, left: 0, right: 0, child: _ControlCapsule()),
      ],
    );
  }
}

/// The vitals HUD — the same numbers as the strip, floated over the canvas.
class _VitalsHud extends StatelessWidget {
  const _VitalsHud();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final pump = context.watch<LiveDataPump>();
    final parser = context.watch<DataParser>();
    final hrv = context.watch<HRVPacketService>();
    final settings = context.watch<StudioSettings>();
    final data = parser.currentOpenViewData;
    final simulated = pump.isSimulated;

    String v(num? value, {int decimals = 0}) => value == null || value == 0
        ? '—'
        : value.toStringAsFixed(decimals);

    final double? tempC =
        simulated ? pump.tempTrend.lastOrNull : data?.temperature;

    final items = <(IconData, Color, String, String, bool)>[
      (
        Icons.favorite,
        p.trace.ecg1,
        v(simulated ? pump.hrTrend.lastOrNull : data?.heartRate),
        'bpm',
        true
      ),
      (
        Icons.bloodtype_outlined,
        p.trace.ppg,
        v(simulated ? pump.spo2Trend.lastOrNull : data?.spo2),
        '%',
        false
      ),
      (
        Icons.air,
        p.trace.respiration,
        v(simulated ? pump.respTrend.lastOrNull : data?.respirationRate),
        '/min',
        false
      ),
      (
        Icons.device_thermostat,
        p.trace.temperature,
        v(tempC == null ? null : settings.temperature(tempC), decimals: 1),
        settings.temperatureUnit,
        false
      ),
      (
        Icons.ssid_chart,
        p.trace.eeg1,
        hrv.sdnn == null ? '—' : '${hrv.sdnn}',
        'ms',
        false
      ),
    ];

    return _HudPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(width: 20),
              Container(width: 1, height: 24, color: p.hudOutline),
              const SizedBox(width: 20),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                items[i].$5
                    ? Icon(items[i].$1, size: 17, color: items[i].$2)
                    : Icon(items[i].$1, size: 17, color: items[i].$2),
                const SizedBox(width: 7),
                Text(
                  items[i].$3,
                  style: HpiText.mono(p.textPrimary,
                      size: 28, weight: FontWeight.w500),
                ),
                const SizedBox(width: 7),
                Text(items[i].$4.toUpperCase(), style: HpiText.unit(p)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The floating control capsule: the toolbar's essentials, nothing more.
class _ControlCapsule extends StatelessWidget {
  const _ControlCapsule();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    final settings = context.watch<StudioSettings>();
    final pump = context.watch<LiveDataPump>();
    final controller = pump.controller;
    final paused = controller.settings.isPaused;

    return Align(
      child: _HudPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        elevated: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HpiToolButton(
              icon: Icons.fullscreen_exit,
              label: 'Focus',
              active: true,
              height: 34,
              onPressed: nav.toggleFocusMode,
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 24, color: p.hudOutline),
            const SizedBox(width: 10),
            HpiToolButton(
              icon: paused ? Icons.play_arrow : Icons.pause,
              label: paused ? 'Resume' : 'Freeze',
              translucent: true,
              height: 32,
              onPressed: controller.togglePause,
            ),
            const SizedBox(width: 10),
            const SizedBox(width: 10),
            _CapsuleMarker(),
            const SizedBox(width: 10),
            Container(width: 1, height: 24, color: p.hudOutline),
            const SizedBox(width: 10),
            HpiSegmented<double>(
              translucent: true,
              segments: const [
                HpiSegment(value: 12.5, label: '12.5'),
                HpiSegment(value: 25, label: '25'),
                HpiSegment(value: 50, label: '50'),
              ],
              value: settings.sweepSpeedMmPerSec,
              onChanged: (v) => settings.sweepSpeedMmPerSec = v,
            ),
            const SizedBox(width: 10),
            HpiSegmented<double>(
              translucent: true,
              segments: const [
                HpiSegment(value: 5, label: '5s'),
                HpiSegment(value: 10, label: '10s'),
                HpiSegment(value: 30, label: '30s'),
              ],
              value: settings.windowSeconds,
              onChanged: (v) {
                settings.windowSeconds = v;
                controller.setTimeWindow(v);
              },
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 24, color: p.hudOutline),
            const SizedBox(width: 10),
            HpiToolButton(
              icon: Icons.tune,
              label: '${controller.visibleChannels.length}'
                  ' / ${controller.channels.length}',
              translucent: true,
              height: 32,
              onPressed: () {
                nav.setFocusMode(false);
                nav.selectTool(InspectorTool.channels);
              },
            ),
            const SizedBox(width: 8),
            HpiMono('ESC exits', size: 9.5, color: p.textFaint),
          ],
        ),
      ),
    );
  }
}

class _CapsuleMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<RecordingEngine>();
    final recording = engine.state == RecordingState.recording;
    return HpiToolButton(
      icon: Icons.bookmark_add,
      label: 'Mark',
      translucent: true,
      height: 32,
      tooltip: recording ? null : 'Start recording to drop markers',
      onPressed: recording ? () => dropMarker(context) : null,
    );
  }
}

/// The translucent, blurred panel both HUD elements are built from.
class _HudPanel extends StatelessWidget {
  const _HudPanel({
    required this.child,
    required this.padding,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return ClipRRect(
      borderRadius: BorderRadius.circular(elevated ? HpiRadius.hud : 14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: elevated ? 14 : 10, sigmaY: elevated ? 14 : 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: p.hudSurface,
            border: Border.all(color: p.hudOutline),
            borderRadius: BorderRadius.circular(elevated ? HpiRadius.hud : 14),
            boxShadow: elevated
                ? const [
                    BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 32,
                      offset: Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// `MM:SS` or `HH:MM:SS` for the streaming clock.
String formatClock(Duration d) {
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:$m:$s';
  return '$m:$s';
}
