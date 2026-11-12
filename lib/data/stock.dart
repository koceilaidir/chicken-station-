import 'package:sqlite3/sqlite3.dart' hide Session;

import '../ui/format.dart';
import 'db.dart';

Database get _db => AppDb.I.db;

/// Article acheté (pain, poulet, huile d'olive, canettes…). Pas de stock calculé :
/// les portions sont faites à l'œil, on garde seulement l'historique et l'évolution des prix.
class Ingredient {
  Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    this.photo,
    required this.cost,
    required this.active,
  });

  final int id;
  String name;
  String unit;
  String? photo;

  /// Dernier prix payé pour une unité (DA par kg, par pièce, par litre…).
  int cost;
  bool active;

  factory Ingredient.fromRow(Row r) => Ingredient(
        id: r['id'] as int,
        name: r['name'] as String,
        unit: r['unit'] as String,
        photo: r['photo'] as String?,
        cost: r['cost'] as int,
        active: (r['active'] as int) == 1,
      );
}

/// Ligne d'un bon d'achat.
class ReceptionLine {
  ReceptionLine(this.ingredient, this.qty, this.unitPrice);
  final Ingredient ingredient;
  final double qty;
  final int unitPrice;
  int get total => (qty * unitPrice).round();
}

/// Ce qu'on sait d'un article sur un mois : quantité, montant, prix moyen, évolution du prix.
class ArticleStats {
  ArticleStats({
    required this.article,
    required this.qty,
    required this.amount,
    required this.lastPrice,
    required this.previousPrice,
    required this.lastDate,
  });

  final Ingredient article;
  final double qty;
  final int amount;
  final int lastPrice;

  /// Prix de l'achat d'avant (0 si un seul achat connu).
  final int previousPrice;
  final DateTime? lastDate;

  int get averagePrice => qty <= 0 ? 0 : (amount / qty).round();

  /// Évolution du dernier prix par rapport au précédent, en % (null si inconnu).
  int? get priceChange =>
      previousPrice <= 0 || lastPrice <= 0 ? null : ((lastPrice - previousPrice) * 100 / previousPrice).round();
}

void _audit(int? userId, String action, String detail) => AppDb.I.audit(userId, action, detail);

class StockRepo {
  static List<Ingredient> ingredients({bool onlyActive = false}) => _db
      .select('SELECT * FROM ingredients ${onlyActive ? 'WHERE active = 1' : ''} ORDER BY active DESC, name COLLATE NOCASE')
      .map(Ingredient.fromRow)
      .toList();

  static Ingredient? byId(int id) {
    final r = _db.select('SELECT * FROM ingredients WHERE id = ?', [id]);
    return r.isEmpty ? null : Ingredient.fromRow(r.first);
  }

  /// Article tapé à la main sur un bon : retrouvé par son nom et son unité, ou créé.
  static Ingredient articleNamed(int? userId, String name, String unit) {
    final r = _db.select(
      'SELECT * FROM ingredients WHERE name = ? COLLATE NOCASE AND unit = ? ORDER BY active DESC LIMIT 1',
      [name.trim(), unit],
    );
    if (r.isNotEmpty) return Ingredient.fromRow(r.first);
    return byId(addIngredient(userId, name.trim(), unit))!;
  }

  /// Dernier prix payé pour un article tapé à la main (0 si jamais acheté).
  static int lastPrice(String name, String unit) {
    final r = _db.select('SELECT cost FROM ingredients WHERE name = ? COLLATE NOCASE AND unit = ? LIMIT 1', [name.trim(), unit]);
    return r.isEmpty ? 0 : r.first['cost'] as int;
  }

  static int addIngredient(int? userId, String name, String unit, {String? photo}) {
    _db.execute(
      'INSERT INTO ingredients (name, unit, photo, stock, min_stock, cost, active) VALUES (?, ?, ?, 0, 0, 0, 1)',
      [name, unit, photo],
    );
    final id = _db.lastInsertRowId;
    _audit(userId, 'stock_ingredient', 'Article ajouté : $name ($unit)');
    return id;
  }

  static void saveIngredient(int? userId, Ingredient i) {
    _db.execute(
      'UPDATE ingredients SET name = ?, unit = ?, photo = ?, active = ? WHERE id = ?',
      [i.name, i.unit, i.photo, i.active ? 1 : 0, i.id],
    );
    _audit(userId, 'stock_ingredient', 'Article modifié : ${i.name} (${i.unit})${i.active ? '' : ' · plus acheté'}');
  }

  // -------------------------------------------------------------- bons d'achat

  /// Enregistre un bon d'achat (date choisie, fournisseur facultatif). Le dernier prix de chaque article est mis à jour.
  static int receive({
    required int? userId,
    required int? supplierId,
    required List<ReceptionLine> lines,
    String note = '',
    String supplierName = '',
    DateTime? date,
  }) {
    final total = lines.fold<int>(0, (a, l) => a + l.total);
    final now = DateTime.now();
    final at = date == null ? now : DateTime(date.year, date.month, date.day, now.hour, now.minute, now.second);
    _db.execute('BEGIN');
    try {
      _db.execute(
        'INSERT INTO purchases (created_at, user_id, supplier_id, total, note) VALUES (?, ?, ?, ?, ?)',
        [at.toIso8601String(), userId, supplierId, total, note],
      );
      final purchaseId = _db.lastInsertRowId;
      for (final l in lines) {
        _db.execute(
          'INSERT INTO purchase_lines (purchase_id, ingredient_id, qty, unit_price, total) VALUES (?, ?, ?, ?, ?)',
          [purchaseId, l.ingredient.id, l.qty, l.unitPrice, l.total],
        );
        _db.execute('UPDATE ingredients SET cost = ? WHERE id = ?', [l.unitPrice, l.ingredient.id]);
      }
      _db.execute('COMMIT');
      _audit(
        userId,
        'stock_reception',
        "Bon d'achat · ${supplierName.isEmpty ? 'sans fournisseur' : supplierName} · ${lines.length} article(s) · ${fmtDa(total)}"
            '${date == null ? '' : ' · daté du ${fmtDate(at)}'}',
      );
      return purchaseId;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Annule un bon saisi par erreur (la dette du fournisseur baisse). Un paiement fait avec s'annule à part.
  static void cancelReception(int purchaseId, int? userId, String reason) {
    final p = _db.select('SELECT * FROM purchases WHERE id = ? AND cancelled = 0', [purchaseId]);
    if (p.isEmpty) return;
    _db.execute('UPDATE purchases SET cancelled = 1 WHERE id = ?', [purchaseId]);
    _audit(userId, 'stock_reception', "Bon d'achat annulé · ${fmtDa(p.first['total'] as int)} · motif : $reason");
  }

  /// Bons d'achat d'une période (annulés compris), plus récents en premier.
  static List<Map<String, Object?>> receptions({
    DateTime? from,
    DateTime? to,
    int? supplierId,
    bool noSupplier = false,
    int limit = 500,
  }) {
    final where = <String>['p.opening = 0'];
    final args = <Object?>[];
    if (from != null) {
      where.add('p.created_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('p.created_at < ?');
      args.add(to.toIso8601String());
    }
    if (supplierId != null) {
      where.add('p.supplier_id = ?');
      args.add(supplierId);
    }
    if (noSupplier) where.add('p.supplier_id IS NULL');
    args.add(limit);
    return _db
        .select(
          'SELECT p.id, p.created_at, p.total, p.note, p.cancelled, s.name AS supplier, u.name AS user_name, '
          '(SELECT COUNT(*) FROM purchase_lines WHERE purchase_id = p.id) AS n '
          'FROM purchases p LEFT JOIN suppliers s ON s.id = p.supplier_id LEFT JOIN users u ON u.id = p.user_id '
          '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY p.created_at DESC, p.id DESC LIMIT ?',
          args,
        )
        .map((r) => Map<String, Object?>.from(r))
        .toList();
  }

  /// Détail d'un bon : « 10 kg Frites à 250 DA ».
  static List<String> receptionLines(int purchaseId) => _db
      .select(
        'SELECT l.qty, l.unit_price, i.name, i.unit FROM purchase_lines l JOIN ingredients i ON i.id = l.ingredient_id WHERE l.purchase_id = ?',
        [purchaseId],
      )
      .map((r) => '${fmtQty((r['qty'] as num).toDouble())} ${r['unit']} ${r['name']} à ${fmtDa(r['unit_price'] as int)}')
      .toList();

  /// Total des bons (non annulés) entre deux dates.
  static int totalBetween(DateTime from, DateTime to) => (_db.select(
        'SELECT COALESCE(SUM(total), 0) AS t FROM purchases WHERE cancelled = 0 AND opening = 0 AND created_at >= ? AND created_at < ?',
        [from.toIso8601String(), to.toIso8601String()],
      ).first['t'] as num)
          .toInt();

  /// Achats du mois par article, avec le dernier prix et l'évolution par rapport à l'achat précédent.
  static List<ArticleStats> stats(DateTime month) {
    final from = DateTime(month.year, month.month);
    final to = DateTime(month.year, month.month + 1);
    final out = <ArticleStats>[];
    for (final a in ingredients()) {
      final m = _db.select(
        'SELECT COALESCE(SUM(l.qty), 0) AS q, COALESCE(SUM(l.total), 0) AS t FROM purchase_lines l '
        'JOIN purchases p ON p.id = l.purchase_id WHERE p.cancelled = 0 AND l.ingredient_id = ? AND p.created_at >= ? AND p.created_at < ?',
        [a.id, from.toIso8601String(), to.toIso8601String()],
      ).first;
      final prices = _db.select(
        'SELECT l.unit_price, p.created_at FROM purchase_lines l JOIN purchases p ON p.id = l.purchase_id '
        'WHERE p.cancelled = 0 AND l.ingredient_id = ? AND p.created_at < ? ORDER BY p.created_at DESC, p.id DESC LIMIT 2',
        [a.id, to.toIso8601String()],
      );
      out.add(ArticleStats(
        article: a,
        qty: (m['q'] as num).toDouble(),
        amount: (m['t'] as num).toInt(),
        lastPrice: prices.isEmpty ? 0 : prices.first['unit_price'] as int,
        previousPrice: prices.length < 2 ? 0 : prices[1]['unit_price'] as int,
        lastDate: prices.isEmpty ? null : DateTime.parse(prices.first['created_at'] as String),
      ));
    }
    return out;
  }
}
