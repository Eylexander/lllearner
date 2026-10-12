import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Accent colors to choose from when wallpaper colors are off or unavailable.
const seeds = [
  (name: 'Vermillon', color: Color(0xFFB7312C)),
  (name: 'Jade', color: Color(0xFF2E7D5B)),
  (name: 'Océan', color: Color(0xFF1F6FB2)),
  (name: 'Lavande', color: Color(0xFF6B4FA8)),
  (name: 'Ambre', color: Color(0xFF9A6A00)),
];

/// A custom color in Material's tonal roles.
typedef Tonal = ({Color color, Color onColor, Color container, Color onContainer});

/// Colors that carry a meaning (right / wrong-ish / streak, and the four tones). The
/// first three are harmonized with the theme's primary color as Material 3 recommends
/// for custom colors, so they fit any wallpaper or accent in light and dark mode.
class Palette extends ThemeExtension<Palette> {
  const Palette({required this.success, required this.warning, required this.streak, required this.tones});

  final Tonal success, warning, streak;

  /// Tones 1 to 4, then the neutral tone (Pleco's families: red, green, blue, purple).
  final List<Color> tones;

  /// Tones 1 to 4 for light and dark mode, tuned to stay apart with protanopia,
  /// deuteranopia and tritanopia (at least 10 OKLab units between any two of them, the
  /// neutral tone and the text color, against 4 to 6 for Pleco's colors), with 4.5:1
  /// contrast on the surface. Not harmonized: shifting their hues would undo that.
  static const _lightTones = [Color(0xFFD72B0B), Color(0xFF127F78), Color(0xFF3500F1), Color(0xFF7C4EAE)];
  static const _darkTones = [Color(0xFFFD5B0B), Color(0xFF4FEA6A), Color(0xFF4998FE), Color(0xFFC5819A)];

  factory Palette.of(ColorScheme cs) {
    // Tonal spot (Material's default) for the roles: light containers, readable text.
    Tonal custom(Color c) {
      final s = ColorScheme.fromSeed(seedColor: c.harmonizeWith(cs.primary), brightness: cs.brightness);
      return (color: s.primary, onColor: s.onPrimary, container: s.primaryContainer, onContainer: s.onPrimaryContainer);
    }

    return Palette(
      success: custom(const Color(0xFF2E7D32)),
      warning: custom(const Color(0xFFE65100)),
      streak: custom(const Color(0xFFFF8F00)),
      tones: [...cs.brightness == Brightness.light ? _lightTones : _darkTones, cs.onSurfaceVariant],
    );
  }

  /// Color for a tone (1-5); 0 (not a syllable) gets null, i.e. the text color.
  Color? tone(int t) => t == 0 ? null : tones[t - 1];

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 || other == null ? this : other;
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

ThemeData buildTheme(ColorScheme cs) => ThemeData(
  colorScheme: cs,
  extensions: [Palette.of(cs)],
  scaffoldBackgroundColor: cs.surface,
  appBarTheme: AppBarTheme(backgroundColor: cs.surface, surfaceTintColor: Colors.transparent),
  cardTheme: CardThemeData(
    elevation: 0,
    color: cs.surfaceContainerLow,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 48))),
  outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48))),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
  listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 20)),
);
