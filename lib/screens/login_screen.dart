import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/repos.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'backup_screen.dart';

/// Écran de connexion : choix du profil puis code PIN à 4 chiffres.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<AppUser> _users = [];
  AppUser? _selected;
  String _pin = '';
  bool _error = false;
  int _tries = 0;
  DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _users = UserRepo.all(onlyActive: true);
    if (_users.isNotEmpty) _selected = _users.first;
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => _now = DateTime.now()));
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _clock?.cancel();
    super.dispose();
  }

  void _press(String k) {
    final u = _selected;
    if (u == null) return;
    if (k == 'del') {
      setState(() {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        _error = false;
      });
      return;
    }
    if (_pin.length >= 4) return;
    setState(() {
      _pin += k;
      _error = false;
    });
    if (_pin.length == 4) {
      if (UserRepo.checkPin(u, _pin)) {
        _tries = 0;
        Session.I.login(u);
      } else {
        _tries++;
        AppDb.I.audit(u.id, 'pin_incorrect', 'Essai raté n°$_tries');
        setState(() => _error = true);
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _pin = '');
        });
      }
    }
  }

  /// Sur un PC neuf (aucune vente) : charger directement une sauvegarde.
  Future<void> _restoreFromLogin() async {
    final path = await pickBackupFile();
    if (path == null || !mounted) return;
    if (await restoreFlow(context, path) && mounted) {
      setState(() {
        _users = UserRepo.all(onlyActive: true);
        _selected = _users.isEmpty ? null : _users.first;
        _pin = '';
      });
    }
  }

  /// Clavier physique : chiffres et retour arrière, quel que soit l'élément qui a le focus
  /// (sauf quand une fenêtre est ouverte par-dessus, ex. restauration de sauvegarde).
  bool _onHardwareKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _press('del');
      return true;
    }
    final c = e.character;
    if (c != null && RegExp(r'^[0-9]$').hasMatch(c)) {
      _press(c);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Row(
          children: [
            Container(
              width: 420,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(40, 40, 40, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(width: 230),
                  const SizedBox(height: 24),
                  Text(fmtTime(_now),
                      style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w700, letterSpacing: -2, height: 1)),
                  Text(fmtLongDate(_now), style: const TextStyle(fontSize: 17, color: AppColors.textSecondary)),
                  const SizedBox(height: 24),
                  const Text('Choisissez votre profil', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (c, i) {
                        final u = _users[i];
                        final sel = u.id == _selected?.id;
                        final admin = u.role == 'admin';
                        return Material(
                          color: sel ? AppColors.yellowSoft : const Color(0xFFF7F7F9),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(() {
                              _selected = u;
                              _pin = '';
                              _error = false;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 21,
                                    backgroundColor: admin ? AppColors.text : const Color(0xFFE9E9EE),
                                    child: Text(u.initials,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: admin ? AppColors.yellow : const Color(0xFF3A3A3C))),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(u.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                        Text(Perm.roleLabels[u.role] ?? u.role,
                                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Developed by Minerva',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3A3A3C))),
                  const Text('+213 782 05 51 93 · koceilaidir92@gmail.com',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const VerticalDivider(width: 1, color: AppColors.separator),
            Expanded(child: Center(child: _pinPad())),
          ],
        ),
      ),
    );
  }

  Widget _pinPad() {
    final u = _selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(u == null ? 'Aucun utilisateur' : 'Code PIN · ${u.name}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          _error
              ? 'Code incorrect${_tries >= 3 ? ' · plusieurs essais ratés, enregistrés' : ''}'
              : 'Tapez vos 4 chiffres',
          style: TextStyle(
            fontSize: 14,
            color: _error ? AppColors.redText : AppColors.textSecondary,
            fontWeight: _error ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 9),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _error ? AppColors.red : (i < _pin.length ? AppColors.text : Colors.transparent),
                  border: Border.all(color: _error || i < _pin.length ? Colors.transparent : const Color(0xFFC7C7CC), width: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 30),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'del'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final k in row) _key(k)],
            ),
          ),
        if (_users.length == 1 && u != null && u.role == 'admin')
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Première installation : code administrateur 1234 (à changer dans Réglages › Utilisateurs)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        if (AppDb.isOpen && AppDb.I.isFresh)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Nouvelle installation ? Charger une sauvegarde'),
              onPressed: _restoreFromLogin,
            ),
          ),
      ],
    );
  }

  Widget _key(String k) {
    if (k.isEmpty) return const SizedBox(width: 78 + 26, height: 78);
    final del = k == 'del';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Material(
        color: del ? Colors.transparent : Colors.white,
        shape: const CircleBorder(),
        elevation: del ? 0 : 0.5,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _press(k),
          child: SizedBox(
            width: 78,
            height: 78,
            child: Center(
              child: del
                  ? const Icon(Icons.backspace_outlined, size: 26)
                  : Text(k, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
    );
  }
}
