import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/attendance.dart';
import '../data/purchasing.dart';
import '../data/repos.dart';
import '../data/settings.dart';
import '../data/stock.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'day_dialogs.dart';
import 'stock_screen.dart';

/// Montant + source (coffre / caisse) + note. Renvoie null si annulé.
Future<({int amount, String source, String note})?> askPayment(
  BuildContext context, {
  required String title,
  int? suggested,
  String hint = 'Montant en DA',
  bool withSource = true,
  String sourceDefault = 'caisse',
}) {
  final amount = TextEditingController(text: suggested == null || suggested <= 0 ? '' : '$suggested');
  final note = TextEditingController();
  var source = sourceDefault;
  return showDialog<({int amount, String source, String note})>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(scrollable: true, 
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldBox(controller: amount, hint: hint, numeric: true, big: true, autofocus: true),
              if (withSource) ...[
                const SizedBox(height: 12),
                IosSegmented<String>(
                  values: const ['caisse', 'coffre'],
                  selected: source,
                  label: (v) => v == 'coffre' ? 'Payé depuis le coffre' : 'Payé depuis la caisse',
                  onChanged: (v) => setD(() => source = v),
                ),
              ],
              const SizedBox(height: 12),
              FieldBox(controller: note, hint: 'Note (facultatif)'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Retour')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.text),
            onPressed: () async {
              final v = parseAmount(amount.text);
              if (v == null || v <= 0) return;
              final src = withSource ? await ensureCashOpen(c, source) : source;
              if (src == null || !c.mounted) return;
              Navigator.pop(c, (amount: v, source: src, note: note.text.trim()));
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    ),
  );
}

/// Début de mois : la paie du mois dernier est-elle réglée ?
/// Oui → on enregistre le paiement du reste (le compteur revient à zéro).
/// Pas encore → on garde ce qui est dû, et on redemande le lendemain.
Future<void> remindUnpaidPayroll(BuildContext context) async {
  if (!Session.I.can(Perm.paie)) return;
  final today = DateTime.now();
  final todayKey = '${today.year}-${today.month}-${today.day}';
  if (Settings.get('payroll_reminder_snooze') == todayKey) return;
  final prev = monthKey(DateTime(today.year, today.month - 1));
  final due = <(Employee, int)>[];
  final notValidated = <String>[];
  for (final e in PayrollRepo.employees()) {
    if (!e.worksIn(prev) || (e.trackedFrom.isNotEmpty && prev.compareTo(e.trackedFrom) < 0)) continue;
    final rest = PayrollRepo.month(e, prev).remaining;
    if (rest <= 0) continue;
    due.add((e, rest));
    final r = AttendanceRepo.recap(e, prev);
    if (r.suggestedDeduction != PayrollRepo.fromAttendance(e.id, prev, 'retenue') ||
        r.suggestedBonus != PayrollRepo.fromAttendance(e.id, prev, 'prime')) {
      notValidated.add(e.name);
    }
  }
  if (due.isEmpty || !context.mounted) return;
  final total = due.fold<int>(0, (a, d) => a + d.$2);
  final monthName = fmtMonth(DateTime(today.year, today.month - 1));
  var source = 'caisse';
  final answer = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(scrollable: true, 
        title: Text('Paie de $monthName'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Avez-vous payé vos employés ? Il reste à payer :'),
              const SizedBox(height: 8),
              for (final d in due) KeyValueRow(d.$1.name, fmtDa(d.$2), bold: true),
              KeyValueRow('Total', fmtDa(total), bold: true, valueColor: AppColors.redText),
              if (notValidated.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Pointage pas encore validé pour ${notValidated.join(', ')} : '
                  'validez-le d\'abord dans Dépenses › Employés si vous voulez compter absences et doubles.',
                  style: const TextStyle(fontSize: 12, color: AppColors.redText, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              const Text('Si oui, l\'argent est sorti de :', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              IosSegmented<String>(
                values: const ['caisse', 'coffre'],
                selected: source,
                label: (v) => v == 'caisse' ? 'La caisse' : 'Le coffre',
                onChanged: (v) => setD(() => source = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'later'), child: const Text('Pas encore payé')),
          FilledButton(onPressed: () => Navigator.pop(c, 'paid'), child: const Text('Oui, tout est payé')),
        ],
      ),
    ),
  );
  if (answer != 'paid') {
    Settings.set('payroll_reminder_snooze', todayKey);
    return;
  }
  if (!context.mounted) return;
  final src = await ensureCashOpen(context, source);
  if (src == null || !context.mounted) return;
  try {
    for (final d in due) {
      PayrollRepo.record(
        userId: Session.I.user!.id,
        employee: d.$1,
        kind: 'salaire',
        amount: d.$2,
        month: prev,
        source: src,
        note: 'paie de $monthName soldée',
      );
    }
    if (context.mounted) toast(context, 'Paie de $monthName soldée : ${fmtDa(total)}.');
  } catch (e) {
    if (context.mounted) toast(context, e is StateError ? e.message : '$e', error: true);
  }
}

String _monthOffset(int delta) {
  final n = DateTime.now();
  return monthKey(DateTime(n.year, n.month + delta));
}

String _shiftMonth(String key, int delta) {
  final y = int.parse(key.substring(0, 4));
  final m = int.parse(key.substring(5, 7));
  return monthKey(DateTime(y, m + delta));
}

/// Choix d'un mois avec deux flèches (‹ novembre 2026 ›), jusqu'à [max] au plus tard.
class _MonthStepper extends StatelessWidget {
  const _MonthStepper({required this.value, required this.onChanged, required this.max});
  final String value;
  final String max;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFE9E9EE), borderRadius: BorderRadius.circular(11)),
      child: Row(
        children: [
          IconButton(onPressed: () => onChanged(_shiftMonth(value, -1)), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(_monthLabel(value), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: value.compareTo(max) >= 0 ? null : () => onChanged(_shiftMonth(value, 1)),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

String _monthLabel(String key) {
  final y = int.parse(key.substring(0, 4));
  final m = int.parse(key.substring(5, 7));
  return fmtMonth(DateTime(y, m));
}

/// Achats et paie : fournisseurs (dettes, paiements) et employés (salaires, acomptes, primes).
/// Fournisseurs (dettes, paiements) ou paie des employés (salaires, acomptes, primes).
/// [payroll] false : fournisseurs, affichés comme onglet de l'écran Achats (sans grand titre).
class PurchasingScreen extends StatefulWidget {
  const PurchasingScreen({super.key, this.payroll = false, this.embedded = false, this.onChanged});
  final bool payroll;

  /// Affiché comme onglet de la page Dépenses : pas de grand titre.
  final bool embedded;

  /// Prévient la page Dépenses qu'un montant a changé (pour rafraîchir le résumé).
  final VoidCallback? onChanged;

  @override
  State<PurchasingScreen> createState() => _PurchasingScreenState();
}

/// Entrée « Paie » du menu.
class PayrollScreen extends StatelessWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context) => const PurchasingScreen(payroll: true);
}

class _PurchasingScreenState extends State<PurchasingScreen> {
  int? _supplierId;
  int? _employeeId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  int get _uid => Session.I.user!.id;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.payroll) return _suppliersTab();
    if (widget.embedded) return _employeesTab();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        const PageHeader(
          title: 'Paie',
          subtitle: 'Salaire du mois, acomptes et primes : le reste à payer est calculé tout seul',
        ),
        const SizedBox(height: 16),
        _employeesTab(),
      ],
    );
  }

  Widget _split(Widget left, Widget right) => LayoutBuilder(
        builder: (c, cons) => cons.maxWidth < 860
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 14), right])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [SizedBox(width: 330, child: left), const SizedBox(width: 14), Expanded(child: right)],
              ),
      );

  /// Exécute une écriture ; affiche l'erreur claire si elle est refusée (caisse insuffisante…).
  void _guard(void Function() action, String ok) {
    try {
      action();
      setState(() {});
      toast(context, ok);
    } catch (e) {
      toast(context, e is StateError ? e.message : '$e', error: true);
    }
  }

  /// Payer depuis le coffre plus que ce que l'appli y compte : on prévient avant.
  Future<bool> _sourceOk(String source, int amount) async {
    if (source != 'coffre') return true;
    final safe = SafeRepo.balance();
    if (amount <= safe) return true;
    return confirm(
      context,
      'Coffre insuffisant dans l\'appli',
      'D\'après l\'appli, le coffre ne contient que ${fmtDa(safe)}. Si l\'argent y est vraiment, '
          'enregistrez d\'abord un versement dans Coffre pour que les comptes restent justes.\n\nPayer quand même ?',
      ok: 'Payer quand même',
    );
  }

  Future<String?> _reason(String title) async {
    final r = await askText(context, title, hint: 'Motif obligatoire (ex. erreur de montant)', ok: 'Annuler la ligne');
    return r == null || r.isEmpty ? null : r;
  }

  // ========================================================================== fournisseurs

  Widget _suppliersTab() {
    final list = SupplierRepo.all();
    // -1 : achats sans fournisseur (marché, dépannage).
    final loose = StockRepo.receptions(noSupplier: true, limit: 200);
    if (_supplierId == null || (_supplierId != -1 && !list.any((s) => s.id == _supplierId))) {
      _supplierId = list.isNotEmpty ? list.first.id : (loose.isNotEmpty ? -1 : null);
    }
    final sel = list.where((s) => s.id == _supplierId).firstOrNull;
    final total = list.fold<int>(0, (a, s) => a + (s.debt > 0 ? s.debt : 0));
    final left = IosCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Row(
              children: [
                const Expanded(child: SectionLabel('Fournisseurs')),
                Text('total dû ${fmtDa(total)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: total > 0 ? AppColors.redText : AppColors.textSecondary)),
              ],
            ),
          ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucun fournisseur.')),
          for (final s in list)
            Material(
              color: s.id == _supplierId ? AppColors.yellowSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text(s.name,
                    style: TextStyle(fontWeight: FontWeight.w700, color: s.active ? AppColors.text : AppColors.textSecondary)),
                subtitle: Text(s.phone.isEmpty ? (s.active ? 'fournisseur' : 'désactivé') : s.phone),
                trailing: Text(
                  s.debt > 0 ? fmtDa(s.debt) : (s.debt < 0 ? 'avance ${fmtDa(-s.debt)}' : 'à jour'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: s.debt > 0 ? AppColors.redText : AppColors.greenText),
                ),
                onTap: () => setState(() => _supplierId = s.id),
              ),
            ),
          if (loose.isNotEmpty)
            Material(
              color: _supplierId == -1 ? AppColors.yellowSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Achats sans fournisseur', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('marché, dépannage… payés sur place'),
                onTap: () => setState(() => _supplierId = -1),
              ),
            ),
          const SizedBox(height: 6),
          SecondaryButton(
            label: '+ Nouveau fournisseur',
            onPressed: () => _editSupplier(null),
          ),
        ],
      ),
    );
    final right = _supplierId == -1
        ? _looseDetail(loose)
        : (sel == null ? const IosCard(child: Text('Ajoutez votre premier fournisseur.')) : _supplierDetail(sel));
    return _split(left, right);
  }

  /// Bons d'achat sans fournisseur (payés sur place).
  Widget _looseDetail(List<Map<String, Object?>> bons) {
    final canCancel = Session.I.can(Perm.reception);
    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Achats sans fournisseur', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              if (Session.I.can(Perm.reception))
                SecondaryButton(
                  label: "+ Bon d'achat",
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (_) => const ReceptionDialog());
                    if (ok == true && mounted) setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final r in bons)
            _HistoryRow(
              title: StockRepo.receptionLines(r['id'] as int).join(' · '),
              value: fmtDa(r['total'] as int),
              sub: '${fmtDateTime(DateTime.parse(r['created_at'] as String))}'
                  '${((r['note'] as String?) ?? '').isEmpty ? '' : ' · ${r['note']}'}',
              cancelled: (r['cancelled'] as int) == 1,
              onCancel: !canCancel || (r['cancelled'] as int) == 1
                  ? null
                  : () async {
                      final reason = await _reason("Annuler ce bon d'achat");
                      if (reason == null || !mounted) return;
                      _guard(() => StockRepo.cancelReception(r['id'] as int, _uid, reason),
                          "Bon annulé. Le paiement fait sur place s'annule dans Clôture ou Coffre (dépense).");
                    },
            ),
        ],
      ),
    );
  }

  Future<void> _paySupplier(Supplier s) async {
    final r = await askPayment(context, title: 'Payer ${s.name}', suggested: s.debt);
    if (r == null || !mounted) return;
    if (r.amount > s.debt) {
      final ok = await confirm(
        context,
        'Payer plus que la dette ?',
        '${s.name} n\'attend que ${fmtDa(s.debt < 0 ? 0 : s.debt)}. Les ${fmtDa(r.amount - (s.debt < 0 ? 0 : s.debt))} en plus '
            'seront comptés comme une avance chez ce fournisseur (déduite du prochain bon d\'achat).',
        ok: 'Oui, c\'est une avance',
      );
      if (!ok || !mounted) return;
    }
    if (!await _sourceOk(r.source, r.amount) || !mounted) return;
    _guard(
      () => SupplierRepo.pay(userId: _uid, supplier: s, amount: r.amount, source: r.source, note: r.note),
      'Paiement de ${fmtDa(r.amount)} enregistré.',
    );
  }

  Widget _supplierDetail(Supplier s) {
    final history = SupplierRepo.history(s.id);
    final canCancel = Session.I.can(Perm.fournisseurs);
    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Wrap(
                      spacing: 14,
                      children: [
                        _contact(Icons.phone_outlined, s.phone.isEmpty ? 'Pas de téléphone' : s.phone),
                        if (s.product.isNotEmpty) _contact(Icons.inventory_2_outlined, s.product),
                        if (s.note.isNotEmpty) _contact(Icons.notes_outlined, s.note),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Modifier', onPressed: () => _editSupplier(s), icon: const Icon(Icons.edit_outlined)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: StatTile(
                  label: s.debt < 0 ? 'Avance chez lui' : 'Reste à payer',
                  value: fmtDa(s.debt.abs()),
                  valueColor: s.debt > 0 ? AppColors.redText : AppColors.greenText,
                  highlight: true,
                ),
              ),
              if (Session.I.can(Perm.reception))
                SecondaryButton(
                  label: "+ Bon d'achat",
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (_) => ReceptionDialog(supplier: s));
                    if (ok == true && mounted) setState(() {});
                  },
                ),
              if (Session.I.can(Perm.fournisseurs))
                SecondaryButton(label: "+ Crédit d'avant", onPressed: () => _oldCredit(s)),
              PrimaryButton(label: 'Payer', onPressed: () => _paySupplier(s)),
            ],
          ),
          const SizedBox(height: 14),
          const SectionLabel('Historique'),
          if (history.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Rien pour le moment.')),
          for (final e in history)
            _HistoryRow(
              title: e.isPurchase && !e.opening && StockRepo.receptionLines(e.id).isNotEmpty
                  ? StockRepo.receptionLines(e.id).join(' · ')
                  : e.label,
              value: '${e.isPurchase ? '+' : '−'} ${fmtDa(e.amount)}',
              sub: e.opening ? fmtDateTime(e.at) : (e.isPurchase ? '${fmtDateTime(e.at)} · ${e.label}' : fmtDateTime(e.at)),
              color: e.isPurchase ? AppColors.redText : AppColors.greenText,
              cancelled: e.cancelled,
              onCancel: !canCancel || e.cancelled
                  ? null
                  : () async {
                      final reason = await _reason(e.isPurchase ? "Annuler ce bon d'achat" : 'Annuler ce paiement');
                      if (reason == null || !mounted) return;
                      _guard(
                        () {
                          if (e.isPurchase) {
                            StockRepo.cancelReception(e.id, _uid, reason);
                          } else {
                            SupplierRepo.cancelPayment(e.id, _uid, reason);
                          }
                        },
                        e.isPurchase
                            ? "Bon d'achat annulé : la dette du fournisseur est corrigée."
                            : 'Paiement annulé : l\'argent est remis là d\'où il était sorti.',
                      );
                    },
            ),
        ],
      ),
    );
  }

  /// Bons papier pas encore payés quand on commence avec l'appli : on reporte le total une fois.
  Future<void> _oldCredit(Supplier s) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(scrollable: true, 
        title: Text("Crédit d'avant l'appli · ${s.name}"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Ce que vous lui deviez déjà avant de commencer avec l'appli (bons papier pas encore payés). "
                "Ça s'ajoute à son reste à payer, sans compter dans les achats du mois.",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              FieldBox(controller: amount, hint: 'Montant total dû en DA', numeric: true, autofocus: true),
              const SizedBox(height: 10),
              FieldBox(controller: note, hint: 'Note (ex. 3 bons de novembre)'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final v = parseAmount(amount.text) ?? 0;
    if (v <= 0) {
      toast(context, 'Tapez le montant dû.', error: true);
      return;
    }
    _guard(() => SupplierRepo.addOldCredit(_uid, s.id, v, note.text.trim()),
        "Crédit ajouté : ${s.name} attend maintenant ${fmtDa(s.debt + v)}.");
  }

  Widget _contact(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      );

  /// Fiche contact d'un fournisseur : nom, téléphone, ce qu'il livre d'habitude, note.
  Future<void> _editSupplier(Supplier? s) async {
    final name = TextEditingController(text: s?.name ?? '');
    final phone = TextEditingController(text: s?.phone ?? '');
    final product = TextEditingController(text: s?.product ?? '');
    final note = TextEditingController(text: s?.note ?? '');
    var active = s?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(scrollable: true, 
          title: Text(s == null ? 'Nouveau fournisseur' : 'Fiche de ${s.name}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldBox(controller: name, hint: 'Nom (ex. Khalil)', autofocus: s == null),
                const SizedBox(height: 10),
                FieldBox(controller: phone, hint: 'Téléphone', numeric: true),
                const SizedBox(height: 10),
                FieldBox(controller: product, hint: 'Ce qu\'il livre (ex. Viande)'),
                const SizedBox(height: 4),
                const Text('Proposé sur chaque nouveau bon, modifiable.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                FieldBox(controller: note, hint: 'Note (jours de livraison…) facultatif'),
                if (s != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    activeTrackColor: AppColors.green,
                    onChanged: (v) => setD(() => active = v),
                    title: const Text('Actif'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  toast(c, 'Tapez le nom du fournisseur.', error: true);
                  return;
                }
                if (s == null) {
                  _supplierId = SupplierRepo.add(_uid, name.text.trim(), phone.text.trim(),
                      product: product.text.trim(), note: note.text.trim());
                } else {
                  s
                    ..name = name.text.trim()
                    ..phone = phone.text.trim()
                    ..product = product.text.trim()
                    ..note = note.text.trim()
                    ..active = active;
                  SupplierRepo.save(_uid, s);
                }
                Navigator.pop(c, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) setState(() {});
  }


  // ========================================================================== employés

  Widget _employeesTab() {
    final mk = monthKey(_month);
    final list = PayrollRepo.employees().where((e) => e.active || e.worksIn(mk)).toList();
    if (_employeeId == null || !list.any((e) => e.id == _employeeId)) _employeeId = list.isEmpty ? null : list.first.id;
    final sel = list.where((e) => e.id == _employeeId).firstOrNull;
    final isCurrent = mk == monthKey(DateTime.now());
    final toPay = PayrollRepo.totalRemaining(mk);
    final payroll = PayrollRepo.totalSalaries(mk);
    final left = IosCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(fmtMonth(_month), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              'Masse salariale ${fmtDa(payroll)} · reste à payer ${fmtDa(toPay)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: toPay > 0 ? AppColors.text : AppColors.greenText),
            ),
          ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucun employé ce mois-ci.')),
          for (final e in list)
            Builder(builder: (_) {
              final m = PayrollRepo.month(e, mk);
              final overdue = PayrollRepo.unpaidBefore(e, mk).isNotEmpty;
              return Material(
                color: e.id == _employeeId ? AppColors.yellowSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(e.name,
                      style: TextStyle(fontWeight: FontWeight.w700, color: e.active ? AppColors.text : AppColors.textSecondary)),
                  subtitle: Text('${e.job.isEmpty ? 'employé' : e.job} · ${fmtDa(m.salary)} / mois${overdue ? ' · mois précédent non soldé' : ''}',
                      style: TextStyle(color: overdue ? AppColors.redText : null)),
                  trailing: Text(
                    m.remaining <= 0 ? 'soldé' : 'reste ${fmtDa(m.remaining)}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: m.remaining <= 0 ? AppColors.greenText : AppColors.text),
                  ),
                  onTap: () => setState(() => _employeeId = e.id),
                ),
              );
            }),
          const SizedBox(height: 6),
          SecondaryButton(label: '+ Nouvel employé', onPressed: () => _editEmployee(null)),
        ],
      ),
    );
    final right = sel == null
        ? const IosCard(child: Text('Ajoutez vos employés avec leur salaire mensuel : il sert au calcul de la paie et de l\'objectif du mois.'))
        : _employeeDetail(sel, mk);
    return _split(left, right);
  }

  Widget _employeeDetail(Employee e, String mk) {
    final m = PayrollRepo.month(e, mk);
    final lines = PayrollRepo.lines(e.id, mk);
    final unpaid = PayrollRepo.unpaidBefore(e, mk);
    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(
                      '${e.job.isEmpty ? 'Employé' : e.job} · depuis ${_monthLabel(e.startMonth)}'
                      '${e.endMonth.isEmpty ? '' : ' · parti après ${_monthLabel(e.endMonth)}'}${e.phone.isEmpty ? '' : ' · ${e.phone}'}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Modifier la fiche', onPressed: () => _editEmployee(e), icon: const Icon(Icons.edit_outlined)),
            ],
          ),
          for (final u in unpaid)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_monthLabel(u.month)} : il reste ${fmtDa(u.remaining)} à lui payer',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.redText)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _month = DateTime(int.parse(u.month.substring(0, 4)), int.parse(u.month.substring(5, 7)));
                    }),
                    child: const Text('Voir ce mois'),
                  ),
                ],
              ),
            ),
          if (e.worksIn(mk)) _attendanceCard(e, mk, m),
          const SizedBox(height: 12),
          SectionLabel('Paie de ${fmtMonth(_month)}'),
          if (!e.worksIn(mk))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Pas employé ce mois-là.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          KeyValueRow('Salaire du mois', fmtDa(m.salary)),
          if (m.bonus > 0) KeyValueRow('Primes', '+ ${fmtDa(m.bonus)}', valueColor: AppColors.greenText),
          if (m.deduction > 0) KeyValueRow('Retenues (absences)', '− ${fmtDa(m.deduction)}', valueColor: AppColors.redText),
          KeyValueRow('Acomptes déjà donnés', '− ${fmtDa(m.advances)}'),
          KeyValueRow('Salaire déjà versé', '− ${fmtDa(m.paid)}'),
          KeyValueRow(
            m.remaining < 0 ? 'Trop versé (à déduire le mois prochain)' : 'Reste à lui payer',
            fmtDa(m.remaining.abs()),
            bold: true,
            valueColor: m.remaining > 0 ? AppColors.text : (m.remaining < 0 ? AppColors.redText : AppColors.greenText),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SecondaryButton(label: '+ Acompte', onPressed: () => _pay(e, mk, 'acompte', null, m)),
              SecondaryButton(label: '+ Prime', onPressed: () => _pay(e, mk, 'prime', null, m)),
              PrimaryButton(
                label: m.remaining > 0 ? 'Payer le reste · ${fmtDa(m.remaining)}' : 'Salaire soldé',
                onPressed: m.remaining > 0 ? () => _pay(e, mk, 'salaire', m.remaining, m) : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SectionLabel('Acomptes et paiements du mois'),
          if (lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Rien ce mois-ci.')),
          for (final l in lines)
            _HistoryRow(
              title: '${PayLine.kindLabels[l.kind] ?? l.kind}${l.origin == 'pointage' ? ' (pointage)' : ''}',
              value: fmtDa(l.amount),
              sub: [
                fmtDateTime(l.at),
                if (l.source.isNotEmpty) l.source == 'coffre' ? 'du coffre' : 'de la caisse',
                if (l.note.isNotEmpty) l.note,
              ].join(' · '),
              cancelled: l.cancelled,
              onCancel: l.cancelled
                  ? null
                  : () async {
                      final reason = await _reason('Annuler : ${PayLine.kindLabels[l.kind]} de ${fmtDa(l.amount)}');
                      if (reason == null || !mounted) return;
                      _guard(() => PayrollRepo.cancelLine(l.id, _uid, reason), 'Ligne annulée.');
                    },
            ),
        ],
      ),
    );
  }

  /// Bilan du pointage du mois (absences, demis, doubles au prix de la journée), validé à la main.
  Widget _attendanceCard(Employee e, String mk, PayMonth m) {
    final r = AttendanceRepo.recap(e, mk);
    final bonusApplied = PayrollRepo.fromAttendance(e.id, mk, 'prime');
    final dedApplied = PayrollRepo.fromAttendance(e.id, mk, 'retenue');
    final needDed = r.suggestedDeduction != dedApplied;
    final needBonus = r.suggestedBonus != bonusApplied;
    final parts = <String>[
      if (r.absent > 0) '${r.absent} absence(s)',
      if (r.demi > 0) '${r.demi} demi-journée(s)',
      if (r.doubles > 0) '${r.doubles} double(s)',
    ];
    Future<void> validate() async {
      final ok = await confirm(
        context,
        'Valider le pointage de ${fmtMonth(_month)} ?',
        [
          if (r.suggestedDeduction > 0 || dedApplied > 0)
            'Retenue : ${r.absent} absence(s) × ${fmtDa(e.dayRate)} + ${r.demi} demi × ${fmtDa((e.dayRate / 2).round())} = ${fmtDa(r.suggestedDeduction)}',
          if (r.suggestedBonus > 0 || bonusApplied > 0)
            'Prime : ${r.doubles} double(s) × ${fmtDa(e.dayRate)} = ${fmtDa(r.suggestedBonus)}',
          'Reste à lui payer après : ${fmtDa(m.remaining + (dedApplied - r.suggestedDeduction) + (r.suggestedBonus - bonusApplied))}.',
          'Aucun argent ne sort maintenant.',
        ].join('\n'),
        ok: 'Valider',
      );
      if (!ok || !mounted) return;
      _guard(() {
        if (needDed) {
          PayrollRepo.setFromAttendance(
            userId: _uid, employee: e, month: mk, kind: 'retenue', amount: r.suggestedDeduction,
            note: '${r.absent} absence(s), ${r.demi} demi × ${fmtDa(e.dayRate)}',
          );
        }
        if (needBonus) {
          PayrollRepo.setFromAttendance(
            userId: _uid, employee: e, month: mk, kind: 'prime', amount: r.suggestedBonus,
            note: '${r.doubles} double(s) × ${fmtDa(e.dayRate)}',
          );
        }
      }, 'Pointage validé.');
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Pointage de ${fmtMonth(_month)}'),
          const SizedBox(height: 4),
          Text(parts.isEmpty ? 'Ni absence, ni demi, ni double : mois complet.' : parts.join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            e.dayRate > 0
                ? 'Prix de la journée : ${fmtDa(e.dayRate)} (modifiable sur sa fiche)'
                : 'Prix de la journée pas indiqué : modifiez sa fiche pour calculer retenues et primes.',
            style: TextStyle(fontSize: 12, color: e.dayRate > 0 ? AppColors.textSecondary : AppColors.redText),
          ),
          if (r.suggestedDeduction > 0) Text('Retenue : − ${fmtDa(r.suggestedDeduction)}', style: const TextStyle(color: AppColors.redText)),
          if (r.suggestedBonus > 0) Text('Prime doubles : + ${fmtDa(r.suggestedBonus)}', style: const TextStyle(color: AppColors.greenText)),
          const SizedBox(height: 8),
          if (e.dayRate > 0 && (needDed || needBonus))
            Align(
              alignment: Alignment.centerLeft,
              child: PrimaryButton(
                label: dedApplied == 0 && bonusApplied == 0 ? 'Valider le pointage' : 'Mettre à jour le pointage',
                onPressed: validate,
              ),
            )
          else if (!r.isEmpty && e.dayRate > 0)
            const Text('✓ Pointage déjà compté dans la paie', style: TextStyle(color: AppColors.greenText, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _pay(Employee e, String mk, String kind, int? suggested, PayMonth m) async {
    final r = await askPayment(
      context,
      title: '${PayLine.kindLabels[kind]} · ${e.name} · ${fmtMonth(_month)}',
      suggested: suggested,
      withSource: kind != 'prime',
      hint: kind == 'prime' ? 'Montant de la prime (ajoutée à ce qui lui est dû)' : 'Montant en DA',
    );
    if (r == null || !mounted) return;
    if (kind != 'prime' && r.amount > m.remaining) {
      final ok = await confirm(
        context,
        'Plus que ce qui lui est dû ?',
        'Il ne reste que ${fmtDa(m.remaining < 0 ? 0 : m.remaining)} à payer à ${e.name} pour ${fmtMonth(_month)}. '
            'Le surplus apparaîtra comme « trop versé » à déduire le mois prochain.',
        ok: 'Continuer',
      );
      if (!ok || !mounted) return;
    }
    if (kind != 'prime' && !await _sourceOk(r.source, r.amount)) return;
    if (!mounted) return;
    _guard(
      () => PayrollRepo.record(
        userId: _uid,
        employee: e,
        kind: kind,
        amount: r.amount,
        month: mk,
        source: r.source,
        note: r.note,
      ),
      '${PayLine.kindLabels[kind]} de ${fmtDa(r.amount)} enregistré(e) pour ${fmtMonth(_month)}.',
    );
  }

  Future<void> _editEmployee(Employee? e) async {
    final name = TextEditingController(text: e?.name ?? '');
    final job = TextEditingController(text: e?.job ?? '');
    final phone = TextEditingController(text: e?.phone ?? '');
    final salary = TextEditingController(text: e == null || e.salary == 0 ? '' : '${e.salary}');
    final dayRate = TextEditingController(text: e == null || e.dayRate == 0 ? '' : '${e.dayRate}');
    var active = e?.active ?? true;
    var startMonth = _monthOffset(0);
    var salaryFrom = _monthOffset(0);
    var endMonth = _monthOffset(0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          final newSalary = parseAmount(salary.text) ?? 0;
          final salaryChanged = e != null && newSalary != e.salary;
          return AlertDialog(scrollable: true, 
            title: Text(e == null ? 'Nouvel employé' : 'Fiche de ${e.name}'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FieldBox(controller: name, hint: 'Nom', autofocus: e == null),
                    const SizedBox(height: 10),
                    FieldBox(controller: job, hint: 'Poste (ex. cuisinier, caissier)'),
                    const SizedBox(height: 10),
                    FieldBox(controller: phone, hint: 'Téléphone'),
                    const SizedBox(height: 10),
                    FieldBox(
                      controller: salary,
                      hint: 'Salaire mensuel en DA (obligatoire)',
                      numeric: true,
                      onChanged: (_) => setD(() {}),
                    ),
                    const SizedBox(height: 10),
                    FieldBox(
                      controller: dayRate,
                      hint: newSalary > 0 ? 'Prix de la journée en DA (ex. ${fmtNum((newSalary / 30).round())})' : 'Prix de la journée en DA',
                      numeric: true,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Retiré pour une absence, ajouté pour une double journée, la moitié pour une demi.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (e == null) ...[
                      const SizedBox(height: 12),
                      const Text('Arrivé en', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      _MonthStepper(
                        value: startMonth,
                        max: _monthOffset(1),
                        onChanged: (v) => setD(() => startMonth = v),
                      ),
                      const SizedBox(height: 4),
                      const Text('Les mois avant son arrivée ne lui sont pas dus.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                    if (salaryChanged) ...[
                      const SizedBox(height: 12),
                      const Text('Nouveau salaire applicable à partir de',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      IosSegmented<String>(
                        values: [_monthOffset(0), _monthOffset(1)],
                        selected: salaryFrom,
                        label: _monthLabel,
                        onChanged: (v) => setD(() => salaryFrom = v),
                      ),
                      const SizedBox(height: 4),
                      const Text('Les mois d\'avant gardent l\'ancien salaire.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                    if (e != null) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: active,
                        activeTrackColor: AppColors.green,
                        onChanged: (v) => setD(() => active = v),
                        title: const Text('Travaille encore ici'),
                      ),
                      if (e.active && !active) ...[
                        const Text('Dernier mois travaillé', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        IosSegmented<String>(
                          values: [_monthOffset(-1), _monthOffset(0)],
                          selected: endMonth,
                          label: _monthLabel,
                          onChanged: (v) => setD(() => endMonth = v),
                        ),
                        const SizedBox(height: 4),
                        const Text('Pensez à solder sa paie de ce dernier mois.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
              FilledButton(
                onPressed: () {
                  final s = parseAmount(salary.text);
                  if (name.text.trim().isEmpty || s == null || s <= 0) {
                    toast(context, 'Indiquez le nom et le salaire mensuel.', error: true);
                    return;
                  }
                  final rate = parseAmount(dayRate.text) ?? 0;
                  if (rate <= 0) {
                    toast(context, 'Indiquez le prix de la journée (ex. ${fmtNum((s / 30).round())} DA).', error: true);
                    return;
                  }
                  if (e == null) {
                    _employeeId = PayrollRepo.add(
                      _uid,
                      name.text.trim(),
                      job.text.trim(),
                      s,
                      phone: phone.text.trim(),
                      startMonth: startMonth,
                      dayRate: rate,
                    );
                  } else {
                    e
                      ..name = name.text.trim()
                      ..job = job.text.trim()
                      ..phone = phone.text.trim()
                      ..salary = s
                      ..dayRate = rate
                      ..active = active;
                    PayrollRepo.save(_uid, e, salaryFrom: salaryFrom, endMonth: endMonth);
                  }
                  Navigator.pop(c, true);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) setState(() {});
  }
}

/// Ligne d'historique avec annulation tracée (barrée une fois annulée).
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.value,
    required this.sub,
    required this.cancelled,
    this.color,
    this.onCancel,
  });

  final String title;
  final String value;
  final String sub;
  final bool cancelled;
  final Color? color;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final strike = cancelled ? TextDecoration.lineThrough : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3)))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: strike,
                      color: cancelled ? AppColors.textSecondary : AppColors.text,
                    )),
                Text(cancelled ? '$sub · annulé' : sub, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              decoration: strike,
              color: cancelled ? AppColors.textSecondary : (color ?? AppColors.text),
            ),
          ),
          if (onCancel != null)
            IconButton(
              tooltip: 'Annuler (erreur de saisie)',
              onPressed: onCancel,
              icon: const Icon(Icons.undo, size: 18, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
