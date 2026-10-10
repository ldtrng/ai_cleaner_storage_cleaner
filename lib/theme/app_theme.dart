import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Palette: #0F2A1D · #375534 · #6B9071 · #AEC3B0 · #E3EED4
abstract final class Palette {
  static const forest = Color(0xFF0F2A1D);
  static const moss = Color(0xFF375534);
  static const sage = Color(0xFF6B9071);
  static const mist = Color(0xFFAEC3B0);
  static const cream = Color(0xFFE3EED4);

  // Derived tones used for surfaces.
  static const creamLight = Color(0xFFF2F7EA);
  static const forestLight = Color(0xFF173A28);
  static const forestCard = Color(0xFF1D4230);
  static const danger = Color(0xFFC2563F);
}

/// Semantic tokens that both themes provide.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bgTop,
    required this.bgBottom,
    required this.card,
    required this.cardStrong,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.track,
  });

  final Color bgTop;
  final Color bgBottom;
  final Color card;
  final Color cardStrong;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color track;

  static const light = AppTokens(
    bgTop: Palette.creamLight,
    bgBottom: Palette.cream,
    card: Colors.white,
    cardStrong: Palette.moss,
    textMuted: Color(0xFF5D7564),
    accent: Palette.moss,
    onAccent: Palette.cream,
    track: Color(0xFFD5E2CD),
  );

  static const dark = AppTokens(
    bgTop: Palette.forest,
    bgBottom: Palette.forestLight,
    card: Palette.forestCard,
    cardStrong: Palette.moss,
    textMuted: Palette.mist,
    accent: Palette.cream,
    onAccent: Palette.forest,
    track: Color(0xFF2A4F3A),
  );

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      bgTop: Color.lerp(bgTop, other.bgTop, t)!,
      bgBottom: Color.lerp(bgBottom, other.bgBottom, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardStrong: Color.lerp(cardStrong, other.cardStrong, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      track: Color.lerp(track, other.track, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

const _fontFamily = 'Outfit';

/// Outfit ships as a variable font, so weight must also be set as a font variation.
TextStyle font(
  double size,
  FontWeight weight, {
  Color? color,
  double? height,
  double? spacing,
}) => TextStyle(
  fontFamily: _fontFamily,
  fontSize: size,
  fontWeight: weight,
  fontVariations: [FontVariation.weight(weight.value.toDouble())],
  color: color,
  height: height,
  letterSpacing: spacing,
);

TextTheme _textTheme(Color main, Color muted) => TextTheme(
  displaySmall: font(34, FontWeight.w700, color: main, height: 1.1),
  headlineMedium: font(28, FontWeight.w700, color: main, height: 1.15),
  headlineSmall: font(24, FontWeight.w600, color: main),
  titleLarge: font(20, FontWeight.w600, color: main),
  titleMedium: font(16, FontWeight.w600, color: main),
  titleSmall: font(14, FontWeight.w600, color: main),
  bodyLarge: font(16, FontWeight.w400, color: main),
  bodyMedium: font(14, FontWeight.w400, color: main),
  bodySmall: font(12, FontWeight.w400, color: muted),
  labelLarge: font(16, FontWeight.w600, color: main),
  labelMedium: font(13, FontWeight.w500, color: main),
  labelSmall: font(11, FontWeight.w500, color: muted),
);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final tokens = dark ? AppTokens.dark : AppTokens.light;
  final onBg = dark ? Palette.cream : Palette.forest;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? Palette.cream : Palette.moss,
    onPrimary: dark ? Palette.forest : Palette.cream,
    primaryContainer: dark ? Palette.moss : Palette.mist,
    onPrimaryContainer: dark ? Palette.cream : Palette.forest,
    secondary: Palette.sage,
    onSecondary: Colors.white,
    secondaryContainer: dark ? Palette.forestCard : Palette.cream,
    onSecondaryContainer: onBg,
    tertiary: Palette.mist,
    onTertiary: Palette.forest,
    error: Palette.danger,
    onError: Colors.white,
    surface: dark ? Palette.forest : Palette.creamLight,
    onSurface: onBg,
    onSurfaceVariant: tokens.textMuted,
    surfaceContainerHighest: tokens.card,
    surfaceContainerHigh: tokens.card,
    surfaceContainer: tokens.card,
    surfaceContainerLow: tokens.card,
    outline: dark ? Palette.sage : Palette.mist,
    outlineVariant: tokens.track,
  );

  final text = _textTheme(onBg, tokens.textMuted);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    textTheme: text,
    scaffoldBackgroundColor: tokens.bgTop,
    extensions: [tokens],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: onBg,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle:
          (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        disabledBackgroundColor: tokens.track,
        disabledForegroundColor: tokens.textMuted,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: font(16, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onBg,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        side: BorderSide(color: dark ? Palette.sage : Palette.mist, width: 1.5),
        textStyle: font(16, FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? Palette.mist : Palette.moss,
        textStyle: font(14, FontWeight.w600),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? Palette.forestLight : Palette.creamLight,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(color: tokens.textMuted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Palette.forestLight : Palette.creamLight,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Palette.cream : Palette.forest,
      contentTextStyle: font(
        14,
        FontWeight.w500,
        color: dark ? Palette.forest : Palette.cream,
      ),
      shape: const StadiumBorder(),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (dark ? Palette.cream : Palette.moss)
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(dark ? Palette.forest : Palette.cream),
      side: BorderSide(color: dark ? Palette.mist : Palette.sage, width: 1.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (dark ? Palette.forest : Palette.cream)
            : Palette.mist,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? (dark ? Palette.cream : Palette.moss)
            : tokens.track,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStatePropertyAll(dark ? Palette.cream : Palette.moss),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: dark ? Palette.cream : Palette.moss,
      linearTrackColor: tokens.track,
      circularTrackColor: tokens.track,
    ),
    dividerTheme: DividerThemeData(color: tokens.track, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: onBg,
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodySmall,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      hintStyle: text.bodyMedium?.copyWith(color: tokens.textMuted),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}
