import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/hrv_packet_service.dart';
import '../../services/live_data_pump.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_plots.dart';
import '../../widgets/hpi/hpi_primitives.dart';

/// HRV analysis (design 2b).
///
/// Metric tiles use the vitals-card grammar; the Poincaré plot and the R-R
/// tachogram are first-class cards rather than an afterthought. Reset is a quiet
/// outline button — amber stays reserved for Record.
class HrvScreen extends StatelessWidget {
  const HrvScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final hrv = context.watch<HRVPacketService>();
    final pump = context.watch<LiveDataPump>();
    final beats = hrv.rrIntervals;
    final quality = hrv.signalQuality;

    return ScreenBody(
      header: ScreenHeader(
        title: StudioDestination.hrv.title,
        badge: hrv.isConnected && hrv.latestData != null
            ? (hrv.isValid
                ? HpiBadge('Live', tone: p.success)
                : HpiBadge('Learning', tone: p.accent))
            : HpiBadge('No data', tone: p.textMuted),
        subtitle: hrv.latestData == null
            ? 'The device streams HRV as its own packet type · nothing received yet'
            : '${beats.length} R-R intervals · '
                '${hrv.packetsReceived} packets · '
                '${quality == null ? "quality unknown" : "signal quality $quality%"}',
        action: HpiGhostButton(
          label: 'Reset session',
          icon: Icons.restart_alt,
          onPressed: hrv.packetsReceived == 0 ? null : hrv.reset,
        ),
      ),
      child: ScreenColumns(
        sideFirst: true,
        sideWidth: 400,
        side: _MetricsColumn(hrv: hrv, pump: pump),
        main: _PlotsCard(hrv: hrv),
      ),
    );
  }
}

class _MetricsColumn extends StatelessWidget {
  const _MetricsColumn({required this.hrv, required this.pump});

  final HRVPacketService hrv;
  final LiveDataPump pump;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final data = hrv.latestData;

    // The firmware's HRV packet carries pNN50 and mean R-R, but the current
    // build reports them as zero. Say so rather than printing a plausible 0.
    String metric(int? value) => value == null ? '—' : '$value';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'SDNN',
                value: metric(hrv.sdnn),
                unit: 'ms',
                tag: data?.sdnnLevel,
              ),
            ),
            kCardGapH,
            Expanded(
              child: _MetricTile(
                label: 'RMSSD',
                value: metric(hrv.rmssd),
                unit: 'ms',
                tag: data?.rmssdLevel,
              ),
            ),
          ],
        ),
        kCardGap,
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'pNN50',
                value: metric(hrv.pnn50),
                unit: '%',
                footnote: hrv.pnn50 == 0 ? 'not reported by firmware' : null,
              ),
            ),
            kCardGapH,
            Expanded(
              child: _MetricTile(
                label: 'Mean R-R',
                value: metric(hrv.meanRr),
                unit: 'ms',
                footnote: hrv.meanRr == 0 ? 'not reported by firmware' : null,
              ),
            ),
          ],
        ),
        kCardGap,
        Expanded(
          child: HpiCard(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            child: HpiColumn(
              gap: 10,
              children: [
                const HpiLabel('Session'),
                HpiKeyValue(
                    'Heart rate',
                    hrv.heartRate == null
                        ? '—'
                        : '${hrv.heartRate} BPM'),
                HpiKeyValue('Last R-R',
                    hrv.rrInterval == null ? '—' : '${hrv.rrInterval} ms'),
                HpiKeyValue('Window', formatClockHms(hrv.historyDuration)),
                HpiKeyValue('Packets received', '${hrv.packetsReceived}'),
                HpiKeyValue(
                  'Arrhythmia flags',
                  data == null
                      ? '—'
                      : (data.hasArrhythmia ? _flags(data) : 'none'),
                  valueColor: data == null
                      ? null
                      : (data.hasArrhythmia ? p.warning : p.success),
                ),
                const HpiRule(margin: EdgeInsets.symmetric(vertical: 2)),
                HpiNote(
                  'Metrics are computed on the device and streamed as HRV '
                  'packets — Studio does not derive them. Research use only, '
                  'not a diagnostic measure.',
                ),
                if (pump.isSimulated)
                  HpiNote(
                    'No device attached, and the built-in generator does not '
                    'produce HRV packets — this screen stays empty until a board '
                    'is connected.',
                    color: p.accent,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _flags(dynamic data) {
    final out = <String>[];
    if (data.bradycardia as bool) out.add('brady');
    if (data.tachycardia as bool) out.add('tachy');
    return out.isEmpty ? 'flagged' : out.join(' · ');
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.unit,
    this.tag,
    this.footnote,
  });

  final String label;
  final String value;
  final String unit;
  final String? tag;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final tone = switch (tag?.toLowerCase()) {
      'normal' => p.success,
      'low' || 'high' => p.warning,
      'very low' => p.error,
      _ => p.textMuted,
    };
    return HpiTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HpiLabel(label),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: HpiText.vital(p.textPrimary)),
              const SizedBox(width: 5),
              Text(unit.toUpperCase(), style: HpiText.unit(p)),
            ],
          ),
          if (tag != null) ...[
            const SizedBox(height: 8),
            HpiTag(tag!, tone: tone),
          ] else if (footnote != null) ...[
            const SizedBox(height: 8),
            HpiNote(footnote!),
          ],
        ],
      ),
    );
  }
}

class _PlotsCard extends StatelessWidget {
  const _PlotsCard({required this.hrv});

  final HRVPacketService hrv;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final beats = hrv.rrIntervals;
    final stats = _PoincareStats.of(beats);

    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HpiSectionTitle('Poincaré', note: 'RRn vs RRn+1'),
          const SizedBox(height: 10),
          Expanded(
            child: HpiPoincarePlot(intervals: beats, color: p.trace.eeg1),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              HpiStatusDot(color: p.trace.eeg1, size: 9),
              const SizedBox(width: 6),
              HpiMono('${beats.length} beats', size: 10.5, color: p.textMuted),
              const SizedBox(width: 16),
              if (stats != null)
                HpiMono(
                  'SD1 ${stats.sd1.toStringAsFixed(0)} ms · '
                  'SD2 ${stats.sd2.toStringAsFixed(0)} ms',
                  size: 10.5,
                  color: p.textMuted,
                ),
              const Spacer(),
              if (stats != null && stats.sd1 > 0)
                HpiMono(
                  'SD2/SD1 ${(stats.sd2 / stats.sd1).toStringAsFixed(2)}',
                  size: 10.5,
                  color: p.textFaint,
                ),
            ],
          ),
          const HpiRule(margin: EdgeInsets.fromLTRB(0, 14, 0, 12)),
          HpiSectionTitle('R-R tachogram',
              note: '${beats.length} most recent intervals'),
          const SizedBox(height: 10),
          SizedBox(
            height: 132,
            child: beats.length < 2
                ? HpiWell(
                    child: Center(
                      child: HpiNote('Waiting for R-R intervals'),
                    ),
                  )
                : HpiPlotWell(
                    topLabel: '${_max(beats)} ms',
                    bottomLabel: '${_min(beats)} ms',
                    child: HpiLinePlot(
                      values: beats.map((e) => e.toDouble()).toList(),
                      color: p.trace.eeg1,
                      strokeWidth: 1.6,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static int _min(List<int> xs) => xs.reduce((a, b) => a < b ? a : b);
  static int _max(List<int> xs) => xs.reduce((a, b) => a > b ? a : b);
}

/// SD1/SD2 computed here from the streamed intervals, so the caption under the
/// plot describes the points that are actually drawn.
class _PoincareStats {
  const _PoincareStats(this.sd1, this.sd2);

  final double sd1;
  final double sd2;

  static _PoincareStats? of(List<int> intervals) {
    if (intervals.length < 3) return null;
    final diffs = <double>[];
    for (var i = 1; i < intervals.length; i++) {
      diffs.add((intervals[i] - intervals[i - 1]).toDouble());
    }
    final sd1 = _sd(diffs) / math.sqrt2;
    final sdnn = _sd(intervals.map((e) => e.toDouble()).toList());
    final sd2sq = 2 * sdnn * sdnn - sd1 * sd1;
    return _PoincareStats(sd1, sd2sq <= 0 ? 0 : math.sqrt(sd2sq));
  }

  static double _sd(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = xs.reduce((a, b) => a + b) / xs.length;
    var acc = 0.0;
    for (final x in xs) {
      acc += (x - m) * (x - m);
    }
    return math.sqrt(acc / xs.length);
  }
}

/// `HH:MM:SS` for the session window.
String formatClockHms(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
