import 'package:flutter/material.dart';

/// Couleurs et styles communs (style iOS minimaliste, accent jaune Chicken Station).
class AppColors {
  static const yellow = Color(0xFFFFC72C);
  static const yellowSoft = Color(0xFFFFF4D1);
  static const background = Color(0xFFF2F2F7);
  static const card = Colors.white;
  static const text = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF6E6E73);
  static const separator = Color(0xFFE5E5EA);
  static const fill = Color(0xFFF2F2F7);
  static const green = Color(0xFF34C759);
  static const greenText = Color(0xFF1E7A34);
  static const greenSoft = Color(0xFFE3F7E8);
  static const red = Color(0xFFFF3B30);
  static const redText = Color(0xFFC4000F);
  static const redSoft = Color(0xFFFDECEC);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.yellow,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.text,
    onPrimary: Colors.white,
    secondary: AppColors.yellow,
    onSecondary: AppColors.text,
    surface: AppColors.card,
    onSurface: AppColors.text,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Segoe UI',
    dividerColor: AppColors.separator,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Carte blanche arrondie, comme dans la maquette.
class IosCard extends StatelessWidget {
  const IosCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: child,
    );
  }
}

/// Petit titre gris en majuscules (en-tête de section iOS).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// Bouton principal jaune.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.yellow,
          foregroundColor: AppColors.text,
          disabledBackgroundColor: AppColors.fill,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      ),
    );
  }
}

/// Bouton secondaire gris clair.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: AppColors.fill,
          foregroundColor: AppColors.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
