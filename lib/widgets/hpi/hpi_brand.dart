import 'package:flutter/material.dart';

import '../../theme/hpi_tokens.dart';

/// Where each brand asset is allowed to appear, so logo use stays consistent.
class HpiBrandAssets {
  HpiBrandAssets._();

  /// Wordmark for dark chrome (light ink + amber "6").
  static const String wordmarkDark = 'assets/brand/hpi6-wordmark-dark.png';

  /// Wordmark for light chrome (dark ink + amber "6").
  static const String wordmarkLight = 'assets/brand/hpi6-wordmark-light.png';

  /// Full mono lockup in brand blue — device identity cards.
  static const String monoBlue = 'assets/brand/hpi6-mono-blue.png';

  /// Full mono lockup in white — dimmed empty states on dark chrome.
  static const String monoWhite = 'assets/brand/hpi6-mono-white.png';

  /// Round app mark — About and window/app icon contexts.
  static const String round = 'assets/brand/logo-round.png';
}

/// The app-bar lockup: theme-correct wordmark + the "STUDIO" qualifier.
///
/// This is the only place the wordmark appears in chrome — every screen inherits
/// it from the shell rather than drawing its own header.
class HpiWordmark extends StatelessWidget {
  const HpiWordmark({super.key, this.height = 17, this.showQualifier = true});

  final double height;
  final bool showQualifier;

  @override
  Widget build(BuildContext context) {
    final p = context.hpi;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          isLight ? HpiBrandAssets.wordmarkLight : HpiBrandAssets.wordmarkDark,
          height: height,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'HealthyPi 6',
        ),
        if (showQualifier) ...[
          const SizedBox(width: 10),
          Text(
            'Studio',
            style: TextStyle(
              fontFamily: HpiFonts.ui,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.76,
              color: p.textFaint,
            ),
          ),
        ],
      ],
    );
  }
}

/// The mono lockup, tinted for the surface it sits on.
class HpiMonoMark extends StatelessWidget {
  const HpiMonoMark({
    super.key,
    required this.width,
    this.variant = HpiMonoVariant.blue,
    this.opacity = 1,
  });

  final double width;
  final HpiMonoVariant variant;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // The white lockup disappears on the light ramp, so fall back to blue there.
    final asset = switch (variant) {
      HpiMonoVariant.blue => HpiBrandAssets.monoBlue,
      HpiMonoVariant.white =>
        isLight ? HpiBrandAssets.monoBlue : HpiBrandAssets.monoWhite,
    };
    return Opacity(
      opacity: opacity,
      child: Image.asset(
        asset,
        width: width,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'HealthyPi 6',
      ),
    );
  }
}

enum HpiMonoVariant { blue, white }
