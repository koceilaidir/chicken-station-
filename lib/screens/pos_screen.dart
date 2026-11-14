import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/repos.dart';
import '../data/settings.dart';
import '../hardware/hardware_service.dart';
import '../hardware/tickets.dart';
import '../state/session.dart';
import '../ui/touch_keyboard.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'day_dialogs.dart';

/// Écran de vente : familles, produits, bon en cours, encaissement.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Family> _families = [];
  final Map<int, List<Product>> _products = {};
  int? _familyId;
  final List<CartLine> _cart = [];
  String _mode = 'Sur place';
  bool _kitchenSent = false;

  /// Ce que la cuisine a déjà reçu pour la commande en attente reprise (produit + remarque → quantité).
  Map<String, int>? _sentToKitchen;
  Map<String, Product> _sentProducts = {};

  /// L'écran client ne répond pas : on le dit une fois par session, sans bloquer la vente.
  static bool _displayWarned = false;
  void _displayError(Object e) {
    if (_displayWarned || !mounted) return;
    _displayWarned = true;
    toast(context, "Écran client : $e Réglez-le dans Réglages › Matériel › Trouver l'afficheur.", error: true);
  }

  static String _key(CartLine l) => '${l.product.id}|${l.note}';

  Map<String, int> _snapshot(List<CartLine> lines) {
    final m = <String, int>{};
    for (final l in lines) {
      m[_key(l)] = (m[_key(l)] ?? 0) + l.qty;
    }
    return m;
  }

  /// Commande modifiée : la cuisine ne reçoit que ce qui a été ajouté (et ce qui est à enlever).
  Future<void> _kitchenChanges({required int number, required String cashier, required List<CartLine> lines}) async {
    final before = _sentToKitchen;
    if (before == null) {
      await _kitchen(number: number, mode: _mode, cashier: cashier, lines: lines, banner: 'COMMANDE MODIFIÉE');
      return;
    }
    final now = _snapshot(lines);
    final byKey = {for (final l in lines) _key(l): l};
    final added = <CartLine>[];
    for (final e in now.entries) {
      final d = e.value - (before[e.key] ?? 0);
      if (d > 0) added.add(CartLine(product: byKey[e.key]!.product, qty: d, note: byKey[e.key]!.note));
    }
    final removed = <CartLine>[];
    final products = _sentProducts;
    for (final e in before.entries) {
      final d = e.value - (now[e.key] ?? 0);
      final product = byKey[e.key]?.product ?? products[e.key];
      if (d > 0 && product != null) {
        final note = e.key.substring(e.key.indexOf('|') + 1);
        removed.add(CartLine(product: product, qty: d, note: note.isEmpty ? 'À ENLEVER' : '$note · À ENLEVER'));
      }
    }
    if (added.isEmpty && removed.isEmpty) return;
    await _kitchen(
      number: number,
      mode: _mode,
      cashier: cashier,
      lines: [...added, ...removed],
      banner: removed.isEmpty ? 'AJOUT' : 'COMMANDE MODIFIÉE',
    );
  }
  bool _busy = false;

  /// Commande en attente reprise dans le panier (null = nouvelle commande).
  int? _pendingId;
  int? _pendingNumber;
  final _search = TextEditingController();

  static const _modes = ['Sur place', 'À emporter', 'Livraison'];

  HardwareService get _hw => HardwareService.I;


  /// Bon cuisine avec seulement les produits à préparer. Commande sans rien à cuisiner (boissons) : pas de bon.
  Future<void> _kitchen({
    required int number,
    required String mode,
    required String cashier,
    required List<CartLine> lines,
    String? banner,
  }) async {
    final cook = MenuRepo.kitchenFamilies();
    final toCook = lines.where((l) => cook.contains(l.product.familyId)).toList();
    if (toCook.isEmpty) return;
    await _hw.printKitchen(Tickets.kitchen(number: number, mode: mode, cashier: cashier, lines: toCook, banner: banner));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    final fams = MenuRepo.families(onlyActive: true);
    _products.clear();
    for (final f in fams) {
      _products[f.id] = MenuRepo.products(f.id, onlyActive: true);
    }
    setState(() {
      _families = fams.where((f) => (_products[f.id] ?? []).isNotEmpty).toList();
      if (_families.isNotEmpty && !_families.any((f) => f.id == _familyId)) {
        _familyId = _families.first.id;
      }
    });
  }

  int get _total => _cart.fold(0, (a, l) => a + l.total);
  int get _count => _cart.fold(0, (a, l) => a + l.qty);

  Map<int, String> get _familyNames => {for (final f in _families) f.id: f.name};

  void _cartChanged() {
    _kitchenSent = false;
    _hw.showAmount(fmtDisplay(_total)).catchError(_displayError);
  }

  void _add(Product p) {
    setState(() {
      final i = _cart.indexWhere((l) => l.product.id == p.id && l.note.isEmpty);
      if (i >= 0) {
        _cart[i].qty++;
      } else {
        _cart.add(CartLine(product: p));
      }
    });
    _cartChanged();
  }

  void _bump(CartLine l, int d) {
    setState(() {
      l.qty += d;
      if (l.qty <= 0) _cart.remove(l);
    });
    _cartChanged();
  }

  Future<void> _editNote(CartLine l) async {
    final note = await askText(context, 'Remarque pour la cuisine', hint: 'ex. sans oignon', initial: l.note);
    if (note == null) return;
    setState(() => l.note = note);
    _kitchenSent = false;
  }

  void _clear() {
    final kept = _pendingNumber;
    setState(() {
      _cart.clear();
      _kitchenSent = false;
      _pendingId = null;
      _sentToKitchen = null;
      _pendingNumber = null;
    });
    _hw.clearDisplay().catchError((_) {});
    if (kept != null) toast(context, 'La commande n° ${_n(kept)} reste en attente.');
  }

  static String _n(int number) => number.toString().padLeft(3, '0');

  /// Vérifie qu'une journée est ouverte ; sinon propose de l'ouvrir.
  Future<Day?> _ensureDay() async {
    final d = DayRepo.current();
    if (d != null) return d;
    if (!mounted) return null;
    if (!Session.I.can(Perm.cloture)) {
      toast(context, "La journée n'est pas ouverte. Demandez au gérant d'ouvrir la caisse.", error: true);
      return null;
    }
    return openDayDialog(context);
  }

  /// « Payer après » : le bon part en cuisine, la commande est gardée en attente de paiement.
  Future<void> _hold() async {
    if (_cart.isEmpty || _busy) return;
    final day = await _ensureDay();
    if (day == null || !mounted) return;
    final user = Session.I.user!;
    final lines = List<CartLine>.from(_cart);
    final wasPending = _pendingId != null;
    final mustPrint = !_kitchenSent;
    final before = _sentToKitchen;
    final r = SaleRepo.hold(
      dayId: day.id,
      userId: user.id,
      mode: _mode,
      lines: lines,
      familyNames: _familyNames,
      saleId: _pendingId,
    );
    String? error;
    if (mustPrint) {
      try {
        if (wasPending) {
          _sentToKitchen = before;
          await _kitchenChanges(number: r.number, cashier: user.name, lines: lines);
        } else {
          await _kitchen(number: r.number, mode: _mode, cashier: user.name, lines: lines);
        }
      } catch (e) {
        error = '$e';
      }
    }
    if (!mounted) return;
    setState(() {
      _cart.clear();
      _kitchenSent = false;
      _pendingId = null;
      _sentToKitchen = null;
      _pendingNumber = null;
    });
    _hw.clearDisplay().catchError((_) {});
    if (error != null) {
      toast(context, 'Commande n° ${_n(r.number)} en attente, mais cuisine : $error', error: true);
    } else {
      toast(context, 'Commande n° ${_n(r.number)} ${mustPrint ? 'envoyée en cuisine' : 'remise'} en attente de paiement.');
    }
  }

  /// Remet une commande en attente dans le panier pour l'encaisser ou la modifier.
  Future<void> _resume(Map<String, Object?> sale) async {
    if (_cart.isNotEmpty && _pendingId != sale['id']) {
      final ok = await confirm(
        context,
        'Remplacer la commande en cours ?',
        _pendingId != null
            ? 'La commande n° ${_n(_pendingNumber!)} reste en attente.'
            : 'Les articles de la commande en cours seront retirés.',
        ok: 'Remplacer',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(SaleRepo.lines(sale['id'] as int));
      _mode = sale['mode'] as String;
      _pendingId = sale['id'] as int;
      _pendingNumber = sale['number'] as int;
      _kitchenSent = true;
      _sentToKitchen = _snapshot(_cart);
      _sentProducts = {for (final l in _cart) _key(l): l.product};
    });
    _hw.showAmount(fmtDisplay(_total)).catchError(_displayError);
  }

  /// Annule une commande (en attente ou payée), motif facultatif ; prévient la cuisine si elle n'était pas payée.
  Future<bool> _cancelSale(Map<String, Object?> sale) async {
    if (!Session.I.can(Perm.annuler)) {
      toast(context, "Vous n'avez pas le droit d'annuler. Demandez au gérant.", error: true);
      return false;
    }
    final pending = sale['status'] == 'pending';
    final number = sale['number'] as int;
    final reason = await askText(
      context,
      pending ? 'Annuler la commande n° ${_n(number)}' : 'Annuler le ticket n° ${_n(number)}',
      hint: 'Motif (facultatif)',
      ok: 'Annuler la commande',
    );
    if (reason == null || !mounted) return false;
    final id = sale['id'] as int;
    final lines = SaleRepo.lines(id);
    SaleRepo.cancel(id, Session.I.user!.id, reason);
    if (_pendingId == id) {
      setState(() {
        _cart.clear();
        _kitchenSent = false;
        _pendingId = null;
        _sentToKitchen = null;
        _pendingNumber = null;
      });
      _hw.clearDisplay().catchError((_) {});
    }
    String? error;
    try {
      await _kitchen(
        number: number,
        mode: sale['mode'] as String,
        cashier: Session.I.user!.name,
        lines: lines,
        banner: 'COMMANDE ANNULÉE',
      );
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return true;
    final refund = !pending && sale['payment'] == 'cash' ? sale['total'] as int : 0;
    final parts = [
      '${pending ? 'Commande' : 'Ticket'} n° ${_n(number)} annulé',
      if (refund > 0) 'rendez ${fmtDa(refund)} au client',
      if (error != null) 'cuisine non prévenue : $error',
    ];
    toast(context, parts.join(' · '), error: error != null);
    return true;
  }

  Future<void> _showPending() async {
    final day = DayRepo.current();
    if (day == null) {
      toast(context, 'Aucune journée ouverte.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => _SalesDialog(
        title: 'Commandes en attente',
        subtitle: 'Envoyées en cuisine, pas encore payées',
        load: () => SaleRepo.pending(day.id).map((m) => {...m, 'status': 'pending'}).toList(),
        empty: 'Aucune commande en attente.',
        onResume: (sale) {
          Navigator.pop(c);
          _resume(sale);
        },
        onCancel: _cancelSale,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pay(String payment) async {
    if (_cart.isEmpty || _busy) return;
    final day = await _ensureDay();
    if (day == null || !mounted) return;
    int? cashGiven;
    if (payment == 'cash') {
      cashGiven = await _askCash(_total);
      if (cashGiven == null) return;
    }
    setState(() => _busy = true);
    final user = Session.I.user!;
    final lines = List<CartLine>.from(_cart);
    final wasPending = _pendingId != null;
    final pendingBefore = _pendingId;
    final number = SaleRepo.record(
      dayId: day.id,
      userId: user.id,
      mode: _mode,
      payment: payment,
      lines: lines,
      familyNames: _familyNames,
      cashGiven: cashGiven,
      saleId: _pendingId,
    );
    final errors = <String>[];
    if (!_kitchenSent) {
      try {
        if (wasPending && pendingBefore != null) {
          await _kitchenChanges(number: number, cashier: user.name, lines: lines);
        } else {
          await _kitchen(number: number, mode: _mode, cashier: user.name, lines: lines);
        }
      } catch (e) {
        errors.add('Cuisine : $e');
      }
    }
    try {
      await _hw.printTicket(Tickets.customer(
        number: number,
        mode: _mode,
        cashier: user.name,
        lines: lines,
        payment: payment,
        cashGiven: cashGiven,
      ));
    } catch (e) {
      errors.add('Ticket : $e');
    }
    if (payment == 'cash') {
      try {
        await _hw.openDrawer();
      } catch (e) {
        errors.add('Tiroir : $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _cart.clear();
      _kitchenSent = false;
      _pendingId = null;
      _sentToKitchen = null;
      _pendingNumber = null;
    });
    // L'écran client garde le total quelques secondes, puis s'efface pour le client suivant.
    Future<void>.delayed(const Duration(seconds: 6), () {
      if (mounted && _cart.isEmpty) _hw.clearDisplay().catchError((_) {});
    });
    final rendu = cashGiven != null ? cashGiven - lines.fold<int>(0, (a, l) => a + l.total) : 0;
    if (errors.isEmpty) {
      toast(context, 'Ticket n° $number payé${rendu > 0 ? ' · rendu ${fmtDa(rendu)}' : ''}');
    } else {
      toast(context, 'Vente n° $number enregistrée, mais : ${errors.join(' · ')}', error: true);
    }
  }

  Future<int?> _askCash(int total) {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        final given = parseAmount(ctrl.text) ?? total;
        final rendu = given - total;
        final options = <int>{total, ...[500, 1000, 2000, 5000].where((v) => v > total), ((total / 1000).ceil() * 1000)}
            .where((v) => v >= total)
            .toList()
          ..sort();
        return AlertDialog(scrollable: true, 
          title: Text('Encaisser ${fmtDa(total)}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Espèces reçues', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                FieldBox(controller: ctrl, hint: fmtNum(total), numeric: true, big: true, autofocus: true, onChanged: (_) => setD(() {})),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in options)
                      ActionChip(
                        label: Text(v == total ? 'Compte juste' : fmtDa(v)),
                        onPressed: () => setD(() => ctrl.text = '$v'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: rendu < 0 ? AppColors.redSoft : AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(rendu < 0 ? 'Il manque' : 'À rendre',
                          style: TextStyle(fontWeight: FontWeight.w700, color: rendu < 0 ? AppColors.redText : AppColors.greenText)),
                      const Spacer(),
                      Text(fmtDa(rendu.abs()),
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800, color: rendu < 0 ? AppColors.redText : AppColors.greenText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Retour')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.text),
              onPressed: rendu < 0 ? null : () => Navigator.pop(c, given),
              child: const Text('Valider le paiement'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _openDrawerNoSale() async {
    final reason = await askText(context, 'Ouvrir le tiroir sans vente', hint: 'Motif (ex. faire la monnaie)');
    if (reason == null || reason.isEmpty) return;
    try {
      await _hw.openDrawer();
      AppDb.I.audit(Session.I.user!.id, 'tiroir_sans_vente', reason);
    } catch (e) {
      if (mounted) toast(context, 'Tiroir : $e', error: true);
    }
  }

  Future<void> _showLastTickets() async {
    final day = DayRepo.current();
    if (day == null) {
      toast(context, "Aucune journée ouverte.");
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => _SalesDialog(
        title: 'Derniers tickets',
        subtitle: "Aujourd'hui · les annulations sont tracées (qui, quand, motif éventuel)",
        load: () => SaleRepo.lastSales(day.id),
        empty: "Aucun ticket aujourd'hui.",
        onResume: (sale) {
          Navigator.pop(c);
          _resume(sale);
        },
        onCancel: _cancelSale,
      ),
    );
    if (mounted) setState(() {});
  }

  // ======================================================================== UI

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final List<Product> items;
    if (q.isNotEmpty) {
      items = [for (final list in _products.values) ...list.where((p) => p.name.toLowerCase().contains(q))];
    } else {
      items = _products[_familyId] ?? [];
    }
    final fam = _families.where((f) => f.id == _familyId).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) => Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topBar(),
                const SizedBox(height: 14),
                _familyStrip(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(q.isNotEmpty ? 'Recherche' : (fam?.name ?? ''),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${items.length} articles', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      mainAxisExtent: 196,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (c, i) => _productCard(items[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
        _cartPanel(box.maxWidth < 950 ? 300 : 340),
      ],
    ),
    );
  }

  Widget _topBar() {
    final day = DayRepo.current();
    final pendingCount = day == null ? 0 : SaleRepo.pendingCount(day.id);
    return LayoutBuilder(
      builder: (context, c) {
        // Petits écrans (1024×768…) : boutons en icônes, recherche plus étroite, puis sur deux lignes.
        final compact = c.maxWidth < 760;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Caisse', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            Text(
              day == null ? 'Journée non ouverte' : 'Journée ouverte à ${fmtTime(day.openedAt)} · ${Session.I.user?.name ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: day == null ? AppColors.redText : AppColors.textSecondary),
            ),
          ],
        );
        final search = SizedBox(
          height: 40,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            readOnly: TouchKeyboard.enabled,
            showCursor: true,
            onTap: TouchKeyboard.enabled
                ? () => TouchKeyboard.open(_search, onChanged: (_) => setState(() {}))
                : null,
            decoration: InputDecoration(
              hintText: 'Rechercher',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: const Color(0xFFE9E9EE),
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        );
        final buttons = <Widget>[
          const SizedBox(width: 8),
          _TopButton(
            icon: Icons.schedule,
            label: compact
                ? (pendingCount == 0 ? null : '$pendingCount')
                : (pendingCount == 0 ? 'En attente' : 'En attente · $pendingCount'),
            tooltip: 'Commandes en attente de paiement',
            highlight: pendingCount > 0,
            onPressed: _showPending,
          ),
          const SizedBox(width: 6),
          _TopButton(
            icon: Icons.receipt_long_outlined,
            label: compact ? null : 'Tickets',
            tooltip: 'Derniers tickets (annuler, reprendre)',
            onPressed: _showLastTickets,
          ),
          if (Session.I.can(Perm.tiroir)) ...[
            const SizedBox(width: 6),
            _TopButton(
              icon: Icons.inbox_outlined,
              label: compact ? null : 'Tiroir',
              tooltip: 'Ouvrir le tiroir sans vente',
              onPressed: _openDrawerNoSale,
            ),
          ],
          IconButton(tooltip: 'Recharger le menu', onPressed: _load, icon: const Icon(Icons.refresh)),
        ];
        if (c.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 8),
              Row(children: [Expanded(child: search), ...buttons]),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 8),
            SizedBox(width: compact ? 170 : (c.maxWidth < 960 ? 180 : 220), child: search),
            ...buttons,
          ],
        );
      },
    );
  }

  Widget _familyStrip() {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _families.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (c, i) {
          final f = _families[i];
          final sel = f.id == _familyId && _search.text.isEmpty;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              _familyId = f.id;
              _search.clear();
            }),
            child: SizedBox(
              width: 74,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sel ? AppColors.yellow : Colors.white,
                    ),
                    child: PhotoBox(photo: f.photo, size: 52, radius: 26, fallback: f.name),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? AppColors.text : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _productCard(Product p) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _add(p),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhotoBox(photo: p.photo, width: double.infinity, height: 104, fallback: p.name),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(fmtDa(p.price), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
                      child: const Icon(Icons.add, size: 18, color: AppColors.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartPanel(double width) {
    return Container(
      width: width,
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(_pendingNumber == null ? 'Commande' : 'Commande n° ${_n(_pendingNumber!)}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_cart.isNotEmpty)
                      IconButton(
                        tooltip: _pendingId != null ? 'Fermer (la commande reste en attente)' : 'Vider la commande',
                        onPressed: _clear,
                        style: IconButton.styleFrom(
                          backgroundColor: _pendingId != null ? AppColors.fill : AppColors.redSoft,
                        ),
                        icon: Icon(
                          _pendingId != null ? Icons.close : Icons.delete_outline,
                          color: _pendingId != null ? AppColors.text : AppColors.redText,
                        ),
                      ),
                  ],
                ),
                if (_pendingId != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('En attente de paiement · déjà en cuisine', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        InkWell(
                          onTap: () => _cancelSale({
                            'id': _pendingId,
                            'number': _pendingNumber,
                            'status': 'pending',
                            'mode': _mode,
                            'total': _total,
                          }),
                          child: const Text('Annuler', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.redText)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                IosSegmented<String>(
                  values: _modes,
                  selected: _mode,
                  label: (m) => m,
                  onChanged: (m) => setState(() {
                    _mode = m;
                    _kitchenSent = false;
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? const Center(
                    child: Text('Touchez un plat pour l\'ajouter', style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F3)),
                    itemBuilder: (c, i) => _cartLine(_cart[i]),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.separator))),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('$_count article(s) · $_mode', style: const TextStyle(color: AppColors.textSecondary)),
                    const Spacer(),
                    if (_pendingId != null && !_kitchenSent)
                      const Text('modifiée', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A6A00))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(fmtDa(_total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: 'Envoie le bon en cuisine et garde la commande en attente : on encaisse quand le client paie',
                        child: SecondaryButton(label: 'Payer après', onPressed: _cart.isEmpty || _busy ? null : _hold),
                      ),
                    ),
                    if (Settings.tpe) ...[
                      const SizedBox(width: 8),
                      Expanded(child: SecondaryButton(label: 'TPE', onPressed: _cart.isEmpty ? null : () => _pay('card'))),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.yellow,
                      foregroundColor: AppColors.text,
                      disabledBackgroundColor: AppColors.fill,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    onPressed: _cart.isEmpty || _busy ? null : () => _pay('cash'),
                    child: Text(_cart.isEmpty ? 'Encaisser' : 'Encaisser · ${fmtDa(_total)}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartLine(CartLine l) {
    return InkWell(
      onLongPress: () => _editNote(l),
      onDoubleTap: () => _editNote(l),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            PhotoBox(photo: l.product.photo, size: 46, fallback: l.product.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(fmtDa(l.total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  if (l.note.isNotEmpty)
                    Text('+ ${l.note}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => _bump(l, -1), icon: const Icon(Icons.remove, size: 18)),
                  Text('${l.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => _bump(l, 1), icon: const Icon(Icons.add, size: 18)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton à icône et texte de la barre du haut (icône seule sur petit écran).
class _TopButton extends StatelessWidget {
  const _TopButton({required this.icon, required this.label, required this.onPressed, this.highlight = false, this.tooltip = ''});

  final IconData icon;
  final String? label;
  final String tooltip;
  final VoidCallback onPressed;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          style: IconButton.styleFrom(
            backgroundColor: highlight ? AppColors.yellow : const Color(0xFFE9E9EE),
            foregroundColor: AppColors.text,
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          backgroundColor: highlight ? AppColors.yellow : const Color(0xFFE9E9EE),
          foregroundColor: AppColors.text,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label!),
      ),
    );
  }
}

/// Liste de commandes (en attente, ou derniers tickets) avec reprise et annulation tracée.
class _SalesDialog extends StatefulWidget {
  const _SalesDialog({
    required this.title,
    required this.subtitle,
    required this.load,
    required this.empty,
    required this.onResume,
    required this.onCancel,
  });

  final String title;
  final String subtitle;
  final List<Map<String, Object?>> Function() load;
  final String empty;
  final void Function(Map<String, Object?> sale) onResume;
  final Future<bool> Function(Map<String, Object?> sale) onCancel;

  @override
  State<_SalesDialog> createState() => _SalesDialogState();
}

class _SalesDialogState extends State<_SalesDialog> {
  @override
  Widget build(BuildContext context) {
    final sales = widget.load();
    final canCancel = Session.I.can(Perm.annuler);
    return AlertDialog(scrollable: true, 
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(widget.subtitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary)),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 440,
        child: sales.isEmpty
            ? Center(child: Text(widget.empty, style: const TextStyle(color: AppColors.textSecondary)))
            : ListView.separated(
                itemCount: sales.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F3)),
                itemBuilder: (c, i) => _row(sales[i], canCancel),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }

  Widget _row(Map<String, Object?> s, bool canCancel) {
    final status = s['status'] as String;
    final cancelled = status == 'cancelled';
    final pending = status == 'pending';
    final number = (s['number'] as int).toString().padLeft(3, '0');
    final time = fmtTime(DateTime.parse(s['created_at'] as String));
    final how = pending ? 'non payée' : (s['payment'] == 'card' ? 'TPE' : 'Espèces');
    final (tag, tagColor, tagBg) = switch (status) {
      'cancelled' => ('Annulé', AppColors.redText, AppColors.redSoft),
      'pending' => ('En attente', const Color(0xFF8A6A00), AppColors.yellowSoft),
      _ => ('Payé', AppColors.greenText, AppColors.greenSoft),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('N° $number · ${fmtDa(s['total'] as int)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          decoration: cancelled ? TextDecoration.lineThrough : null,
                          color: cancelled ? AppColors.textSecondary : AppColors.text,
                        )),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(6)),
                      child: Text(tag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tagColor)),
                    ),
                  ],
                ),
                Text(
                  [time, how, s['mode'], s['user_name'] ?? '', if (s['items'] != null) '${s['items']} article(s)']
                      .where((x) => '$x'.isNotEmpty)
                      .join(' · '),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                if (cancelled && (s['cancel_reason'] as String? ?? '').isNotEmpty)
                  Text('Motif : ${s['cancel_reason']}', style: const TextStyle(fontSize: 12, color: AppColors.redText)),
              ],
            ),
          ),
          if (pending)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.text),
                onPressed: () => widget.onResume(s),
                child: const Text('Reprendre'),
              ),
            ),
          if (!cancelled && canCancel)
            TextButton(
              onPressed: () async {
                if (await widget.onCancel(s) && mounted) setState(() {});
              },
              child: const Text('Annuler', style: TextStyle(color: AppColors.redText)),
            ),
        ],
      ),
    );
  }
}
