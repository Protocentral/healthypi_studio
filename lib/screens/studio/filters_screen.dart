import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/filter_models.dart';
import '../../services/digital_filter.dart';
import '../../services/filter_integration_service.dart';
import '../../services/live_data_pump.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_settings.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_plots.dart';
import '../../widgets/hpi/hpi_primitives.dart';

/// One stage in a modality's display chain.
class FilterStage {
  FilterStage({
    required this.name,
    required this.type,
    required this.enabled,
    required this.value,
    required this.min,
    required this.max,
    this.highValue,
    this.unit = 'Hz',
    this.followsMains = false,
  });

  final String name;
  final FilterType type;
  bool enabled;
  double value;
  final double min;
  final double max;

  /// Set for band-pass stages, where [value] is the low edge.
  final double? highValue;
  final String unit;

  /// Mains notch stages take their frequency from Settings, not from a slider.
  final bool followsMains;

  double get fraction =>
      max <= min ? 0 : ((value - min) / (max - min)).clamp(0.0, 1.0);

  set fraction(double f) => value = min + (max - min) * f.clamp(0.0, 1.0);

  String label(int mainsHz) {
    if (followsMains) return '$mainsHz $unit';
    if (highValue != null) {
      return '${_n(value)} – ${_n(highValue!)} $unit';
    }
    return '${_n(value)} $unit';
  }

  static String _n(double v) =>
      v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// One modality's chain, with the trace colour that identifies it.
class ModalityChain {
  ModalityChain({
    required this.id,
    required this.name,
    required this.channelIds,
    required this.samplingRate,
    required this.stages,
  });

  final String id;
  final String name;
  final List<String> channelIds;
  final double samplingRate;
  final List<FilterStage> stages;

  int get activeCount => stages.where((s) => s.enabled).length;
}

/// Filters (design 2e).
///
/// A before/after preview at the top so a change is legible immediately, then
/// the whole chain per modality in one grid. The "display only" badge and the
/// closing note answer the question this screen always raises.
class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => FiltersScreenState();
}

class FiltersScreenState extends State<FiltersScreen> {
  late List<ModalityChain> _chains = _defaultChains();
  String? _presetName = 'Resting ECG';
  bool _splitPreview = true;

  /// Preview channel — Lead II is the lead a clinician reads first.
  static const String _previewChannel = 'ecg2';

  List<Widget> buildStatusItems(BuildContext context) {
    final p = context.hpi;
    final active = _chains.fold<int>(0, (n, c) => n + c.activeCount);
    return [
      StatusItem('$active stages active', icon: Icons.filter_alt, tone: p.brand),
      StatusItem('${_latencyMs().toStringAsFixed(0)} ms added latency'),
      const StatusItem('raw capture unaffected'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return ScreenBody(
      header: ScreenHeader(
        title: StudioDestination.filters.title,
        badge: HpiBadge('Display only', tone: p.brand),
        subtitle: 'Applied to the on-screen trace · recordings stay raw',
        action: HpiGhostButton(
          label: 'Restore defaults',
          icon: Icons.restart_alt,
          onPressed: () => setState(() {
            _chains = _defaultChains();
            _presetName = 'Resting ECG';
            _apply();
          }),
        ),
      ),
      child: ScreenColumns(
        sideWidth: 296,
        side: _SidePanel(
          presetName: _presetName,
          latencyMs: _latencyMs(),
          onPreset: _applyPreset,
        ),
        main: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 226,
              child: _PreviewCard(
                split: _splitPreview,
                channelId: _previewChannel,
                chain: _chainFor(_previewChannel),
                mainsHz: context.watch<StudioSettings>().mains.hz,
                onSplit: (v) => setState(() => _splitPreview = v),
              ),
            ),
            kCardGap,
            Expanded(child: _ChainGrid(chains: _chains, onChanged: _onChanged)),
          ],
        ),
      ),
    );
  }

  void _onChanged() {
    setState(() => _presetName = null);
    _apply();
  }

  ModalityChain _chainFor(String channelId) =>
      _chains.firstWhere((c) => c.channelIds.contains(channelId),
          orElse: () => _chains.first);

  /// Push the chain into the service the acquisition path actually uses.
  ///
  /// `FilterIntegrationService` holds one filter per channel, so the enabled
  /// stage with the narrowest effect is the one applied; the rest are shown but
  /// noted as pending in the side panel.
  void _apply() {
    final service = context.read<FilterIntegrationService>();
    final mains = context.read<StudioSettings>().mains.hz.toDouble();
    var anyEnabled = false;

    for (final chain in _chains) {
      final stage = chain.stages.firstWhere(
        (s) => s.enabled,
        orElse: () => FilterStage(
          name: 'none',
          type: FilterType.lowpass,
          enabled: false,
          value: 0,
          min: 0,
          max: 1,
        ),
      );
      for (final channelId in chain.channelIds) {
        if (!stage.enabled) {
          service.removeFilterFromChannel(channelId);
          continue;
        }
        final design = FilterDesign(
          type: stage.type,
          cutoffLow: stage.followsMains ? mains : stage.value,
          cutoffHigh: stage.highValue,
          order: stage.type == FilterType.notch ? 2 : 4,
          samplingRate: chain.samplingRate,
          qFactor: stage.type == FilterType.notch ? 30 : null,
        );
        final error = design.validate();
        if (error != null) {
          debugPrint('⚠️ ${chain.name} ${stage.name}: $error');
          continue;
        }
        service.applyFilterToChannel(channelId, design);
        anyEnabled = true;
      }
    }
    service.setFilteringEnabled(anyEnabled);
  }

  void _applyPreset(String name) {
    setState(() {
      _presetName = name;
      _chains = switch (name) {
        'Exercise' => _defaultChains()
          ..first.stages[0].value = 1.0
          ..first.stages[1].value = 35,
        'EEG resting-state' => _defaultChains()
          ..forEach((c) {
            if (c.id == 'eeg') return;
            for (final s in c.stages) {
              s.enabled = false;
            }
          }),
        'Raw — no filtering' => _defaultChains()
          ..forEach((c) {
            for (final s in c.stages) {
              s.enabled = false;
            }
          }),
        _ => _defaultChains(),
      };
    });
    _apply();
  }

  /// Group delay of the enabled chain, at the modality's own sample rate.
  double _latencyMs() {
    var worst = 0.0;
    for (final chain in _chains) {
      for (final stage in chain.stages) {
        if (!stage.enabled) continue;
        final design = FilterDesign(
          type: stage.type,
          cutoffLow: stage.value <= 0 ? 0.5 : stage.value,
          cutoffHigh: stage.highValue,
          order: stage.type == FilterType.notch ? 2 : 4,
          samplingRate: chain.samplingRate,
          qFactor: stage.type == FilterType.notch ? 30 : null,
        );
        if (design.validate() != null) continue;
        final samples = OfflineFilter.estimateGroupDelay(design);
        final ms = samples / chain.samplingRate * 1000;
        if (ms > worst) worst = ms;
      }
    }
    return worst;
  }

  static List<ModalityChain> _defaultChains() => [
        ModalityChain(
          id: 'ecg',
          name: 'ECG',
          channelIds: const ['ecg1', 'ecg2', 'ecg3'],
          samplingRate: 500,
          stages: [
            FilterStage(
              name: 'Baseline high-pass',
              type: FilterType.highpass,
              enabled: true,
              value: 0.5,
              min: 0.1,
              max: 2,
            ),
            FilterStage(
              name: 'Low-pass',
              type: FilterType.lowpass,
              enabled: true,
              value: 40,
              min: 15,
              max: 150,
            ),
            FilterStage(
              name: 'Mains notch',
              type: FilterType.notch,
              enabled: true,
              value: 50,
              min: 50,
              max: 60,
              followsMains: true,
            ),
          ],
        ),
        ModalityChain(
          id: 'resp',
          name: 'Respiration',
          channelIds: const ['respiration'],
          samplingRate: 500,
          stages: [
            FilterStage(
              name: 'Band-pass',
              type: FilterType.bandpass,
              enabled: true,
              value: 0.1,
              highValue: 1.0,
              min: 0.05,
              max: 0.5,
            ),
          ],
        ),
        ModalityChain(
          id: 'ppg',
          name: 'PPG',
          channelIds: const ['ppg'],
          samplingRate: 125,
          stages: [
            FilterStage(
              name: 'Band-pass',
              type: FilterType.bandpass,
              enabled: true,
              value: 0.5,
              highValue: 8,
              min: 0.2,
              max: 2,
            ),
          ],
        ),
        ModalityChain(
          id: 'eeg',
          name: 'EEG',
          channelIds: const ['eeg1', 'eeg2'],
          samplingRate: 250,
          stages: [
            FilterStage(
              name: 'High-pass',
              type: FilterType.highpass,
              enabled: true,
              value: 0.5,
              min: 0.1,
              max: 2,
            ),
            FilterStage(
              name: 'Low-pass',
              type: FilterType.lowpass,
              enabled: true,
              value: 45,
              min: 20,
              max: 100,
            ),
            FilterStage(
              name: 'Mains notch',
              type: FilterType.notch,
              enabled: true,
              value: 50,
              min: 50,
              max: 60,
              followsMains: true,
            ),
          ],
        ),
      ];
}

/// Raw against filtered, on the same window, so a change is legible at a glance.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.split,
    required this.channelId,
    required this.chain,
    required this.mainsHz,
    required this.onSplit,
  });

  final bool split;
  final String channelId;
  final ModalityChain chain;
  final int mainsHz;
  final ValueChanged<bool> onSplit;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final pump = context.watch<LiveDataPump>();
    final raw = _recent(pump, channelId, 1000);
    final filtered = _filter(raw, chain, mainsHz);
    final tone = p.trace.forChannel(channelId);

    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HpiSectionTitle(
            'Before / after',
            note: 'Lead II · 2 s window',
            trailing: HpiSegmented<bool>(
              segments: const [
                HpiSegment(value: true, label: 'Split'),
                HpiSegment(value: false, label: 'Overlay'),
              ],
              value: split,
              onChanged: onSplit,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: raw.length < 8
                ? HpiWell(child: Center(child: HpiNote('Waiting for samples…')))
                : (split
                    ? Row(
                        children: [
                          Expanded(
                            child: _Pane(
                              title: 'Raw',
                              titleTone: p.textFaint,
                              sigma: _sigma(raw),
                              values: raw,
                              color: p.textMuted,
                            ),
                          ),
                          kCardGapH,
                          Expanded(
                            child: _Pane(
                              title: 'Filtered',
                              titleTone: tone,
                              sigma: _sigma(filtered),
                              values: filtered,
                              color: tone,
                            ),
                          ),
                        ],
                      )
                    : _OverlayPane(raw: raw, filtered: filtered, tone: tone)),
          ),
        ],
      ),
    );
  }

  static List<double> _recent(LiveDataPump pump, String channelId, int count) {
    final data = pump.controller.channels[channelId];
    if (data == null) return const [];
    final available = data.isBufferFull ? data.maxBufferSize : data.writeIndex;
    if (available == 0) return const [];
    final take = available < count ? available : count;
    final out = List<double>.filled(take, 0);
    final start = data.writeIndex - take;
    for (var i = 0; i < take; i++) {
      final idx = (start + i + data.maxBufferSize * 2) % data.maxBufferSize;
      out[i] = data.buffer[idx].value;
    }
    return out;
  }

  /// Run the preview through the real IIR implementation, not an approximation.
  static List<double> _filter(
      List<double> raw, ModalityChain chain, int mainsHz) {
    if (raw.isEmpty) return raw;
    var out = raw;
    for (final stage in chain.stages) {
      if (!stage.enabled) continue;
      final design = FilterDesign(
        type: stage.type,
        cutoffLow: stage.followsMains ? mainsHz.toDouble() : stage.value,
        cutoffHigh: stage.highValue,
        order: stage.type == FilterType.notch ? 2 : 4,
        samplingRate: chain.samplingRate,
        qFactor: stage.type == FilterType.notch ? 30 : null,
      );
      if (design.validate() != null) continue;
      out = OfflineFilter.apply(out, design, zeroPhase: true);
    }
    return out;
  }

  static double _sigma(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = xs.reduce((a, b) => a + b) / xs.length;
    var acc = 0.0;
    for (final x in xs) {
      acc += (x - m) * (x - m);
    }
    return math.sqrt(acc / xs.length);
  }
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.title,
    required this.titleTone,
    required this.sigma,
    required this.values,
    required this.color,
  });

  final String title;
  final Color titleTone;
  final double sigma;
  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontFamily: HpiFonts.ui,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.05,
                color: titleTone,
              ),
            ),
            const SizedBox(width: 8),
            HpiMono('σ ${sigma.toStringAsFixed(1)}',
                size: 9.5, color: p.textFaint),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: HpiPlotWell(
            child: HpiLinePlot(values: values, color: color, strokeWidth: 1.4),
          ),
        ),
      ],
    );
  }
}

class _OverlayPane extends StatelessWidget {
  const _OverlayPane({
    required this.raw,
    required this.filtered,
    required this.tone,
  });

  final List<double> raw;
  final List<double> filtered;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    // Both traces share one range so the comparison is honest.
    final all = [...raw, ...filtered];
    final lo = all.reduce((a, b) => a < b ? a : b);
    final hi = all.reduce((a, b) => a > b ? a : b);
    return HpiPlotWell(
      child: Stack(
        children: [
          Positioned.fill(
            child: HpiLinePlot(
              values: raw,
              color: p.textMuted.withValues(alpha: 0.7),
              minValue: lo,
              maxValue: hi,
              strokeWidth: 1.2,
            ),
          ),
          Positioned.fill(
            child: HpiLinePlot(
              values: filtered,
              color: tone,
              minValue: lo,
              maxValue: hi,
              strokeWidth: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every modality's chain in one grid, so the whole signal path is on one screen.
class _ChainGrid extends StatelessWidget {
  const _ChainGrid({required this.chains, required this.onChanged});

  final List<ModalityChain> chains;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final mains = context.watch<StudioSettings>().mains.hz;
    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HpiLabel('Filter chain'),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 20,
                runSpacing: 18,
                children: [
                  for (final chain in chains)
                    SizedBox(
                      width: _columnWidth(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 20,
                                height: 3,
                                color: p.trace
                                    .forChannel(chain.channelIds.first),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                chain.name.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: HpiFonts.ui,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.92,
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              HpiMono(
                                '${chain.samplingRate.toStringAsFixed(0)} Hz',
                                size: 9.5,
                                color: p.textFaint,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          for (final stage in chain.stages)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: HpiParamSlider(
                                name: stage.name,
                                enabled: stage.enabled,
                                fraction: stage.fraction,
                                valueLabel: stage.label(mains),
                                tone: p.trace
                                    .forChannel(chain.channelIds.first),
                                onToggle: (v) {
                                  stage.enabled = v;
                                  onChanged();
                                },
                                onChanged: stage.followsMains
                                    ? null
                                    : (f) {
                                        stage.fraction = f;
                                        onChanged();
                                      },
                              ),
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
    );
  }

  /// Two columns when there is room, one when there is not.
  static double _columnWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final available = width - HpiMetrics.railWidth - 296 - 120;
    return available > 760 ? (available - 20) / 2 : available;
  }
}

/// Presets, mains frequency, and the cost of the chain.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.presetName,
    required this.latencyMs,
    required this.onPreset,
  });

  final String? presetName;
  final double latencyMs;
  final ValueChanged<String> onPreset;

  static const List<(String, String)> _presets = [
    ('Resting ECG', 'HP 0.5 · LP 40 · notch'),
    ('Exercise', 'HP 1.0 · LP 35'),
    ('EEG resting-state', 'EEG only · HP 0.5 · LP 45 · notch'),
    ('Raw — no filtering', 'passthrough'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final settings = context.watch<StudioSettings>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HpiCard(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: HpiColumn(
            gap: 10,
            children: [
              const HpiLabel('Presets'),
              for (final preset in _presets)
                HpiOptionRow(
                  title: preset.$1,
                  subtitle: preset.$2,
                  selected: presetName == preset.$1,
                  icon: presetName == preset.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  onTap: () => onPreset(preset.$1),
                ),
              if (presetName == null)
                HpiNote('Custom chain — no preset matches the current settings.'),
            ],
          ),
        ),
        kCardGap,
        HpiCard(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          child: HpiColumn(
            gap: 11,
            children: [
              const HpiLabel('Mains frequency'),
              HpiSegmented<MainsFrequency>(
                height: 32,
                expand: true,
                segments: const [
                  HpiSegment(value: MainsFrequency.fifty, label: '50 Hz'),
                  HpiSegment(value: MainsFrequency.sixty, label: '60 Hz'),
                ],
                value: settings.mains,
                onChanged: (v) => settings.mains = v,
              ),
              HpiNote('Set once per region. The notch stage follows this '
                  'setting on every modality.'),
            ],
          ),
        ),
        kCardGap,
        Expanded(
          child: HpiCard(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            child: HpiColumn(
              gap: 10,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HpiLabel('Cost'),
                HpiKeyValue(
                    'Added latency', '${latencyMs.toStringAsFixed(0)} ms'),
                const HpiRule(),
                HpiNote(
                  'Filtering never touches the file on disk. Exports can opt in '
                  'from the Recordings screen.',
                ),
                HpiNote(
                  'One stage per channel is applied to the live trace today; the '
                  'preview above shows the full chain.',
                  color: p.textFaint,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
