import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/hpi_tokens.dart';
import 'hpi_primitives.dart';

/// The vertical time grid drawn behind every trace, at the design's 10 divisions.
class HpiTimeGrid extends StatelessWidget {
  const HpiTimeGrid({super.key, this.divisions = 10, this.color});

  final int divisions;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(divisions, color ?? context.hpi.gridLine),
      size: Size.infinite,
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.divisions, this.color);

  final int divisions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 1; i < divisions; i++) {
      final x = size.width * i / divisions;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.divisions != divisions || old.color != color;
}

/// A polyline over a value range. The workhorse behind traces, tachograms,
/// spectra and throughput charts.
class HpiLinePlot extends StatelessWidget {
  const HpiLinePlot({
    super.key,
    required this.values,
    required this.color,
    this.minValue,
    this.maxValue,
    this.strokeWidth = 1.6,
    this.fill = false,
    this.baselineFraction,
  });

  final List<double> values;
  final Color color;

  /// Explicit range; when omitted the plot autoscales to the data with headroom.
  final double? minValue;
  final double? maxValue;
  final double strokeWidth;

  /// Fill under the line (used by the throughput chart).
  final bool fill;

  /// Draw a horizontal reference line at this fraction of the height.
  final double? baselineFraction;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePlotPainter(
        values: values,
        color: color,
        minValue: minValue,
        maxValue: maxValue,
        strokeWidth: strokeWidth,
        fill: fill,
        baselineFraction: baselineFraction,
        baselineColor: context.hpi.outline,
      ),
      size: Size.infinite,
    );
  }
}

class _LinePlotPainter extends CustomPainter {
  _LinePlotPainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.fill,
    required this.baselineColor,
    this.minValue,
    this.maxValue,
    this.baselineFraction,
  });

  final List<double> values;
  final Color color;
  final double? minValue;
  final double? maxValue;
  final double strokeWidth;
  final bool fill;
  final double? baselineFraction;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (baselineFraction != null) {
      final y = size.height * baselineFraction!;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = baselineColor
          ..strokeWidth = 1,
      );
    }
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    var lo = minValue ?? double.infinity;
    var hi = maxValue ?? -double.infinity;
    if (minValue == null || maxValue == null) {
      for (final v in values) {
        if (!v.isFinite) continue;
        if (minValue == null && v < lo) lo = v;
        if (maxValue == null && v > hi) hi = v;
      }
      if (!lo.isFinite || !hi.isFinite) return;
      final pad = (hi - lo).abs() * 0.08;
      lo -= pad;
      hi += pad;
    }
    var span = hi - lo;
    if (span.abs() < 1e-9) {
      // A flat trace still deserves to be drawn — centre it.
      lo -= 0.5;
      span = 1;
    }

    final path = Path();
    final dx = size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!v.isFinite) continue;
      final y = size.height - ((v - lo) / span) * size.height;
      final x = i * dx;
      if (path.getBounds().isEmpty && i == 0) {
        path.moveTo(x, y);
      } else if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()..color = color.withValues(alpha: 0.12),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LinePlotPainter old) =>
      old.values != values ||
      old.color != color ||
      old.minValue != minValue ||
      old.maxValue != maxValue ||
      old.fill != fill;
}

/// The tiny trend line inside a vitals card.
class HpiSparkline extends StatelessWidget {
  const HpiSparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 20,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: HpiLinePlot(
        values: values,
        color: color.withValues(alpha: 0.65),
        strokeWidth: 1.6,
      ),
    );
  }
}

/// A vitals card: icon, label, big mono number, unit, and a footer that is
/// either a sparkline or a tag + caption.
class HpiVitalCard extends StatelessWidget {
  const HpiVitalCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.tone,
    this.spark,
    this.tag,
    this.tagTone,
    this.caption,
    this.pulse = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;

  /// Already formatted; pass an em dash when the device has not reported yet.
  final String value;
  final String unit;
  final Color tone;
  final List<double>? spark;
  final String? tag;
  final Color? tagTone;
  final String? caption;

  /// The heart-rate card pulses; nothing else does.
  final bool pulse;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 9),
      decoration: BoxDecoration(
        color: p.cardInner,
        border: Border.all(color: p.outlineSoft),
        borderRadius: HpiRadius.innerCardR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 6),
              Expanded(child: HpiLabel(label)),
              if (pulse) HpiStatusDot(color: tone, size: 6, pulse: true, period: const Duration(milliseconds: 1100)),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HpiText.vital(valueColor ?? p.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              Text(unit.toUpperCase(), style: HpiText.unit(p)),
            ],
          ),
          const Spacer(),
          if (spark != null)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: HpiSparkline(values: spark!, color: tone),
            )
          else if (tag != null || caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                children: [
                  if (tag != null) ...[
                    HpiTag(tag!, tone: tagTone ?? p.success),
                    const SizedBox(width: 5),
                  ],
                  if (caption != null)
                    Expanded(
                      child: Text(
                        caption!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: HpiText.label(p).copyWith(letterSpacing: 0.6),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One channel row in the acquisition canvas: gutter (name, range, gain) ·
/// grid + trace · readout (last value, span, quality).
class HpiChannelRow extends StatelessWidget {
  const HpiChannelRow({
    super.key,
    required this.name,
    required this.detail,
    required this.color,
    required this.samples,
    this.minValue,
    this.maxValue,
    this.gainLabel,
    this.onGainUp,
    this.onGainDown,
    this.lastValue,
    this.spanLabel,
    this.quality,
    this.qualityTone,
    this.lineWidth = 1.6,
    this.showGutter = true,
    this.showReadout = true,
    this.last = false,
    this.overlayRight,
  });

  final String name;
  final String detail;
  final Color color;
  final List<double> samples;
  final double? minValue;
  final double? maxValue;
  final String? gainLabel;
  final VoidCallback? onGainUp;
  final VoidCallback? onGainDown;
  final String? lastValue;
  final String? spanLabel;
  final String? quality;
  final Color? qualityTone;
  final double lineWidth;
  final bool showGutter;
  final bool showReadout;
  final bool last;

  /// A mono note pinned to the top-right of the plot (EEG impedance uses this).
  final String? overlayRight;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return DecoratedBox(
      decoration: last
          ? const BoxDecoration()
          : BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showGutter) _gutter(context),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: HpiTimeGrid()),
                Positioned.fill(
                  child: RepaintBoundary(
                    child: HpiLinePlot(
                      values: samples,
                      color: color,
                      minValue: minValue,
                      maxValue: maxValue,
                      strokeWidth: lineWidth,
                    ),
                  ),
                ),
                if (!showGutter)
                  Positioned(
                    left: 20,
                    bottom: 10,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          name.toUpperCase(),
                          style: TextStyle(
                            fontFamily: HpiFonts.ui,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.38,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 9),
                        HpiMono(detail, size: 10, color: p.textFaint),
                      ],
                    ),
                  ),
                if (overlayRight != null)
                  Positioned(
                    right: 12,
                    top: 8,
                    child: HpiMono(overlayRight!, size: 9.5, color: p.textFaint),
                  ),
              ],
            ),
          ),
          if (showReadout) _readout(context),
        ],
      ),
    );
  }

  Widget _gutter(BuildContext context) {
    final p = context.hpi;
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
            name.toUpperCase(),
            style: TextStyle(
              fontFamily: HpiFonts.ui,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.55,
              color: color,
            ),
          ),
          const SizedBox(height: 5),
          HpiMono(detail, size: 9.5, color: p.textFaint),
          const Spacer(),
          if (gainLabel != null)
            Row(
              children: [
                _gainStep(context, Icons.remove, onGainDown),
                const SizedBox(width: 4),
                Expanded(
                  child: HpiMono(gainLabel!,
                      size: 9.5, color: p.textSecondary, align: TextAlign.center),
                ),
                const SizedBox(width: 4),
                _gainStep(context, Icons.add, onGainUp),
              ],
            ),
        ],
      ),
    );
  }

  Widget _gainStep(BuildContext context, IconData icon, VoidCallback? onTap) {
    final p = context.hpi;
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
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
    );
  }

  Widget _readout(BuildContext context) {
    final p = context.hpi;
    return Container(
      width: HpiMetrics.channelReadoutWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.well,
        border: Border(left: BorderSide(color: p.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastValue != null)
            HpiMono(lastValue!, size: 11.5, color: p.textPrimary),
          if (spanLabel != null) ...[
            const SizedBox(height: 3),
            HpiMono(spanLabel!, size: 9.5, color: p.textFaint),
          ],
          const Spacer(),
          if (quality != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                HpiStatusDot(color: qualityTone ?? p.success, size: 6),
                const SizedBox(width: 4),
                HpiLabel(quality!, letterSpacing: 0.6),
              ],
            ),
        ],
      ),
    );
  }
}

/// The Poincaré scatter with its identity line and SD1/SD2 ellipse.
class HpiPoincarePlot extends StatelessWidget {
  const HpiPoincarePlot({super.key, required this.intervals, required this.color});

  /// Successive R-R intervals in milliseconds.
  final List<int> intervals;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return CustomPaint(
      painter: _PoincarePainter(
        intervals: intervals,
        color: color,
        axis: p.outline,
        grid: p.gridLine,
        tick: p.textFaint,
      ),
      size: Size.infinite,
    );
  }
}

class _PoincarePainter extends CustomPainter {
  _PoincarePainter({
    required this.intervals,
    required this.color,
    required this.axis,
    required this.grid,
    required this.tick,
  });

  final List<int> intervals;
  final Color color;
  final Color axis;
  final Color grid;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0;
    const bottom = 30.0;
    const top = 12.0;
    const right = 10.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    if (plot.width <= 0 || plot.height <= 0) return;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = plot.left + plot.width * i / 4;
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axisPaint);

    if (intervals.length < 3) {
      _text(canvas, 'Waiting for R-R intervals', plot.center, tick,
          align: TextAlign.center);
      return;
    }

    var lo = intervals.reduce(math.min).toDouble();
    var hi = intervals.reduce(math.max).toDouble();
    final pad = math.max(20.0, (hi - lo) * 0.15);
    lo -= pad;
    hi += pad;
    final span = math.max(1.0, hi - lo);

    Offset at(double rrN, double rrN1) => Offset(
          plot.left + ((rrN - lo) / span) * plot.width,
          plot.bottom - ((rrN1 - lo) / span) * plot.height,
        );

    // Identity line — the reference the cloud is judged against.
    _dashed(canvas, at(lo, lo), at(hi, hi),
        Paint()
          ..color = axis
          ..strokeWidth = 1);

    // SD1/SD2 ellipse, rotated onto the identity line.
    final diffs = <double>[];
    for (var i = 1; i < intervals.length; i++) {
      diffs.add((intervals[i] - intervals[i - 1]).toDouble());
    }
    final sd1 = _stdDev(diffs) / math.sqrt2;
    final sd2 = math.sqrt(
      math.max(0, 2 * math.pow(_stdDev(intervals.map((e) => e.toDouble()).toList()), 2) - math.pow(sd1, 2)),
    );
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    final centre = at(mean, mean);
    final scale = plot.width / span;
    if (sd1 > 0 && sd2 > 0) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(-math.pi / 4);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: sd2 * 2 * scale,
        height: sd1 * 2 * scale,
      );
      canvas
        ..drawOval(rect, Paint()..color = color.withValues(alpha: 0.08))
        ..drawOval(
          rect,
          Paint()
            ..color = color.withValues(alpha: 0.5)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        )
        ..restore();
    }

    final dot = Paint()..color = color.withValues(alpha: 0.85);
    canvas.save();
    canvas.clipRect(plot);
    for (var i = 1; i < intervals.length; i++) {
      canvas.drawCircle(
        at(intervals[i - 1].toDouble(), intervals[i].toDouble()),
        3,
        dot,
      );
    }
    canvas.restore();

    _text(canvas, 'RRn (ms)',
        Offset(plot.center.dx, size.height - 14), tick, align: TextAlign.center);
    canvas.save();
    canvas.translate(14, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _text(canvas, 'RRn+1 (ms)', Offset.zero, tick, align: TextAlign.center);
    canvas.restore();
  }

  static double _stdDev(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = xs.reduce((a, b) => a + b) / xs.length;
    final v = xs.map((x) => math.pow(x - m, 2)).reduce((a, b) => a + b) / xs.length;
    return math.sqrt(v);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 5.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = math.min(t + dash, total);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + dash;
    }
  }

  void _text(Canvas canvas, String s, Offset centre, Color color,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: HpiFonts.mono, fontSize: 11, color: color),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PoincarePainter old) =>
      old.intervals != intervals || old.color != color;
}

/// A framed plot with a mono min/max annotation in the corners.
class HpiPlotWell extends StatelessWidget {
  const HpiPlotWell({
    super.key,
    required this.child,
    this.topLabel,
    this.bottomLabel,
    this.height,
    this.showGrid = true,
    this.gridDivisions = 10,
    this.footer,
  });

  final Widget child;
  final String? topLabel;
  final String? bottomLabel;
  final double? height;
  final bool showGrid;
  final int gridDivisions;

  /// A row of axis captions laid across the bottom edge.
  final List<String>? footer;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return HpiWell(
      height: height,
      child: Stack(
        children: [
          if (showGrid)
            Positioned.fill(child: HpiTimeGrid(divisions: gridDivisions)),
          Positioned.fill(child: child),
          if (topLabel != null)
            Positioned(
              left: 9,
              top: 6,
              child: HpiMono(topLabel!, size: 9.5, color: p.textFaint),
            ),
          if (bottomLabel != null)
            Positioned(
              left: 9,
              bottom: 6,
              child: HpiMono(bottomLabel!, size: 9.5, color: p.textFaint),
            ),
          if (footer != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final f in footer!)
                    HpiMono(f, size: 9, color: p.textFaint),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The gap timeline that sits under the throughput chart on Link health.
class HpiGapTimeline extends StatelessWidget {
  const HpiGapTimeline({super.key, required this.gaps, this.height = 22});

  /// Gap positions as fractions of the window (0 = oldest, 1 = now).
  final List<double> gaps;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return HpiWell(
      height: height,
      child: Stack(
        children: [
          for (final g in gaps)
            Align(
              alignment: Alignment(g.clamp(0.0, 1.0) * 2 - 1, 0),
              child: Container(width: 2, color: p.accent),
            ),
        ],
      ),
    );
  }
}
