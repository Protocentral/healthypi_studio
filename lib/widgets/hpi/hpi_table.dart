import 'package:flutter/material.dart';

import '../../theme/hpi_tokens.dart';
import 'hpi_primitives.dart';

/// One column in an [HpiTable].
class HpiColumnSpec {
  const HpiColumnSpec(
    this.label, {
    this.width,
    this.flex,
    this.align = TextAlign.left,
  }) : assert(width != null || flex != null,
            'A column needs either a fixed width or a flex');

  final String label;
  final double? width;
  final int? flex;
  final TextAlign align;
}

/// The selection-driven table used by Recordings, Link health, Device inventory
/// and the Connect device list. One header row, hairline-separated body rows.
class HpiTable extends StatelessWidget {
  const HpiTable({
    super.key,
    required this.columns,
    required this.rows,
    this.leading,
    this.trailingWidth,
    this.scrollable = true,
  });

  final List<HpiColumnSpec> columns;
  final List<HpiTableRow> rows;

  /// A fixed-width slot before the first column (the select-all checkbox).
  final Widget? leading;

  /// A fixed-width slot after the last column (the row overflow affordance).
  final double? trailingWidth;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final r in rows) r],
    );
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: p.well,
            border: Border(bottom: BorderSide(color: p.outlineSoft)),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                SizedBox(width: 16, child: leading),
                const SizedBox(width: 12),
              ],
              for (var i = 0; i < columns.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                _sized(
                  columns[i],
                  Align(
                    alignment: columns[i].align == TextAlign.right
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: HpiLabel(columns[i].label),
                  ),
                ),
              ],
              if (trailingWidth != null) SizedBox(width: trailingWidth! + 12),
            ],
          ),
        ),
        if (scrollable)
          Expanded(child: SingleChildScrollView(child: body))
        else
          body,
      ],
    );
  }

  static Widget _sized(HpiColumnSpec c, Widget child) =>
      c.width != null ? SizedBox(width: c.width, child: child) : Expanded(flex: c.flex!, child: child);
}

/// A body row. `selected` paints the amber selection wash and left marker.
class HpiTableRow extends StatelessWidget {
  const HpiTableRow({
    super.key,
    required this.columns,
    required this.cells,
    this.leading,
    this.trailing,
    this.selected = false,
    this.marker = false,
    this.markerTone,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    this.last = false,
  });

  final List<HpiColumnSpec> columns;
  final List<Widget> cells;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;

  /// Draws the 3px left marker — used on the first row of a selection run.
  final bool marker;
  final Color? markerTone;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final tone = markerTone ?? p.accent;
    Widget row = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: selected ? tone.withValues(alpha: 0.05) : null,
        border: Border(
          bottom: BorderSide(color: last ? Colors.transparent : p.divider),
          left: BorderSide(
            color: marker ? tone : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 16, child: leading),
            const SizedBox(width: 12),
          ],
          for (var i = 0; i < columns.length && i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            HpiTable._sized(columns[i], cells[i]),
          ],
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: row),
    );
  }
}

/// A cell holding a mono value.
class HpiCell extends StatelessWidget {
  const HpiCell(
    this.text, {
    super.key,
    this.size = 11,
    this.color,
    this.align = TextAlign.left,
    this.mono = true,
  });

  final String text;
  final double size;
  final Color? color;
  final TextAlign align;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Text(
      text,
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: mono
          ? HpiText.mono(color ?? p.textSecondary, size: size)
          : HpiText.body(p).copyWith(
              color: color ?? p.textMuted,
              fontSize: size + 0.5,
              height: 1.2,
            ),
    );
  }
}

/// A status cell: dot plus word, in the same grammar as the channel readout.
class HpiStatusCell extends StatelessWidget {
  const HpiStatusCell(this.text, {super.key, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Row(
      children: [
        HpiStatusDot(color: tone, size: 7),
        const SizedBox(width: 6),
        Text(
          text,
          style: HpiText.control(p).copyWith(color: tone, fontSize: 11),
        ),
      ],
    );
  }
}

/// An event-log line: mono timestamp, severity dot, message.
class HpiLogLine extends StatelessWidget {
  const HpiLogLine({
    super.key,
    required this.time,
    required this.message,
    required this.tone,
  });

  final String time;
  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HpiMono(time, size: 10.5, color: p.textFaint),
        const SizedBox(width: 9),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: HpiStatusDot(color: tone, size: 6),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: HpiText.body(p).copyWith(fontSize: 11, height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// A tappable maintenance row: icon, title, chevron.
class HpiActionRow extends StatelessWidget {
  const HpiActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
    this.tone,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: p.well,
            border: Border.all(color: p.outline),
            borderRadius: HpiRadius.buttonR,
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: tone ?? p.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: HpiText.uiTitle(p).copyWith(
                    fontSize: 12,
                    color: tone ?? p.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: p.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
