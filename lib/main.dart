import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/backup.dart';
import 'data/db.dart';
import 'data/models.dart';
import 'data/settings.dart';
import 'hardware/hardware_config.dart';
import 'hardware/hardware_service.dart';
import 'screens/attendance_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/closing_screen.dart';
import 'screens/day_dialogs.dart';
import 'screens/login_screen.dart';
import 'screens/menu_admin_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/purchasing_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/goal_screen.dart';
import 'state/session.dart';
import 'system/windows_shell.dart';
import 'ui/theme.dart';
import 'ui/touch_keyboard.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackupService.loadConfig();
  HardwareService.I = HardwareService(await HardwareConfig.load());
  try {
    await AppDb.open();
  } catch (e) {
    // Base illisible (disque abîmé, fichier supprimé à moitié…) : on propose de charger une sauvegarde.
    runApp(RecoveryApp(error: '$e'));
    return;
  }
  Session.closeLeftoverSession();
  // F11 : plein écran / fenêtre (gérant du matériel seulement). Écouteur global : il ne prend pas
  // le focus clavier, la saisie du code PIN au clavier reste possible.
  HardwareKeyboard.instance.addHandler((e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.f11 && Session.I.can(Perm.materiel)) {
      WindowsShell.setFullscreen(!WindowsShell.isFullscreen);
      return true;
    }
    return false;
  });
  runApp(const ChickenStationApp());
  WindowsShell.applyFullscreenAtStartup(Settings.fullscreen);
  if (BackupService.dueAtStartup) BackupService.auto('démarrage');
}

/// Ferme proprement l'appli (bouton « Quitter l'appli », réservé à l'administrateur).
Future<void> quitApp() async {
  try {
    AppDb.I.audit(Session.I.user?.id, 'arret', "Appli fermée par ${Session.I.user?.name ?? '?'}");
    AppDb.I.close();
  } catch (_) {}
  exit(0);
}

/// Écran de secours quand la base ne s'ouvre pas.
class RecoveryApp extends StatefulWidget {
  const RecoveryApp({super.key, required this.error});
  final String error;

  @override
  State<RecoveryApp> createState() => _RecoveryAppState();
}

class _RecoveryAppState extends State<RecoveryApp> {
  bool _restored = false;

  @override
  Widget build(BuildContext context) {
    if (_restored) return const ChickenStationApp();
    return MaterialApp(
      title: 'Chicken Station',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: IosCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(width: 200),
                    const SizedBox(height: 20),
                    const Text('Les données ne peuvent pas être ouvertes',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                      "Chargez votre dernière sauvegarde pour retrouver l'appli comme elle était. "
                      "Le fichier abîmé est gardé de côté, rien n'est effacé.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: 'Choisir une sauvegarde…',
                      onPressed: () async {
                        final path = await pickBackupFile();
                        if (path == null || !context.mounted) return;
                        if (await restoreFlow(context, path)) setState(() => _restored = true);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Détail technique : ${widget.error}',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    const Text('Developed by Minerva  ·  +213 782 05 51 93  ·  koceilaidir92@gmail.com',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChickenStationApp extends StatelessWidget {
  const ChickenStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chicken Station',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Écran tactile : le clavier Windows ne doit s'ouvrir que quand on touche un champ.
      navigatorObservers: [_NoKeyboardAfterDialog()],
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _hideKeyboard,
        child: TouchKeyboardHost(child: child ?? const SizedBox.shrink()),
      ),
      home: ListenableBuilder(
        listenable: Session.I,
        builder: (context, _) => Session.I.loggedIn ? const AppShell() : const LoginScreen(),
      ),
    );
  }
}

/// Enlève le curseur du champ en cours : le clavier tactile de Windows se referme.
void _hideKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
  TouchKeyboard.close();
}

/// À la fermeture d'une fenêtre, Flutter remet le curseur dans le champ touché avant :
/// sur écran tactile, ça rouvrait le clavier. On l'enlève.
class _NoKeyboardAfterDialog extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _hideKeyboard());
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.perms, this.builder);
  final String label;
  final IconData icon;

  /// L'utilisateur voit l'écran s'il a au moins un de ces droits.
  final List<String> perms;
  final Widget Function() builder;
}

final _items = <_NavItem>[
  _NavItem('Caisse', Icons.point_of_sale_outlined, [Perm.vendre], () => const PosScreen()),
  _NavItem('Caisse du jour', Icons.check_circle_outline, [Perm.cloture, Perm.recette, Perm.depense], () => const ClosingScreen()),
  _NavItem('Compta', Icons.bar_chart_outlined, [Perm.coffre], () => const ComptaScreen()),
  _NavItem('Dépenses', Icons.receipt_long_outlined, DepensesScreen.perms, () => const DepensesScreen()),
  _NavItem('Pointage', Icons.how_to_reg_outlined, AttendanceScreen.perms, () => const AttendanceScreen()),
  _NavItem('Menu', Icons.restaurant_menu, [Perm.menu], () => const MenuAdminScreen()),
  _NavItem('Réglages', Icons.settings_outlined, SettingsScreen.perms, () => const SettingsScreen()),
];

/// Coque de l'application : menu à gauche, écran courant, pied de page Minerva centré en bas.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;
  final ValueNotifier<String?> _displayText = ValueNotifier(null);
  final ValueNotifier<List<SimulatedOutput>> _simTickets = ValueNotifier(const []);

  List<_NavItem> get _visible => _items.where((i) => i.perms.any(Session.I.can)).toList();

  @override
  void initState() {
    super.initState();
    HardwareService.I.onSimulated = _onSimulated;
    _resetIdle();
    // Rappel à l'administrateur si les données ne sont pas protégées.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (Session.I.can(Perm.sauvegarde)) {
        final w = BackupService.healthWarning();
        if (w != null) toast(context, w, error: true);
      }
      // Rappel : ouvrir la caisse avant de travailler.
      await remindOpenDay(context);
      // Nouveau mois : la paie du mois dernier est-elle réglée ?
      if (mounted) await remindUnpaidPayroll(context);
      if (mounted) setState(() {});
    });
  }

  Timer? _idle;

  /// Verrouillage automatique : retour à l'écran des codes PIN après X minutes sans activité.
  void _resetIdle() {
    _idle?.cancel();
    final minutes = Settings.idleLockMinutes;
    if (minutes <= 0) return;
    _idle = Timer(Duration(minutes: minutes), () => Session.I.lockForInactivity(minutes));
  }

  @override
  void dispose() {
    _idle?.cancel();
    HardwareService.I.onSimulated = null;
    _displayText.dispose();
    _simTickets.dispose();
    super.dispose();
  }

  void _onSimulated(SimulatedOutput out) {
    if (!mounted) return;
    switch (out.device) {
      case 'ecran':
        _displayText.value = out.text;
      case 'tiroir':
        toast(context, 'Simulation : le tiroir-caisse s\'ouvre');
      default:
        // Aperçu du ticket : 2 au plus, et chacun disparaît seul après 8 s pour ne pas cacher l'écran.
        final list = [out, ..._simTickets.value];
        _simTickets.value = list.take(2).toList();
        Timer(const Duration(seconds: 8), () {
          if (mounted) _simTickets.value = _simTickets.value.where((t) => !identical(t, out)).toList();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    if (_selected >= items.length) _selected = 0;
    return Listener(
      onPointerDown: (_) => _resetIdle(),
      child: Scaffold(
      body: Row(
        children: [
          _Sidebar(items: items, selected: _selected, onSelect: (i) {
            _hideKeyboard();
            setState(() => _selected = i);
          }),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.separator),
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: items.isEmpty
                          ? const Center(child: Text('Aucun écran autorisé pour cet utilisateur.'))
                          : KeyedSubtree(key: ValueKey(items[_selected].label), child: items[_selected].builder()),
                    ),
                    const _Footer(),
                  ],
                ),
                if (HardwareService.I.simulate) _SimulationOverlay(display: _displayText, tickets: _simTickets),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        'Developed by Minerva  ·  +213 782 05 51 93  ·  koceilaidir92@gmail.com',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.selected, required this.onSelect});

  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final user = Session.I.user;
    return Container(
      width: 92,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          const AppBadge(size: 54),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, i) {
                final item = items[i];
                final active = i == selected;
                final color = active ? AppColors.text : AppColors.textSecondary;
                return Center(
                  child: Material(
                    color: active ? AppColors.yellowSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelect(i),
                      child: SizedBox(
                        width: 76,
                        height: 60,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.icon, size: 22, color: color),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, height: 1.1, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: color),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (user != null)
            Tooltip(
              message: 'Déconnecter ${user.name}',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _logoutDialog(context, user),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: user.role == 'admin' ? AppColors.text : const Color(0xFFE9E9EE),
                      child: Text(user.initials,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: user.role == 'admin' ? AppColors.yellow : const Color(0xFF3A3A3C))),
                    ),
                    const SizedBox(height: 3),
                    const Text('Quitter', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _logoutDialog(BuildContext context, AppUser user) async {
  final admin = user.role == 'admin';
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(user.name),
      content: Text(admin
          ? 'Se déconnecter (retour aux codes PIN), ou fermer complètement l\'appli ?'
          : 'Se déconnecter et revenir à l\'écran des codes PIN ?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
        if (admin)
          TextButton(
            onPressed: () => Navigator.pop(c, 'quit'),
            child: const Text("Quitter l'appli", style: TextStyle(color: AppColors.redText)),
          ),
        FilledButton(onPressed: () => Navigator.pop(c, 'logout'), child: const Text('Se déconnecter')),
      ],
    ),
  );
  if (r == 'logout') Session.I.logout();
  if (r == 'quit') await quitApp();
}

/// Aperçu du mode simulation : écran client (en haut à droite) et tickets imprimés (en bas à droite).
class _SimulationOverlay extends StatelessWidget {
  const _SimulationOverlay({required this.display, required this.tickets});

  final ValueNotifier<String?> display;
  final ValueNotifier<List<SimulatedOutput>> tickets;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            Positioned(
              right: 360,
              top: 10,
              child: ValueListenableBuilder<String?>(
                valueListenable: display,
                builder: (c, v, _) => v == null
                    ? const SizedBox.shrink()
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFF040806), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'Écran client  ${v.isEmpty ? '—' : v}',
                          style: const TextStyle(fontFamily: 'Consolas', fontSize: 15, color: Color(0xFF34E5A0)),
                        ),
                      ),
              ),
            ),
            Positioned(
              right: 360,
              bottom: 30,
              child: ValueListenableBuilder<List<SimulatedOutput>>(
                valueListenable: tickets,
                builder: (c, list, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final t in list.reversed)
                      Container(
                        width: 340,
                        margin: const EdgeInsets.only(left: 10),
                        constraints: const BoxConstraints(maxHeight: 380),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                              decoration: const BoxDecoration(
                                color: AppColors.yellowSoft,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    t.device == 'cuisine' ? 'Simulation · imprimante cuisine' : 'Simulation · imprimante ticket',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => tickets.value = tickets.value.where((x) => x != t).toList(),
                                  ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(10),
                                // Une ligne du ticket = une ligne ici (48 caractères), comme sur le papier.
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    t.text,
                                    softWrap: false,
                                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 10.5, height: 1.25),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
