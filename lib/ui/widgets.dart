import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db.dart';
import 'theme.dart';

/// Logo Chicken Station (ailes).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.width = 220});
  final double width;

  @override
  Widget build(BuildContext context) => Image.asset('assets/images/logo.png', width: width, fit: BoxFit.contain);
}

/// Petite icône ronde du logo.
class AppBadge extends StatelessWidget {
  const AppBadge({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/images/icon.png', width: size, height: size, fit: BoxFit.contain);
}

/// Photo d'un produit ou d'une famille (base d'images de l'appli).
class PhotoBox extends StatelessWidget {
  const PhotoBox({super.key, required this.photo, this.size, this.width, this.height, this.radius = 12, this.fallback = ''});

  final String? photo;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final path = AppDb.I.photoPath(photo);
    final w = width ?? size;
    final h = height ?? size;
    Widget child;
    if (path != null && File(path).existsSync()) {
      child = Image.file(File(path), width: w, height: h, fit: BoxFit.cover, cacheWidth: 400);
    } else {
      child = Container(
        width: w,
        height: h,
        color: AppColors.yellowSoft,
        alignment: Alignment.center,
        child: Text(
          fallback.isEmpty ? '' : fallback.substring(0, 1).toUpperCase(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF8A6A00)),
        ),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

/// Champ de saisie gris arrondi.
class FieldBox extends StatelessWidget {
  const FieldBox({
    super.key,
    required this.controller,
    this.hint = '',
    this.onChanged,
    this.numeric = false,
    this.autofocus = false,
    this.big = false,
    this.obscure = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool numeric;
  final bool autofocus;
  final bool big;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))] : null,
      style: TextStyle(fontSize: big ? 26 : 15, fontWeight: big ? FontWeight.w800 : FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: big ? 22 : 15,
          fontWeight: FontWeight.w400,
          color: const Color(0xFFAEAEB2),
        ),
        filled: true,
        fillColor: AppColors.fill,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: big ? 16 : 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}

/// En-tête de page : petit sur-titre, grand titre, actions à droite.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.overline, this.subtitle, this.actions = const []});

  final String title;
  final String? overline;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overline != null) Text(overline!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
        if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
    if (actions.isEmpty) return titles;
    return LayoutBuilder(
      builder: (context, c) {
        // Écran étroit : les boutons passent sous le titre au lieu de déborder.
        if (c.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titles,
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: titles),
            for (final a in actions) ...[const SizedBox(width: 10), a],
          ],
        );
      },
    );
  }
}

/// Ligne « libellé ……… valeur ».
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.bold = false, this.valueColor, this.sub});

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3)))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
                if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 20 : 15,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte de chiffre clé.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub, this.valueColor, this.highlight = false});

  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? AppColors.yellowSoft : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: valueColor ?? AppColors.text)),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Message rapide en bas de l'écran.
void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.redText : AppColors.text,
      duration: const Duration(seconds: 3),
    ));
}

/// Demande une confirmation oui / non.
Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Demande un texte (motif, nom…).
Future<String?> askText(BuildContext context, String title, {String hint = '', String initial = '', String ok = 'Valider'}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: FieldBox(controller: ctrl, hint: hint, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v.trim())),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Retour')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(ok)),
      ],
    ),
  );
}
