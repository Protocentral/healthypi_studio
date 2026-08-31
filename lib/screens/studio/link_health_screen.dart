import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/data_parser.dart';
import '../../services/eeg_packet_service.dart';
import '../../services/hrv_packet_service.dart';
import '../../services/live_data_pump.dart';
import '../../services/throughput_monitor.dart';
import '../../services/usb_serial_service.dart';
import '../../services/wifi_serial_service.dart';
import '../../shell/screen_frame.dart';
import '../../shell/studio_nav.dart';
import '../../shell/studio_shell.dart';
import '../../theme/hpi_tokens.dart';
import '../../widgets/hpi/hpi_plots.dart';
import '../../widgets/hpi/hpi_primitives.dart';
import '../../widgets/hpi/hpi_table.dart';

/// Link health (design 2f).
///
/// Four headline counters, throughput over time with a gap timeline underneath,
/// and a per-stream table showing expected against actual rate — the fastest way
/// to tell a bad cable from a bad electrode.
class LinkHealthScreen extends StatefulWidget {
  const LinkHealthScreen({super.key});

  @override
  State<LinkHealthScreen> createState() => LinkHealthScreenState();
}

class LinkHealthScreenState extends State<LinkHealthScreen> {
  /// Throughput samples in KB/s, one per second.
  final List<double> _throughputTrend = [];

  /// Gap positions as fractions of the visible window.
  final List<double> _gaps = [];
  final List<_LinkEvent> _events = [];
  Timer? _timer;
  int _lastGapCount = 0;

  static const int _trendLength = 120;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sample());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sample() {
    if (!mounted) return;
    final monitor = context.read<ThroughputMonitor>();
    final parser = context.read<DataParser>();
    final metrics = _activeMetrics(monitor);

    setState(() {
      _throughputTrend.add((metrics?.bytesPerSecond ?? 0) / 1024);
      if (_throughputTrend.length > _trendLength) _throughputTrend.removeAt(0);

      // A new sequence gap since the last tick lands on the timeline at "now".
      if (parser.sequenceGaps > _lastGapCount) {
        _gaps.add(1.0);
        _events.insert(
          0,
          _LinkEvent(
            DateTime.now(),
            'Sequence gap — ${parser.missingBySequence} packets missing in total',
            _LinkSeverity.warning,
          ),
        );
        _lastGapCount = parser.sequenceGaps;
      }
      // Age the existing markers along with the window.
      for (var i = 0; i < _gaps.length; i++) {
        _gaps[i] -= 1 / _trendLength;
      }
      _gaps.removeWhere((g) => g < 0);
      if (_events.length > 40) _events.removeRange(40, _events.length);
    });
  }

  static StreamMetrics? _activeMetrics(ThroughputMonitor monitor) {
    if (monitor.streams.isEmpty) return null;
    return monitor.streams.values.first;
  }

  List<Widget> buildStatusItems(BuildContext context) {
    final p = context.hpi;
    final parser = context.watch<DataParser>();
    final pump = context.watch<LiveDataPump>();
    final healthy = parser.sequenceGaps == 0;
    return [
      StatusItem(
        pump.hasDevice
            ? '${parser.protocolVersionString} · ${healthy ? "seq OK" : "gaps seen"}'
            : 'no transport attached',
        icon: pump.hasDevice
            ? (healthy ? Icons.check_circle : Icons.warning_amber_rounded)
            : Icons.usb_off,
        tone: pump.hasDevice ? (healthy ? p.success : p.warning) : p.textFaint,
      ),
      StatusItem('${parser.packetsPerSecond.toStringAsFixed(0)} Hz · '
          '${parser.sequenceGaps} gaps'),
      StatusItem('${parser.packetsReceived} pkt · '
          '${parser.packetsDropped} dropped'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final pump = context.watch<LiveDataPump>();
    final usb = context.watch<UsbSerialService>();
    final wifi = context.watch<WifiSerialService>();
    final parser = context.watch<DataParser>();
    final monitor = context.watch<ThroughputMonitor>();
    final metrics = _activeMetrics(monitor);

    final transport = usb.isConnected
        ? 'USB CDC · ${usb.connectedPortName ?? "port"}'
        : (wifi.isConnected
            ? 'WiFi · ${wifi.connectedDevice}:${wifi.port}'
            : 'No transport');

    return ScreenBody(
      header: ScreenHeader(
        title: StudioDestination.link.title,
        badge: pump.hasDevice
            ? HpiBadge('Live', tone: p.success)
            : HpiBadge('Offline', tone: p.textMuted),
        subtitle: '$transport · uptime ${formatDuration(pump.streamDuration)}',
        action: HpiGhostButton(
          label: 'Reconnect',
          icon: Icons.restart_alt,
          onPressed: usb.isConnected
              ? () async {
                  final port = usb.connectedPortName;
                  await usb.disconnect();
                  if (port != null) await usb.connect(port);
                }
              : null,
        ),
      ),
      child: ScreenColumns(
        sideWidth: 320,
        side: _SidePanel(events: _events),
        main: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 104,
              child: Row(
                children: [
                  Expanded(
                    child: _Counter(
                      label: 'Throughput',
                      value: metrics == null
                          ? '—'
                          : (metrics.bytesPerSecond / 1024).toStringAsFixed(1),
                      unit: 'KB/s',
                      tone: p.brand,
                    ),
                  ),
                  kCardGapH,
                  Expanded(
                    child: _Counter(
                      label: 'Packet rate',
                      value: parser.packetsPerSecond == 0
                          ? '—'
                          : parser.packetsPerSecond.toStringAsFixed(0),
                      unit: 'pkt/s',
                      tone: p.accent,
                    ),
                  ),
                  kCardGapH,
                  Expanded(
                    child: _Counter(
                      label: 'Dropped',
                      value: '${parser.packetsDropped}',
                      unit: 'total',
                      tone: parser.packetsDropped == 0 ? p.success : p.error,
                    ),
                  ),
                  kCardGapH,
                  Expanded(
                    child: _Counter(
                      label: 'Sequence gaps',
                      value: parser.hasSequenceTracking
                          ? '${parser.sequenceGaps}'
                          : 'n/a',
                      unit: parser.hasSequenceTracking
                          ? '${parser.missingBySequence} missing'
                          : 'v1 stream',
                      tone: parser.sequenceGaps == 0 ? p.success : p.warning,
                    ),
                  ),
                ],
              ),
            ),
            kCardGap,
            Expanded(
              child: _ThroughputCard(
                trend: _throughputTrend,
                gaps: _gaps,
                gapCount: parser.sequenceGaps,
                missing: parser.missingBySequence,
              ),
            ),
            kCardGap,
            _StreamsCard(pump: pump),
          ],
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.unit,
    required this.tone,
  });

  final String label;
  final String value;
  final String unit;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return HpiTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HpiLabel(label),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HpiText.vital(tone),
                ),
              ),
              const SizedBox(width: 6),
              Text(unit.toUpperCase(), style: HpiText.unit(p)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThroughputCard extends StatelessWidget {
  const _ThroughputCard({
    required this.trend,
    required this.gaps,
    required this.gapCount,
    required this.missing,
  });

  final List<double> trend;
  final List<double> gaps;
  final int gapCount;
  final int missing;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final peak = trend.isEmpty
        ? 0.0
        : trend.reduce((a, b) => a > b ? a : b);

    return HpiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HpiSectionTitle('Throughput', note: 'last 2 min · KB/s'),
          const SizedBox(height: 12),
          Expanded(
            child: trend.length < 2
                ? HpiWell(
                    child: Center(child: HpiNote('Collecting samples…')),
                  )
                : HpiPlotWell(
                    topLabel: peak <= 0
                        ? '0'
                        : peak.toStringAsFixed(0),
                    bottomLabel: '0',
                    child: HpiLinePlot(
                      values: trend,
                      color: p.brand,
                      minValue: 0,
                      maxValue: peak <= 0 ? 1 : peak * 1.15,
                      strokeWidth: 1.6,
                      fill: true,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 74, child: HpiLabel('Gaps')),
              Expanded(child: HpiGapTimeline(gaps: gaps)),
              const SizedBox(width: 10),
              HpiMono(
                gapCount == 0
                    ? 'no gaps this session'
                    : '$gapCount gaps · $missing packets missing',
                size: 10.5,
                color: gapCount == 0 ? p.textMuted : p.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Expected against actual, per stream.
///
/// The parser keeps one counter for the DBLK stream and separate counters for
/// the HRV and EEG packets — there is no per-modality counter for ECG,
/// respiration and PPG, because all three ride in the same record (one
/// `OpenViewData` per ECG sample). So ECG and respiration report the stream's
/// own rate, which is theirs, and PPG reports "shared" rather than the stream
/// rate divided by the 4:1 display decimation: that arithmetic looked like a
/// measurement and would have shown a healthy PPG row with the PPG front-end
/// dead.
class _StreamsCard extends StatelessWidget {
  const _StreamsCard({required this.pump});

  final LiveDataPump pump;

  static const List<HpiColumnSpec> _columns = [
    HpiColumnSpec('Stream', width: 150),
    HpiColumnSpec('Expected', width: 88),
    HpiColumnSpec('Actual', width: 88),
    HpiColumnSpec('Packets', width: 88),
    HpiColumnSpec('Health', flex: 1),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final parser = context.watch<DataParser>();
    final hrv = context.watch<HRVPacketService>();
    final eeg = context.watch<EEGPacketService>();

    // (name, expected Hz, actual Hz or null when not independently measured,
    //  packets or null when the count is not this stream's own)
    final rows = <(String, double, double?, int?)>[
      ('ECG (3 lead)', 500, parser.packetsPerSecond, parser.packetsReceived),
      ('Respiration', 500, parser.packetsPerSecond, parser.packetsReceived),
      ('PPG (red/IR)', LiveDataPump.ppgSampleRate, null, null),
      ('HRV metrics', 1, null, hrv.packetsReceived),
      ('EEG (Fp1/Fp2)', LiveDataPump.eegSampleRate, null,
          eeg.packetsReceived),
    ];

    return HpiCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: HpiTable(
        scrollable: false,
        columns: _columns,
        rows: [
          for (var i = 0; i < rows.length; i++)
            () {
              final (name, expected, actual, packets) = rows[i];
              final ratio =
                  actual == null || expected == 0 ? null : actual / expected;
              final tone = ratio == null
                  ? p.textFaint
                  : (ratio > 0.97 ? p.success : (ratio > 0.8 ? p.accent : p.error));
              return HpiTableRow(
                columns: _columns,
                last: i == rows.length - 1,
                cells: [
                  HpiCell(name, mono: false, color: p.textPrimary, size: 11),
                  HpiCell('${expected.toStringAsFixed(0)} Hz',
                      color: p.textMuted),
                  HpiCell(
                    actual != null
                        ? '${actual.toStringAsFixed(1)} Hz'
                        : (packets == null
                            ? 'shared'
                            : (packets > 0 ? 'streaming' : '—')),
                    color: p.textSecondary,
                  ),
                  HpiCell(packets == null ? '—' : '$packets',
                      color: p.textSecondary),
                  Row(
                    children: [
                      Expanded(
                        child: HpiMeter(
                          fraction:
                              ratio ?? ((packets != null && packets > 0) ? 1 : 0),
                          color: tone,
                          height: 6,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 74,
                        child: HpiMono(
                          ratio != null
                              ? '${(ratio * 100).clamp(0, 999).toStringAsFixed(0)}%'
                              : (packets == null
                                  ? 'with ECG'
                                  : (packets > 0 ? 'active' : 'idle')),
                          size: 10.5,
                          color: tone,
                          align: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }(),
        ],
      ),
    );
  }
}

/// Transport facts and the event log.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.events});

  final List<_LinkEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final usb = context.watch<UsbSerialService>();
    final wifi = context.watch<WifiSerialService>();
    final parser = context.watch<DataParser>();
    final nav = context.read<StudioNavController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HpiCard(
          child: HpiColumn(
            gap: 11,
            children: [
              const HpiLabel('Transport'),
              Row(
                children: [
                  Expanded(
                    child: HpiToolButton(
                      icon: Icons.usb,
                      label: 'USB CDC',
                      height: 32,
                      active: usb.isConnected,
                      onPressed: usb.isConnected
                          ? null
                          : () => nav.go(StudioDestination.live),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HpiToolButton(
                      icon: Icons.wifi,
                      label: 'WiFi',
                      height: 32,
                      active: wifi.isConnected,
                      onPressed: wifi.isConnected
                          ? null
                          : () => nav.go(StudioDestination.live),
                    ),
                  ),
                ],
              ),
              HpiKeyValue(
                'Port',
                usb.isConnected
                    ? (usb.connectedPortName?.split('/').last ?? '—')
                    : (wifi.isConnected ? '${wifi.port}' : '—'),
              ),
              HpiKeyValue('Baud', usb.isConnected ? '921 600' : '—'),
              HpiKeyValue('Protocol', parser.protocolVersionString),
              HpiKeyValue('Control port',
                  usb.controlConnected ? 'open (CDC1)' : 'closed'),
              HpiKeyValue('Buffered packets', '${parser.availablePackets}'),
              if (usb.isReconnecting)
                HpiNote('Reconnecting — attempt ${usb.reconnectAttempts}',
                    color: p.accent),
            ],
          ),
        ),
        kCardGap,
        Expanded(
          child: HpiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HpiLabel('Event log'),
                const SizedBox(height: 10),
                Expanded(
                  child: events.isEmpty
                      ? Center(
                          child: HpiNote(
                            'Nothing to report — no gaps or resyncs since this '
                            'screen was opened.',
                          ),
                        )
                      : ListView.separated(
                          itemCount: events.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => HpiLogLine(
                            time: _clock(events[i].at),
                            message: events[i].message,
                            tone: switch (events[i].severity) {
                              _LinkSeverity.info => p.textMuted,
                              _LinkSeverity.good => p.success,
                              _LinkSeverity.warning => p.accent,
                              _LinkSeverity.error => p.error,
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

enum _LinkSeverity { info, good, warning, error }

class _LinkEvent {
  const _LinkEvent(this.at, this.message, this.severity);

  final DateTime at;
  final String message;
  final _LinkSeverity severity;
}
