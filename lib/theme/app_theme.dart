import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color navy = Color(0xFF0F172A);
  static const Color primary = Color(0xFF0F766E);
  static const Color primaryDark = Color(0xFF115E59);
  static const Color primarySoft = Color(0xFFE6FFFB);
  static const Color teal = primary;
  static const Color bg = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color surfaceSoft = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);
  static const Color textMuted = Color(0xFF64748B);
  static const Color danger = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color purple = Color(0xFF7C3AED);
  static const Color info = Color(0xFF2563EB);

  static const double radius = 14;
  static const double radiusLarge = 18;

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: navy.withOpacity(.045),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ];

  static LinearGradient get enterpriseGradient => const LinearGradient(
        colors: [primaryDark, primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Color statusColor(String? value) {
    final status = (value ?? '').toLowerCase();
    if (status.contains('paid') || status.contains('active') || status.contains('approved') || status.contains('completed')) {
      return success;
    }
    if (status.contains('partial') || status.contains('pending') || status.contains('draft')) {
      return warning;
    }
    if (status.contains('unpaid') || status.contains('inactive') || status.contains('rejected') || status.contains('cancel')) {
      return danger;
    }
    return textMuted;
  }

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      secondary: primaryDark,
      surface: surface,
      error: danger,
      outline: border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'Roboto',
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: border),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: bg,
        foregroundColor: navy,
        iconTheme: IconThemeData(color: navy),
        actionsIconTheme: IconThemeData(color: navy),
        titleTextStyle: TextStyle(
          color: navy,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.35,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: navy.withOpacity(.08),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textMuted,
        textColor: navy,
        titleTextStyle: TextStyle(
          color: navy,
          fontWeight: FontWeight.w800,
          fontSize: 14.5,
        ),
        subtitleTextStyle: TextStyle(
          color: textMuted,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          height: 1.25,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(
          color: textMuted,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: borderStrong,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 44),
          backgroundColor: Colors.white,
          foregroundColor: primary,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: const BorderSide(color: border),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          side: const BorderSide(color: borderStrong),
          foregroundColor: navy,
          textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 3,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
      bottomAppBarTheme: const BottomAppBarThemeData(
        color: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: primarySoft,
        disabledColor: surfaceSoft,
        checkmarkColor: primary,
        deleteIconColor: textMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          color: navy,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
        secondaryLabelStyle: const TextStyle(
          color: navy,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
        elevation: 8,
        insetPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actionTextColor: const Color(0xFF99F6E4),
        closeIconColor: Colors.white,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          color: navy,
          fontSize: 19,
          fontWeight: FontWeight.w900,
          letterSpacing: -.25,
        ),
        contentTextStyle: const TextStyle(
          color: navy,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.white,
        modalBarrierColor: Color(0x660F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(color: navy, fontWeight: FontWeight.w700),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: MaterialStatePropertyAll(Color(0xFFF1F5F9)),
        headingTextStyle: TextStyle(fontWeight: FontWeight.w900, color: navy),
        dataTextStyle: TextStyle(color: navy, fontWeight: FontWeight.w600),
        dividerThickness: .6,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: navy,
        displayColor: navy,
      ).copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.45,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.35,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
    );
  }
}
