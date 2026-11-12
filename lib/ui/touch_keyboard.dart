import 'package:flutter/material.dart';

import '../data/settings.dart';
import 'theme.dart';

/// Clavier intégré à l'appli, pour les caisses à écran tactile sans clavier.
///
/// Quand il est activé (Réglages › Écran et démarrage), les champs ne demandent plus rien à Windows :
/// le clavier tactile de Windows ne s'ouvre donc jamais tout seul. Toucher un champ ouvre ce clavier
/// en bas de l'écran ; il se ferme en touchant ailleurs, avec OK, ou en changeant de page.
class TouchKeyboard {
  static final target = ValueNotifier<KeyTarget?>(null);

  /// Lu à chaque construction de champ (réglage enregistré dans la base).
  static bool get enabled {
    try {
      return Settings.flag('touch_keyboard');
    } catch (_) {
      return false; // base pas encore ouverte
    }
  }

  static set enabled(bool v) => Settings.setFlag('touch_keyboard', v);

  static void open(
    TextEditingController controller, {
    bool numeric = false,
    bool decimal = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    BuildContext? field,
  }) {
    target.value =
        KeyTarget(controller, numeric: numeric, decimal: decimal, onChanged: onChanged, onSubmitted: onSubmitted);
    // Le clavier prend le bas de l'écran : on fait défiler pour garder le champ visible.
    if (field != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (field.mounted) {
            Scrollable.ensureVisible(field, alignment: 0.4, duration: const Duration(milliseconds: 200));
          }
        });
      });
    }
  }

  static void close() {
    if (target.value != null) target.value = null;
  }
}

class KeyTarget {
  KeyTarget(this.controller, {required this.numeric, this.decimal = false, this.onChanged, this.onSubmitted});
  final TextEditingController controller;
  final bool numeric;
  final bool decimal;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  void _set(String text) {
    controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    onChanged?.call(text);
  }

  void type(String s) => _set(controller.text + s);

  void backspace() {
    final t = controller.text;
    if (t.isNotEmpty) _set(t.characters.skipLast(1).toString());
  }

  void clear() => _set('');
}

/// Place le clavier sous le contenu de l'appli (les fenêtres remontent au-dessus).
class TouchKeyboardHost extends StatelessWidget {
  const TouchKeyboardHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<KeyTarget?>(
      valueListenable: TouchKeyboard.target,
      builder: (context, t, _) => Column(
        children: [
          Expanded(child: child),
          if (t != null) _Panel(key: ValueKey(t), target: t),
        ],
      ),
    );
  }
}

class _Panel extends StatefulWidget {
  const _Panel({super.key, required this.target});
  final KeyTarget target;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  bool _shift = true; // majuscule pour la première lettre
  bool _digits = false;

  KeyTarget get t => widget.target;

  void _letter(String s) {
    t.type(_shift ? s.toUpperCase() : s);
    if (_shift) setState(() => _shift = false);
  }

  void _ok() {
    final submit = t.onSubmitted;
    TouchKeyboard.close();
    submit?.call(t.controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final rows = t.numeric
        ? <List<Widget>>[
            [_k('1'), _k('2'), _k('3')],
            [_k('4'), _k('5'), _k('6')],
            [_k('7'), _k('8'), _k('9')],
            [t.decimal ? _k(',') : _k('00'), _k('0'), _back()],
          ]
        : _digits
            ? <List<Widget>>[
                [for (final c in '1234567890'.split('')) _k(c)],
                [for (final c in '-/:;()&@"'.split('')) _k(c)],
                [_k('.'), _k(','), _k('?'), _k('!'), _k("'"), _k('+'), _k('%'), _back(flex: 2)],
                [_mode('ABC'), _space(), _okKey()],
              ]
            : <List<Widget>>[
                [for (final c in 'azertyuiop'.split('')) _l(c)],
                [for (final c in 'qsdfghjklm'.split('')) _l(c)],
                [_shiftKey(), for (final c in 'wxcvbn'.split('')) _l(c), _l('é'), _l('è'), _back()],
                [_mode('123'), _l('à'), _l('ç'), _space(), _k('.'), _k(','), _okKey()],
              ];
    return Material(
      color: const Color(0xFFD1D3D9),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: t.numeric ? 420 : 980),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.controller.text.isEmpty ? ' ' : t.controller.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(onPressed: () => setState(t.clear), child: const Text('Effacer')),
                      if (t.numeric) ...[
                        const SizedBox(width: 6),
                        SizedBox(width: 120, child: Row(children: [_okKey()])),
                      ],
                      IconButton(
                        tooltip: 'Fermer le clavier',
                        onPressed: TouchKeyboard.close,
                        icon: const Icon(Icons.keyboard_hide_outlined),
                      ),
                    ],
                  ),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: r),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _key({required Widget child, required VoidCallback onTap, int flex = 1, Color? color}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: color ?? Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                onTap();
                setState(() {});
              },
              child: SizedBox(height: 54, child: Center(child: child)),
            ),
          ),
        ),
      );

  Widget _k(String s) =>
      _key(child: Text(s, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)), onTap: () => t.type(s));

  Widget _l(String s) => _key(
        child: Text(_shift ? s.toUpperCase() : s, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        onTap: () => _letter(s),
      );

  Widget _back({int flex = 1}) => _key(
        flex: flex,
        color: const Color(0xFFADB1BA),
        child: const Icon(Icons.backspace_outlined),
        onTap: t.backspace,
      );

  Widget _shiftKey() => _key(
        color: _shift ? Colors.white : const Color(0xFFADB1BA),
        child: Icon(_shift ? Icons.keyboard_capslock : Icons.arrow_upward),
        onTap: () => _shift = !_shift,
      );

  Widget _mode(String label) => _key(
        flex: 2,
        color: const Color(0xFFADB1BA),
        child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        onTap: () => _digits = !_digits,
      );

  Widget _space() => _key(flex: 5, child: const Text('espace'), onTap: () => t.type(' '));

  Widget _okKey() => _key(
        flex: 2,
        color: AppColors.yellow,
        child: const Text('OK', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        onTap: _ok,
      );
}
