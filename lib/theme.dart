import 'package:flutter/material.dart';

/// ManifestWell design tokens.
///
/// A vivid violet-to-blue nebula sky, frosted-glass surfaces, and light that
/// glows: lilac and sky-blue for action, star-gold for what is lucky. Headings
/// are set in Cinzel (flared caps); everything people read is Nunito Sans.
class MW {
  MW._();

  // Sky
  static const ink = Color(0xFF160F3A);
  static const inkDeep = Color(0xFF0E0928);
  static const indigo = Color(0xFF241A58);
  static const raised = Color(0xFF2B1F66);

  // Text
  static const text = Color(0xFFFFFFFF);
  static const textDim = Color(0xFFE3DAF7);
  static const textFaint = Color(0xFFB4A8DA);

  // Glass
  static const hairline = Color(0x33FFFFFF);
  static const glass = Color(0x1FFFFFFF);
  static const glassStrong = Color(0x2EFFFFFF);

  // Light
  static const violet = Color(0xFFA25CFF);
  static const lilac = Color(0xFFC9B0FF);
  static const sky = Color(0xFF52A8FF);
  static const water = Color(0xFF7CD0FF);

  // Star gold: only ever used for stars, luck and proof.
  static const gold = Color(0xFFFFD66B);
  static const goldBright = Color(0xFFFFE8A0);
  static const goldDeep = Color(0xFFE9B545);

  /// The glowing purple-to-blue used on primary pills.
  static const glow = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFA65DFF), Color(0xFF55A9FF)],
  );

  static const gutter = 20.0;

  static FontWeight _fw(double w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

  /// Cinzel: wordmark, headings, big numerals.
  static TextStyle display(double size,
          {Color color = text, double weight = 700, bool italic = false}) =>
      TextStyle(
        fontFamily: 'Cinzel',
        fontSize: size,
        height: 1.12,
        color: color,
        fontWeight: _fw(weight),
        fontVariations: [FontVariation('wght', weight)],
        letterSpacing: size * 0.02,
      );

  /// Section headings such as RECENT WISHES.
  static TextStyle heading(double size, {Color color = text}) =>
      display(size, color: color, weight: 700).copyWith(letterSpacing: size * 0.03);

  /// What a person wrote: wishes, wins, notes.
  static TextStyle voice(double size, {Color color = text, double weight = 600}) =>
      ui(size, color: color, weight: weight, height: 1.32);

  /// Wishes contain emoji, which Nunito has none of. Naming each platform's
  /// emoji font keeps them rendering in colour everywhere; a name that isn't
  /// installed is simply skipped.
  static const emojiFonts = ['Apple Color Emoji', 'Noto Color Emoji', 'Segoe UI Emoji'];

  static TextStyle ui(double size,
          {Color color = textDim, double weight = 500, double height = 1.4}) =>
      TextStyle(
        fontFamily: 'NunitoSans',
        fontFamilyFallback: emojiFonts,
        fontSize: size,
        height: height,
        color: color,
        fontWeight: _fw(weight),
        fontVariations: [FontVariation('wght', weight)],
      );

  static TextStyle caps({Color color = textFaint, double size = 11}) =>
      ui(size, color: color, weight: 800).copyWith(letterSpacing: size * 0.14);

  /// Soft outer glow for titles over the nebula.
  static List<Shadow> titleGlow = [
    Shadow(color: lilac.withValues(alpha: 0.9), blurRadius: 18),
    Shadow(color: Colors.white.withValues(alpha: 0.55), blurRadius: 4),
  ];

  static ThemeData theme() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: ink,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: violet,
        onPrimary: Colors.white,
        secondary: sky,
        surface: raised,
        onSurface: text,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'NunitoSans',
        bodyColor: text,
        displayColor: text,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: raised,
        elevation: 0,
        contentTextStyle: ui(14, color: text, weight: 700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: hairline),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? violet : glassStrong,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: raised,
        dialBackgroundColor: indigo,
        hourMinuteColor: indigo,
        dayPeriodColor: indigo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: lilac,
        selectionColor: violet.withValues(alpha: 0.4),
        selectionHandleColor: lilac,
      ),
    );
  }
}
