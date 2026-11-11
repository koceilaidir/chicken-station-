import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/purchasing.dart';
import '../data/stock.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../data/repos.dart';
import 'purchasing_screen.dart';

enum _Tab {
  suppliers('Fournisseurs'),
  employees('Employés'),
  charges('Charges');

  const _Tab(this.label);
  final String label;
}

const _units = ['pièce', 'kg', 'g', 'L', 'cl', 'tranche', 'paquet', 'boîte', 'bouteille', 'canette', 'carton', 'sac'];

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

  Future<void> _newBon() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const ReceptionDialog());
    if (ok == true && mounted) setState(() {});
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
            if (Session.I.can(Perm.reception)) PrimaryButton(label: "+ Bon d'achat", onPressed: _newBon),
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
          return AlertDialog(
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

// ============================================================================ fenêtre « bon d'achat »

class _Line {
  _Line(this.ingredient) : price = TextEditingController(text: ingredient.cost > 0 ? '${ingredient.cost}' : '');
  Ingredient ingredient;
  final qty = TextEditingController(text: '1');
  final TextEditingController price;

  double get q => parseQty(qty.text) ?? 0;
  int get p => parseAmount(price.text) ?? 0;
  int get total => (q * p).round();
}

/// Saisie d'un bon d'achat tel qu'on le reçoit : date, fournisseur, articles (quantité × prix), payé ou à crédit.
class ReceptionDialog extends StatefulWidget {
  const ReceptionDialog({super.key, this.supplierId});
  final int? supplierId;

  @override
  State<ReceptionDialog> createState() => _ReceptionDialogState();
}

class _ReceptionDialogState extends State<ReceptionDialog> {
  late List<Ingredient> _ings = StockRepo.ingredients(onlyActive: true);
  late List<Supplier> _suppliers = SupplierRepo.all(onlyActive: true);
  int? _supplierId;
  final _lines = <_Line>[];
  final _paid = TextEditingController();
  final _note = TextEditingController();
  String _source = 'coffre';
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.supplierId;
    if (_ings.isNotEmpty) _lines.add(_Line(_ings.first));
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.qty.dispose();
      l.price.dispose();
    }
    _paid.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _total => _lines.fold<int>(0, (a, l) => a + l.total);

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _newSupplier() async {
    final name = await askText(context, 'Nouveau fournisseur', hint: 'Nom');
    if (name == null || name.isEmpty) return;
    final id = SupplierRepo.add(Session.I.user!.id, name, '');
    setState(() {
      _suppliers = SupplierRepo.all(onlyActive: true);
      _supplierId = id;
    });
  }

  /// Crée un article qui n'est pas dans la liste et le met sur [line] (ou sur une nouvelle ligne).
  Future<void> _newArticle(_Line? line) async {
    final name = await askText(context, 'Nouvel article', hint: "Nom (ex. Huile d'olive)");
    if (name == null || name.isEmpty || !mounted) return;
    final unit = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Unité de « $name »'),
        content: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final u in _units) ActionChip(label: Text(u), onPressed: () => Navigator.pop(c, u))],
        ),
      ),
    );
    if (unit == null) return;
    final id = StockRepo.addIngredient(Session.I.user!.id, name, unit);
    setState(() {
      _ings = StockRepo.ingredients(onlyActive: true);
      final created = _ings.firstWhere((i) => i.id == id);
      if (line == null) {
        _lines.add(_Line(created));
      } else {
        line.ingredient = created;
        line.price.text = '';
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year - 1), lastDate: now);
    if (d != null) setState(() => _date = d);
  }

  void _save() {
    final valid = _lines.where((l) => l.q > 0 && l.p > 0).toList();
    if (valid.isEmpty) {
      toast(context, 'Indiquez au moins un article avec sa quantité et son prix.', error: true);
      return;
    }
    final paid = parseAmount(_paid.text) ?? 0;
    final total = valid.fold<int>(0, (a, l) => a + l.total);
    if (paid < 0 || paid > total) {
      toast(context, 'Le montant payé doit être entre 0 et ${fmtDa(total)}.', error: true);
      return;
    }
    if (paid > 0 && !Session.I.can(Perm.fournisseurs)) {
      toast(context, "Vous n'avez pas le droit de payer les fournisseurs : laissez « payé » vide.", error: true);
      return;
    }
    final supplier = _suppliers.where((s) => s.id == _supplierId).firstOrNull;
    if (supplier == null && paid < total) {
      toast(context, 'Sans fournisseur, le bon doit être payé en entier (personne à qui devoir le reste).', error: true);
      return;
    }
    final uid = Session.I.user!.id;
    setState(() => _saving = true);
    try {
      StockRepo.receive(
        userId: uid,
        supplierId: supplier?.id,
        lines: [for (final l in valid) ReceptionLine(l.ingredient, l.q, l.p)],
        note: _note.text.trim(),
        supplierName: supplier?.name ?? '',
        date: _sameDay(_date, DateTime.now()) ? null : _date,
      );
      if (paid > 0) {
        if (supplier != null) {
          supplier.debt += total;
          SupplierRepo.pay(userId: uid, supplier: supplier, amount: paid, source: _source, note: 'avec le bon');
        } else {
          SupplierRepo.payWithoutSupplier(userId: uid, amount: paid, source: _source, label: 'Achat marchandise');
        }
      }
      toast(context, "Bon d'achat enregistré : ${valid.length} article(s), ${fmtDa(total)}.");
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPay = Session.I.can(Perm.fournisseurs);
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    return AlertDialog(
      title: const Text("Bon d'achat"),
      content: SizedBox(
        width: 780,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Fournisseur'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Sans fournisseur (marché, dépannage…)')),
                      for (final s in _suppliers)
                        DropdownMenuItem<int?>(value: s.id, child: Text('${s.name}${s.debt > 0 ? ' · doit ${fmtDa(s.debt)}' : ''}')),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                ),
                if (canPay) TextButton(onPressed: _newSupplier, child: const Text('+ Nouveau')),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Date du bon :  ', style: TextStyle(color: AppColors.textSecondary)),
                ChoiceChip(label: const Text("Aujourd'hui"), selected: _sameDay(_date, today), onSelected: (_) => setState(() => _date = today)),
                ChoiceChip(label: const Text('Hier'), selected: _sameDay(_date, yesterday), onSelected: (_) => setState(() => _date = yesterday)),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_sameDay(_date, today) || _sameDay(_date, yesterday) ? 'Autre date' : fmtDate(_date)),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(flex: 4, child: Text('Article', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                SizedBox(width: 8),
                Expanded(flex: 2, child: Text('Quantité', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                SizedBox(width: 8),
                Expanded(flex: 2, child: Text('Prix unitaire (DA)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                SizedBox(width: 148),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final l in _lines)
                    Padding(
                      key: ObjectKey(l),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<int>(
                              key: ValueKey('${identityHashCode(l)}-${l.ingredient.id}-${_ings.length}'),
                              initialValue: l.ingredient.id,
                              isExpanded: true,
                              items: [for (final i in _ings) DropdownMenuItem(value: i.id, child: Text('${i.name} (${i.unit})'))],
                              onChanged: (v) => setState(() {
                                l.ingredient = _ings.firstWhere((i) => i.id == v);
                                // Prix proposé : le dernier payé pour cet article.
                                l.price.text = l.ingredient.cost > 0 ? '${l.ingredient.cost}' : '';
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: FieldBox(controller: l.qty, hint: l.ingredient.unit, onChanged: (_) => setState(() {}))),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: FieldBox(controller: l.price, hint: 'DA / ${l.ingredient.unit}', numeric: true, onChanged: (_) => setState(() {})),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(fmtDa(l.total), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            onPressed: _lines.length <= 1 ? null : () => setState(() => _lines.remove(l)),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (_ings.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => setState(() => _lines.add(_Line(_ings.first))),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter une ligne'),
                        ),
                      TextButton.icon(
                        onPressed: () => _newArticle(null),
                        icon: const Icon(Icons.fiber_new_outlined),
                        label: const Text('Article pas dans la liste'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                const Text('Total du bon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(fmtDa(_total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            if (canPay)
              Row(
                children: [
                  Expanded(
                    child: FieldBox(
                      controller: _paid,
                      hint: _supplierId == null ? 'Payé maintenant (en entier)' : 'Payé maintenant (vide = à crédit)',
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(onPressed: () => setState(() => _paid.text = '$_total'), child: const Text('Tout payé')),
                  const SizedBox(width: 6),
                  IosSegmented<String>(
                    expand: false,
                    values: const ['coffre', 'caisse'],
                    selected: _source,
                    label: (v) => v == 'coffre' ? 'Du coffre' : 'De la caisse',
                    onChanged: (v) => setState(() => _source = v),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            FieldBox(controller: _note, hint: 'N° du bon, remarque…'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.text),
          onPressed: _saving ? null : _save,
          child: const Text('Enregistrer le bon'),
        ),
      ],
    );
  }
}
