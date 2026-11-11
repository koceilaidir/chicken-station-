import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Choisit un fichier .csbak sur le PC (clé USB, autre dossier…).
Future<String?> pickBackupFile() async {
  const group = XTypeGroup(label: 'Sauvegardes Chicken Station', extensions: <String>[backupExtension]);
  final f = await openFile(
    acceptedTypeGroups: const <XTypeGroup>[group],
    initialDirectory: BackupService.folderReachable ? BackupService.config.folder : null,
  );
  return f?.path;
}

/// Parcours complet : lecture et vérification du fichier, aperçu, confirmation, restauration.
/// Renvoie true si les données ont été remplacées.
Future<bool> restoreFlow(BuildContext context, String path) async {
  // 1. Lecture (déchiffrement + vérification du sceau).
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _BusyDialog('Lecture et vérification de la sauvegarde…'),
  );
  OpenedBackup? opened;
  String? error;
  try {
    opened = await BackupService.inspect(path);
  } catch (e) {
    error = '$e';
  }
  if (!context.mounted) return false;
  Navigator.of(context, rootNavigator: true).pop();
  if (opened == null) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sauvegarde refusée'),
        content: Text(error ?? 'Fichier illisible.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
    return false;
  }

  // 2. Aperçu et confirmation.
  final b = opened;
  var withHardware = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.verified_outlined, color: AppColors.greenText),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Fichier authentique et complet.',
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.greenText)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              KeyValueRow('Faite le', fmtLongDate(b.meta.createdAt), sub: 'à ${fmtTime(b.meta.createdAt)}'),
              if (b.meta.reason.isNotEmpty) KeyValueRow('Occasion', b.meta.reason),
              if (b.meta.userName.isNotEmpty) KeyValueRow('Par', b.meta.userName),
              KeyValueRow('Journées', fmtNum(b.meta.counts['journees'] ?? 0)),
              KeyValueRow('Ventes', fmtNum(b.meta.counts['ventes'] ?? 0)),
              KeyValueRow('Produits · utilisateurs',
                  '${b.meta.counts['produits'] ?? 0} · ${b.meta.counts['utilisateurs'] ?? 0}'),
              KeyValueRow('Photos', fmtNum(b.photoCount)),
              if (b.hasHardware)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: withHardware,
                  onChanged: (v) => setD(() => withHardware = v ?? false),
                  title: const Text('Restaurer aussi les réglages du matériel'),
                  subtitle: const Text('Imprimantes, afficheur, mode simulation. À cocher sur le PC de la boutique.'),
                ),
              const SizedBox(height: 8),
              const Text(
                "Toutes les données actuelles seront remplacées par celles de la sauvegarde. "
                "L'état actuel est d'abord sauvegardé à part, pour pouvoir revenir en arrière.",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.redText),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;

  // 3. Restauration.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _BusyDialog('Restauration en cours… ne fermez pas l\'appli.'),
  );
  String? failure;
  try {
    await BackupService.restore(b, hardware: withHardware, restoredBy: Session.I.user?.name ?? '');
  } catch (e) {
    failure = '$e';
  }
  if (!context.mounted) return failure == null;
  Navigator.of(context, rootNavigator: true).pop();
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(failure == null ? 'Restauration terminée' : 'Restauration impossible'),
      content: Text(failure == null
          ? "L'appli est revenue à l'état du ${fmtDateTime(b.meta.createdAt)}.\nReconnectez-vous avec votre code PIN de cette date."
          : failure),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
  return failure == null;
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 18),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Réglages › Sauvegarde : dossier, sauvegarde manuelle et automatique, restauration.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  BackupConfig get _cfg => BackupService.config;

  Future<void> _chooseFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Choisir ce dossier',
      initialDirectory: BackupService.folderReachable ? _cfg.folder : null,
    );
    if (path == null) return;
    _cfg.folder = path;
    await BackupService.saveConfig();
    if (!mounted) return;
    setState(() {});
    if (BackupService.list().isEmpty) {
      await _backupNow();
    } else {
      toast(context, 'Dossier choisi. ${BackupService.list().length} sauvegarde(s) trouvée(s) dedans.');
    }
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    try {
      final f = await BackupService.backupNow(reason: 'manuelle');
      if (mounted) toast(context, 'Sauvegarde faite : ${f.path.split(RegExp(r'[\\/]')).last}');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Restaurer écrase toutes les données : réservé aux administrateurs.
  bool get _canRestore => Session.I.user?.role == 'admin';

  Future<void> _restore(String path) async {
    if (!_canRestore) {
      toast(context, 'Seul un administrateur peut restaurer une sauvegarde.', error: true);
      return;
    }
    final done = await restoreFlow(context, path);
    if (done) Session.I.clear();
  }

  Future<void> _restoreOther() async {
    final path = await pickBackupFile();
    if (path != null && mounted) await _restore(path);
  }

  @override
  Widget build(BuildContext context) {
    final files = BackupService.list();
    final warning = BackupService.healthWarning();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          title: 'Sauvegarde',
          subtitle: 'Copies chiffrées de toutes les données, lisibles uniquement par Chicken Station',
          actions: [
            if (_canRestore) SecondaryButton(label: 'Restaurer un fichier…', onPressed: _restoreOther),
            PrimaryButton(
              label: 'Sauvegarder maintenant',
              busy: _busy,
              onPressed: BackupService.hasFolder ? _backupNow : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (warning != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.redText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(warning, style: const TextStyle(color: AppColors.redText, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: IosCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Dossier de sauvegarde'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.folder_outlined,
                            color: BackupService.folderReachable ? AppColors.text : AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            BackupService.hasFolder ? _cfg.folder : 'Aucun dossier choisi',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SecondaryButton(
                          label: BackupService.hasFolder ? 'Changer' : 'Choisir un dossier',
                          onPressed: _chooseFolder,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Conseil : une clé USB qui reste branchée, ou un dossier OneDrive / Google Drive. "
                      "Ainsi une copie existe hors du PC si celui-ci tombe en panne ou est volé.",
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const Divider(height: 28),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _cfg.auto,
                      onChanged: (v) async {
                        setState(() => _cfg.auto = v);
                        await BackupService.saveConfig();
                      },
                      title: const Text('Sauvegarde automatique', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text("À chaque clôture de journée, et au démarrage de l'appli si la dernière date de plus de 20 h."),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Sauvegardes gardées dans le dossier', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        DropdownButton<int>(
                          value: const [30, 60, 90, 180, 0].contains(_cfg.keep) ? _cfg.keep : 60,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 30, child: Text('30 dernières')),
                            DropdownMenuItem(value: 60, child: Text('60 dernières')),
                            DropdownMenuItem(value: 90, child: Text('90 dernières')),
                            DropdownMenuItem(value: 180, child: Text('180 dernières')),
                            DropdownMenuItem(value: 0, child: Text('Toutes')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() => _cfg.keep = v);
                            await BackupService.saveConfig();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  StatTile(
                    label: 'Dernière sauvegarde',
                    value: _cfg.lastAt == null ? 'Jamais' : fmtDate(_cfg.lastAt!),
                    sub: _cfg.lastAt == null ? null : 'à ${fmtTime(_cfg.lastAt!)}',
                    highlight: true,
                  ),
                  const SizedBox(height: 12),
                  StatTile(
                    label: 'Dans le dossier',
                    value: '${files.length}',
                    sub: files.isEmpty
                        ? 'sauvegarde'
                        : 'sauvegarde(s) · ${BackupService.sizeLabel(files.fold<int>(0, (a, f) => a + f.size))}',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Revenir à une date'),
              const SizedBox(height: 4),
              const Text(
                "Choisissez la sauvegarde : l'appli redevient exactement comme à ce moment-là.",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              if (files.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucune sauvegarde dans ce dossier.'),
                ),
              for (final f in files)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3)))),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${fmtLongDate(f.date)} · ${fmtTime(f.date)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            Text(
                              '${f.label.isEmpty ? 'sauvegarde' : f.label} · ${BackupService.sizeLabel(f.size)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (_canRestore) TextButton(onPressed: () => _restore(f.path), child: const Text('Restaurer')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
