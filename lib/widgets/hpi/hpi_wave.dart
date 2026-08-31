import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/waveform_models.dart';
import '../../theme/hpi_tokens.dart';

/// Paints one channel's visible window straight out of its circular buffer.
///
/// The buffer is read in place rather than copied into a `List<double>` — at
/// 500 Hz across seven channels that copy would dominate every frame.
///
/// The trace drives its own repaints off a ticker. `ChannelController` does not
/// notify on every sample (500 Hz of `notifyListeners` would rebuild the world),
/// so a trace that waited for a parent rebuild would advance only as often as
/// something else in the tree happened to change — roughly once a second with no
/// device attached. The ticker compares the buffer's write cursor each frame and
/// repaints the painter directly, without rebuilding any widget.
class HpiWaveTrace extends StatefulWidget {
  const HpiWaveTrace({
    super.key,
    required this.data,
    required this.windowSeconds,
    required this.color,
    this.strokeWidth = 1.6,
    this.gridDivisions = 10,
  });

  final ChannelData data;
  final double windowSeconds;
  final Color color;
  final double strokeWidth;
  final int gridDivisions;

  @override
  State<HpiWaveTrace> createState() => _HpiWaveTraceState();
}

class _HpiWaveTraceState extends State<HpiWaveTrace>
    with SingleTickerProviderStateMixin {
  /// The painter's repaint signal: the write cursor at the last frame that
  /// actually moved it. Notifying this marks the trace dirty; nothing rebuilds.
  late final ValueNotifier<int> _revision =
      ValueNotifier<int>(widget.data.writeIndex);
  late final Ticker _ticker = createTicker(_onFrame);

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  /// One integer compare per channel per frame. A frozen trace, a paused
  /// acquisition and an offscreen screen all cost nothing beyond it.
  void _onFrame(Duration _) {
    final cursor = widget.data.writeIndex;
    if (cursor != _revision.value) _revision.value = cursor;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _revision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TracePainter(
          data: widget.data,
          windowSeconds: widget.windowSeconds,
          color: widget.color,
          strokeWidth: widget.strokeWidth,
          gridDivisions: widget.gridDivisions,
          gridColor: p.gridLine,
          repaint: _revision,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter({
    required this.data,
    required this.windowSeconds,
    required this.color,
    required this.strokeWidth,
    required this.gridDivisions,
    required this.gridColor,
    required super.repaint,
  });

  final ChannelData data;
  final double windowSeconds;
  final Color color;
  final double strokeWidth;
  final int gridDivisions;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (gridDivisions > 1) {
      final grid = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      for (var i = 1; i < gridDivisions; i++) {
        final x = size.width * i / gridDivisions;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      }
    }

    final capacity = data.maxBufferSize;
    final available = data.isBufferFull ? capacity : data.writeIndex;
    if (available < 2) return;

    final wanted = (windowSeconds * data.samplingRate).round().clamp(2, capacity);
    final count = available < wanted ? available : wanted;

    // Vertical range: the channel's configured window, or the buffer's own
    // extent when the channel is autoscaling.
    var lo = data.config.minValue;
    var hi = data.config.maxValue;
    if (data.config.autoScale) {
      lo = data.minInBuffer;
      hi = data.maxInBuffer;
      final pad = (hi - lo).abs() * 0.1;
      lo -= pad;
      hi += pad;
    }
    var span = hi - lo;
    if (!span.isFinite || span.abs() < 1e-9) {
      lo -= 0.5;
      span = 1;
    }

    // A trace never needs more points than the canvas has pixels.
    final stride = (count / (size.width * 2)).ceil().clamp(1, count);
    final path = Path();
    final start = data.writeIndex - count;
    var first = true;
    for (var i = 0; i < count; i += stride) {
      final idx = (start + i + capacity * 2) % capacity;
      final v = data.buffer[idx].value;
      if (!v.isFinite) continue;
      final x = size.width * (i / (count - 1));
      final y = size.height - ((v - lo) / span) * size.height;
      if (first) {
        path.moveTo(x, y.clamp(-size.height, size.height * 2));
        first = false;
      } else {
        path.lineTo(x, y.clamp(-size.height, size.height * 2));
      }
    }
    if (first) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.restore();
  }

  /// New samples come in through `repaint`; this only covers the presentation
  /// changing under a trace that is otherwise still.
  @override
  bool shouldRepaint(_TracePainter old) =>
      old.data != data ||
      old.color != color ||
      old.windowSeconds != windowSeconds ||
      old.strokeWidth != strokeWidth ||
      old.gridDivisions != gridDivisions ||
      old.gridColor != gridColor;
}

/// Peak-to-peak and last-sample readouts derived from the live buffer.
///
/// These are measurements, not estimates: everything here comes from samples the
/// device actually sent.
class ChannelReadout {
  const ChannelReadout({
    required this.lastValue,
    required this.min,
    required this.max,
    required this.hasSignal,
  });

  factory ChannelReadout.of(ChannelData data) {
    final available = data.isBufferFull ? data.maxBufferSize : data.writeIndex;
    if (available == 0) {
      return const ChannelReadout(
          lastValue: 0, min: 0, max: 0, hasSignal: false);
    }
    final last = data
        .buffer[(data.writeIndex - 1 + data.maxBufferSize) % data.maxBufferSize]
        .value;
    final min = data.minInBuffer;
    final max = data.maxInBuffer;
    return ChannelReadout(
      lastValue: last,
      min: min,
      max: max,
      // A dead lead reads as a flat line; that is worth calling out.
      hasSignal: (max - min).abs() > 1e-6,
    );
  }

  final double lastValue;
  final double min;
  final double max;
  final bool hasSignal;

  String formatted(String unit, {int decimals = 2}) =>
      '${lastValue.toStringAsFixed(decimals)} $unit';

  String get span =>
      '${min.toStringAsFixed(0)} / ${max.toStringAsFixed(0)}';
}
