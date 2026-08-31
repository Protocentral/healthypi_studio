import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/live_data_pump.dart';
import '../services/recording_engine.dart';
import '../services/usb_serial_service.dart';
import '../services/wifi_serial_service.dart';
import '../models/recording_models.dart';
import '../theme/hpi_tokens.dart';
import '../widgets/hpi/hpi_brand.dart';
import '../widgets/hpi/hpi_primitives.dart';
import 'studio_nav.dart';
import 'studio_settings.dart';

/// One chrome for every screen: top device bar, labelled rail, and a single
/// status line. Screens are content inside it and never push their own
/// `Scaffold`, so the rail can never vanish.
class StudioShell extends StatelessWidget {
  const StudioShell({
    super.key,
    required this.child,
    required this.primaryAction,
    required this.statusItems,
    this.chromeDimmed = false,
    this.hideRailLabels = false,
  });

  /// The screen's content.
  final Widget child;

  /// The screen's single amber action, or null when it has none.
  final Widget? primaryAction;

  /// The status-line items, left to right; the clock is appended by the shell.
  final List<Widget> statusItems;

  /// Connect state: the rail dims rather than disappearing.
  final bool chromeDimmed;
  final bool hideRailLabels;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      color: p.canvas,
      child: Column(
        children: [
          StudioAppBar(primaryAction: primaryAction),
          Expanded(
            child: Row(
              children: [
                StudioRail(dimInactive: chromeDimmed, hideLabels: hideRailLabels),
                Expanded(child: RepaintBoundary(child: child)),
              ],
            ),
          ),
          StudioStatusBar(items: statusItems),
        ],
      ),
    );
  }
}

/// The top device bar. Identity on the left, link and session state in the
/// middle, theme switch and the one primary action on the right.
class StudioAppBar extends StatelessWidget {
  const StudioAppBar({super.key, this.primaryAction});

  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final compact = context.hpiCompact;
    return Container(
      height: HpiMetrics.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: p.chrome,
        border: Border(bottom: BorderSide(color: p.outlineSoft)),
      ),
      child: Row(
        children: [
          const HpiWordmark(),
          const SizedBox(width: 14),
          Container(width: 1, height: 24, color: p.outlineSoft),
          const SizedBox(width: 14),
          const _LinkChip(),
          if (!compact) ...[
            const SizedBox(width: 10),
            const _RateChip(),
            const SizedBox(width: 10),
            const _StorageChip(),
          ],
          const Spacer(),
          const _SessionPill(),
          const SizedBox(width: 10),
          const _ThemeSwitch(),
          if (primaryAction != null) ...[
            const SizedBox(width: 10),
            primaryAction!,
          ],
        ],
      ),
    );
  }
}

/// Device identity and transport. Green and pulsing while a board is streaming;
/// grey and still when nothing is attached.
class _LinkChip extends StatelessWidget {
  const _LinkChip();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    return Consumer3<UsbSerialService, WifiSerialService, LiveDataPump>(
      builder: (context, usb, wifi, pump, _) {
        if (!pump.hasDevice) {
          return HpiChip(
            onTap: nav.showConnect,
            children: [
              HpiStatusDot(color: p.textFaint, size: 7),
              Text(
                pump.isSimulated ? 'Demo data' : 'No device',
                style: HpiText.control(p).copyWith(color: p.textSecondary),
              ),
              HpiMono(
                pump.isSimulated ? 'simulated' : 'not connected',
                size: 10,
                color: p.textFaint,
              ),
            ],
          );
        }
        final transport = usb.isConnected
            ? 'USB CDC · ${_shortPort(usb.connectedPortName)}'
            : 'WiFi · ${wifi.connectedDevice ?? "tcp"}';
        return HpiChip(
          tone: p.success,
          onTap: () => nav.go(StudioDestination.link),
          children: [
            HpiStatusDot(color: p.success, size: 7, pulse: true),
            Text(
              'HealthyPi 6',
              style: HpiText.control(p)
                  .copyWith(color: p.textPrimary, fontWeight: FontWeight.w500),
            ),
            HpiMono(transport, size: 10, color: p.textMuted),
          ],
        );
      },
    );
  }

  static String _shortPort(String? port) {
    if (port == null) return 'port';
    final parts = port.split('/');
    return parts.isEmpty ? port : parts.last;
  }
}

/// Live sample rate and loss, the two numbers that say whether to trust a trace.
class _RateChip extends StatelessWidget {
  const _RateChip();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    return Consumer<LiveDataPump>(
      builder: (context, pump, _) {
        final parser = context.watch<StudioLinkSnapshot>();
        final rate = parser.packetsPerSecond;
        final loss = parser.lossPercent;
        final healthy = pump.isSimulated || (rate > 0 && loss < 1);
        return HpiChip(
          onTap: () => nav.go(StudioDestination.link),
          children: [
            HpiMono(
              pump.isSimulated ? '500 Hz' : '${rate.toStringAsFixed(0)} Hz',
              size: 10.5,
              color: healthy ? p.success : p.warning,
            ),
            Text('|', style: TextStyle(color: p.textFaint, fontSize: 11)),
            HpiMono(
              pump.isSimulated
                  ? 'demo'
                  : '${loss.toStringAsFixed(2)}% loss',
              size: 10.5,
              color: p.textSecondary,
            ),
          ],
        );
      },
    );
  }
}

/// Free space where recordings land — the constraint a long session hits first.
class _StorageChip extends StatelessWidget {
  const _StorageChip();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    return Consumer<RecordingEngine>(
      builder: (context, engine, _) {
        return HpiChip(
          onTap: () => nav.go(StudioDestination.records),
          children: [
            Icon(Icons.sd_card, size: 15, color: p.brand),
            HpiMono(
              engine.state == RecordingState.recording
                  ? _formatBytes(engine.fileSizeBytes)
                  : 'Recordings',
              size: 10.5,
              color: p.textSecondary,
            ),
          ],
        );
      },
    );
  }
}

/// Subject/session pill — set once in Settings, stamped into every file.
class _SessionPill extends StatelessWidget {
  const _SessionPill();

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.read<StudioNavController>();
    return Consumer<StudioSession>(
      builder: (context, session, _) => HpiChip(
        onTap: () => nav.go(StudioDestination.settings),
        children: [
          Icon(Icons.badge_outlined, size: 15, color: p.textMuted),
          Text(
            session.sessionId,
            style: HpiText.control(p).copyWith(color: p.textPrimary),
          ),
          if (session.hasSubject) ...[
            Text('·', style: TextStyle(color: p.textFaint, fontSize: 11)),
            Text(session.subject, style: HpiText.control(p)),
          ] else
            Text(
              'no subject',
              style: HpiText.control(p).copyWith(color: p.textFaint),
            ),
          Icon(Icons.expand_more, size: 15, color: p.textFaint),
        ],
      ),
    );
  }
}

/// Dark/light switch — the same tokens on an inverted ramp.
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StudioSettings>();
    final isLight = Theme.of(context).brightness == Brightness.light;
    return HpiSegmented<bool>(
      segments: const [
        HpiSegment(value: false, icon: Icons.dark_mode),
        HpiSegment(value: true, icon: Icons.light_mode),
      ],
      value: isLight,
      onChanged: (light) =>
          settings.themeMode = light ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

/// The labelled rail. Amber left-edge indicator on the active destination —
/// nowhere else in the rail is amber used.
class StudioRail extends StatelessWidget {
  const StudioRail({super.key, this.dimInactive = false, this.hideLabels = false});

  /// Connect state: destinations that need a source are dimmed, not removed.
  final bool dimInactive;
  final bool hideLabels;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final nav = context.watch<StudioNavController>();
    return Container(
      width: hideLabels ? HpiMetrics.railWidthCompact : HpiMetrics.railWidth,
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: p.chrome,
        border: Border(right: BorderSide(color: p.outlineSoft)),
      ),
      child: Column(
        // Items span the rail. Without this they shrink-wrap to their label, so
        // the "left edge" indicator floated inward by however wide the word was
        // — 5.7px for SETTINGS, 30.9px for HRV — and sat flush against the text.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in StudioDestination.primary) _item(context, nav, d),
          const Spacer(),
          for (final d in StudioDestination.secondary) _item(context, nav, d),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _item(
      BuildContext context, StudioNavController nav, StudioDestination d) {
    final p = context.hpi;
    final active = nav.destination == d;
    final dimmed = dimInactive && !active && d.needsSource;
    final ink = active ? p.accent : p.textMuted;
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => nav.go(d),
          child: Tooltip(
            message: d.title,
            child: Container(
              // The 3px border is added to this padding, so content clears the
              // indicator by 7px rather than touching it.
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              decoration: BoxDecoration(
                color: active ? p.accent.withValues(alpha: 0.08) : null,
                border: Border(
                  left: BorderSide(
                    color: active ? p.accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Icon(active ? d.activeIcon : d.icon, size: 22, color: ink),
                  if (!hideLabels) ...[
                    const SizedBox(height: 3),
                    Text(
                      d.label.toUpperCase(),
                      style: HpiText.railLabel(ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The single status line at the bottom of every screen.
class StudioStatusBar extends StatelessWidget {
  const StudioStatusBar({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      height: HpiMetrics.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: p.chrome,
        border: Border(top: BorderSide(color: p.outlineSoft)),
      ),
      child: Row(
        children: [
          // The status line must still read at the 1200x800 minimum, so the
          // items scroll rather than overflow.
          Expanded(
            child: ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: item,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const _Clock(),
        ],
      ),
    );
  }
}

/// One status-line item: optional icon, then mono text.
class StatusItem extends StatelessWidget {
  const StatusItem(this.text, {super.key, this.icon, this.tone});

  final String text;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: tone ?? p.textMuted),
          const SizedBox(width: 5),
        ],
        HpiMono(text, size: 10.5, color: p.textMuted),
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late DateTime _now = DateTime.now();
  late final Stream<void> _tick = Stream<void>.periodic(const Duration(seconds: 1));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: _tick,
      builder: (context, _) {
        _now = DateTime.now();
        final t = '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}';
        return HpiMono(t, size: 10.5, color: context.hpi.textSecondary);
      },
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// A tiny read model of link health so the app bar can rebuild on transport
/// numbers without watching the 500 Hz parser directly.
class StudioLinkSnapshot extends ChangeNotifier {
  double _packetsPerSecond = 0;
  double _lossPercent = 0;
  int _packetsReceived = 0;
  int _packetsDropped = 0;
  int _gaps = 0;
  String _protocol = 'unknown';

  double get packetsPerSecond => _packetsPerSecond;
  double get lossPercent => _lossPercent;
  int get packetsReceived => _packetsReceived;
  int get packetsDropped => _packetsDropped;
  int get gaps => _gaps;
  String get protocol => _protocol;

  void update({
    required double packetsPerSecond,
    required double lossPercent,
    required int packetsReceived,
    required int packetsDropped,
    required int gaps,
    required String protocol,
  }) {
    if (_packetsPerSecond == packetsPerSecond &&
        _lossPercent == lossPercent &&
        _packetsReceived == packetsReceived &&
        _packetsDropped == packetsDropped &&
        _gaps == gaps &&
        _protocol == protocol) {
      return;
    }
    _packetsPerSecond = packetsPerSecond;
    _lossPercent = lossPercent;
    _packetsReceived = packetsReceived;
    _packetsDropped = packetsDropped;
    _gaps = gaps;
    _protocol = protocol;
    notifyListeners();
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Byte formatter shared by the screens that report file sizes.
String formatBytes(int bytes) => _formatBytes(bytes);

/// `HH:MM:SS` for elapsed durations.
String formatDuration(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
