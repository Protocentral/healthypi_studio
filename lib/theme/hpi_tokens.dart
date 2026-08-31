/// Design tokens for the HealthyPi Studio revamp.
///
/// Source of truth: [docs/DESIGN_SYSTEM.md](../../docs/DESIGN_SYSTEM.md). Change
/// a token here and there, or the two drift.
///
/// The rules the whole app follows:
///  * Dark surfaces step canvas -> chrome -> card; nothing is pure black.
///  * Brand blue is selection and navigation. Signal amber is reserved for the
///    single primary action per screen (and the active-nav indicator).
///  * Traces are a semantic ramp, not primaries: the three ECG leads share the
///    amber family so they read as one modality; respiration green, PPG blue,
///    EEG violet, temperature orange.
///  * Saira caps for screen titles, Jost for nav/labels/buttons, Montserrat for
///    body copy, JetBrains Mono for every number.
library;

import 'package:flutter/material.dart';

/// Font families. Bundled as static instances in `assets/fonts` so the app
/// renders identically offline.
class HpiFonts {
  HpiFonts._();

  /// Screen titles, section titles — always uppercase with wide tracking.
  static const String display = 'Saira';

  /// Navigation, labels, buttons, chips.
  static const String ui = 'Jost';

  /// Body copy and explanatory text.
  static const String body = 'Montserrat';

  /// Every number, identifier, file name and unit-bearing readout.
  static const String mono = 'JetBrainsMono';
}

/// Corner radii used across the shell.
class HpiRadius {
  HpiRadius._();

  static const double chip = 999;
  static const double control = 6;
  static const double button = 8;
  static const double card = 12;
  static const double innerCard = 10;
  static const double hud = 16;

  static const BorderRadius controlR = BorderRadius.all(Radius.circular(control));
  static const BorderRadius buttonR = BorderRadius.all(Radius.circular(button));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius innerCardR =
      BorderRadius.all(Radius.circular(innerCard));
  static const BorderRadius pillR = BorderRadius.all(Radius.circular(chip));
}

/// Fixed chrome metrics from the design (1600x1000 default, 1200x800 minimum).
class HpiMetrics {
  HpiMetrics._();

  static const double appBarHeight = 60;
  static const double railWidth = 96;
  static const double railWidthCompact = 68;
  static const double statusBarHeight = 34;
  static const double inspectorDockWidth = 52;
  static const double screenPadding = 18;
  static const double cardGap = 12;
  static const double columnGap = 14;
  static const double channelGutterWidth = 118;
  static const double channelReadoutWidth = 96;
  static const double toolbarHeight = 44;

  /// Below this width the rail drops its labels and side columns narrow.
  static const double compactBreakpoint = 1340;
}

/// The semantic colour set, resolved per theme. Read it from a [BuildContext]
/// with `context.hpi` (see [HpiPaletteContext]).
@immutable
class HpiPalette extends ThemeExtension<HpiPalette> {
  const HpiPalette({
    required this.canvas,
    required this.chrome,
    required this.card,
    required this.cardInner,
    required this.well,
    required this.outline,
    required this.outlineSoft,
    required this.divider,
    required this.brand,
    required this.brandSoft,
    required this.brandInk,
    required this.accent,
    required this.accentInk,
    required this.success,
    required this.warning,
    required this.error,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.trace,
    required this.gridLine,
    required this.hudSurface,
    required this.hudOutline,
  });

  /// Page background behind the cards (design: #0E1418).
  final Color canvas;

  /// App bar, rail, status bar, and card fill (design: #14191E).
  final Color chrome;

  /// Card fill — same step as chrome so cards read as chrome-level surfaces.
  final Color card;

  /// Raised inner card / tile (design: #1C2228).
  final Color cardInner;

  /// Recessed plot wells and table headers (design: #111619).
  final Color well;

  /// Control outlines (design: #2C363E).
  final Color outline;

  /// Card outlines (design: #232B32).
  final Color outlineSoft;

  /// Hairline row separators (design: #1B2228).
  final Color divider;

  /// Brand blue — selection, navigation, informational accents.
  final Color brand;

  /// Brand blue at low opacity for selected fills.
  final Color brandSoft;

  /// Text/icon colour that reads on [brand] fills.
  final Color brandInk;

  /// Signal amber — the one primary action per screen, and active nav.
  final Color accent;

  /// Text/icon colour that reads on [accent] fills.
  final Color accentInk;

  final Color success;
  final Color warning;
  final Color error;

  /// Headline / value text (design: #ECEFF1).
  final Color textPrimary;

  /// Body copy (design: #B9C2C8).
  final Color textSecondary;

  /// Labels and secondary metadata (design: #8D99A1).
  final Color textMuted;

  /// Axis ticks and the quietest metadata (design: #5C666D / #6B767E).
  final Color textFaint;

  /// The semantic trace ramp.
  final HpiTraceRamp trace;

  /// Vertical time grid inside plot wells.
  final Color gridLine;

  /// Translucent HUD panel fill used by Focus mode.
  final Color hudSurface;
  final Color hudOutline;

  static const HpiPalette dark = HpiPalette(
    canvas: Color(0xFF0E1418),
    chrome: Color(0xFF14191E),
    card: Color(0xFF14191E),
    cardInner: Color(0xFF1C2228),
    well: Color(0xFF111619),
    outline: Color(0xFF2C363E),
    outlineSoft: Color(0xFF232B32),
    divider: Color(0xFF1B2228),
    brand: Color(0xFF6FB3CC),
    brandSoft: Color(0x296FB3CC),
    brandInk: Color(0xFF9FD3E4),
    accent: Color(0xFFFBBF24),
    accentInk: Color(0xFF1F1300),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFB923C),
    error: Color(0xFFF87171),
    textPrimary: Color(0xFFECEFF1),
    textSecondary: Color(0xFFB9C2C8),
    textMuted: Color(0xFF8D99A1),
    textFaint: Color(0xFF6B767E),
    trace: HpiTraceRamp.dark,
    gridLine: Color(0xFF191F25),
    hudSurface: Color(0xD1101519),
    hudOutline: Color(0x1AFFFFFF),
  );

  static const HpiPalette light = HpiPalette(
    canvas: Color(0xFFFAFBFC),
    chrome: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardInner: Color(0xFFF1F4F5),
    well: Color(0xFFF7F9FA),
    outline: Color(0xFFDDE1E3),
    outlineSoft: Color(0xFFE2E7E9),
    divider: Color(0xFFE7EBED),
    brand: Color(0xFF2C6E84),
    brandSoft: Color(0x1F2C6E84),
    brandInk: Color(0xFF1F5566),
    accent: Color(0xFFF59E0B),
    accentInk: Color(0xFF1F1300),
    success: Color(0xFF16A34A),
    warning: Color(0xFFC2410C),
    error: Color(0xFFDC2626),
    textPrimary: Color(0xFF16202A),
    textSecondary: Color(0xFF3F4C55),
    textMuted: Color(0xFF5D6B75),
    textFaint: Color(0xFF7A7E80),
    trace: HpiTraceRamp.light,
    gridLine: Color(0xFFEAEEF0),
    hudSurface: Color(0xE6FFFFFF),
    hudOutline: Color(0x14000000),
  );

  @override
  HpiPalette copyWith({
    Color? canvas,
    Color? chrome,
    Color? card,
    Color? cardInner,
    Color? well,
    Color? outline,
    Color? outlineSoft,
    Color? divider,
    Color? brand,
    Color? brandSoft,
    Color? brandInk,
    Color? accent,
    Color? accentInk,
    Color? success,
    Color? warning,
    Color? error,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    HpiTraceRamp? trace,
    Color? gridLine,
    Color? hudSurface,
    Color? hudOutline,
  }) {
    return HpiPalette(
      canvas: canvas ?? this.canvas,
      chrome: chrome ?? this.chrome,
      card: card ?? this.card,
      cardInner: cardInner ?? this.cardInner,
      well: well ?? this.well,
      outline: outline ?? this.outline,
      outlineSoft: outlineSoft ?? this.outlineSoft,
      divider: divider ?? this.divider,
      brand: brand ?? this.brand,
      brandSoft: brandSoft ?? this.brandSoft,
      brandInk: brandInk ?? this.brandInk,
      accent: accent ?? this.accent,
      accentInk: accentInk ?? this.accentInk,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      trace: trace ?? this.trace,
      gridLine: gridLine ?? this.gridLine,
      hudSurface: hudSurface ?? this.hudSurface,
      hudOutline: hudOutline ?? this.hudOutline,
    );
  }

  @override
  HpiPalette lerp(ThemeExtension<HpiPalette>? other, double t) {
    if (other is! HpiPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return HpiPalette(
      canvas: c(canvas, other.canvas),
      chrome: c(chrome, other.chrome),
      card: c(card, other.card),
      cardInner: c(cardInner, other.cardInner),
      well: c(well, other.well),
      outline: c(outline, other.outline),
      outlineSoft: c(outlineSoft, other.outlineSoft),
      divider: c(divider, other.divider),
      brand: c(brand, other.brand),
      brandSoft: c(brandSoft, other.brandSoft),
      brandInk: c(brandInk, other.brandInk),
      accent: c(accent, other.accent),
      accentInk: c(accentInk, other.accentInk),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      error: c(error, other.error),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      textFaint: c(textFaint, other.textFaint),
      trace: trace.lerp(other.trace, t),
      gridLine: c(gridLine, other.gridLine),
      hudSurface: c(hudSurface, other.hudSurface),
      hudOutline: c(hudOutline, other.hudOutline),
    );
  }
}

/// The semantic trace ramp. ECG leads share the amber family on purpose so the
/// three leads read as one modality.
@immutable
class HpiTraceRamp {
  const HpiTraceRamp({
    required this.ecg1,
    required this.ecg2,
    required this.ecg3,
    required this.respiration,
    required this.ppg,
    required this.ppgIr,
    required this.eeg1,
    required this.eeg2,
    required this.temperature,
  });

  final Color ecg1;
  final Color ecg2;
  final Color ecg3;
  final Color respiration;
  final Color ppg;
  final Color ppgIr;
  final Color eeg1;
  final Color eeg2;
  final Color temperature;

  static const HpiTraceRamp dark = HpiTraceRamp(
    ecg1: Color(0xFFFBBF24),
    ecg2: Color(0xFFF59E0B),
    ecg3: Color(0xFFD97706),
    respiration: Color(0xFF4CC38A),
    ppg: Color(0xFF6FB3CC),
    ppgIr: Color(0xFF4E8FA8),
    eeg1: Color(0xFF8B84F0),
    eeg2: Color(0xFFA78BFA),
    temperature: Color(0xFFFB923C),
  );

  /// Traces darken one step in the light theme so they hold on white.
  static const HpiTraceRamp light = HpiTraceRamp(
    ecg1: Color(0xFFB45309),
    ecg2: Color(0xFF92400E),
    ecg3: Color(0xFF7C2D12),
    respiration: Color(0xFF15803D),
    ppg: Color(0xFF2C6E84),
    ppgIr: Color(0xFF1F5566),
    eeg1: Color(0xFF4338CA),
    eeg2: Color(0xFF6D28D9),
    temperature: Color(0xFFC2410C),
  );

  HpiTraceRamp lerp(HpiTraceRamp other, double t) {
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return HpiTraceRamp(
      ecg1: c(ecg1, other.ecg1),
      ecg2: c(ecg2, other.ecg2),
      ecg3: c(ecg3, other.ecg3),
      respiration: c(respiration, other.respiration),
      ppg: c(ppg, other.ppg),
      ppgIr: c(ppgIr, other.ppgIr),
      eeg1: c(eeg1, other.eeg1),
      eeg2: c(eeg2, other.eeg2),
      temperature: c(temperature, other.temperature),
    );
  }

  /// Trace colour for a [ChannelController] channel id.
  Color forChannel(String channelId) {
    switch (channelId) {
      case 'ecg1':
        return ecg1;
      case 'ecg2':
        return ecg2;
      case 'ecg3':
        return ecg3;
      case 'respiration':
        return respiration;
      case 'ppg':
        return ppg;
      case 'ppg_ir':
        return ppgIr;
      case 'eeg1':
        return eeg1;
      case 'eeg2':
        return eeg2;
      case 'temperature':
        return temperature;
      default:
        return ppg;
    }
  }
}

/// `context.hpi` — the resolved palette for the active theme.
extension HpiPaletteContext on BuildContext {
  HpiPalette get hpi =>
      Theme.of(this).extension<HpiPalette>() ?? HpiPalette.dark;

  /// True when the window is narrow enough to need the compact chrome.
  bool get hpiCompact =>
      MediaQuery.sizeOf(this).width < HpiMetrics.compactBreakpoint;
}

/// The type scale. Every style names the role it plays in the design so screens
/// never hand-roll a `TextStyle`.
class HpiText {
  HpiText._();

  /// Saira 600 / 19px / +0.06em caps — the screen title.
  static TextStyle screenTitle(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.display,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.14,
        height: 1.1,
        color: p.textPrimary,
      );

  /// Saira 600 / 12px caps — a card's section title.
  static TextStyle sectionTitle(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.display,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.96,
        color: p.textSecondary,
      );

  /// Montserrat 400 / 12px — the context line under a screen title.
  static TextStyle screenSubtitle(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.body,
        fontSize: 12,
        color: p.textFaint,
      );

  /// Jost 600 / 10px / +0.12em caps — the ubiquitous field label.
  static TextStyle label(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.ui,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: p.textMuted,
      );

  /// Jost 500 / 11px — control and chip text.
  static TextStyle control(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.ui,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.22,
        color: p.textSecondary,
      );

  /// Jost 500 / 12.5px — navigation rows, list titles.
  static TextStyle uiTitle(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.ui,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: p.textPrimary,
      );

  /// Jost 600 / 12.5px / +0.04em — primary button label.
  static TextStyle button(Color ink) => TextStyle(
        fontFamily: HpiFonts.ui,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: ink,
      );

  /// Jost 600 / 9.5px / +0.06em caps — the rail label.
  static TextStyle railLabel(Color ink) => TextStyle(
        fontFamily: HpiFonts.ui,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.57,
        color: ink,
      );

  /// Montserrat 400 / 12px — body copy in cards and rows.
  static TextStyle body(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.body,
        fontSize: 12,
        height: 1.5,
        color: p.textSecondary,
      );

  /// Montserrat 400 / 11px — the quiet explanatory note that closes a card.
  static TextStyle note(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.body,
        fontSize: 11,
        height: 1.5,
        color: p.textFaint,
      );

  /// JetBrains Mono 500 / 34px — the big vital number.
  static TextStyle vital(Color ink) => TextStyle(
        fontFamily: HpiFonts.mono,
        fontSize: 34,
        height: 1,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.68,
        color: ink,
      );

  /// JetBrains Mono 600 / 10px / +0.08em caps — the unit beside a vital.
  static TextStyle unit(HpiPalette p) => TextStyle(
        fontFamily: HpiFonts.ui,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: p.textFaint,
      );

  /// JetBrains Mono — every number, at the size you ask for.
  static TextStyle mono(
    Color ink, {
    double size = 12,
    FontWeight weight = FontWeight.w400,
  }) =>
      TextStyle(
        fontFamily: HpiFonts.mono,
        fontSize: size,
        fontWeight: weight,
        color: ink,
      );
}
