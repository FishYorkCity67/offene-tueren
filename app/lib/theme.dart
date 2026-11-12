import 'package:flutter/material.dart';

import 'models/event.dart';

/// Farben im ruhigen „Hissbit“-Stil: warmes Elfenbein bzw. warmes Anthrazit,
/// dunkle Tinte für Text und Knöpfe, ein Jade-Akzent. Keine Verläufe, kein Glühen.
class Palette {
  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.outline,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.onInk,
    required this.accent,
    required this.warn,
    required this.warnBg,
    required this.dark,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color outline;
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color onInk;
  final Color accent;
  final Color warn;
  final Color warnBg;
  final bool dark;

  static const light = Palette(
    background: Color(0xFFFBFAF7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF3F1EC),
    outline: Color(0xFFE7E3DA),
    ink: Color(0xFF1C1A17),
    inkSoft: Color(0xFF3A3732),
    muted: Color(0xFF7A746A),
    onInk: Color(0xFFFBFAF7),
    accent: Color(0xFF1D7357),
    warn: Color(0xFF9A5B0B),
    warnBg: Color(0xFFFBF1E1),
    dark: false,
  );

  static const night = Palette(
    background: Color(0xFF131211),
    surface: Color(0xFF1C1B19),
    surfaceAlt: Color(0xFF242320),
    outline: Color(0xFF2F2D29),
    ink: Color(0xFFEFECE6),
    inkSoft: Color(0xFFD4D0C8),
    muted: Color(0xFF9B958B),
    onInk: Color(0xFF131211),
    accent: Color(0xFF5BB592),
    warn: Color(0xFFE2A54D),
    warnBg: Color(0xFF2B2318),
    dark: true,
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? night : light;

  /// Kategorie-Farben: kräftig genug, um bunt zu wirken, aber gedämpft (kein Neon).
  Color category(Category c) => switch (c) {
        Category.hochschule => dark ? const Color(0xFF7F9CE8) : const Color(0xFF3B5BB0),
        Category.schule => dark ? const Color(0xFFE8A64A) : const Color(0xFFC97A12),
        Category.ausbildung => dark ? const Color(0xFF5CC09A) : const Color(0xFF23845F),
        Category.sonstiges => dark ? const Color(0xFFE77F72) : const Color(0xFFBF4436),
        Category.gratis => dark ? const Color(0xFF4FC3C1) : const Color(0xFF0E8486),
        Category.flohmarkt => dark ? const Color(0xFFC79AD4) : const Color(0xFF8A548F),
        Category.ferienprogramm => dark ? const Color(0xFFA9C95A) : const Color(0xFF5E8A1C),
        Category.saisonal => dark ? const Color(0xFFE48AA2) : const Color(0xFFA83A5B),
      };

  /// Farbe der Altersstufe eines Ferienjobs.
  Color ageColor(int minAge) => switch (minAge) {
        <= 14 => accent,
        15 => dark ? const Color(0xFF7F9CE8) : const Color(0xFF3B5BB0),
        16 => dark ? const Color(0xFFE8A64A) : const Color(0xFFC97A12),
        _ => muted,
      };

  Color categoryTint(Category c) =>
      Color.alphaBlend(category(c).withValues(alpha: dark ? 0.18 : 0.11), surface);
}

const serif = 'serif';

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme(
    brightness: p.dark ? Brightness.dark : Brightness.light,
    primary: p.ink,
    onPrimary: p.onInk,
    secondary: p.accent,
    onSecondary: p.onInk,
    error: const Color(0xFFB3261E),
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.ink,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.background,
    surfaceContainer: p.surfaceAlt,
    surfaceContainerHigh: p.surfaceAlt,
    surfaceContainerHighest: p.outline,
    outline: p.outline,
    outlineVariant: p.outline,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    splashFactory: InkSparkle.splashFactory,
  );

  TextStyle head(double size, {FontWeight w = FontWeight.w600, double h = 1.15}) => TextStyle(
        fontFamily: serif,
        fontSize: size,
        fontWeight: w,
        height: h,
        color: p.ink,
        letterSpacing: -0.2,
      );

  final text = base.textTheme.copyWith(
    displaySmall: head(34),
    headlineMedium: head(28),
    headlineSmall: head(23),
    titleLarge: head(20),
    titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600, color: p.ink, letterSpacing: 0),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: p.ink),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(color: p.inkSoft, height: 1.45),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(color: p.inkSoft, height: 1.4),
    bodySmall: base.textTheme.bodySmall?.copyWith(color: p.muted, height: 1.35),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium: base.textTheme.labelMedium?.copyWith(color: p.muted, letterSpacing: 0.2),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));

  return base.copyWith(
    textTheme: text,
    dividerTheme: DividerThemeData(color: p.outline, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.onInk,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: BorderSide(color: p.outline, width: 1.2),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.ink, shape: shape),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onInk : p.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceAlt),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.outline),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.onInk, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.outline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// Kurze, weiche Bewegungen – und keine, wenn das System Animationen abschaltet.
class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 520);
  static const curve = Curves.easeOutCubic;

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}
