import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/settings.dart';

import '../data/models.dart';
import '../data/repos.dart';
import '../hardware/hardware_service.dart';
import '../hardware/tickets.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'day_dialogs.dart';

/// Journée : ouverture, dépenses, clôture à l'aveugle, rapport Z.
class ClosingScreen extends StatefulWidget {
  const ClosingScreen({super.key});

  @override
  State<ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<ClosingScreen> {
  final _counted = TextEditingController();
  final _reason = TextEditingController();
  final _taken = TextEditingController();
  int? _validatedCount;

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    _taken.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final d = await openDayDialog(context);
    if (d != null && mounted) {
      toast(context, 'Journée ouverte avec un fond de ${fmtDa(d.openingFund)}');
      setState(() {});
    }
  }

  void _validateCount() {
    final v = parseAmount(_counted.text);
    if (v == null || v < 0) {
      toast(context, 'Tapez le montant total compté dans le tiroir.', error: true);
      return;
    }
    setState(() {
      _validatedCount = v;
      _taken.text = '$v';
    });
  }

  Future<void> _close(Day day, DaySummary s) async {
    final counted = _validatedCount;
    if (counted == null) return;
    final waiting = SaleRepo.pendingCount(day.id);
    if (waiting > 0) {
      toast(
        context,
        '$waiting commande(s) en attente de paiement : encaissez-les ou annulez-les dans la Caisse (bouton « En attente ») avant de clôturer.',
        error: true,
      );
      return;
    }
    final diff = counted - s.expectedInDrawer;
    if (diff != 0 && _reason.text.trim().isEmpty) {
      toast(context, "Indiquez le motif de l'écart avant de clôturer.", error: true);
      return;
    }
    final taken = parseAmount(_taken.text) ?? counted;
    if (taken < 0 || taken > counted) {
      toast(context, 'Le montant emporté doit être entre 0 et ${fmtDa(counted)}.', error: true);
      return;
    }
    final ok = await confirm(
      context,
      'Clôturer la journée ?',
      'Compté ${fmtDa(counted)} · écart ${fmtSigned(diff)} DA · emporté ${fmtDa(taken)}.\n'
          'Après clôture, la journée est verrouillée.',
      ok: 'Clôturer',
    );
    if (!ok) return;
    final user = Session.I.user!;
    final expenses = ExpenseRepo.forDay(day.id);
    DayRepo.close(
      day: day,
      userId: user.id,
      counted: counted,
      expected: s.expectedInDrawer,
      reason: _reason.text.trim(),
      takenHome: taken,
    );
    try {
      for (var i = 0; i < Settings.zCopies; i++) {
        await HardwareService.I.printTicket(Tickets.zReport(
          s: s,
          counted: counted,
          takenHome: taken,
          reason: _reason.text.trim(),
          closedBy: user.name,
          expenses: expenses,
        ));
      }
    } catch (e) {
      if (mounted) toast(context, 'Journée clôturée, mais impression du Z impossible : $e', error: true);
    }
    if (!mounted) return;
    setState(() {
      _validatedCount = null;
      _counted.clear();
      _reason.clear();
      _taken.clear();
    });
    toast(context, 'Journée clôturée. ${fmtDa(taken)} ajoutés au coffre.');
    final backupError = await BackupService.auto('clôture');
    if (backupError != null && mounted) toast(context, backupError, error: true);
  }

  Future<void> _cancelExpense(Expense e) async {
    final reason = await askText(context, 'Annuler « ${e.label} » (${fmtDa(e.amount)})',
        hint: 'Motif obligatoire (ex. montant faux, saisie en double)', ok: 'Annuler la dépense');
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      ExpenseRepo.cancel(e.id, Session.I.user!.id, reason);
      setState(() {});
      toast(context, e.source == 'coffre' ? 'Dépense annulée : l\'argent est remis au coffre.' : 'Dépense annulée : la caisse attendue est corrigée.');
    } catch (err) {
      toast(context, err is StateError ? err.message : '$err', error: true);
    }
  }

  Future<void> _printReport(Day day, {required bool sales, required bool spending}) async {
    try {
      await HardwareService.I.printTicket(Tickets.dayReport(
        s: DayRepo.summary(day),
        expenses: ExpenseRepo.forDay(day.id),
        sales: sales,
        spending: spending,
        printedBy: Session.I.user?.name ?? '',
      ));
      if (mounted) toast(context, 'Rapport envoyé à l\'imprimante.');
    } catch (e) {
      if (mounted) toast(context, 'Impression impossible : $e', error: true);
    }
  }

  /// Dernière journée clôturée (la veille en général).
  Day? _lastClosed() {
    final l = DayRepo.closedBetween(DateTime.now().subtract(const Duration(days: 60)), DateTime.now().add(const Duration(days: 1)));
    return l.isEmpty ? null : l.first;
  }

  /// Détail d'une journée clôturée, comme sur le Z, avec réimpression.
  Future<void> _showDay(Day d) async {
    final s = DayRepo.summary(d);
    final expenses = ExpenseRepo.forDay(d.id);
    final diff = d.diff ?? 0;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Clôture du ${fmtLongDate(d.openedAt)}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ouverte à ${fmtTime(d.openedAt)} · clôturée ${d.closedAt == null ? '' : 'le ${fmtDateTime(d.closedAt!)}'} par ${d.closedBy ?? '—'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                const SectionLabel('Ventes'),
                KeyValueRow("Chiffre d'affaires", fmtDa(s.totalSales), bold: true),
                KeyValueRow('Tickets', '${s.tickets}', sub: 'panier moyen ${fmtDa(s.averageTicket)}'),
                KeyValueRow('Espèces', fmtDa(s.cashSales)),
                KeyValueRow('TPE', fmtDa(s.cardSales)),
                if (s.cancelledCount > 0) KeyValueRow('Annulations', '${s.cancelledCount} · ${fmtDa(s.cancelledTotal)}'),
                for (final f in s.byFamily.entries) KeyValueRow('  ${f.key}', fmtDa(f.value)),
                const SizedBox(height: 10),
                const SectionLabel('Caisse'),
                KeyValueRow('Fond du matin', fmtDa(d.openingFund)),
                KeyValueRow('Ventes en espèces', '+ ${fmtDa(s.cashSales)}', valueColor: AppColors.greenText),
                KeyValueRow('Dépenses payées en caisse', '− ${fmtDa(s.cashExpenses)}', valueColor: AppColors.redText),
                KeyValueRow('Attendu', fmtDa(d.expected ?? s.expectedInDrawer), bold: true),
                KeyValueRow('Compté', fmtDa(d.counted ?? 0), bold: true),
                KeyValueRow(
                  diff == 0 ? 'Caisse juste' : 'Écart',
                  '${fmtSigned(diff)} DA',
                  bold: true,
                  valueColor: diff < 0 ? AppColors.redText : (diff > 0 ? AppColors.greenText : AppColors.textSecondary),
                  sub: (d.reason ?? '').isEmpty ? null : 'Motif : ${d.reason}',
                ),
                KeyValueRow('Emporté au coffre', fmtDa(d.takenHome ?? 0)),
                if (expenses.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const SectionLabel('Dépenses'),
                  for (final e in expenses)
                    KeyValueRow(e.label, fmtDa(e.amount), sub: '${e.category} · ${e.source == 'caisse' ? 'caisse' : 'coffre'}'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Réimprimer le Z'),
            onPressed: () async {
              try {
                await HardwareService.I.printTicket(Tickets.zReport(
                  s: s,
                  counted: d.counted ?? 0,
                  takenHome: d.takenHome ?? 0,
                  reason: d.reason ?? '',
                  closedBy: d.closedBy ?? '',
                  expenses: expenses,
                ));
                if (mounted) toast(context, 'Z envoyé à l\'imprimante.');
              } catch (e) {
                if (mounted) toast(context, 'Impression impossible : $e', error: true);
              }
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = DayRepo.current();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          title: 'Caisse du jour',
          subtitle: day == null ? 'Aucune journée ouverte' : '${fmtLongDate(day.openedAt)} · ouverte à ${fmtTime(day.openedAt)}',
          actions: [
            if (Session.I.can(Perm.recette) && _lastClosed() != null)
              SecondaryButton(label: 'Clôture précédente', onPressed: () => _showDay(_lastClosed()!)),
            if (day == null && Session.I.can(Perm.cloture)) PrimaryButton(label: 'Ouvrir la journée', onPressed: _open),
            if (day != null && Session.I.can(Perm.recette))
              PopupMenuButton<String>(
                tooltip: 'Imprimer un rapport sans clôturer',
                onSelected: (v) => _printReport(day, sales: v != 'depenses', spending: v != 'recette'),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'recette', child: Text('Imprimer la recette')),
                  PopupMenuItem(value: 'depenses', child: Text('Imprimer les dépenses')),
                  PopupMenuItem(value: 'tout', child: Text('Imprimer les deux')),
                ],
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Imprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (day == null) _noDay() else _openDay(day),
      ],
    );
  }

  Widget _noDay() {
    final last = DayRepo.closedBetween(DateTime.now().subtract(const Duration(days: 7)), DateTime.now().add(const Duration(days: 1)));
    final s = DayRepo.suggestedFund();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatTile(
          label: 'Fond conseillé pour ouvrir aujourd\'hui',
          value: fmtDa(s.suggested),
          sub: 'Monnaie ${fmtDa(s.change)} + dépenses moyennes ${fmtDa(s.avgExpenses)} + 10 %',
          highlight: true,
        ),
        const SizedBox(height: 16),
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('7 derniers jours'),
              if (last.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 10), child: Text('Aucune clôture pour le moment.')),
              for (final d in last)
                InkWell(
                  onTap: Session.I.can(Perm.recette) ? () => _showDay(d) : null,
                  child: KeyValueRow(
                    fmtLongDate(d.openedAt),
                    'écart ${fmtSigned(d.diff ?? 0)} DA',
                    sub: 'Compté ${fmtDa(d.counted ?? 0)} · emporté ${fmtDa(d.takenHome ?? 0)} · ${d.closedBy ?? ''} · toucher pour le détail',
                    valueColor: (d.diff ?? 0) < 0 ? AppColors.redText : ((d.diff ?? 0) > 0 ? AppColors.greenText : AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _openDay(Day day) {
    final s = DayRepo.summary(day);
    final expenses = ExpenseRepo.forDay(day.id, withCancelled: true);
    final seeMoney = Session.I.can(Perm.recette);
    final canClose = Session.I.can(Perm.cloture);
    final counted = _validatedCount;
    final diff = counted == null ? 0 : counted - s.expectedInDrawer;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seeMoney) ...[
          // Résumé : ce qui est entré, ce qui est sorti. La recette ne compte jamais le fond.
          IosCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Résumé de la journée'),
                const SizedBox(height: 4),
                KeyValueRow('Fond ramené ce matin', fmtDa(day.openingFund)),
                KeyValueRow(
                  'Recette du jour (sans le fond)',
                  fmtDa(s.totalSales),
                  bold: true,
                  sub: '${s.tickets} ticket(s) · espèces ${fmtDa(s.cashSales)} · TPE ${fmtDa(s.cardSales)}',
                ),
                KeyValueRow('Entré en espèces', '+ ${fmtDa(s.cashSales)}', valueColor: AppColors.greenText),
                KeyValueRow('Sorti de la caisse (dépenses)', '− ${fmtDa(s.cashExpenses)}', valueColor: AppColors.redText),
                KeyValueRow(
                  'Recette en espèces après dépenses',
                  fmtDa(s.cashSales - s.cashExpenses),
                  bold: true,
                  sub: 'ce que la journée laisse en plus du fond',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SectionLabel('Sorties du jour'),
                  const Spacer(),
                  if (Session.I.can(Perm.depense))
                    TextButton.icon(
                      onPressed: () async {
                        if (await addExpenseDialog(context, dayId: day.id)) setState(() {});
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Dépense'),
                    ),
                ],
              ),
              if (expenses.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aucune dépense aujourd\'hui.')),
              for (final e in expenses)
                Row(
                  children: [
                    Expanded(
                      child: Opacity(
                        opacity: e.cancelled ? 0.5 : 1,
                        child: KeyValueRow(
                          e.cancelled ? '${e.label} (annulée)' : e.label,
                          fmtDa(e.amount),
                          sub: e.cancelled ? 'Annulée' : (e.source == 'caisse' ? 'de la caisse' : 'du coffre (pas dans le tiroir)'),
                        ),
                      ),
                    ),
                    if (!e.cancelled && Session.I.can(Perm.depense))
                      IconButton(
                        tooltip: 'Annuler cette dépense (erreur de saisie)',
                        icon: const Icon(Icons.undo, size: 18, color: AppColors.textSecondary),
                        onPressed: () => _cancelExpense(e),
                      ),
                  ],
                ),
              if (expenses.isNotEmpty) KeyValueRow('Total sorti de la caisse', fmtDa(s.cashExpenses), bold: true),
            ],
          ),
        ),
      ],
    );

    final right = !canClose
        ? const IosCard(child: Text('La clôture est réservée au gérant.'))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IosCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(seeMoney ? 'Comptage de la caisse' : "Comptage à l'aveugle"),
                    if (seeMoney) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Vous devez trouver (fond compris)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(fmtDa(s.expectedInDrawer), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                            Text(
                              'fond ${fmtDa(day.openingFund)} + espèces ${fmtDa(s.cashSales)} − sorties ${fmtDa(s.cashExpenses)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      seeMoney
                          ? "Comptez tout l'argent du tiroir, fond compris, et tapez le total."
                          : "Comptez tout l'argent du tiroir, fond compris, et tapez le total. "
                              "Le montant attendu s'affiche seulement après validation.",
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: FieldBox(controller: _counted, hint: 'Montant compté', numeric: true, big: true)),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 58,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.text,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _validateCount,
                            child: const Text('Valider'),
                          ),
                        ),
                      ],
                    ),
                    if (counted != null) ...[
                      const SizedBox(height: 8),
                      KeyValueRow('Fond du matin', fmtDa(day.openingFund)),
                      KeyValueRow('Ventes en espèces', '+ ${fmtDa(s.cashSales)}', valueColor: AppColors.greenText),
                      KeyValueRow('Dépenses payées en caisse', '− ${fmtDa(s.cashExpenses)}', valueColor: AppColors.redText),
                      KeyValueRow('À trouver', fmtDa(s.expectedInDrawer), bold: true),
                      KeyValueRow('Compté (fond compris)', fmtDa(counted), bold: true),
                      KeyValueRow('Compté sans le fond', fmtDa(counted - day.openingFund)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: diff == 0 ? AppColors.greenSoft : const Color(0xFFFFF1E6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(diff == 0 ? 'Caisse juste' : 'Écart',
                                style: TextStyle(fontWeight: FontWeight.w700, color: diff == 0 ? AppColors.greenText : const Color(0xFFA33200))),
                            const Spacer(),
                            Text('${fmtSigned(diff)} DA',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: diff == 0 ? AppColors.greenText : const Color(0xFFA33200))),
                          ],
                        ),
                      ),
                      if (diff != 0) ...[
                        const SizedBox(height: 10),
                        FieldBox(controller: _reason, hint: "Motif de l'écart (obligatoire)"),
                      ],
                      const SizedBox(height: 12),
                      const Text('À emporter au coffre', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      FieldBox(controller: _taken, numeric: true),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.yellow,
                            foregroundColor: AppColors.text,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          onPressed: () => _close(day, s),
                          child: const Text('Enregistrer la clôture'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Builder(builder: (_) {
                        final f = DayRepo.suggestedFund();
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.wb_sunny_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Demain, ramenez ${fmtDa(f.suggested)} de fond',
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      'monnaie ${fmtDa(f.change)} + dépenses moyennes ${fmtDa(f.avgExpenses)} + 10 %',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          );

    return LayoutBuilder(
      builder: (c, cons) => cons.maxWidth < 900
          ? Column(children: [left, const SizedBox(height: 16), right])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(flex: 3, child: left), const SizedBox(width: 16), Expanded(flex: 2, child: right)],
            ),
    );
  }
}
