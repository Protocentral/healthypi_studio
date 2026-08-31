import 'package:flutter/material.dart';

import '../../theme/hpi_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Text primitives
// ─────────────────────────────────────────────────────────────────────────────

/// The uppercase field label used above every value and inside every card.
class HpiLabel extends StatelessWidget {
  const HpiLabel(this.text, {super.key, this.color, this.letterSpacing});

  final String text;
  final Color? color;
  final double? letterSpacing;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Text(
      text.toUpperCase(),
      style: HpiText.label(p).copyWith(
        color: color,
        letterSpacing: letterSpacing,
      ),
    );
  }
}

/// A Saira caps title for a card section.
class HpiSectionTitle extends StatelessWidget {
  const HpiSectionTitle(this.text, {super.key, this.trailing, this.note});

  final String text;

  /// A mono qualifier that sits immediately after the title.
  final String? note;

  /// Pushed to the far end of the row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Row(
      children: [
        Text(text.toUpperCase(), style: HpiText.sectionTitle(p)),
        if (note != null) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              note!,
              overflow: TextOverflow.ellipsis,
              style: HpiText.mono(p.textFaint, size: 10),
            ),
          ),
        ],
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// Every number in the app goes through here so the mono face is never missed.
class HpiMono extends StatelessWidget {
  const HpiMono(
    this.text, {
    super.key,
    this.size = 12,
    this.color,
    this.weight = FontWeight.w400,
    this.align,
    this.overflow,
  });

  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  final TextAlign? align;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Text(
      text,
      textAlign: align,
      overflow: overflow,
      style: HpiText.mono(color ?? p.textPrimary, size: size, weight: weight),
    );
  }
}

/// Montserrat body copy.
class HpiBody extends StatelessWidget {
  const HpiBody(this.text, {super.key, this.color, this.size = 12});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Text(
      text,
      style: HpiText.body(p).copyWith(color: color, fontSize: size),
    );
  }
}

/// The quiet note that closes a card and answers the question it raises.
class HpiNote extends StatelessWidget {
  const HpiNote(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Text(text, style: HpiText.note(p).copyWith(color: color));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Surfaces
// ─────────────────────────────────────────────────────────────────────────────

/// A chrome-level card: `#14191E` on a `#232B32` outline.
class HpiCard extends StatelessWidget {
  const HpiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.color,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Overridden only to call attention to a card (e.g. a pending OTA).
  final Color? borderColor;
  final Color? color;

  /// Set when the card holds a table or plot that must not bleed past the radius.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? p.card,
        border: Border.all(color: borderColor ?? p.outlineSoft),
        borderRadius: HpiRadius.cardR,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A raised tile inside a card — the metric tiles on HRV use this.
class HpiTile extends StatelessWidget {
  const HpiTile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(15, 13, 15, 13),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      decoration: BoxDecoration(
        color: p.cardInner,
        border: Border.all(color: p.outlineSoft),
        borderRadius: HpiRadius.innerCardR,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A recessed well — every plot and table header sits in one of these.
class HpiWell extends StatelessWidget {
  const HpiWell({super.key, required this.child, this.height, this.clip = true});

  final Widget child;
  final double? height;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      height: height,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: p.well,
        border: Border.all(color: p.gridLine),
        borderRadius: HpiRadius.buttonR,
      ),
      child: child,
    );
  }
}

/// A one-pixel rule inside a card.
class HpiRule extends StatelessWidget {
  const HpiRule({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      height: 1,
      color: context.hpi.outlineSoft,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chips, pills and badges
// ─────────────────────────────────────────────────────────────────────────────

/// The app-bar chip: a rounded outline holding a dot, a name and a mono detail.
class HpiChip extends StatelessWidget {
  const HpiChip({
    super.key,
    required this.children,
    this.tone,
    this.onTap,
  });

  final List<Widget> children;

  /// When set, the chip borrows this colour for its outline and fill.
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final chip = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tone == null ? p.cardInner : tone!.withValues(alpha: 0.08),
        border: Border.all(
          color: tone == null ? p.outline : tone!.withValues(alpha: 0.35),
        ),
        borderRadius: HpiRadius.pillR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _spaced(children, 6),
      ),
    );
    if (onTap == null) return chip;
    return _Clickable(onTap: onTap, child: chip);
  }
}

/// A small pulsing dot — live connection and heartbeat indicators.
class HpiStatusDot extends StatefulWidget {
  const HpiStatusDot({
    super.key,
    required this.color,
    this.size = 7,
    this.pulse = false,
    this.period = const Duration(milliseconds: 1600),
  });

  final Color color;
  final double size;
  final bool pulse;
  final Duration period;

  @override
  State<HpiStatusDot> createState() => _HpiStatusDotState();
}

class _HpiStatusDotState extends State<HpiStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(HpiStatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulse && _c.isAnimating) {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    // "Reduce motion" in Settings routes through MediaQuery.disableAnimations.
    if (!widget.pulse || MediaQuery.disableAnimationsOf(context)) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
      child: dot,
    );
  }
}

/// The state badge beside a screen title: LIVE, DISPLAY ONLY, UPDATE AVAILABLE.
class HpiBadge extends StatelessWidget {
  const HpiBadge(this.text, {super.key, required this.tone, this.filled = true});

  final String text;
  final Color tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? tone.withValues(alpha: 0.1) : null,
        border: Border.all(color: tone.withValues(alpha: 0.4)),
        borderRadius: HpiRadius.pillR,
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: HpiFonts.ui,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: tone,
        ),
      ),
    );
  }
}

/// A tighter inline tag, used for normal/abnormal on metric tiles.
class HpiTag extends StatelessWidget {
  const HpiTag(this.text, {super.key, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: HpiFonts.ui,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.57,
          color: tone,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Buttons
// ─────────────────────────────────────────────────────────────────────────────

/// The single amber primary action per screen. Nothing else may be amber-filled.
class HpiPrimaryButton extends StatelessWidget {
  const HpiPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 36,
    this.tone,
    this.filledIcon = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  /// Overridden when the action's meaning changes (e.g. red while recording).
  final Color? tone;
  final bool filledIcon;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final enabled = onPressed != null;
    final fill = (tone ?? p.accent).withValues(alpha: enabled ? 1 : 0.35);
    return _Clickable(
      onTap: onPressed,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: fill, borderRadius: HpiRadius.buttonR),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: p.accentInk),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HpiText.button(p.accentInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quiet outline button — everything that is not the primary action.
class HpiGhostButton extends StatelessWidget {
  const HpiGhostButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 34,
    this.expand = false,
    this.tone,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool expand;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final ink = tone ?? p.textSecondary;
    final enabled = onPressed != null;
    return _Clickable(
      onTap: onPressed,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: p.cardInner,
          border: Border.all(color: tone?.withValues(alpha: 0.5) ?? p.outline),
          borderRadius: HpiRadius.buttonR,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment:
              expand ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 16, color: ink.withValues(alpha: enabled ? 1 : 0.4)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HpiText.button(ink.withValues(alpha: enabled ? 1 : 0.4))
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A toolbar button. `active` turns it amber-outlined; it never becomes a fill.
class HpiToolButton extends StatelessWidget {
  const HpiToolButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.active = false,
    this.height = 28,
    this.shortcut,
    this.translucent = false,
    this.tooltip,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool active;
  final double height;

  /// The key that also triggers this action, shown as a faint mono hint.
  final String? shortcut;

  /// Used inside the Focus-mode HUD capsule, where fills would muddy the trace.
  final bool translucent;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final ink = active ? p.accent : p.textSecondary;
    Widget button = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 10),
      decoration: BoxDecoration(
        color: active
            ? p.accent.withValues(alpha: 0.14)
            : (translucent ? Colors.transparent : p.cardInner),
        border: Border.all(
          color: active
              ? p.accent
              : (translucent ? p.hudOutline : p.outline),
        ),
        borderRadius: HpiRadius.controlR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 15, color: ink),
          if (icon != null && label != null) const SizedBox(width: 5),
          if (label != null)
            Flexible(
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HpiText.control(p).copyWith(color: ink),
              ),
            ),
          if (shortcut != null) ...[
            const SizedBox(width: 4),
            HpiMono(shortcut!, size: 9.5, color: p.textFaint),
          ],
        ],
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return _Clickable(onTap: onPressed, child: button);
  }
}

/// The segmented control used for sweep speed, window length, transports, …
class HpiSegmented<T> extends StatelessWidget {
  const HpiSegmented({
    super.key,
    required this.segments,
    required this.value,
    this.onChanged,
    this.height = 28,
    this.expand = false,
    this.trailingNote,
    this.translucent = false,
  });

  final List<HpiSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  final double height;

  /// Stretch each segment to share the row equally (used in side panels).
  final bool expand;

  /// A non-interactive unit label appended after the segments (e.g. "mm/s").
  final String? trailingNote;
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: translucent ? p.hudOutline : p.outline),
        borderRadius: HpiRadius.controlR,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final s in segments)
            _segment(context, s, s.value == value, expand),
          if (trailingNote != null)
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: translucent ? Colors.transparent : p.well,
              child: Text(
                trailingNote!,
                style: HpiText.control(p).copyWith(color: p.textFaint),
              ),
            ),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, HpiSegment<T> s, bool on, bool expand) {
    final p = context.hpi;
    final child = _Clickable(
      onTap: onChanged == null ? null : () => onChanged!(s.value),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: on
            ? p.brand.withValues(alpha: 0.16)
            : (translucent ? Colors.transparent : p.well),
        child: s.icon != null
            ? Icon(s.icon, size: 15, color: on ? p.brandInk : p.textMuted)
            : Text(
                s.label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HpiText.control(p)
                    .copyWith(color: on ? p.brandInk : p.textMuted),
              ),
      ),
    );
    return expand ? Expanded(child: child) : child;
  }
}

class HpiSegment<T> {
  const HpiSegment({required this.value, this.label, this.icon})
      : assert(label != null || icon != null);

  final T value;
  final String? label;
  final IconData? icon;
}

/// The 34×19 pill switch used for every boolean in the design.
class HpiToggle extends StatelessWidget {
  const HpiToggle({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return _Clickable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 34,
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? p.brand.withValues(alpha: 0.35) : p.outlineSoft,
          border: Border.all(color: value ? p.brand : p.outline),
          borderRadius: HpiRadius.pillR,
        ),
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: value ? p.brandInk : p.textFaint,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// A radio-style option card — export formats and filter presets.
class HpiOptionRow extends StatelessWidget {
  const HpiOptionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    this.onTap,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  /// When null a radio dot is drawn instead.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return _Clickable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.brand.withValues(alpha: 0.08) : p.well,
          border: Border.all(color: selected ? p.brand : p.outline),
          borderRadius: HpiRadius.buttonR,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null)
              Icon(icon, size: 16, color: selected ? p.brand : p.textFaint)
            else
              Container(
                width: 15,
                height: 15,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? p.brand : p.outline),
                ),
                child: selected
                    ? Container(
                        width: 7,
                        height: 7,
                        decoration:
                            BoxDecoration(color: p.brand, shape: BoxShape.circle),
                      )
                    : null,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: HpiText.uiTitle(p).copyWith(fontSize: 12)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: HpiText.mono(p.textFaint, size: 10),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A checkbox in the table grammar (square, amber when checked).
class HpiCheckbox extends StatelessWidget {
  const HpiCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.tone,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final t = tone ?? p.accent;
    return _Clickable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value ? t : Colors.transparent,
          border: Border.all(color: value ? t : p.outline),
          borderRadius: BorderRadius.circular(4),
        ),
        child: value ? Icon(Icons.check, size: 13, color: p.accentInk) : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rows and meters
// ─────────────────────────────────────────────────────────────────────────────

/// A label/value row: Montserrat key on the left, mono value on the right.
class HpiKeyValue extends StatelessWidget {
  const HpiKeyValue(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: HpiText.body(p).copyWith(color: p.textMuted, height: 1.2),
          ),
        ),
        const SizedBox(width: 8),
        HpiMono(value, size: 12, color: valueColor ?? p.textPrimary),
      ],
    );
  }
}

/// A settings row: title, optional explanation, and a control on the right.
class HpiSettingRow extends StatelessWidget {
  const HpiSettingRow({
    super.key,
    required this.title,
    this.description,
    required this.control,
    this.last = false,
  });

  final String title;
  final String? description;
  final Widget control;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: p.divider)),
            ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: HpiText.body(p)
                      .copyWith(color: p.textPrimary, fontSize: 12.5, height: 1.3),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: HpiText.note(p).copyWith(fontSize: 10.5, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          control,
        ],
      ),
    );
  }
}

/// A horizontal meter — band power, electrode impedance, stream health, OTA.
class HpiMeter extends StatelessWidget {
  const HpiMeter({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 8,
    this.track,
  });

  final double fraction;
  final Color color;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: track ?? p.divider,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0,
          child: Container(color: color),
        ),
      ),
    );
  }
}

/// A labelled meter row: name, optional range note, bar, value.
class HpiMeterRow extends StatelessWidget {
  const HpiMeterRow({
    super.key,
    required this.name,
    this.note,
    required this.fraction,
    required this.color,
    required this.value,
    this.nameWidth = 52,
    this.noteWidth = 62,
    this.valueWidth = 40,
    this.barHeight = 8,
  });

  final String name;
  final String? note;
  final double fraction;
  final Color color;
  final String value;
  final double nameWidth;
  final double noteWidth;
  final double valueWidth;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Row(
      children: [
        SizedBox(
          width: nameWidth,
          child: Text(
            name,
            style: HpiText.control(p)
                .copyWith(color: p.textPrimary, fontSize: 11.5),
          ),
        ),
        if (note != null)
          SizedBox(
            width: noteWidth,
            child: HpiMono(note!, size: 10, color: p.textFaint),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: HpiMeter(fraction: fraction, color: color, height: barHeight),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: valueWidth,
          child: HpiMono(value,
              size: 11, color: p.textSecondary, align: TextAlign.right),
        ),
      ],
    );
  }
}

/// A slider in the filter-chain grammar: toggle, name, track, mono value.
class HpiParamSlider extends StatelessWidget {
  const HpiParamSlider({
    super.key,
    required this.name,
    required this.enabled,
    required this.fraction,
    required this.valueLabel,
    required this.tone,
    this.onToggle,
    this.onChanged,
    this.nameWidth = 132,
  });

  final String name;
  final bool enabled;
  final double fraction;
  final String valueLabel;
  final Color tone;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<double>? onChanged;
  final double nameWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final active = enabled ? tone : p.outline;
    return Row(
      children: [
        HpiToggle(value: enabled, onChanged: onToggle),
        const SizedBox(width: 11),
        SizedBox(
          width: nameWidth,
          child: Text(
            name,
            style: HpiText.body(p).copyWith(
              fontSize: 11.5,
              height: 1.2,
              color: enabled ? p.textPrimary : p.textFaint,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: active,
              inactiveTrackColor: p.outlineSoft,
              thumbColor: active,
              overlayColor: active.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: fraction.clamp(0.0, 1.0),
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 76,
          child: HpiMono(
            valueLabel,
            size: 10.5,
            color: enabled ? p.textSecondary : p.textFaint,
            align: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// A keycap, as used by the Shortcuts card.
class HpiKeyCap extends StatelessWidget {
  const HpiKeyCap(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.well,
        border: Border.all(color: p.outline),
        borderRadius: BorderRadius.circular(5),
      ),
      child: HpiMono(text, size: 10.5, color: p.textPrimary),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Vertical stack with a uniform gap — the card interior pattern.
class HpiColumn extends StatelessWidget {
  const HpiColumn({
    super.key,
    required this.children,
    this.gap = 10,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: _spaced(children, gap, vertical: true),
    );
  }
}

/// Horizontal row with a uniform gap.
class HpiRow extends StatelessWidget {
  const HpiRow({
    super.key,
    required this.children,
    this.gap = 10,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: _spaced(children, gap),
    );
  }
}

List<Widget> _spaced(List<Widget> items, double gap, {bool vertical = false}) {
  if (items.length < 2) return items;
  final out = <Widget>[];
  for (var i = 0; i < items.length; i++) {
    if (i > 0) {
      out.add(vertical ? SizedBox(height: gap) : SizedBox(width: gap));
    }
    out.add(items[i]);
  }
  return out;
}

/// Pointer/keyboard affordance shared by every control above.
class _Clickable extends StatelessWidget {
  const _Clickable({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Opacity(opacity: 0.55, child: child);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}
