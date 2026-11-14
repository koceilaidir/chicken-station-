import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/repos.dart';
import '../data/settings.dart';
import '../hardware/hardware_service.dart';
import '../hardware/tickets.dart';
import '../state/session.dart';
import '../system/windows_shell.dart';
import '../ui/theme.dart';
import '../ui/touch_keyboard.dart';
import '../ui/widgets.dart';
import 'activity_screen.dart';
import 'backup_screen.dart';
import 'hardware_screen.dart';
import 'users_screen.dart';

class _Section {
  const _Section(this.label, this.icon, this.perm, this.builder, {this.adminOnly = false});
  final String label;
  final IconData icon;
  final String perm;
  final Widget Function() builder;

  /// Réservé à l'administrateur (un autre compte ne pourrait que consulter : inutile de l'afficher).
  final bool adminOnly;

  bool visibleFor() => adminOnly ? Session.I.user?.role == 'admin' : Session.I.can(perm);
}

/// Réglages : utilisateurs, activité, sauvegarde, matériel, impressions, écran — une seule entrée dans le menu.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Le menu « Réglages » apparaît si l'utilisateur a au moins un de ces droits
  /// (la gestion des utilisateurs, elle, n'apparaît que pour l'administrateur).
  static const perms = [Perm.activite, Perm.sauvegarde, Perm.materiel];

  static bool visibleFor() => Session.I.user?.role == 'admin' || perms.any(Session.I.can);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final _sections = <_Section>[
    _Section('Utilisateurs', Icons.people_outline, Perm.users, () => const UsersScreen(), adminOnly: true),
    _Section('Activité', Icons.history, Perm.activite, () => const ActivityScreen()),
    _Section('Sauvegarde', Icons.cloud_upload_outlined, Perm.sauvegarde, () => const BackupScreen()),
    _Section('Matériel', Icons.print_outlined, Perm.materiel, () => const HardwareScreen()),
    _Section('Impressions', Icons.receipt_outlined, Perm.materiel, () => const PrintSettingsScreen()),
    _Section('Écran et démarrage', Icons.desktop_windows_outlined, Perm.materiel, () => const DisplaySettingsScreen()),
    _Section('Remise à zéro', Icons.restart_alt, Perm.sauvegarde, () => const ResetScreen(), adminOnly: true),
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final visible = _sections.where((s) => s.visibleFor()).toList();
    if (visible.isEmpty) return const Center(child: Text('Aucun réglage autorisé.'));
    if (_index >= visible.length) _index = 0;
    final current = visible[_index];
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 1000;
        final page = KeyedSubtree(key: ValueKey(current.label), child: current.builder());
        if (narrow) {
          // Petit écran : sous-menu en haut, sur une ligne qui défile.
          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ChoiceChip(
                    avatar: Icon(visible[i].icon, size: 18),
                    label: Text(visible[i].label),
                    selected: i == _index,
                    onSelected: (_) => setState(() => _index = i),
                  ),
                ),
              ),
              Expanded(child: page),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 230,
              margin: const EdgeInsets.fromLTRB(20, 20, 0, 16),
              child: IosCard(
                padding: const EdgeInsets.all(8),
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(10, 6, 10, 10),
                      child: Text('Réglages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    ),
                    for (var i = 0; i < visible.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: i == _index ? AppColors.yellowSoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            leading: Icon(visible[i].icon, size: 20, color: AppColors.text),
                            title: Text(visible[i].label,
                                style: TextStyle(fontSize: 15, fontWeight: i == _index ? FontWeight.w700 : FontWeight.w500)),
                            onTap: () => setState(() => _index = i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: page),
          ],
        );
      },
    );
  }
}

// ============================================================================ impressions

/// Réglages › Impressions : en-tête et mentions légales du ticket, exemplaires du rapport Z.
class PrintSettingsScreen extends StatefulWidget {
  const PrintSettingsScreen({super.key});

  @override
  State<PrintSettingsScreen> createState() => _PrintSettingsScreenState();
}

class _PrintSettingsScreenState extends State<PrintSettingsScreen> {
  final Map<String, TextEditingController> _ctrl = {
    for (final f in TicketField.all) f.key: TextEditingController(text: f.value),
  };
  bool _dirty = false;

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    for (final f in TicketField.all) {
      f.value = _ctrl[f.key]!.text.trim();
    }
    logActivity('reglages', 'Champs du ticket modifiés');
    setState(() => _dirty = false);
    toast(context, 'Ticket enregistré.');
  }

  Future<void> _testPrint() async {
    if (_dirty) _save();
    try {
      await HardwareService.I.printTicket(Tickets.sample());
      if (mounted) toast(context, 'Ticket d\'essai envoyé.');
    } catch (e) {
      if (mounted) toast(context, 'Impression impossible : $e', error: true);
    }
  }

  Widget _field(TicketField f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: 170, child: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: FieldBox(
              controller: _ctrl[f.key]!,
              hint: f.hint.isEmpty ? 'Laisser vide pour ne pas imprimer' : f.hint,
              onChanged: (_) => setState(() => _dirty = true),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copies = Settings.zCopies;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          overline: 'Réglages',
          title: 'Impressions',
          subtitle: 'Ce qui est imprimé sur le ticket client. Un champ vide n\'est pas imprimé.',
          actions: [
            SecondaryButton(label: 'Imprimer un essai', onPressed: _testPrint),
            PrimaryButton(label: 'Enregistrer', onPressed: _dirty ? _save : null),
          ],
        ),
        const SizedBox(height: 16),
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('En-tête du ticket'),
              const SizedBox(height: 10),
              for (final f in TicketField.header) _field(f),
              const SizedBox(height: 6),
              const SectionLabel('Mentions légales (bas du ticket)'),
              const SizedBox(height: 10),
              for (final f in TicketField.legal) _field(f),
              const SizedBox(height: 6),
              const SectionLabel('Message de fin'),
              const SizedBox(height: 10),
              _field(TicketField.thanks),
            ],
          ),
        ),
        const SizedBox(height: 16),
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Rapport de clôture (Z)'),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text("Nombre d'exemplaires imprimés à la clôture",
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IosSegmented<int>(
                    expand: false,
                    values: const [0, 1, 2],
                    selected: copies < 0 ? 0 : (copies > 2 ? 2 : copies),
                    label: (n) => n == 0 ? 'Aucun' : '$n',
                    onChanged: (n) {
                      setState(() => Settings.zCopies = n);
                      logActivity('reglages', 'Rapport Z : $n exemplaire(s)');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'À tout moment de la journée, la page Clôture permet d\'imprimer la recette, les dépenses, ou les deux.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================ écran et démarrage

/// Réglages › Écran et démarrage : plein écran, lancement avec Windows, verrouillage automatique.
class DisplaySettingsScreen extends StatefulWidget {
  const DisplaySettingsScreen({super.key});

  @override
  State<DisplaySettingsScreen> createState() => _DisplaySettingsScreenState();
}

class _DisplaySettingsScreenState extends State<DisplaySettingsScreen> {
  bool? _autostart;

  @override
  void initState() {
    super.initState();
    WindowsShell.autostartEnabled().then((v) {
      if (mounted) setState(() => _autostart = v);
    }).catchError((Object _) {
      if (mounted) setState(() => _autostart = false);
    });
  }

  Future<void> _setAutostart(bool v) async {
    try {
      await WindowsShell.setAutostart(v);
      logActivity('reglages', v ? 'Lancement avec Windows activé' : 'Lancement avec Windows désactivé');
      if (mounted) setState(() => _autostart = v);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  void _setFullscreen(bool v) {
    Settings.fullscreen = v;
    WindowsShell.setFullscreen(v);
    logActivity('reglages', v ? 'Plein écran activé' : 'Plein écran désactivé');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final idle = Settings.idleLockMinutes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        const PageHeader(overline: 'Réglages', title: 'Écran et démarrage'),
        const SizedBox(height: 16),
        IosCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: Settings.fullscreen,
                activeTrackColor: AppColors.green,
                onChanged: _setFullscreen,
                title: const Text('Plein écran', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    "L'appli occupe tout l'écran et cache la barre des tâches Windows. "
                    'Touche F11 pour basculer (réservée au gérant du matériel).'),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: TouchKeyboard.enabled,
                activeTrackColor: AppColors.green,
                onChanged: (v) {
                  TouchKeyboard.enabled = v;
                  TouchKeyboard.close();
                  logActivity('reglages', v ? 'Clavier intégré activé' : 'Clavier intégré désactivé');
                  setState(() {});
                },
                title: const Text('Clavier intégré (écran tactile)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    "Pour une caisse sans clavier : toucher un champ ouvre le clavier de l'appli en bas de l'écran, "
                    "et le clavier de Windows ne s'ouvre plus tout seul. À laisser désactivé sur un PC avec clavier."),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: Settings.tpe,
                activeTrackColor: AppColors.green,
                onChanged: (v) {
                  Settings.tpe = v;
                  logActivity('reglages', v ? 'Paiement par TPE activé' : 'Paiement par TPE désactivé');
                  setState(() {});
                },
                title: const Text('Paiement par carte (TPE)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Affiche le bouton TPE en caisse. À activer seulement si la boutique a un terminal de paiement.'),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autostart ?? false,
                activeTrackColor: AppColors.green,
                onChanged: _autostart == null ? null : _setAutostart,
                title: const Text('Lancer avec Windows', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  "L'appli s'ouvre toute seule quand le PC démarre, sur l'écran des codes PIN.\n"
                  'Programme lancé : ${WindowsShell.executable}',
                ),
              ),
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verrouillage automatique', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text("Retour à l'écran des codes PIN si personne ne touche l'écran.",
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  IosSegmented<int>(
                    expand: false,
                    values: const [0, 2, 5, 15],
                    selected: const [0, 2, 5, 15].contains(idle) ? idle : 0,
                    label: (m) => m == 0 ? 'Jamais' : '$m min',
                    onChanged: (m) {
                      setState(() => Settings.idleLockMinutes = m);
                      logActivity('reglages', m == 0 ? 'Verrouillage automatique désactivé' : 'Verrouillage après $m min');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "À chaque démarrage, l'appli s'ouvre toujours sur l'écran des codes PIN : si quelqu'un était resté connecté "
          '(PC éteint, coupure de courant), sa session est fermée et c\'est noté dans le journal d\'activité.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}


/// Remise à zéro (administrateur) : efface les essais pour démarrer pour de vrai, garde le menu.
class ResetScreen extends StatefulWidget {
  const ResetScreen({super.key});

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  bool _busy = false;

  Future<void> _reset() async {
    if (Session.I.user?.role != 'admin') return;
    if (!BackupService.hasFolder) {
      toast(context, "Choisissez d'abord un dossier dans Réglages › Sauvegarde : une sauvegarde est faite avant d'effacer.", error: true);
      return;
    }
    final word = await askText(
      context,
      'Tout remettre à zéro ?',
      hint: 'Tapez EFFACER pour confirmer',
      ok: 'Remettre à zéro',
    );
    if (word == null || !mounted) return;
    if (word.trim().toUpperCase() != 'EFFACER') {
      toast(context, 'Rien n\'a été effacé (il fallait taper EFFACER).', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await BackupService.backupNow(reason: 'avant remise à zéro');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Sauvegarde impossible, rien n\'a été effacé : $e', error: true);
      }
      return;
    }
    try {
      final u = Session.I.user!;
      AppDb.I.resetAllButMenu(u.id, u.name);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Remise à zéro impossible : $e', error: true);
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Appli remise à zéro'),
        content: const Text(
          "Les essais sont effacés (une sauvegarde a été faite juste avant).\n\n"
          "Pour démarrer : Compta › Coffre, tapez ce qu'il y a dans le coffre, puis ouvrez la journée "
          "dans Clôture avec le fond de caisse.",
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Se reconnecter'))],
      ),
    );
    Session.I.logout();
  }

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        const PageHeader(title: 'Remise à zéro', subtitle: 'Réservé à l\'administrateur'),
        const SizedBox(height: 16),
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Démarrer pour de vrai'),
              const SizedBox(height: 6),
              const Text(
                "Après les essais et la formation, effacez tout ce qui a été tapé pour commencer avec des comptes propres.",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              const Text('Effacé', style: TextStyle(fontWeight: FontWeight.w700)),
              line(Icons.close, 'Ventes, tickets, journées et clôtures', AppColors.redText),
              line(Icons.close, 'Dépenses, coffre et écarts de caisse', AppColors.redText),
              line(Icons.close, "Fournisseurs, bons d'achat et paiements", AppColors.redText),
              line(Icons.close, 'Employés, salaires et acomptes', AppColors.redText),
              line(Icons.close, "Journal d'activité", AppColors.redText),
              const SizedBox(height: 10),
              const Text('Gardé', style: TextStyle(fontWeight: FontWeight.w700)),
              line(Icons.check, 'Le menu : familles, produits, prix et photos', AppColors.greenText),
              line(Icons.check, 'Les utilisateurs et leurs codes PIN', AppColors.greenText),
              line(Icons.check, 'Imprimantes, tiroir, ticket et réglages', AppColors.greenText),
              line(Icons.check, "La liste des articles d'achat et les titres de charges", AppColors.greenText),
              const SizedBox(height: 12),
              const Text(
                "Une sauvegarde est faite juste avant : en cas d'erreur, on peut revenir en arrière depuis Sauvegarde.",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.redText),
                  onPressed: _busy ? null : _reset,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.restart_alt),
                  label: const Text('Tout remettre à zéro (sauf le menu)'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
