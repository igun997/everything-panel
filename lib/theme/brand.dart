import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

/// PT Cipta Dua Saudara (ciptadusa.com) brand tokens.
///
/// Taken from the live site stylesheet: charcoal page, mint "signal" accent,
/// sage "edge" accent, DM Sans for display/body and Space Mono for labels.
class Brand {
  const Brand._();

  // Dark palette (primary experience).
  static const pageDark = Color(0xFF0A0A0A);
  static const cardDark = Color(0xFF111111);
  static const chipDark = Color(0xFF1C1C1C);
  static const signalDark = Color(0xFF59F2BD);
  static const edgeDark = Color(0xFF95ABA7);

  // Light palette.
  static const pageLight = Color(0xFFF6F5F1);
  static const cardLight = Color(0xFFFFFFFF);
  static const chipLight = Color(0xFFECEBE7);
  static const signalLight = Color(0xFF0F9B6C);
  static const edgeLight = Color(0xFF4A6B66);

  static const ink = Color(0xFF16181A);
  static const danger = Color(0xFFFF6B6B);
  static const warning = Color(0xFFFFC857);
}

/// Semantic colors resolved for the current brightness.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.page,
    required this.card,
    required this.chip,
    required this.signal,
    required this.edge,
    required this.text,
    required this.textMuted,
    required this.danger,
    required this.warning,
    required this.isDark,
  });

  final Color page;
  final Color card;
  final Color chip;
  final Color signal;
  final Color edge;
  final Color text;
  final Color textMuted;
  final Color danger;
  final Color warning;
  final bool isDark;

  static const dark = BrandColors(
    page: Brand.pageDark,
    card: Brand.cardDark,
    chip: Brand.chipDark,
    signal: Brand.signalDark,
    edge: Brand.edgeDark,
    text: Color(0xFFF4F6F5),
    textMuted: Color(0xFF9AA5A2),
    danger: Brand.danger,
    warning: Brand.warning,
    isDark: true,
  );

  static const light = BrandColors(
    page: Brand.pageLight,
    card: Brand.cardLight,
    chip: Brand.chipLight,
    signal: Brand.signalLight,
    edge: Brand.edgeLight,
    text: Brand.ink,
    textMuted: Color(0xFF5E6B68),
    danger: Color(0xFFD64545),
    warning: Color(0xFFB7791F),
    isDark: false,
  );

  @override
  BrandColors copyWith() => this;

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) =>
      t < 0.5 ? this : (other as BrandColors? ?? this);
}

extension BrandContext on BuildContext {
  BrandColors get brand => Theme.of(this).extension<BrandColors>()!;
}

/// Brand fonts come from Google Fonts at runtime. Tests switch this off so they never
/// touch the network and fall back to the platform fonts.
bool useBrandFonts = true;

/// Family used when [useBrandFonts] is off. Tests set it to a real font so text measures
/// like it does on a device instead of in the blocky test font.
String? fallbackFontFamily;

/// Same, for the mono labels (eyebrows, ids, metrics). Falls back to [fallbackFontFamily].
String? fallbackMonoFontFamily;

/// Mono label style (Space Mono), used for eyebrows, ids and metrics.
TextStyle monoStyle(Color color, {double size = 11, FontWeight? weight}) => useBrandFonts
    ? GoogleFonts.spaceMono(
        color: color,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        letterSpacing: 0.4,
      )
    : TextStyle(
        fontFamily: fallbackMonoFontFamily ?? fallbackFontFamily ?? 'monospace',
        color: color,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        letterSpacing: 0.4,
      );

ThemeData buildTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? BrandColors.dark : BrandColors.light;
  final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: useBrandFonts ? null : fallbackFontFamily);

  // Size-specific tracking: tight on large type, near zero on body.
  final dm = (useBrandFonts ? GoogleFonts.dmSansTextTheme(base.textTheme) : base.textTheme).apply(
    bodyColor: colors.text,
    displayColor: colors.text,
  );
  final textTheme = dm.copyWith(
    displayLarge: dm.displayLarge?.copyWith(letterSpacing: -2, height: 1.02),
    displayMedium: dm.displayMedium?.copyWith(letterSpacing: -1.6, height: 1.04),
    headlineLarge: dm.headlineLarge?.copyWith(letterSpacing: -1.2, height: 1.08, fontWeight: FontWeight.w500),
    headlineMedium: dm.headlineMedium?.copyWith(letterSpacing: -0.8, height: 1.1, fontWeight: FontWeight.w500),
    titleLarge: dm.titleLarge?.copyWith(letterSpacing: -0.4, fontWeight: FontWeight.w600),
    titleMedium: dm.titleMedium?.copyWith(letterSpacing: -0.2, fontWeight: FontWeight.w600),
    bodyLarge: dm.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: dm.bodyMedium?.copyWith(height: 1.45),
    labelLarge: dm.labelLarge?.copyWith(letterSpacing: 0.1, fontWeight: FontWeight.w600),
    labelSmall: dm.labelSmall?.copyWith(letterSpacing: 0.4),
  );

  return base.copyWith(
    scaffoldBackgroundColor: colors.page,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.signal,
      brightness: brightness,
      surface: colors.page,
    ).copyWith(primary: colors.signal, secondary: colors.edge),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: [colors],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.signal,
      selectionColor: colors.signal.withValues(alpha: 0.3),
    ),
  );
}
