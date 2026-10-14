import 'package:flutter/material.dart';

/// Static geometry shared by both themes. Glassmorphism favours generous
/// corner radii and two blur tiers: [blurStrong] for persistent chrome (nav /
/// toolbar / panel sheet) and [blurSoft] for modals (dialog / bottom sheet).
abstract final class MuPicPalette {
  static const radiusLg = 20.0; // cards, sheets, banners
  static const radiusMd = 14.0; // controls, thumbnails
  static const radiusPill = 999.0; // pills / chips

  static const blurStrong = 28.0; // nav / toolbar / panel sheet
  static const blurSoft = 16.0; // modals (dialog / bottom sheet)

  /// Editor / filter image backdrop. Kept dark in BOTH themes so on-screen
  /// color judgment stays accurate regardless of the surrounding chrome. This
  /// area is deliberately left out of the glass treatment.
  static const canvasDark = Color(0xFF1B1B1B);
}

/// Theme-aware Fluent color tokens.
///
/// Registered on [ThemeData] via [ThemeExtension] so every widget can read the
/// current brightness-correct palette with `Theme.of(context).extension<FluentTokens>()!`
/// (or the [fluent] shortcut on [BuildContext]). This replaces the old hard-coded
/// pastel constants, which could not adapt to dark mode.
@immutable
class FluentTokens extends ThemeExtension<FluentTokens> {
  const FluentTokens({
    required this.accent,
    required this.onAccent,
    required this.accent2,
    required this.teal,
    required this.textPrimary,
    required this.textSecondary,
    required this.layer,
    required this.layerAlt,
    required this.subtle,
    required this.divider,
    required this.scaffold,
    required this.banner,
    required this.glassTint,
    required this.glassBorder,
    required this.glassShadow,
    required this.bgBase,
    required this.blobA,
    required this.blobB,
    required this.blobC,
  });

  /// Windows accent blue — the single Fluent primary color.
  final Color accent;
  /// Text / icons drawn on top of [accent].
  final Color onAccent;
  /// Secondary accent (Fluent purple) for the occasional second hue.
  final Color accent2;
  /// Tertiary teal, replaces the old mint accent sparingly.
  final Color teal;
  final Color textPrimary;
  final Color textSecondary;
  /// Card / sheet / pill surface.
  final Color layer;
  /// Slightly offset surface for nested cards.
  final Color layerAlt;
  /// Very low-contrast fill for placeholders / hover.
  final Color subtle;
  final Color divider;
  /// Window background (Mica base).
  final Color scaffold;
  /// Album banner gradient (accent-based).
  final Gradient banner;

  /// Primary translucent fill for glass surfaces.
  final Color glassTint;
  /// Hairline highlight border drawn on glass edges.
  final Color glassBorder;
  /// Soft drop shadow color under glass.
  final Color glassShadow;
  /// Solid base behind the ambient mesh gradient.
  final Color bgBase;
  /// Three ambient mesh blobs.
  final Color blobA;
  final Color blobB;
  final Color blobC;

  @override
  FluentTokens copyWith({
    Color? accent,
    Color? onAccent,
    Color? accent2,
    Color? teal,
    Color? textPrimary,
    Color? textSecondary,
    Color? layer,
    Color? layerAlt,
    Color? subtle,
    Color? divider,
    Color? scaffold,
    Gradient? banner,
    Color? glassTint,
    Color? glassBorder,
    Color? glassShadow,
    Color? bgBase,
    Color? blobA,
    Color? blobB,
    Color? blobC,
  }) {
    return FluentTokens(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accent2: accent2 ?? this.accent2,
      teal: teal ?? this.teal,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      layer: layer ?? this.layer,
      layerAlt: layerAlt ?? this.layerAlt,
      subtle: subtle ?? this.subtle,
      divider: divider ?? this.divider,
      scaffold: scaffold ?? this.scaffold,
      banner: banner ?? this.banner,
      glassTint: glassTint ?? this.glassTint,
      glassBorder: glassBorder ?? this.glassBorder,
      glassShadow: glassShadow ?? this.glassShadow,
      bgBase: bgBase ?? this.bgBase,
      blobA: blobA ?? this.blobA,
      blobB: blobB ?? this.blobB,
      blobC: blobC ?? this.blobC,
    );
  }

  @override
  FluentTokens lerp(ThemeExtension<FluentTokens>? other, double t) {
    if (other is! FluentTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return FluentTokens(
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accent2: c(accent2, other.accent2),
      teal: c(teal, other.teal),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      layer: c(layer, other.layer),
      layerAlt: c(layerAlt, other.layerAlt),
      subtle: c(subtle, other.subtle),
      divider: c(divider, other.divider),
      scaffold: c(scaffold, other.scaffold),
      banner: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          c(banner.colors.first, other.banner.colors.first),
          c(banner.colors.last, other.banner.colors.last),
        ],
      ),
      glassTint: c(glassTint, other.glassTint),
      glassBorder: c(glassBorder, other.glassBorder),
      glassShadow: c(glassShadow, other.glassShadow),
      bgBase: c(bgBase, other.bgBase),
      blobA: c(blobA, other.blobA),
      blobB: c(blobB, other.blobB),
      blobC: c(blobC, other.blobC),
    );
  }
}

/// Convenience accessor: `context.fluent.accent`.
extension FluentContextX on BuildContext {
  FluentTokens get fluent => Theme.of(this).extension<FluentTokens>()!;
}

/// Fluent-styled Material 3 themes (light + dark).
abstract final class MuPicTheme {
  static const _fontFamily = 'Segoe UI';

  static const FluentTokens _lightTokens = FluentTokens(
    accent: Color(0xFF005FB8),
    onAccent: Color(0xFFFFFFFF),
    accent2: Color(0xFF8764B8),
    teal: Color(0xFF008272),
    textPrimary: Color(0xFF1B1B1B),
    textSecondary: Color(0xFF616161),
    layer: Color(0xE6FFFFFF),
    layerAlt: Color(0xD9FFFFFF),
    subtle: Color(0x0A000000),
    divider: Color(0x14000000),
    scaffold: Color(0xFFF3F3F3),
    banner: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF005FB8), Color(0xFF4CC2FF)],
    ),
    glassTint: Color(0xB3FFFFFF),
    glassBorder: Color(0x66FFFFFF),
    glassShadow: Color(0x1F000000),
    bgBase: Color(0xFFF3F3F3),
    blobA: Color(0xFFBBD6FF),
    blobB: Color(0xFFD8C7F2),
    blobC: Color(0xFFBDEBDD),
  );

  static const FluentTokens _darkTokens = FluentTokens(
    accent: Color(0xFF4CC2FF),
    onAccent: Color(0xFF00172B),
    accent2: Color(0xFFB4A0E5),
    teal: Color(0xFF6CD4C0),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFCFCFCF),
    layer: Color(0xE62B2B2B),
    layerAlt: Color(0xD9323232),
    subtle: Color(0x14FFFFFF),
    divider: Color(0x1FFFFFFF),
    scaffold: Color(0xFF202020),
    banner: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF003A70), Color(0xFF115D9E)],
    ),
    glassTint: Color(0x992B2B2B),
    glassBorder: Color(0x33FFFFFF),
    glassShadow: Color(0x66000000),
    bgBase: Color(0xFF202020),
    blobA: Color(0xFF123A5E),
    blobB: Color(0xFF2A1E4A),
    blobC: Color(0xFF0E4A44),
  );

  static ThemeData get light => _build(Brightness.light, _lightTokens);
  static ThemeData get dark => _build(Brightness.dark, _darkTokens);

  static ThemeData _build(Brightness brightness, FluentTokens t) {
    final scheme = ColorScheme.fromSeed(
      seedColor: t.accent,
      brightness: brightness,
    ).copyWith(
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accent2,
      tertiary: t.teal,
      surface: t.layer,
      onSurface: t.textPrimary,
      error: brightness == Brightness.light
          ? const Color(0xFFC42B1C)
          : const Color(0xFFFF99A4),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: _fontFamily,
    );

    return base.copyWith(
      scaffoldBackgroundColor: t.scaffold,
      extensions: [t],
      textTheme: base.textTheme
          .apply(
            bodyColor: t.textPrimary,
            displayColor: t.textPrimary,
          )
          .copyWith(
            // Fluent leans on Segoe UI Variable weights.
            titleSmall: base.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: t.textPrimary,
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: t.layer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MuPicPalette.radiusLg),
          side: BorderSide(color: t.glassBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: t.textPrimary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: t.accent,
        inactiveTrackColor: t.subtle,
        thumbColor: t.accent,
        overlayColor: t.accent.withValues(alpha: 0.14),
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? t.accent
              : t.subtle,
        ),
        trackOutlineColor: WidgetStateProperty.all(t.divider),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MuPicPalette.radiusLg),
        ),
      ),
      dividerTheme: DividerThemeData(color: t.divider, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.glassTint,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(MuPicPalette.radiusLg),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.glassTint,
        surfaceTintColor: Colors.transparent,
        iconColor: t.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MuPicPalette.radiusLg),
          side: BorderSide(color: t.glassBorder),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.layer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MuPicPalette.radiusLg),
          side: BorderSide(color: t.glassBorder),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF2B2B2B)
            : const Color(0xFFF3F3F3),
        contentTextStyle: TextStyle(
          color: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF1B1B1B),
          fontFamily: _fontFamily,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
    );
  }
}
