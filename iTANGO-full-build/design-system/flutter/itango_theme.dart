// itango_theme.dart
// Generated from design-tokens.json — keep in sync. Do not hardcode colors
// elsewhere in the app; always reference ItangoColors / ItangoTheme.
//
// Usage:
//   MaterialApp(
//     theme: ItangoTheme.light,
//     darkTheme: ItangoTheme.dark,
//     themeMode: ThemeMode.system,
//   )
//
// Access iTANGO-specific tokens (gradients, warmth colors) via:
//   Theme.of(context).extension<ItangoExtras>()!

import 'package:flutter/material.dart';

/// Raw color primitives, 1:1 with design-tokens.json `color` block.
class ItangoColors {
  ItangoColors._();

  // Dark theme (default brand experience)
  static const bgBase = Color(0xFF0A0A0F);
  static const bgSurface = Color(0xFF15151F);
  static const bgSurfaceElevated = Color(0xFF1E1E2A);

  static const brandGradientStart = Color(0xFFB0202A);
  static const brandGradientEnd = Color(0xFF4A0E12);
  static const brandPrimary = Color(0xFF9E1B23);
  static const brandPrimaryDeep = Color(0xFF6E1319);
  static const brandLogoBlack = Color(0xFF181212);

  static const accentCyan = Color(0xFF22D3EE);
  static const accentAmber = Color(0xFFF59E0B);
  static const accentEmerald = Color(0xFF34D399);

  static const statusLive = Color(0xFFFF2D55);
  static const statusWarmthHot = Color(0xFFFF3D71);
  static const statusWarmthWarm = Color(0xFFF59E0B);
  static const statusSuccess = Color(0xFF34D399);
  static const statusWarning = Color(0xFFFBBF24);
  static const statusDanger = Color(0xFFEF4444);
  static const statusInfo = Color(0xFF22D3EE);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA1A1AA);
  static const textTertiary = Color(0xFF71717A);
  static const textLink = Color(0xFFC084FC);

  static const borderSubtle = Color(0xFF27272F);
  static const borderDefault = Color(0xFF3F3F4A);

  // Light theme
  static const lightBgBase = Color(0xFFFAFAFA);
  static const lightBgSurface = Color(0xFFFFFFFF);
  static const lightBgSurfaceElevated = Color(0xFFF4F4F6);
  static const lightTextPrimary = Color(0xFF0A0A0F);
  static const lightTextSecondary = Color(0xFF52525B);
  static const lightTextTertiary = Color(0xFFA1A1AA);
  static const lightBorderSubtle = Color(0xFFE4E4E7);
  static const lightBorderDefault = Color(0xFFD4D4D8);
}

/// Gradients used across primary CTAs, live badges, and warmth indicators.
class ItangoGradients {
  ItangoGradients._();

  static const primaryCta = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ItangoColors.brandGradientStart, ItangoColors.brandGradientEnd],
  );

  static const warmthHot = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [ItangoColors.statusWarmthHot, ItangoColors.statusWarmthWarm],
  );

  static const liveBadge = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [ItangoColors.statusLive, ItangoColors.brandPrimary],
  );
}

/// Spacing scale — always use ItangoSpacing.x instead of magic numbers.
class ItangoSpacing {
  ItangoSpacing._();
  static const s0 = 0.0;
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s12 = 48.0;
  static const s16 = 64.0;
  static const s20 = 80.0;
}

/// Radii — matches design-tokens.json `radius` block.
class ItangoRadius {
  ItangoRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xl2 = 28.0;
  static const pill = 999.0;
}

/// Custom ThemeExtension carrying iTANGO-specific tokens that don't map
/// cleanly onto Flutter's built-in ThemeData fields (gradients, warmth
/// colors, component-specific sizing). Access via:
///   Theme.of(context).extension<ItangoExtras>()!.primaryCtaGradient
@immutable
class ItangoExtras extends ThemeExtension<ItangoExtras> {
  const ItangoExtras({
    required this.primaryCtaGradient,
    required this.warmthHotGradient,
    required this.liveBadgeGradient,
    required this.statusLive,
    required this.statusSuccess,
    required this.accentCyan,
    required this.accentAmber,
    required this.accentEmerald,
    required this.bottomNavHeight,
    required this.fabSize,
  });

  final Gradient primaryCtaGradient;
  final Gradient warmthHotGradient;
  final Gradient liveBadgeGradient;
  final Color statusLive;
  final Color statusSuccess;
  final Color accentCyan;
  final Color accentAmber;
  final Color accentEmerald;
  final double bottomNavHeight;
  final double fabSize;

  static const dark = ItangoExtras(
    primaryCtaGradient: ItangoGradients.primaryCta,
    warmthHotGradient: ItangoGradients.warmthHot,
    liveBadgeGradient: ItangoGradients.liveBadge,
    statusLive: ItangoColors.statusLive,
    statusSuccess: ItangoColors.statusSuccess,
    accentCyan: ItangoColors.accentCyan,
    accentAmber: ItangoColors.accentAmber,
    accentEmerald: ItangoColors.accentEmerald,
    bottomNavHeight: 64,
    fabSize: 56,
  );

  // Light theme keeps the same brand gradients/status colors — only
  // surfaces and text invert. This is deliberate: iTANGO's brand gradient
  // is the one constant across modes.
  static const light = dark;

  @override
  ItangoExtras copyWith({
    Gradient? primaryCtaGradient,
    Gradient? warmthHotGradient,
    Gradient? liveBadgeGradient,
    Color? statusLive,
    Color? statusSuccess,
    Color? accentCyan,
    Color? accentAmber,
    Color? accentEmerald,
    double? bottomNavHeight,
    double? fabSize,
  }) {
    return ItangoExtras(
      primaryCtaGradient: primaryCtaGradient ?? this.primaryCtaGradient,
      warmthHotGradient: warmthHotGradient ?? this.warmthHotGradient,
      liveBadgeGradient: liveBadgeGradient ?? this.liveBadgeGradient,
      statusLive: statusLive ?? this.statusLive,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      accentCyan: accentCyan ?? this.accentCyan,
      accentAmber: accentAmber ?? this.accentAmber,
      accentEmerald: accentEmerald ?? this.accentEmerald,
      bottomNavHeight: bottomNavHeight ?? this.bottomNavHeight,
      fabSize: fabSize ?? this.fabSize,
    );
  }

  @override
  ItangoExtras lerp(ThemeExtension<ItangoExtras>? other, double t) {
    if (other is! ItangoExtras) return this;
    return this; // Gradients/brand colors are constant across modes; no lerp needed.
  }
}

/// Public entry point: ItangoTheme.light / ItangoTheme.dark
class ItangoTheme {
  ItangoTheme._();

  static const _fontFamily = 'Inter';

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: ItangoColors.brandPrimary,
      onPrimary: ItangoColors.textPrimary,
      secondary: ItangoColors.accentCyan,
      onSecondary: ItangoColors.bgBase,
      surface: ItangoColors.bgSurface,
      onSurface: ItangoColors.textPrimary,
      error: ItangoColors.statusDanger,
      onError: ItangoColors.textPrimary,
      outline: ItangoColors.borderDefault,
    );

    return _base(scheme: scheme, extras: ItangoExtras.dark).copyWith(
      scaffoldBackgroundColor: ItangoColors.bgBase,
      cardColor: ItangoColors.bgSurface,
      dividerColor: ItangoColors.borderSubtle,
    );
  }

  static ThemeData get light {
    const scheme = ColorScheme.light(
      brightness: Brightness.light,
      primary: ItangoColors.brandPrimary,
      onPrimary: Colors.white,
      secondary: ItangoColors.accentCyan,
      onSecondary: ItangoColors.lightTextPrimary,
      surface: ItangoColors.lightBgSurface,
      onSurface: ItangoColors.lightTextPrimary,
      error: ItangoColors.statusDanger,
      onError: Colors.white,
      outline: ItangoColors.lightBorderDefault,
    );

    return _base(scheme: scheme, extras: ItangoExtras.light).copyWith(
      scaffoldBackgroundColor: ItangoColors.lightBgBase,
      cardColor: ItangoColors.lightBgSurface,
      dividerColor: ItangoColors.lightBorderSubtle,
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required ItangoExtras extras,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    final textPrimary = isDark ? ItangoColors.textPrimary : ItangoColors.lightTextPrimary;
    final textSecondary = isDark ? ItangoColors.textSecondary : ItangoColors.lightTextSecondary;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      brightness: scheme.brightness,
      extensions: [extras],
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: textPrimary),
        headlineMedium: TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.25, color: textPrimary),
        headlineSmall: TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w700, color: textPrimary),
        titleMedium: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w400, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w400, color: textSecondary),
        bodySmall: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w400, color: textSecondary),
        labelLarge: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: textSecondary),
        labelSmall: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s6, vertical: ItangoSpacing.s4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ItangoRadius.pill)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ItangoRadius.lg),
          side: BorderSide(color: isDark ? ItangoColors.borderSubtle : ItangoColors.lightBorderSubtle),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? ItangoColors.bgSurfaceElevated : ItangoColors.lightBgSurfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: ItangoSpacing.s4, vertical: ItangoSpacing.s3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ItangoRadius.md),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: textSecondary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: ItangoColors.brandGradientStart,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

/// A reusable gradient CTA button, since Flutter's ElevatedButton doesn't
/// support gradient fills natively. Use wherever the design calls for the
/// pink→violet pill CTA (Next, Say Hi, Join Activity, Create Event).
class ItangoGradientButton extends StatelessWidget {
  const ItangoGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.gradient = ItangoGradients.primaryCta,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final Gradient gradient;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ItangoRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(ItangoRadius.pill),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: ItangoSpacing.s4),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(ItangoRadius.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              if (icon != null) ...[
                const SizedBox(width: ItangoSpacing.s2),
                Icon(icon, color: Colors.white, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
