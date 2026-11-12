import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/purchasing.dart';
import '../data/stock.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../data/repos.dart';
import 'day_dialogs.dart';
import 'purchasing_screen.dart';

enum _Tab {
  suppliers('Fournisseurs'),
  employees('Employés'),
  charges('Charges');

  const _Tab(this.label);
  final String label;
}

/// Dépenses : fournisseurs et leurs bons d'achat, employés et leur paie, charges (loyer, électricité…).
/// Tout ce qui sort de l'argent passe par ici (ou par une dépense de caisse à la clôture).
class DepensesScreen extends StatefulWidget {
  const DepensesScreen({super.key});

  /// L'entrée « Dépenses » du menu apparaît avec au moins un de ces droits.
  static const perms = [Perm.stock, Perm.reception, Perm.fournisseurs, Perm.paie, Perm.coffre];

  @override
  State<DepensesScreen> createState() => _DepensesScreenState();
}

class _DepensesScreenState extends State<DepensesScreen> {
  late _Tab _tab = _tabs.first;

  int get _uid => Session.I.user!.id;

  void _refresh() {
    if (mounted) setState(() {});
  }

  List<_Tab> get _tabs => [
        if (Session.I.can(Perm.fournisseurs) || Session.I.can(Perm.reception) || Session.I.can(Perm.stock)) _Tab.suppliers,
        if (Session.I.can(Perm.paie)) _Tab.employees,
        if (Session.I.can(Perm.coffre)) _Tab.charges,
      ];

  Future<void> _divers() async {
    if (await addExpenseDialog(context, divers: true) && mounted) {
      toast(context, 'Dépense enregistrée.');
      setState(() {});
    }
  }

  Future<void> _history() async {
    await showDialog<void>(context: context, builder: (_) => const _ExpenseHistory());
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (tabs.isEmpty) return const Center(child: Text('Aucune dépense autorisée.'));
    if (!tabs.contains(_tab)) _tab = tabs.first;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month);
    final to = DateTime(now.year, now.month + 1);
    final mk = monthKey(now);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          title: 'Dépenses',
          subtitle: 'Fournisseurs, employés et charges : tout ce qui sort de l\'argent',
          actions: [
            SecondaryButton(label: 'Historique', onPressed: _history),
            const SizedBox(width: 8),
            if (Session.I.can(Perm.depense) || Session.I.can(Perm.coffre))
              PrimaryButton(label: '+ Dépense divers', onPressed: _divers),
          ],
        ),
        const SizedBox(height: 14),
        // Résumé du mois en cours.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(width: 210, child: StatTile(label: 'Achats ce mois', value: fmtDa(StockRepo.totalBetween(from, to)))),
            SizedBox(
              width: 210,
              child: StatTile(
                label: 'Dû aux fournisseurs',
                value: fmtDa(SupplierRepo.totalDebt()),
                valueColor: SupplierRepo.totalDebt() > 0 ? AppColors.redText : AppColors.greenText,
              ),
            ),
            if (Session.I.can(Perm.paie))
              SizedBox(
                width: 210,
                child: StatTile(
                  label: 'Salaires restant à payer',
                  value: fmtDa(PayrollRepo.totalRemaining(mk) + PayrollRepo.totalOverdue(mk)),
                  sub: PayrollRepo.totalOverdue(mk) > 0 ? 'dont ${fmtDa(PayrollRepo.totalOverdue(mk))} des mois passés' : null,
                  valueColor: PayrollRepo.totalRemaining(mk) + PayrollRepo.totalOverdue(mk) > 0 ? AppColors.redText : null,
                ),
              ),
            if (Session.I.can(Perm.coffre))
              SizedBox(width: 210, child: StatTile(label: 'Charges payées ce mois', value: fmtDa(ChargesRepo.paidBetween(from, to)))),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: IosSegmented<_Tab>(
            expand: false,
            values: tabs,
            selected: _tab,
            label: (t) => t.label,
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        const SizedBox(height: 14),
        switch (_tab) {
          _Tab.suppliers => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_priceAlert(), PurchasingScreen(onChanged: _refresh)],
            ),
          _Tab.employees => PurchasingScreen(payroll: true, embedded: true, onChanged: _refresh),
          _Tab.charges => _chargesTab(),
        },
      ],
    );
  }

  /// Bandeau « prix en hausse » d'après les derniers bons d'achat.
  Widget _priceAlert() {
    final rising = StockRepo.stats(DateTime.now()).where((s) => (s.priceChange ?? 0) >= 5).toList();
    if (rising.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: AppColors.redText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Prix en hausse : ${rising.map((s) => '${s.article.name} +${s.priceChange} %').join(' · ')}. '
              'Pensez à vérifier vos prix de vente.',
              style: const TextStyle(color: AppColors.redText, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================== charges

  Widget _chargesTab() {
    final charges = ChargesRepo.all();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Le montant se tape au moment de payer (au mois, au trimestre…). Touchez une charge pour voir ses paiements.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            SecondaryButton(
              label: '+ Charge',
              onPressed: () async {
                final label = await askText(context, 'Nouvelle charge', hint: 'ex. Assurance, Entretien hotte');
                if (label == null || label.isEmpty) return;
                ChargesRepo.add(_uid, label);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        IosCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (final c in charges)
                InkWell(
                  onTap: () => _chargeHistory(c),
                  child: Opacity(
                    opacity: c.active ? 1 : 0.45,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3)))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                Text(
                                  c.lastAt == null
                                      ? 'jamais payé dans l\'appli'
                                      : 'dernier paiement ${fmtDa(c.lastAmount)} le ${fmtDate(c.lastAt!)}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          if (c.monthTotal > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text('${fmtDa(c.monthTotal)} ce mois',
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.greenText)),
                            ),
                          if (c.active) PrimaryButton(label: 'Payer', onPressed: () => _payCharge(c)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _payCharge(MonthlyCharge c) async {
    final r = await askPayment(
      context,
      title: 'Payer : ${c.label}',
      suggested: c.lastAmount > 0 ? c.lastAmount : null,
      hint: 'Montant de la facture en DA',
    );
    if (r == null || !mounted) return;
    try {
      ChargesRepo.pay(userId: _uid, charge: c, amount: r.amount, source: r.source, note: r.note);
      setState(() {});
      toast(context, '${c.label} : ${fmtDa(r.amount)} enregistré.');
    } catch (e) {
      toast(context, '$e', error: true);
    }
  }

  Future<void> _chargeHistory(MonthlyCharge c) async {
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) {
          final list = ChargesRepo.history(c.id);
          return AlertDialog(scrollable: true, 
            title: Text(c.label),
            content: SizedBox(
              width: 520,
              height: 380,
              child: list.isEmpty
                  ? const Center(child: Text('Aucun paiement pour le moment.', style: TextStyle(color: AppColors.textSecondary)))
                  : ListView(
                      children: [
                        for (final p in list)
                          Row(
                            children: [
                              Expanded(
                                child: Opacity(
                                  opacity: p.cancelled ? 0.5 : 1,
                                  child: KeyValueRow(
                                    p.cancelled ? '${p.label} (annulé)' : p.label,
                                    fmtDa(p.amount),
                                    sub: p.cancelled
                                        ? 'Annulé · ${p.cancelReason}'
                                        : '${fmtDateTime(p.at)} · ${p.source == 'coffre' ? 'du coffre' : 'de la caisse'}',
                                  ),
                                ),
                              ),
                              if (!p.cancelled)
                                IconButton(
                                  tooltip: 'Annuler (erreur de saisie)',
                                  icon: const Icon(Icons.undo, size: 18, color: AppColors.textSecondary),
                                  onPressed: () async {
                                    final reason = await askText(context, 'Annuler ce paiement',
                                        hint: 'Motif obligatoire (ex. montant faux)', ok: 'Annuler le paiement');
                                    if (reason == null || reason.isEmpty) return;
                                    try {
                                      ExpenseRepo.cancel(p.expenseId, _uid, reason);
                                      setD(() {});
                                      if (mounted) setState(() {});
                                    } catch (e) {
                                      if (mounted) toast(context, e is StateError ? e.message : '$e', error: true);
                                    }
                                  },
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final name = await askText(context, 'Renommer', initial: c.label, ok: 'Enregistrer');
                  if (name == null || name.isEmpty) return;
                  c.label = name;
                  ChargesRepo.save(_uid, c);
                  if (d.mounted) Navigator.pop(d);
                  if (mounted) setState(() {});
                },
                child: const Text('Renommer'),
              ),
              TextButton(
                onPressed: () {
                  c.active = !c.active;
                  ChargesRepo.save(_uid, c);
                  Navigator.pop(d);
                  if (mounted) setState(() {});
                },
                child: Text(c.active ? 'Masquer' : 'Réafficher'),
              ),
              FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer')),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }
}

// ============================================================================ historique des dépenses

/// Toutes les dépenses d'une période, regroupées par type : salaires, fournisseurs, charges, divers…
class _ExpenseHistory extends StatefulWidget {
  const _ExpenseHistory();

  @override
  State<_ExpenseHistory> createState() => _ExpenseHistoryState();
}

class _ExpenseHistoryState extends State<_ExpenseHistory> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _type;

  @override
  Widget build(BuildContext context) {
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1);
    final all = ExpenseRepo.between(from, to);
    final active = all.where((e) => !e.cancelled).toList();
    final byType = <String, int>{};
    for (final e in active) {
      byType[e.category] = (byType[e.category] ?? 0) + e.amount;
    }
    final types = byType.keys.toList()..sort((a, b) => byType[b]!.compareTo(byType[a]!));
    final shown = _type == null ? all : all.where((e) => e.category == _type).toList();
    final total = active.fold<int>(0, (a, e) => a + e.amount);
    final isCurrent = _month.year == DateTime.now().year && _month.month == DateTime.now().month;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Historique des dépenses', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(fmtMonth(_month), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  IconButton(
                    onPressed: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Text('Total dépensé', style: TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(fmtDa(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(label: const Text('Tout'), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
                  for (final t in types)
                    ChoiceChip(
                      label: Text('$t · ${fmtDa(byType[t]!)}'),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = _type == t ? null : t),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('Aucune dépense sur cette période.', style: TextStyle(color: AppColors.textSecondary)))
                    : ListView(
                        children: [
                          for (final e in shown)
                            Opacity(
                              opacity: e.cancelled ? 0.45 : 1,
                              child: KeyValueRow(
                                e.cancelled ? '${e.label} (annulée)' : e.label,
                                fmtDa(e.amount),
                                sub: '${fmtDateTime(e.createdAt)} · ${e.category} · '
                                    '${e.source == 'caisse' ? 'de la caisse' : 'du coffre'}'
                                    '${e.userName.isEmpty ? '' : ' · ${e.userName}'}',
                              ),
                            ),
                        ],
                      ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================ fenêtre « bon d'achat »

class _Line {
  _Line(String name, {this.unit = 'kg'}) : name = TextEditingController(text: name);
  final TextEditingController name;
  final qty = TextEditingController();
  final price = TextEditingController();

  /// 'kg' ou 'pièce' : la quantité et le prix suivent cette unité.
  String unit;

  double get q => parseQty(qty.text) ?? 0;
  int get p => parseAmount(price.text) ?? 0;
  int get total => (q * p).round();

  void dispose() {
    name.dispose();
    qty.dispose();
    price.dispose();
  }
}

/// Bon d'achat d'un fournisseur, tel qu'on le reçoit : date, produits tapés à la main
/// (quantité ou kilos × prix), et ce qu'on lui donne maintenant.
/// Sans fournisseur ([supplier] null) : achat payé sur place (marché, dépannage).
class ReceptionDialog extends StatefulWidget {
  const ReceptionDialog({super.key, this.supplier});
  final Supplier? supplier;

  @override
  State<ReceptionDialog> createState() => _ReceptionDialogState();
}

class _ReceptionDialogState extends State<ReceptionDialog> {
  final _lines = <_Line>[];
  final _paid = TextEditingController();
  final _note = TextEditingController();
  String _source = 'caisse';
  DateTime _date = DateTime.now();
  bool _saving = false;

  Supplier? get _s => widget.supplier;

  @override
  void initState() {
    super.initState();
    _addLine(_s?.product ?? '');
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _paid.dispose();
    _note.dispose();
    super.dispose();
  }

  void _addLine(String name) {
    final l = _Line(name);
    if (name.isNotEmpty) {
      final last = StockRepo.lastPrice(name, l.unit);
      if (last > 0) l.price.text = '$last';
    }
    _lines.add(l);
  }

  int get _total => _lines.fold<int>(0, (a, l) => a + l.total);
  int get _paidNow => parseAmount(_paid.text) ?? 0;

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year - 1), lastDate: now);
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final valid = _lines.where((l) => l.name.text.trim().isNotEmpty && l.q > 0 && l.p > 0).toList();
    if (valid.isEmpty) {
      toast(context, 'Tapez au moins un produit avec sa quantité et son prix.', error: true);
      return;
    }
    final total = valid.fold<int>(0, (a, l) => a + l.total);
    final paid = _paidNow;
    if (paid > 0 && !Session.I.can(Perm.fournisseurs)) {
      toast(context, "Vous n'avez pas le droit de payer les fournisseurs : laissez « payé » vide.", error: true);
      return;
    }
    if (_s == null && paid != total) {
      toast(context, 'Sans fournisseur, le bon se paie en entier sur place.', error: true);
      return;
    }
    var source = _source;
    if (paid > 0) {
      final src = await ensureCashOpen(context, source);
      if (src == null || !mounted) return;
      source = src;
    }
    final uid = Session.I.user!.id;
    setState(() => _saving = true);
    try {
      StockRepo.receive(
        userId: uid,
        supplierId: _s?.id,
        lines: [for (final l in valid) ReceptionLine(StockRepo.articleNamed(uid, l.name.text, l.unit), l.q, l.p)],
        note: _note.text.trim(),
        supplierName: _s?.name ?? '',
        date: _sameDay(_date, DateTime.now()) ? null : _date,
      );
      if (paid > 0) {
        if (_s != null) {
          _s!.debt += total;
          SupplierRepo.pay(userId: uid, supplier: _s!, amount: paid, source: source, note: 'avec le bon');
        } else {
          SupplierRepo.payWithoutSupplier(userId: uid, amount: paid, source: source, label: 'Achat marchandise');
        }
      }
      if (!mounted) return;
      toast(context, "Bon d'achat enregistré : ${fmtDa(total)}${paid > 0 ? ', payé ${fmtDa(paid)}' : ', à crédit'}.");
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, e is StateError ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPay = Session.I.can(Perm.fournisseurs);
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final before = _s?.debt ?? 0;
    final after = before + _total - _paidNow;
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête : le fournisseur (fixe) et ce qu'on lui doit déjà.
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.receipt_long_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Bon d'achat", style: label),
                        Text(_s?.name ?? 'Achat sans fournisseur',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                      ],
                    ),
                  ),
                  if (_s != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(before < 0 ? 'Avance chez lui' : 'Déjà dû', style: label),
                        Text(fmtDa(before.abs()),
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: before > 0 ? AppColors.redText : AppColors.greenText)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Tout le contenu défile : le clavier de l'écran tactile ne cache jamais le champ en cours.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              // Date du bon
              Row(
                children: [
                  const Text('Date du bon', style: label),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        ChoiceChip(
                            label: const Text("Aujourd'hui"),
                            selected: _sameDay(_date, today),
                            onSelected: (_) => setState(() => _date = today)),
                        ChoiceChip(
                            label: const Text('Hier'),
                            selected: _sameDay(_date, yesterday),
                            onSelected: (_) => setState(() => _date = yesterday)),
                        ChoiceChip(
                          avatar: const Icon(Icons.calendar_today, size: 16),
                          label: Text(_sameDay(_date, today) || _sameDay(_date, yesterday) ? 'Autre date' : fmtDate(_date)),
                          selected: !_sameDay(_date, today) && !_sameDay(_date, yesterday),
                          onSelected: (_) => _pickDate(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Expanded(flex: 5, child: Text('Produit', style: label)),
                  SizedBox(width: 8),
                  SizedBox(width: 150, child: Text('Vendu au', style: label)),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('Quantité', style: label)),
                  SizedBox(width: 8),
                  Expanded(flex: 3, child: Text('Prix (DA)', style: label)),
                  SizedBox(width: 136),
                ],
              ),
              const SizedBox(height: 6),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in _lines)
                      Container(
                        key: ObjectKey(l),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: _WhiteField(controller: l.name, hint: 'ex. Viande', onChanged: (_) => setState(() {})),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 150,
                              child: IosSegmented<String>(
                                values: const ['kg', 'pièce'],
                                selected: l.unit,
                                label: (v) => v == 'kg' ? 'Kilo' : 'Pièce',
                                onChanged: (v) => setState(() => l.unit = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _WhiteField(
                                controller: l.qty,
                                hint: l.unit == 'kg' ? 'kg' : 'nombre',
                                decimal: true,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: _WhiteField(
                                controller: l.price,
                                hint: l.unit == 'kg' ? 'DA le kilo' : 'DA la pièce',
                                numeric: true,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text(fmtDa(l.total),
                                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                            ),
                            IconButton(
                              tooltip: 'Enlever la ligne',
                              onPressed: _lines.length <= 1
                                  ? null
                                  : () => setState(() {
                                        _lines.remove(l);
                                        l.dispose();
                                      }),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: 'Ajouter un produit',
                        child: Material(
                          color: AppColors.yellow,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => _addLine('')),
                            child: const SizedBox(width: 44, height: 44, child: Icon(Icons.add, size: 26)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const Divider(height: 22),
              Row(
                children: [
                  const Text('Total du bon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(fmtDa(_total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ],
              ),
              const SizedBox(height: 10),
              if (canPay) ...[
                Row(
                  children: [
                    Expanded(
                      child: FieldBox(
                        controller: _paid,
                        hint: _s == null ? 'Payé maintenant (en entier)' : 'Donné maintenant (vide = à crédit)',
                        numeric: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SecondaryButton(label: 'Montant du bon', onPressed: () => setState(() => _paid.text = '$_total')),
                    const SizedBox(width: 8),
                    IosSegmented<String>(
                      expand: false,
                      values: const ['caisse', 'coffre'],
                      selected: _source,
                      label: (v) => v == 'coffre' ? 'Du coffre' : 'De la caisse',
                      onChanged: (v) => setState(() => _source = v),
                    ),
                  ],
                ),
                if (_s != null && _total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      after > 0
                          ? 'Après ce bon : il restera ${fmtDa(after)} à lui payer.'
                          : after < 0
                              ? 'Après ce bon : ${fmtDa(-after)} d\'avance chez lui.'
                              : 'Après ce bon : vous ne lui devez plus rien.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: after > 0 ? AppColors.redText : AppColors.greenText,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              FieldBox(controller: _note, hint: 'Remarque, n° du bon (facultatif)'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
                  const SizedBox(width: 8),
                  PrimaryButton(label: 'Enregistrer le bon', onPressed: _saving ? null : _save),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Champ blanc, pour les lignes du bon posées sur fond gris.
class _WhiteField extends StatelessWidget {
  const _WhiteField({required this.controller, required this.hint, this.numeric = false, this.decimal = false, this.onChanged});
  final TextEditingController controller;
  final String hint;
  final bool numeric;
  final bool decimal;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(fillColor: Colors.white),
        ),
        child: FieldBox(controller: controller, hint: hint, numeric: numeric, decimal: decimal, onChanged: onChanged, fill: Colors.white),
      );
}
