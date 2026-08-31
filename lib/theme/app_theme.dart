import 'package:flutter/material.dart';

import 'hpi_tokens.dart';

/// Builds the two HealthyPi Studio themes from [HpiPalette].
///
/// Both themes carry the palette as a [ThemeExtension] so every widget can read
/// semantic colours with `context.hpi` instead of hard-coding hex values.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _build(HpiPalette.dark, Brightness.dark);
  static ThemeData get lightTheme => _build(HpiPalette.light, Brightness.light);

  static ThemeData _build(HpiPalette p, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: HpiFonts.body,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[p],
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.canvas,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.brand,
        onPrimary: brightness == Brightness.dark
            ? const Color(0xFF07171D)
            : Colors.white,
        secondary: p.accent,
        onSecondary: p.accentInk,
        error: p.error,
        onError: Colors.white,
        surface: p.chrome,
        onSurface: p.textPrimary,
        surfaceContainerHighest: p.cardInner,
        onSurfaceVariant: p.textMuted,
        outline: p.outline,
        outlineVariant: p.outlineSoft,
      ),
      dividerTheme: DividerThemeData(color: p.outlineSoft, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textMuted, size: 20),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.brandSoft,
        selectionHandleColor: p.brand,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(p.outline),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.cardInner,
          border: Border.all(color: p.outline),
          borderRadius: HpiRadius.controlR,
        ),
        textStyle: HpiText.control(p),
        waitDuration: const Duration(milliseconds: 500),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: HpiRadius.cardR,
          side: BorderSide(color: p.outlineSoft),
        ),
        titleTextStyle: HpiText.screenTitle(p).copyWith(fontSize: 15),
        contentTextStyle: HpiText.body(p),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.cardInner,
        contentTextStyle: HpiText.body(p).copyWith(color: p.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: HpiRadius.buttonR,
          side: BorderSide(color: p.outline),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: HpiRadius.cardR,
          side: BorderSide(color: p.outlineSoft),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.accentInk,
          elevation: 0,
          textStyle: HpiText.button(p.accentInk),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 36),
          shape: const RoundedRectangleBorder(borderRadius: HpiRadius.buttonR),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textSecondary,
          backgroundColor: p.cardInner,
          side: BorderSide(color: p.outline),
          textStyle: HpiText.button(p.textSecondary).copyWith(fontSize: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          minimumSize: const Size(0, 34),
          shape: const RoundedRectangleBorder(borderRadius: HpiRadius.buttonR),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.brand,
          textStyle: HpiText.control(p).copyWith(color: p.brand),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.well,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        hintStyle: HpiText.body(p).copyWith(color: p.textFaint),
        labelStyle: HpiText.label(p),
        border: OutlineInputBorder(
          borderRadius: HpiRadius.buttonR,
          borderSide: BorderSide(color: p.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: HpiRadius.buttonR,
          borderSide: BorderSide(color: p.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: HpiRadius.buttonR,
          borderSide: BorderSide(color: p.accent),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: p.textSecondary,
        displayColor: p.textPrimary,
        fontFamily: HpiFonts.body,
      ),
    );
  }
}
