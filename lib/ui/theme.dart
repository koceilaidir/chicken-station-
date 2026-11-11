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
    // Pas de teinte beige du Material 3 : fenêtres blanches, puces jaune pâle, comme sur la maquette.
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF7F7F9),
    surfaceContainer: AppColors.fill,
    surfaceContainerHigh: Colors.white,
    surfaceContainerHighest: const Color(0xFFE9E9EE),
    secondaryContainer: AppColors.yellowSoft,
    onSecondaryContainer: AppColors.text,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Segoe UI',
    dividerColor: AppColors.separator,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text, fontFamily: 'Segoe UI'),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.text,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
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

/// Sélecteur à segments façon iOS (fond gris, case choisie blanche en relief), comme sur la maquette.
class IosSegmented<T> extends StatelessWidget {
  const IosSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.label,
    this.expand = true,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T value) label;

  /// true : prend toute la largeur, cases égales. false : largeur du texte.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      for (final v in values)
        _segment(v),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFE9E9EE), borderRadius: BorderRadius.circular(11)),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [for (final c in children) expand ? Expanded(child: c) : c],
      ),
    );
  }

  Widget _segment(T v) {
    final sel = v == selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: expand ? 6 : 14, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: sel
              ? const [
                  BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2)),
                  BoxShadow(color: Color(0x0A000000), blurRadius: 1, offset: Offset(0, 0)),
                ]
              : null,
        ),
        child: Text(
          label(v),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }
}
