import 'package:flutter/material.dart';

import '../theme/hpi_tokens.dart';
import '../widgets/hpi/hpi_primitives.dart';

/// The header every screen shares: Saira caps title, an optional state badge, a
/// Montserrat context line, and a quiet action on the far right.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.badge,
    this.subtitle,
    this.action,
  });

  final String title;

  /// LIVE / DISPLAY ONLY / UPDATE AVAILABLE — see [HpiBadge].
  final Widget? badge;
  final String? subtitle;

  /// Never amber: the primary action for the app lives in the top bar.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HpiMetrics.screenPadding,
        16,
        HpiMetrics.screenPadding,
        12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title.toUpperCase(), style: HpiText.screenTitle(p)),
          if (badge != null) ...[const SizedBox(width: 12), badge!],
          if (subtitle != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HpiText.screenSubtitle(p),
              ),
            ),
          ] else
            const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// A screen's body: header, then content in the shell's 18px gutter.
class ScreenBody extends StatelessWidget {
  const ScreenBody({
    super.key,
    required this.header,
    required this.child,
    this.padded = true,
    this.toolbar,
  });

  final ScreenHeader header;

  /// Sits flush between the header and the content (the acquisition toolbar).
  final Widget? toolbar;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        header,
        ?toolbar,
        Expanded(
          child: padded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HpiMetrics.screenPadding,
                    0,
                    HpiMetrics.screenPadding,
                    16,
                  ),
                  child: child,
                )
              : child,
        ),
      ],
    );
  }
}

/// The main column + side column layout that most screens use.
class ScreenColumns extends StatelessWidget {
  const ScreenColumns({
    super.key,
    required this.main,
    required this.side,
    this.sideWidth = 320,
    this.sideFirst = false,
  });

  final Widget main;
  final Widget side;
  final double sideWidth;

  /// HRV puts its metric column on the left.
  final bool sideFirst;

  @override
  Widget build(BuildContext context) {
    // At the 1200px minimum the side column narrows rather than clipping.
    final width = context.hpiCompact ? sideWidth * 0.82 : sideWidth;
    final children = <Widget>[
      SizedBox(width: width, child: side),
      const SizedBox(width: HpiMetrics.columnGap),
      Expanded(child: main),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sideFirst ? children : children.reversed.toList(),
    );
  }
}

/// The 44px acquisition toolbar rule the Live and EEG canvases sit under.
class ScreenToolbar extends StatelessWidget {
  const ScreenToolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Container(
      height: HpiMetrics.toolbarHeight,
      margin: const EdgeInsets.symmetric(horizontal: HpiMetrics.screenPadding),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.divider),
          bottom: BorderSide(color: p.divider),
        ),
      ),
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        ),
      ),
    );
  }
}

/// A centred "nothing here yet" state that keeps the screen's grammar.
class ScreenEmptyState extends StatelessWidget {
  const ScreenEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: p.outline),
            const SizedBox(height: 14),
            Text(title.toUpperCase(),
                style: HpiText.sectionTitle(p), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: HpiText.note(p)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Vertical gap between cards, so screens do not repeat the constant.
const SizedBox kCardGap = SizedBox(height: HpiMetrics.cardGap);
const SizedBox kCardGapH = SizedBox(width: HpiMetrics.cardGap);
