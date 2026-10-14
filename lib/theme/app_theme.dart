import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color cardBackground;
  final Color cardBorder;
  final Color subtleBackground;
  final Color subtleBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color statusWarning;
  final Color statusDanger;
  final Color buttonForeground;
  final Color accent;
  final Color accentSecondary;
  final Color instrumentRing;
  final Color instrumentFace;
  final Color modalHandle;
  final List<Color> dashboardGradient;

  const AppColors({
    required this.background,
    required this.cardBackground,
    required this.cardBorder,
    required this.subtleBackground,
    required this.subtleBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.statusWarning,
    required this.statusDanger,
    required this.buttonForeground,
    required this.accent,
    required this.accentSecondary,
    required this.instrumentRing,
    required this.instrumentFace,
    required this.modalHandle,
    required this.dashboardGradient,
  });

  static const dark = AppColors(
    background: Colors.black,
    cardBackground: Color(0xFF141414),
    cardBorder: Color(0x1FFFFFFF),
    subtleBackground: Color(0xFF1E1E1E),
    subtleBorder: Color(0x19FFFFFF),
    textPrimary: Colors.white,
    textSecondary: Color(0xB3FFFFFF),
    textMuted: Color(0x61FFFFFF),
    statusWarning: Color(0xFFFFD54F),
    statusDanger: Color(0xFFFF5252),
    buttonForeground: Colors.black,
    accent: Color(0xFFFFBF00),
    accentSecondary: Color(0xFF39FF14),
    instrumentRing: Color(0xFF374151),
    instrumentFace: Colors.black,
    modalHandle: Color(0x3DFFFFFF),
    dashboardGradient: [Colors.black, Color(0xFF0D0D0D)],
  );

  static const light = AppColors(
    background: Color(0xFFF5F5F7),
    cardBackground: Colors.white,
    cardBorder: Color(0xFFE5E5EA),
    subtleBackground: Color(0xFFE8E8ED),
    subtleBorder: Color(0xFFD1D1D6),
    textPrimary: Color(0xFF333336),
    textSecondary: Color(0xFF6E6E73),
    textMuted: Color(0xFF8E8E93),
    statusWarning: Color(0xFFD97706),
    statusDanger: Color(0xFFDC2626),
    buttonForeground: Colors.white,
    accent: Color(0xFF228DEB),
    accentSecondary: Color(0xFF28A745),
    instrumentRing: Color(0xFFD1D1D6),
    instrumentFace: Colors.white,
    modalHandle: Color(0xFFC7C7CC),
    dashboardGradient: [Color(0xFFF5F5F7), Color(0xFFE8E8ED)],
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? cardBackground,
    Color? cardBorder,
    Color? subtleBackground,
    Color? subtleBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? statusWarning,
    Color? statusDanger,
    Color? buttonForeground,
    Color? accent,
    Color? accentSecondary,
    Color? instrumentRing,
    Color? instrumentFace,
    Color? modalHandle,
    List<Color>? dashboardGradient,
  }) {
    return AppColors(
      background: background ?? this.background,
      cardBackground: cardBackground ?? this.cardBackground,
      cardBorder: cardBorder ?? this.cardBorder,
      subtleBackground: subtleBackground ?? this.subtleBackground,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      statusWarning: statusWarning ?? this.statusWarning,
      statusDanger: statusDanger ?? this.statusDanger,
      buttonForeground: buttonForeground ?? this.buttonForeground,
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      instrumentRing: instrumentRing ?? this.instrumentRing,
      instrumentFace: instrumentFace ?? this.instrumentFace,
      modalHandle: modalHandle ?? this.modalHandle,
      dashboardGradient: dashboardGradient ?? this.dashboardGradient,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t) ?? background,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t) ?? cardBackground,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t) ?? cardBorder,
      subtleBackground: Color.lerp(subtleBackground, other.subtleBackground, t) ?? subtleBackground,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t) ?? subtleBorder,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t) ?? statusWarning,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t) ?? statusDanger,
      buttonForeground: Color.lerp(buttonForeground, other.buttonForeground, t) ?? buttonForeground,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t) ?? accentSecondary,
      instrumentRing: Color.lerp(instrumentRing, other.instrumentRing, t) ?? instrumentRing,
      instrumentFace: Color.lerp(instrumentFace, other.instrumentFace, t) ?? instrumentFace,
      modalHandle: Color.lerp(modalHandle, other.modalHandle, t) ?? modalHandle,
      dashboardGradient: [
        Color.lerp(dashboardGradient[0], other.dashboardGradient[0], t) ?? dashboardGradient[0],
        Color.lerp(dashboardGradient[1], other.dashboardGradient[1], t) ?? dashboardGradient[1],
      ],
    );
  }
}

extension AppThemeX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? AppColors.dark : AppColors.light);

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

class AppTheme {
  static final ThemeData darkTheme = _buildDarkTheme();
  static final ThemeData lightTheme = _buildLightTheme();

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.dark.background,
      cardColor: AppColors.dark.cardBackground,
      primaryColor: AppColors.dark.accent,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFBF00),
        secondary: Color(0xFF39FF14),
        surface: Color(0xFF141414),
        onSurface: Colors.white,
      ),
      textTheme: GoogleFonts.robotoTextTheme(
        ThemeData.dark().textTheme,
      ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.comfortaa(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF1C1C1E),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF161616),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF111111),
        selectedItemColor: Color(0xFFFFBF00),
        unselectedItemColor: Colors.white38,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x1FFFFFFF),
        thickness: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: Color(0xFFFFBF00),
        labelColor: Color(0xFFFFBF00),
        unselectedLabelColor: Colors.white60,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF42A5F5);
          }
          return Colors.white70;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF1565C0);
          }
          return Colors.white12;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.dark.accent,
          foregroundColor: Colors.black,
        ),
      ),
      extensions: const [AppColors.dark],
      useMaterial3: true,
    );
  }

  static ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.light.background,
      cardColor: AppColors.light.cardBackground,
      primaryColor: AppColors.light.accent,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF148DEB),
        secondary: Color(0xFF28A745),
        surface: Colors.white,
        onSurface: Color(0xFF333336),
      ),
      textTheme: GoogleFonts.robotoTextTheme(
        ThemeData.light().textTheme,
      ).apply(
        bodyColor: const Color(0xFF333336),
        displayColor: const Color(0xFF333336),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.light.background,
        foregroundColor: const Color(0xFF333336),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.comfortaa(
          color: const Color(0xFF333336),
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF148DEB),
        unselectedItemColor: Color(0xFF8E8E93),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5E5EA),
        thickness: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: Color(0xFF148DEB),
        labelColor: Color(0xFF148DEB),
        unselectedLabelColor: Color(0xFF8E8E93),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF42A5F5);
          }
          return const Color(0xFF8E8E93);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF1565C0);
          }
          return const Color(0xFFE5E5EA);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.light.accent,
          foregroundColor: Colors.white,
        ),
      ),
      extensions: const [AppColors.light],
      useMaterial3: true,
    );
  }

  static TextStyle font({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    FontStyle? fontStyle,
  }) {
    return GoogleFonts.roboto(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
      fontStyle: fontStyle,
    );
  }

  static TextStyle numericFont({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
  }) {
    return GoogleFonts.roboto(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle brandFont({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
  }) {
    return GoogleFonts.comfortaa(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
}
