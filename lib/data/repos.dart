import 'dart:async';

import 'package:sqlite3/sqlite3.dart' hide Session;

import '../state/session.dart';
import '../ui/format.dart';
import 'db.dart';
import 'models.dart';

Database get _db => AppDb.I.db;

/// Note une action de l'utilisateur connecté dans le journal d'activité.
void logActivity(String action, [String detail = '']) => AppDb.I.audit(Session.I.user?.id, action, detail);

/// Les fiches (produit, utilisateur) s'enregistrent à chaque touche tapée. Pour le journal, on attend
/// 2 secondes sans modification puis on note UNE ligne : « prix 600 → 650 DA » et pas « 6 », « 65 »…
class _PendingLog {
  _PendingLog(this.before);
  final Map<String, Object?> before;
  Timer? timer;
}

final _pendingLogs = <String, _PendingLog>{};

void _deferLog(String key, Map<String, Object?> Function() before, void Function(Map<String, Object?> before) flush) {
  final p = _pendingLogs.putIfAbsent(key, () => _PendingLog(before()));
  p.timer?.cancel();
  p.timer = Timer(const Duration(seconds: 2), () {
    _pendingLogs.remove(key);
    if (AppDb.isOpen) flush(p.before);
  });
}

// ============================================================================ utilisateurs

class UserRepo {
  static List<AppUser> all({bool onlyActive = false}) => _db
      .select('SELECT * FROM users WHERE deleted = 0 ${onlyActive ? 'AND active = 1' : ''} ORDER BY id')
      .map(AppUser.fromRow)
      .toList();

  static AppUser? byId(int id) {
    final r = _db.select('SELECT * FROM users WHERE id = ?', [id]);
    return r.isEmpty ? null : AppUser.fromRow(r.first);
  }

  static bool checkPin(AppUser u, String pin) => u.pinHash == hashPin(pin);

  static int create(String name, String pin, String role, Set<String> perms) {
    _db.execute(
      'INSERT INTO users (name, pin_hash, role, perms, active) VALUES (?, ?, ?, ?, 1)',
      [name, hashPin(pin), role, perms.join(',')],
    );
    final id = _db.lastInsertRowId;
    logActivity('utilisateur_cree', '$name · ${Perm.roleLabels[role] ?? role}');
    return id;
  }

  static Map<String, Object?> _snapshot(int id) {
    final r = _db.select('SELECT name, role, perms, active FROM users WHERE id = ?', [id]);
    return r.isEmpty ? {} : Map<String, Object?>.from(r.first);
  }

  static void save(AppUser u) {
    _deferLog('user${u.id}', () => _snapshot(u.id), (before) {
      final now = _snapshot(u.id);
      if (before.isEmpty || now.isEmpty) return;
      final changes = <String>[];
      if (before['name'] != now['name']) changes.add('nom : ${before['name']} → ${now['name']}');
      if (before['role'] != now['role']) changes.add('rôle : ${Perm.roleLabels[now['role']] ?? now['role']}');
      if (before['perms'] != now['perms']) changes.add('droits modifiés');
      if (before['active'] != now['active']) changes.add(now['active'] == 1 ? 'réactivé' : 'désactivé');
      if (changes.isNotEmpty) logActivity('utilisateur_modifie', '${now['name']} · ${changes.join(', ')}');
    });
    _db.execute(
      'UPDATE users SET name = ?, role = ?, perms = ?, active = ? WHERE id = ?',
      [u.name, u.role, u.perms.join(','), u.active ? 1 : 0, u.id],
    );
  }

  /// Supprime un utilisateur : il disparaît des listes et ne peut plus se connecter,
  /// mais ses ventes et son activité passées gardent son nom.
  static void delete(AppUser u) {
    _db.execute('UPDATE users SET deleted = 1, active = 0 WHERE id = ?', [u.id]);
    logActivity('utilisateur_supprime', u.name);
  }

  static void setPin(int userId, String pin) {
    _db.execute('UPDATE users SET pin_hash = ? WHERE id = ?', [hashPin(pin), userId]);
    logActivity('pin_modifie', byId(userId)?.name ?? '');
  }

  /// Nombre d'administrateurs actifs (on interdit de supprimer le dernier).
  static int activeAdmins() =>
      _db.select("SELECT COUNT(*) AS n FROM users WHERE active = 1 AND deleted = 0 AND role = 'admin'").first['n'] as int;
}

// ============================================================================ menu

class MenuRepo {
  static List<Family> families({bool onlyActive = false}) => _db
      .select('SELECT * FROM families ${onlyActive ? 'WHERE active = 1' : ''} ORDER BY rank, id')
      .map(Family.fromRow)
      .toList();

  static List<Product> products(int familyId, {bool onlyActive = false}) => _db
      .select(
        'SELECT * FROM products WHERE family_id = ? ${onlyActive ? 'AND active = 1' : ''} ORDER BY rank, id',
        [familyId],
      )
      .map(Product.fromRow)
      .toList();

  static int countProducts(int familyId) =>
      _db.select('SELECT COUNT(*) AS n FROM products WHERE family_id = ?', [familyId]).first['n'] as int;

  static int addFamily(String name) {
    final rank = (_db.select('SELECT COALESCE(MAX(rank), 0) AS m FROM families').first['m'] as int) + 1;
    _db.execute('INSERT INTO families (name, rank, photo, active) VALUES (?, ?, NULL, 1)', [name, rank]);
    final id = _db.lastInsertRowId;
    logActivity('famille_ajoutee', name);
    return id;
  }

  static Map<String, Object?> _familySnapshot(int id) {
    final r = _db.select('SELECT name, photo, active FROM families WHERE id = ?', [id]);
    return r.isEmpty ? {} : Map<String, Object?>.from(r.first);
  }

  static void saveFamily(Family f) {
    _deferLog('family${f.id}', () => _familySnapshot(f.id), (before) {
      final now = _familySnapshot(f.id);
      if (before.isEmpty || now.isEmpty) return;
      final changes = <String>[];
      if (before['name'] != now['name']) changes.add('ancien nom : ${before['name']}');
      if (before['photo'] != now['photo']) changes.add('photo changée');
      if (before['active'] != now['active']) changes.add(now['active'] == 1 ? 'remise en caisse' : 'masquée');
      if (changes.isNotEmpty) logActivity('famille_modifiee', '${now['name']} · ${changes.join(', ')}');
    });
    _db.execute(
      'UPDATE families SET name = ?, rank = ?, photo = ?, active = ? WHERE id = ?',
      [f.name, f.rank, f.photo, f.active ? 1 : 0, f.id],
    );
  }

  static int addProduct(int familyId, String name, int price, String? photo) {
    final rank = (_db.select(
              'SELECT COALESCE(MAX(rank), 0) AS m FROM products WHERE family_id = ?',
              [familyId],
            ).first['m'] as int) +
        1;
    _db.execute(
      'INSERT INTO products (family_id, name, price, description, photo, rank, active) VALUES (?, ?, ?, \'\', ?, ?, 1)',
      [familyId, name, price, photo, rank],
    );
    final id = _db.lastInsertRowId;
    logActivity('produit_ajoute', '$name · ${fmtDa(price)}');
    return id;
  }

  static Map<String, Object?> _productSnapshot(int id) {
    final r = _db.select('SELECT name, price, description, photo, active FROM products WHERE id = ?', [id]);
    return r.isEmpty ? {} : Map<String, Object?>.from(r.first);
  }

  static void saveProduct(Product p) {
    _deferLog('product${p.id}', () => _productSnapshot(p.id), (before) {
      final now = _productSnapshot(p.id);
      if (before.isEmpty || now.isEmpty) return;
      final changes = <String>[];
      if (before['price'] != now['price']) changes.add('prix ${fmtNum(before['price'] as int)} → ${fmtDa(now['price'] as int)}');
      if (before['name'] != now['name']) changes.add('ancien nom : ${before['name']}');
      if (before['description'] != now['description']) changes.add('description');
      if (before['photo'] != now['photo']) changes.add('photo changée');
      if (before['active'] != now['active']) changes.add(now['active'] == 1 ? 'remis en vente' : 'retiré de la vente');
      if (changes.isNotEmpty) logActivity('produit_modifie', '${now['name']} · ${changes.join(', ')}');
    });
    _db.execute(
      'UPDATE products SET family_id = ?, name = ?, price = ?, description = ?, photo = ?, rank = ?, active = ? WHERE id = ?',
      [p.familyId, p.name, p.price, p.description, p.photo, p.rank, p.active ? 1 : 0, p.id],
    );
  }

  static void deleteProduct(int id) {
    // Les ventes passées gardent le nom et le prix : on peut supprimer sans perte d'historique.
    final r = _db.select('SELECT name FROM products WHERE id = ?', [id]);
    _db.execute('DELETE FROM products WHERE id = ?', [id]);
    logActivity('produit_supprime', r.isEmpty ? '' : r.first['name'] as String);
  }

  /// Supprime une famille et tous ses produits (l'historique des ventes reste intact).
  static void deleteFamily(Family f) {
    final n = countProducts(f.id);
    _db.execute('BEGIN');
    _db.execute('DELETE FROM products WHERE family_id = ?', [f.id]);
    _db.execute('DELETE FROM families WHERE id = ?', [f.id]);
    _db.execute('COMMIT');
    logActivity('famille_supprimee', '${f.name}${n > 0 ? ' · avec $n produit(s)' : ''}');
  }

  /// Réécrit l'ordre (rank = 1, 2, 3…) dans l'ordre de la liste.
  static void reorderProducts(List<Product> ordered) {
    _db.execute('BEGIN');
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].rank = i + 1;
      _db.execute('UPDATE products SET rank = ? WHERE id = ?', [i + 1, ordered[i].id]);
    }
    _db.execute('COMMIT');
    logActivity('ordre_menu', 'Ordre des produits modifié');
  }

  static void reorderFamilies(List<Family> ordered) {
    _db.execute('BEGIN');
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].rank = i + 1;
      _db.execute('UPDATE families SET rank = ? WHERE id = ?', [i + 1, ordered[i].id]);
    }
    _db.execute('COMMIT');
    logActivity('ordre_menu', 'Ordre des familles modifié');
  }
}

// ============================================================================ journée

class DayRepo {
  static const _select = 'SELECT d.*, u.name AS closed_by_name FROM days d LEFT JOIN users u ON u.id = d.closed_by';

  static Day? current() {
    final r = _db.select('$_select WHERE d.closed_at IS NULL ORDER BY d.id DESC LIMIT 1');
    return r.isEmpty ? null : Day.fromRow(r.first);
  }

  static Day? byId(int id) {
    final r = _db.select('$_select WHERE d.id = ?', [id]);
    return r.isEmpty ? null : Day.fromRow(r.first);
  }

  /// Journées clôturées entre deux dates (incluses), plus récentes en premier.
  static List<Day> closedBetween(DateTime from, DateTime to) => _db
      .select(
        '$_select WHERE d.closed_at IS NOT NULL AND d.opened_at >= ? AND d.opened_at < ? ORDER BY d.opened_at DESC',
        [from.toIso8601String(), to.toIso8601String()],
      )
      .map(Day.fromRow)
      .toList();

  /// Ouvre la journée avec le fond de caisse ramené.
  /// Le fond sort du coffre : il est enregistré comme mouvement négatif.
  static Day open(int userId, int fund) {
    _db.execute('BEGIN');
    _db.execute('INSERT INTO days (opened_at, opened_by, opening_fund) VALUES (?, ?, ?)', [nowIso(), userId, fund]);
    final id = _db.lastInsertRowId;
    if (fund > 0) {
      _db.execute(
        'INSERT INTO safe_moves (created_at, user_id, label, amount, kind, day_id) VALUES (?, ?, ?, ?, ?, ?)',
        [nowIso(), userId, 'Fond de caisse ramené au resto', -fund, 'fond', id],
      );
    }
    _db.execute('COMMIT');
    AppDb.I.audit(userId, 'ouverture_journee', 'Fond de caisse ${fmtDa(fund)}');
    return byId(id)!;
  }

  static DaySummary summary(Day day) {
    final paid = _db.select(
      "SELECT payment, COUNT(*) AS n, COALESCE(SUM(total), 0) AS t FROM sales WHERE day_id = ? AND status = 'paid' GROUP BY payment",
      [day.id],
    );
    var cash = 0, card = 0, tickets = 0;
    for (final r in paid) {
      tickets += r['n'] as int;
      if (r['payment'] == 'card') {
        card += r['t'] as int;
      } else {
        cash += r['t'] as int;
      }
    }
    final cancelled = _db.select(
      "SELECT COUNT(*) AS n, COALESCE(SUM(total), 0) AS t FROM sales WHERE day_id = ? AND status = 'cancelled'",
      [day.id],
    ).first;
    final exp = _db.select(
      "SELECT COALESCE(SUM(amount), 0) AS t FROM expenses WHERE day_id = ? AND source = 'caisse' AND cancelled = 0",
      [day.id],
    ).first['t'] as int;
    final fam = <String, int>{};
    for (final r in _db.select(
      "SELECT l.family_name AS f, SUM(l.total) AS t FROM sale_lines l JOIN sales s ON s.id = l.sale_id "
      "WHERE s.day_id = ? AND s.status = 'paid' GROUP BY l.family_name ORDER BY t DESC",
      [day.id],
    )) {
      fam[r['f'] as String] = r['t'] as int;
    }
    return DaySummary(
      day: day,
      tickets: tickets,
      cashSales: cash,
      cardSales: card,
      cancelledCount: cancelled['n'] as int,
      cancelledTotal: cancelled['t'] as int,
      cashExpenses: exp,
      byFamily: fam,
    );
  }

  /// Clôture : enregistre le comptage, l'écart, et ce qui part au coffre.
  static Day close({
    required Day day,
    required int userId,
    required int counted,
    required int expected,
    required String reason,
    required int takenHome,
  }) {
    final diff = counted - expected;
    _db.execute('BEGIN');
    _db.execute(
      'UPDATE days SET closed_at = ?, closed_by = ?, counted = ?, expected = ?, diff = ?, reason = ?, taken_home = ? WHERE id = ?',
      [nowIso(), userId, counted, expected, diff, reason, takenHome, day.id],
    );
    if (takenHome > 0) {
      _db.execute(
        'INSERT INTO safe_moves (created_at, user_id, label, amount, kind, day_id) VALUES (?, ?, ?, ?, ?, ?)',
        [nowIso(), userId, 'Emporté à la clôture', takenHome, 'cloture', day.id],
      );
    }
    _db.execute('COMMIT');
    AppDb.I.audit(userId, 'cloture_journee',
        'Compté ${fmtDa(counted)} · attendu ${fmtDa(expected)} · écart ${fmtSigned(diff)} DA · emporté ${fmtDa(takenHome)}');
    return byId(day.id)!;
  }

  /// Fond conseillé = monnaie de rendu + moyenne des dépenses en espèces
  /// des 4 derniers mêmes jours de la semaine + 10 %, arrondi au 500 supérieur.
  static ({int suggested, int change, int avgExpenses}) suggestedFund({int change = 5000}) {
    final today = DateTime.now();
    final amounts = <int>[];
    for (var w = 1; w <= 4; w++) {
      final d = DateTime(today.year, today.month, today.day).subtract(Duration(days: 7 * w));
      final next = d.add(const Duration(days: 1));
      final t = _db.select(
        "SELECT COALESCE(SUM(e.amount), 0) AS t FROM expenses e JOIN days d ON d.id = e.day_id AND e.cancelled = 0 "
        "WHERE e.source = 'caisse' AND d.opened_at >= ? AND d.opened_at < ?",
        [d.toIso8601String(), next.toIso8601String()],
      ).first['t'] as int;
      amounts.add(t);
    }
    final avg = amounts.isEmpty ? 0 : (amounts.reduce((a, b) => a + b) / amounts.length).round();
    final raw = change + avg * 1.1;
    final suggested = ((raw / 500).ceil() * 500).toInt();
    return (suggested: suggested, change: change, avgExpenses: avg);
  }
}

// ============================================================================ ventes

class SaleRepo {
  static int nextNumber(int dayId) =>
      (_db.select('SELECT COALESCE(MAX(number), 0) AS m FROM sales WHERE day_id = ?', [dayId]).first['m'] as int) + 1;

  static void _insertLines(int saleId, List<CartLine> lines, Map<int, String> familyNames) {
    for (final l in lines) {
      _db.execute(
        'INSERT INTO sale_lines (sale_id, product_id, family_name, name, unit_price, qty, total, note) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          saleId,
          l.product.id > 0 ? l.product.id : null,
          familyNames[l.product.familyId] ?? '',
          l.product.name,
          l.product.price,
          l.qty,
          l.total,
          l.note,
        ],
      );
    }
  }

  /// Enregistre une vente payée et renvoie son numéro de ticket.
  /// [saleId] : commande en attente qu'on encaisse (elle garde son numéro).
  static int record({
    required int dayId,
    required int userId,
    required String mode,
    required String payment,
    required List<CartLine> lines,
    required Map<int, String> familyNames,
    int? cashGiven,
    int? saleId,
  }) {
    final total = lines.fold<int>(0, (a, l) => a + l.total);
    _db.execute('BEGIN');
    try {
      int id;
      int number;
      if (saleId == null) {
        number = nextNumber(dayId);
        _db.execute(
          'INSERT INTO sales (day_id, number, created_at, user_id, mode, payment, total, cash_given, status) '
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'paid')",
          [dayId, number, nowIso(), userId, mode, payment, total, cashGiven],
        );
        id = _db.lastInsertRowId;
      } else {
        number = _db.select('SELECT number FROM sales WHERE id = ?', [saleId]).first['number'] as int;
        _db.execute(
          "UPDATE sales SET mode = ?, payment = ?, total = ?, cash_given = ?, status = 'paid' WHERE id = ?",
          [mode, payment, total, cashGiven, saleId],
        );
        _db.execute('DELETE FROM sale_lines WHERE sale_id = ?', [saleId]);
        id = saleId;
      }
      _insertLines(id, lines, familyNames);
      _db.execute('COMMIT');
      return number;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Commande envoyée en cuisine, payée plus tard (status « pending »).
  /// [saleId] : commande déjà en attente qu'on modifie.
  static ({int id, int number}) hold({
    required int dayId,
    required int userId,
    required String mode,
    required List<CartLine> lines,
    required Map<int, String> familyNames,
    int? saleId,
  }) {
    final total = lines.fold<int>(0, (a, l) => a + l.total);
    _db.execute('BEGIN');
    try {
      int id;
      int number;
      if (saleId == null) {
        number = nextNumber(dayId);
        _db.execute(
          'INSERT INTO sales (day_id, number, created_at, user_id, mode, payment, total, cash_given, status) '
          "VALUES (?, ?, ?, ?, ?, 'attente', ?, NULL, 'pending')",
          [dayId, number, nowIso(), userId, mode, total],
        );
        id = _db.lastInsertRowId;
      } else {
        number = _db.select('SELECT number FROM sales WHERE id = ?', [saleId]).first['number'] as int;
        _db.execute('UPDATE sales SET mode = ?, total = ? WHERE id = ?', [mode, total, saleId]);
        _db.execute('DELETE FROM sale_lines WHERE sale_id = ?', [saleId]);
        id = saleId;
      }
      _insertLines(id, lines, familyNames);
      _db.execute('COMMIT');
      return (id: id, number: number);
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Commandes en attente de paiement (plus anciennes en premier).
  static List<Map<String, Object?>> pending(int dayId) => _db
      .select(
        'SELECT s.id, s.number, s.created_at, s.total, s.mode, u.name AS user_name, '
        '(SELECT COALESCE(SUM(qty), 0) FROM sale_lines WHERE sale_id = s.id) AS items '
        "FROM sales s LEFT JOIN users u ON u.id = s.user_id WHERE s.day_id = ? AND s.status = 'pending' ORDER BY s.id",
        [dayId],
      )
      .map((r) => Map<String, Object?>.from(r))
      .toList();

  static int pendingCount(int dayId) =>
      _db.select("SELECT COUNT(*) AS n FROM sales WHERE day_id = ? AND status = 'pending'", [dayId]).first['n'] as int;

  /// Lignes d'une commande, prêtes à remettre dans le panier (prix et noms d'origine).
  static List<CartLine> lines(int saleId) => _db
      .select(
        'SELECT l.*, p.family_id AS pf, p.photo AS pphoto FROM sale_lines l LEFT JOIN products p ON p.id = l.product_id '
        'WHERE l.sale_id = ? ORDER BY l.id',
        [saleId],
      )
      .map((r) => CartLine(
            product: Product(
              id: (r['product_id'] as int?) ?? -(r['id'] as int),
              familyId: (r['pf'] as int?) ?? 0,
              name: r['name'] as String,
              price: r['unit_price'] as int,
              description: '',
              photo: r['pphoto'] as String?,
              rank: 0,
              active: true,
            ),
            qty: r['qty'] as int,
            note: (r['note'] as String?) ?? '',
          ))
      .toList();

  static List<Map<String, Object?>> lastSales(int dayId, {int limit = 30}) => _db
      .select(
        'SELECT s.id, s.number, s.created_at, s.total, s.payment, s.status, s.mode, s.cancel_reason, u.name AS user_name '
        'FROM sales s LEFT JOIN users u ON u.id = s.user_id WHERE s.day_id = ? ORDER BY s.id DESC LIMIT ?',
        [dayId, limit],
      )
      .map((r) => Map<String, Object?>.from(r))
      .toList();

  /// Annulation tracée (ticket payé ou commande en attente) :
  /// la vente reste en base avec le motif et l'auteur.
  static void cancel(int saleId, int userId, String reason) {
    final r = _db.select('SELECT number, total, status FROM sales WHERE id = ?', [saleId]);
    _db.execute(
      "UPDATE sales SET status = 'cancelled', cancel_reason = ?, cancelled_by = ? WHERE id = ? AND status IN ('paid', 'pending')",
      [reason, userId, saleId],
    );
    final what = r.isEmpty
        ? 'Vente $saleId'
        : '${r.first['status'] == 'pending' ? 'Commande en attente' : 'Ticket'} n°${r.first['number']} · ${fmtDa(r.first['total'] as int)}';
    AppDb.I.audit(userId, 'annulation_ticket', reason.isEmpty ? '$what · sans motif' : '$what · motif : $reason');
  }
}

// ============================================================================ dépenses

class ExpenseRepo {
  static const categories = ['Matière', 'Énergie', 'Entretien', 'Emballages', 'Divers'];

  /// Dépenses de la journée. [withCancelled] : inclure les dépenses annulées (affichées barrées).
  static List<Expense> forDay(int dayId, {bool withCancelled = false}) => _db
      .select(
        'SELECT e.*, u.name AS user_name FROM expenses e LEFT JOIN users u ON u.id = e.user_id '
        'WHERE e.day_id = ? ${withCancelled ? '' : 'AND e.cancelled = 0'} ORDER BY e.id DESC',
        [dayId],
      )
      .map(Expense.fromRow)
      .toList();

  /// Annule une dépense saisie par erreur : elle reste visible (barrée) avec le motif.
  /// Payée du coffre : l'argent y revient. Payée de la caisse : la caisse attendue remonte.
  /// Un paiement de salaire ou de fournisseur lié est annulé avec elle.
  static void cancel(int expenseId, int userId, String reason) {
    final r = _db.select('SELECT * FROM expenses WHERE id = ? AND cancelled = 0', [expenseId]);
    if (r.isEmpty) return;
    final e = r.first;
    final day = e['day_id'] as int?;
    if (e['source'] == 'caisse' && day != null) {
      final closed = _db.select('SELECT closed_at FROM days WHERE id = ?', [day]);
      if (closed.isNotEmpty && closed.first['closed_at'] != null) {
        throw StateError(
            'Cette dépense a été payée de la caisse un jour déjà clôturé : la caisse de ce jour est arrêtée. '
            'Corrigez plutôt par un mouvement du coffre.');
      }
    }
    _db.execute('BEGIN');
    try {
      _db.execute('UPDATE expenses SET cancelled = 1, cancel_reason = ? WHERE id = ?', [reason, expenseId]);
      _db.execute('UPDATE pay_moves SET cancelled = 1 WHERE expense_id = ?', [expenseId]);
      _db.execute('UPDATE supplier_payments SET cancelled = 1 WHERE expense_id = ?', [expenseId]);
      if (e['source'] == 'coffre') {
        _db.execute(
          'INSERT INTO safe_moves (created_at, user_id, label, amount, kind, day_id) VALUES (?, ?, ?, ?, ?, ?)',
          [nowIso(), userId, 'Annulation : ${e['label']}', e['amount'], 'annulation', day],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    AppDb.I.audit(userId, 'depense_annulee', '${e['label']} · ${fmtDa(e['amount'] as int)} · motif : $reason');
  }

  /// [source] 'caisse' : l'argent sort du tiroir. 'coffre' : il sort du coffre maison.
  /// Renvoie l'identifiant de la dépense. [log] false : l'appelant note lui-même l'action dans le journal.
  static int add({
    required int? dayId,
    required int userId,
    required String label,
    required String category,
    required int amount,
    required String source,
    bool log = true,
  }) {
    _db.execute('BEGIN');
    _db.execute(
      'INSERT INTO expenses (day_id, created_at, user_id, label, category, amount, source) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [dayId, nowIso(), userId, label, category, amount, source],
    );
    final id = _db.lastInsertRowId;
    if (source == 'coffre') {
      _db.execute(
        'INSERT INTO safe_moves (created_at, user_id, label, amount, kind, day_id) VALUES (?, ?, ?, ?, ?, ?)',
        [nowIso(), userId, 'Dépense : $label', -amount, 'depense', dayId],
      );
    }
    _db.execute('COMMIT');
    if (log) {
      AppDb.I.audit(userId, 'depense', '$label · ${fmtDa(amount)} · $category · payée ${source == 'coffre' ? 'du coffre' : 'de la caisse'}');
    }
    return id;
  }
}

// ============================================================================ coffre

class SafeRepo {
  static int balance() => _db.select('SELECT COALESCE(SUM(amount), 0) AS t FROM safe_moves').first['t'] as int;

  /// Le solde de départ (argent déjà au coffre avant l'appli) a-t-il été saisi ?
  static bool hasStartingBalance() =>
      _db.select("SELECT 1 FROM safe_moves WHERE kind = 'depart' LIMIT 1").isNotEmpty;

  static List<SafeMove> recent({int limit = 50}) => _db
      .select('SELECT * FROM safe_moves ORDER BY id DESC LIMIT ?', [limit])
      .map(SafeMove.fromRow)
      .toList();

  /// Mouvement manuel : versement (+) ou retrait (−), par ex. loyer, retrait du patron.
  static void add(int userId, String label, int amount, String kind) {
    _db.execute(
      'INSERT INTO safe_moves (created_at, user_id, label, amount, kind, day_id) VALUES (?, ?, ?, ?, ?, NULL)',
      [nowIso(), userId, label, amount, kind],
    );
    AppDb.I.audit(userId, 'coffre', '$label · ${fmtSigned(amount)} DA');
  }
}
