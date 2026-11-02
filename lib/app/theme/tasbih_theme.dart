import 'package:flutter/material.dart';

Color hsl(double h, double s, double l, [double a = 1]) =>
    HSLColor.fromAHSL(a, h, s / 100, l / 100).toColor();

class TasbihTheme {
  static final background = hsl(220, 20, 8);
  static final foreground = hsl(45, 30, 90);
  static final card = hsl(220, 15, 12);
  static final soft = hsl(220, 15, 18, .65);
  static final gold = hsl(45, 80, 55);
  static final muted = hsl(220, 10, 62);
  static final accent = hsl(45, 60, 45);
  static final border = hsl(220, 12, 22);
  static final danger = hsl(0, 72, 62);
  static final success = hsl(145, 70, 48);
  static final todo = hsl(355, 78, 62);
  static final gradients = <String, List<Color>>{
    'fajr': [hsl(220, 40, 12), hsl(210, 50, 25), hsl(35, 40, 30)],
    'dhuhr': [hsl(45, 50, 20), hsl(40, 40, 15), hsl(35, 30, 10)],
    'asr': [hsl(35, 50, 18), hsl(30, 45, 14), hsl(25, 35, 10)],
    'maghrib': [hsl(15, 50, 18), hsl(340, 30, 15), hsl(260, 25, 12)],
    'isha': [hsl(240, 30, 8), hsl(230, 25, 10), hsl(220, 20, 8)],
  };
  static final glows = <String, Color>{
    'fajr': hsl(210, 60, 50, .22),
    'dhuhr': hsl(45, 70, 55, .22),
    'asr': hsl(35, 65, 50, .22),
    'maghrib': hsl(15, 70, 50, .22),
    'isha': hsl(240, 50, 50, .22),
  };
  static ThemeData get data => ThemeData(
    brightness: Brightness.dark,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: background,
    fontFamily: 'IBM Plex Sans Arabic',
    fontFamilyFallback: const ['Tasbih Symbols', 'Tasbih Emoji'],
    colorScheme: ColorScheme.dark(
      primary: gold,
      secondary: accent,
      surface: card,
      onSurface: foreground,
      error: danger,
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: foreground, fontSize: 12),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: const Color(0xff0075ff),
      inactiveTrackColor: const Color(0xffeeeeee),
      thumbColor: const Color(0xff0075ff),
      overlayColor: gold.withValues(alpha: .12),
      trackHeight: 4,
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 0),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: TextStyle(color: foreground, fontSize: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
    ),
  );
}
