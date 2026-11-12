import 'package:sqlite3/sqlite3.dart' hide Session;

import '../ui/format.dart';
import 'db.dart';
import 'repos.dart';

Database get _db => AppDb.I.db;

/// Paiement impossible (ex. depuis la caisse alors que la journée n'est pas ouverte).
class PaymentException implements Exception {
  PaymentException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Toute sortie d'argent passe par une dépense : la caisse attendue, le coffre, le Z et le journal restent justes.
int _payOut({
  required int userId,
  required String label,
  required String category,
  required int amount,
  required String source,
}) {
  final day = DayRepo.current();
  if (source == 'caisse') {
    if (day == null) {
      throw PaymentException("La journée n'est pas ouverte : payez depuis le coffre, ou ouvrez d'abord la caisse.");
    }
    final inDrawer = DayRepo.summary(day).expectedInDrawer;
    if (amount > inDrawer) {
      throw PaymentException(
          "Il n'y a que ${fmtDa(inDrawer)} dans la caisse (selon les ventes et les dépenses) : payez depuis le coffre, ou en deux fois.");
    }
  }
  return ExpenseRepo.add(
    dayId: day?.id,
    userId: userId,
    label: label,
    category: category,
    amount: amount,
    source: source,
    log: false,
  );
}

// ============================================================================ fournisseurs

class Supplier {
  Supplier({
    required this.id,
    required this.name,
    required this.phone,
    required this.note,
    required this.active,
    this.product = '',
    this.debt = 0,
  });
  final int id;
  String name;
  String phone;
  String note;

  /// Ce qu'il livre d'habitude (ex. « Viande ») : proposé sur chaque nouveau bon.
  String product;
  bool active;

  /// Reste à payer : réceptions − paiements (annulations exclues). Négatif = avance chez le fournisseur.
  int debt;
}

class SupplierEvent {
  SupplierEvent({
    required this.id,
    required this.at,
    required this.label,
    required this.amount,
    required this.isPurchase,
    required this.cancelled,
    this.opening = false,
  });
  final int id;
  final DateTime at;
  final String label;
  final int amount;
  final bool isPurchase;
  final bool cancelled;

  /// Crédit d'avant l'appli (pas de détail d'articles).
  final bool opening;
}

class SupplierRepo {
  static List<Supplier> all({bool onlyActive = false}) => _db
      .select(
        'SELECT s.*, '
        '(SELECT COALESCE(SUM(total), 0) FROM purchases WHERE supplier_id = s.id AND cancelled = 0) - '
        '(SELECT COALESCE(SUM(amount), 0) FROM supplier_payments WHERE supplier_id = s.id AND cancelled = 0) AS debt '
        'FROM suppliers s ${onlyActive ? 'WHERE s.active = 1' : ''} ORDER BY s.active DESC, s.name COLLATE NOCASE',
      )
      .map((r) => Supplier(
            id: r['id'] as int,
            name: r['name'] as String,
            phone: r['phone'] as String,
            note: r['note'] as String,
            active: (r['active'] as int) == 1,
            product: (r['product'] as String?) ?? '',
            debt: r['debt'] as int,
          ))
      .toList();

  static int add(int userId, String name, String phone, {String product = '', String note = ''}) {
    _db.execute('INSERT INTO suppliers (name, phone, note, product, active) VALUES (?, ?, ?, ?, 1)', [name, phone, note, product]);
    final id = _db.lastInsertRowId;
    AppDb.I.audit(userId, 'fournisseur', 'Ajouté : $name${product.isEmpty ? '' : ' · $product'}');
    return id;
  }

  static void save(int userId, Supplier s) {
    _db.execute('UPDATE suppliers SET name = ?, phone = ?, note = ?, product = ?, active = ? WHERE id = ?',
        [s.name, s.phone, s.note, s.product, s.active ? 1 : 0, s.id]);
    AppDb.I.audit(userId, 'fournisseur', 'Modifié : ${s.name}${s.active ? '' : ' (désactivé)'}');
  }

  /// Ce qu'on devait déjà à ce fournisseur avant de commencer avec l'appli (bons papier non payés).
  /// Augmente sa dette, mais ne compte pas dans les achats du mois.
  static void addOldCredit(int userId, int supplierId, int amount, String note) {
    if (amount <= 0) throw StateError('Montant invalide.');
    _db.execute(
      'INSERT INTO purchases (created_at, user_id, supplier_id, total, note, opening) VALUES (?, ?, ?, ?, ?, 1)',
      [DateTime.now().toIso8601String(), userId, supplierId, amount, note],
    );
    final name = _db.select('SELECT name FROM suppliers WHERE id = ?', [supplierId]).first['name'];
    AppDb.I.audit(userId, 'fournisseur', "Crédit d'avant l'appli : $name · ${fmtDa(amount)}${note.isEmpty ? '' : ' · $note'}");
  }

  static int totalDebt() => all().fold<int>(0, (a, s) => a + (s.debt > 0 ? s.debt : 0));

  /// Réceptions et paiements d'un fournisseur, plus récents en premier (annulés compris, marqués).
  static List<SupplierEvent> history(int supplierId) {
    final out = <SupplierEvent>[];
    for (final r in _db.select(
      'SELECT p.id, p.created_at, p.total, p.cancelled, p.opening, (SELECT COUNT(*) FROM purchase_lines WHERE purchase_id = p.id) AS n, p.note '
      'FROM purchases p WHERE p.supplier_id = ?',
      [supplierId],
    )) {
      final note = (r['note'] as String?) ?? '';
      final opening = (r['opening'] as int? ?? 0) == 1;
      out.add(SupplierEvent(
        id: r['id'] as int,
        at: DateTime.parse(r['created_at'] as String),
        label: opening
            ? "Crédit d'avant l'appli${note.isEmpty ? '' : ' · $note'}"
            : "Bon d'achat · ${r['n']} article(s)${note.isEmpty ? '' : ' · $note'}",
        amount: r['total'] as int,
        isPurchase: true,
        cancelled: (r['cancelled'] as int) == 1,
        opening: opening,
      ));
    }
    for (final r in _db.select(
      'SELECT p.id, p.created_at, p.amount, p.note, p.cancelled, e.source FROM supplier_payments p '
      'LEFT JOIN expenses e ON e.id = p.expense_id WHERE p.supplier_id = ?',
      [supplierId],
    )) {
      final note = (r['note'] as String?) ?? '';
      out.add(SupplierEvent(
        id: r['id'] as int,
        at: DateTime.parse(r['created_at'] as String),
        label: 'Paiement ${r['source'] == 'caisse' ? 'depuis la caisse' : 'depuis le coffre'}${note.isEmpty ? '' : ' · $note'}',
        amount: r['amount'] as int,
        isPurchase: false,
        cancelled: (r['cancelled'] as int) == 1,
      ));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// Achat payé tout de suite sans fournisseur enregistré (marché, dépannage).
  static void payWithoutSupplier({required int userId, required int amount, required String source, required String label}) {
    _payOut(userId: userId, label: label, category: 'Fournisseurs', amount: amount, source: source);
    AppDb.I.audit(userId, 'fournisseur_paiement', '$label · ${fmtDa(amount)} · ${source == 'coffre' ? 'du coffre' : 'de la caisse'}');
  }

  /// Paiement d'un fournisseur (réduit sa dette). [source] : 'caisse' ou 'coffre'.
  static void pay({required int userId, required Supplier supplier, required int amount, required String source, String note = ''}) {
    final expenseId = _payOut(
      userId: userId,
      label: 'Fournisseur : ${supplier.name}',
      category: 'Fournisseurs',
      amount: amount,
      source: source,
    );
    _db.execute(
      'INSERT INTO supplier_payments (created_at, user_id, supplier_id, amount, expense_id, note) VALUES (?, ?, ?, ?, ?, ?)',
      [nowIso(), userId, supplier.id, amount, expenseId, note],
    );
    AppDb.I.audit(userId, 'fournisseur_paiement',
        '${supplier.name} · ${fmtDa(amount)} · ${source == 'coffre' ? 'du coffre' : 'de la caisse'} · reste ${fmtDa(supplier.debt - amount)}');
  }

  /// Annule un paiement saisi par erreur (l'argent revient au coffre ou dans la caisse attendue).
  static void cancelPayment(int paymentId, int userId, String reason) {
    final r = _db.select('SELECT expense_id FROM supplier_payments WHERE id = ? AND cancelled = 0', [paymentId]);
    if (r.isEmpty) return;
    final expenseId = r.first['expense_id'] as int?;
    if (expenseId != null) {
      ExpenseRepo.cancel(expenseId, userId, reason);
    } else {
      _db.execute('UPDATE supplier_payments SET cancelled = 1 WHERE id = ?', [paymentId]);
    }
  }
}

// ============================================================================ employés et paie

class Employee {
  Employee({
    required this.id,
    required this.name,
    required this.job,
    required this.phone,
    required this.salary,
    required this.active,
    required this.startMonth,
    required this.endMonth,
    this.trackedFrom = '',
    this.dayRate = 0,
  });
  final int id;
  String name;
  String job;
  String phone;

  /// Prix d'une journée (DA) : retiré pour une absence, ajouté pour une double, moitié pour une demi.
  int dayRate;

  /// Salaire mensuel actuel (DA). Les mois passés gardent le salaire de l'époque (historique).
  int salary;
  bool active;

  /// Premier mois travaillé (« 2026-11 ») et dernier mois (vide s'il travaille encore).
  String startMonth;
  String endMonth;

  /// Premier mois dont la paie est suivie dans l'appli (les mois d'avant ont été réglés hors appli).
  String trackedFrom;

  bool worksIn(String month) => month.compareTo(startMonth) >= 0 && (endMonth.isEmpty || month.compareTo(endMonth) <= 0);
}

/// Situation d'un employé pour un mois.
class PayMonth {
  PayMonth({required this.salary, required this.advances, required this.paid, required this.bonus, this.deduction = 0});
  final int salary;
  final int advances;
  final int paid;
  final int bonus;

  /// Retenues (absences) : diminuent ce qui est dû, sans mouvement d'argent.
  final int deduction;

  /// Ce que l'employé coûte ce mois : salaire + primes − retenues.
  int get due => salary + bonus - deduction;

  /// Reste à payer = salaire + primes − retenues − acomptes − déjà payé.
  int get remaining => due - advances - paid;
}

class PayLine {
  PayLine({
    required this.id,
    required this.at,
    required this.kind,
    required this.amount,
    required this.note,
    required this.source,
    required this.cancelled,
    this.origin = '',
  });
  final int id;
  final DateTime at;
  final String kind;
  final int amount;
  final String note;
  final String source;
  final bool cancelled;

  /// 'pointage' quand la ligne a été calculée depuis le pointage (doubles journées, absences).
  final String origin;

  static const kindLabels = {'acompte': 'Acompte', 'salaire': 'Salaire', 'prime': 'Prime', 'retenue': 'Retenue'};

  /// Lignes sans mouvement d'argent (elles changent seulement ce qui est dû).
  static const noMoney = {'prime', 'retenue'};
}

class PayrollRepo {
  static Employee _fromRow(Row r) => Employee(
        id: r['id'] as int,
        name: r['name'] as String,
        job: r['job'] as String,
        phone: r['phone'] as String,
        salary: r['salary'] as int,
        active: (r['active'] as int) == 1,
        startMonth: (r['start_month'] as String?) ?? '',
        endMonth: (r['end_month'] as String?) ?? '',
        trackedFrom: (r['tracked_from'] as String?) ?? '',
        dayRate: (r['day_rate'] as int?) ?? 0,
      );

  static List<Employee> employees({bool onlyActive = false}) => _db
      .select('SELECT * FROM employees ${onlyActive ? 'WHERE active = 1' : ''} ORDER BY active DESC, name COLLATE NOCASE')
      .map(_fromRow)
      .toList();

  /// Nouvel employé : salaire mensuel et mois d'arrivée.
  static int add(int userId, String name, String job, int salary,
      {String phone = '', required String startMonth, int dayRate = 0}) {
    // Arrivé le mois dernier ou après : sa paie est suivie depuis son arrivée.
    // Arrivé avant : les mois passés ont été payés hors appli, le suivi commence ce mois-ci.
    final now = DateTime.now();
    final current = monthKey(now);
    final previous = monthKey(DateTime(now.year, now.month - 1));
    final tracked = startMonth.compareTo(previous) >= 0 ? startMonth : current;
    _db.execute(
      'INSERT INTO employees (name, job, phone, salary, active, start_month, end_month, tracked_from, day_rate) VALUES (?, ?, ?, ?, 1, ?, \'\', ?, ?)',
      [name, job, phone, salary, startMonth, tracked, dayRate],
    );
    final id = _db.lastInsertRowId;
    _db.execute('INSERT OR REPLACE INTO employee_salaries (employee_id, from_month, amount) VALUES (?, ?, ?)', [id, startMonth, salary]);
    AppDb.I.audit(userId, 'employe', 'Ajouté : $name · ${fmtDa(salary)} / mois · journée ${fmtDa(dayRate)} · depuis $startMonth');
    return id;
  }

  /// Modifie la fiche. Si le salaire change, il s'applique à partir de [salaryFrom] (les mois d'avant gardent l'ancien).
  /// Un départ fixe le dernier mois travaillé à [endMonth].
  static void save(int userId, Employee e, {required String salaryFrom, String? endMonth}) {
    final old = _db.select('SELECT salary, active, day_rate FROM employees WHERE id = ?', [e.id]).first;
    if (!e.active && (old['active'] as int) == 1) e.endMonth = endMonth ?? e.endMonth;
    if (e.active) e.endMonth = '';
    _db.execute(
      'UPDATE employees SET name = ?, job = ?, phone = ?, salary = ?, active = ?, end_month = ?, day_rate = ? WHERE id = ?',
      [e.name, e.job, e.phone, e.salary, e.active ? 1 : 0, e.endMonth, e.dayRate, e.id],
    );
    final changes = <String>[];
    if (old['day_rate'] != e.dayRate) changes.add('journée ${fmtNum(old['day_rate'] as int)} → ${fmtDa(e.dayRate)}');
    if (old['salary'] != e.salary) {
      _db.execute(
        'INSERT OR REPLACE INTO employee_salaries (employee_id, from_month, amount) VALUES (?, ?, ?)',
        [e.id, salaryFrom, e.salary],
      );
      changes.add('salaire ${fmtNum(old['salary'] as int)} → ${fmtDa(e.salary)} à partir de $salaryFrom');
    }
    if ((old['active'] as int) == 1 && !e.active) changes.add('parti (dernier mois ${e.endMonth})');
    if ((old['active'] as int) == 0 && e.active) changes.add('revenu');
    AppDb.I.audit(userId, 'employe', '${e.name}${changes.isEmpty ? '' : ' · ${changes.join(', ')}'}');
  }

  /// Salaire en vigueur pour un mois (historique des salaires).
  static int salaryFor(int employeeId, String month) {
    final r = _db.select(
      'SELECT amount FROM employee_salaries WHERE employee_id = ? AND from_month <= ? ORDER BY from_month DESC LIMIT 1',
      [employeeId, month],
    );
    return r.isEmpty ? 0 : r.first['amount'] as int;
  }

  static PayMonth month(Employee e, String month) {
    int sum(String kind) => _db.select(
          'SELECT COALESCE(SUM(amount), 0) AS t FROM pay_moves WHERE employee_id = ? AND month = ? AND kind = ? AND cancelled = 0',
          [e.id, month, kind],
        ).first['t'] as int;
    return PayMonth(
      // Avant le suivi dans l'appli, rien n'est dû ici (payé hors appli).
      salary: e.worksIn(month) && (e.trackedFrom.isEmpty || month.compareTo(e.trackedFrom) >= 0) ? salaryFor(e.id, month) : 0,
      advances: sum('acompte'),
      paid: sum('salaire'),
      bonus: sum('prime'),
      deduction: sum('retenue'),
    );
  }

  /// Mois précédents (jusqu'à 6) où il reste quelque chose à payer.
  static List<({String month, int remaining})> unpaidBefore(Employee e, String month) {
    final out = <({String month, int remaining})>[];
    var y = int.parse(month.substring(0, 4));
    var m = int.parse(month.substring(5, 7));
    for (var i = 0; i < 6; i++) {
      m--;
      if (m == 0) {
        m = 12;
        y--;
      }
      final key = '$y-${m.toString().padLeft(2, '0')}';
      if (key.compareTo(e.startMonth) < 0) break;
      if (e.trackedFrom.isNotEmpty && key.compareTo(e.trackedFrom) < 0) break;
      final r = PayrollRepo.month(e, key).remaining;
      if (r > 0) out.add((month: key, remaining: r));
    }
    return out;
  }

  static List<PayLine> lines(int employeeId, String month) => _db
      .select(
        'SELECT p.*, e.source FROM pay_moves p LEFT JOIN expenses e ON e.id = p.expense_id '
        'WHERE p.employee_id = ? AND p.month = ? ORDER BY p.id DESC',
        [employeeId, month],
      )
      .map((r) => PayLine(
            id: r['id'] as int,
            at: DateTime.parse(r['created_at'] as String),
            kind: r['kind'] as String,
            amount: r['amount'] as int,
            note: (r['note'] as String?) ?? '',
            source: (r['source'] as String?) ?? '',
            cancelled: (r['cancelled'] as int) == 1,
            origin: (r['origin'] as String?) ?? '',
          ))
      .toList();

  /// Acompte, salaire ou prime. La prime augmente ce qui est dû ; elle n'est pas un paiement.
  /// Acompte et salaire sortent de l'argent (caisse ou coffre).
  static void record({
    required int userId,
    required Employee employee,
    required String kind,
    required int amount,
    required String month,
    String source = 'coffre',
    String note = '',
    String origin = '',
  }) {
    int? expenseId;
    if (!PayLine.noMoney.contains(kind)) {
      expenseId = _payOut(
        userId: userId,
        label: '${PayLine.kindLabels[kind]} : ${employee.name} ($month)',
        category: 'Salaires',
        amount: amount,
        source: source,
      );
    }
    _db.execute(
      'INSERT INTO pay_moves (created_at, user_id, employee_id, month, kind, amount, expense_id, note, origin) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [nowIso(), userId, employee.id, month, kind, amount, expenseId, note, origin],
    );
    AppDb.I.audit(userId, 'paie',
        '${PayLine.kindLabels[kind]} · ${employee.name} · ${fmtDa(amount)} · mois $month'
        '${PayLine.noMoney.contains(kind) ? '' : ' · ${source == 'coffre' ? 'du coffre' : 'de la caisse'}'}'
        '${note.isEmpty ? '' : ' · $note'}');
  }

  /// Annule une ligne de paie saisie par erreur (l'argent revient là d'où il est sorti).
  static void cancelLine(int lineId, int userId, String reason) {
    final r = _db.select('SELECT * FROM pay_moves WHERE id = ? AND cancelled = 0', [lineId]);
    if (r.isEmpty) return;
    final expenseId = r.first['expense_id'] as int?;
    if (expenseId != null) {
      ExpenseRepo.cancel(expenseId, userId, reason);
    } else {
      _db.execute('UPDATE pay_moves SET cancelled = 1 WHERE id = ?', [lineId]);
      AppDb.I.audit(userId, 'paie',
          '${PayLine.kindLabels[r.first['kind']] ?? r.first['kind']} annulée · ${fmtDa(r.first['amount'] as int)} · motif : $reason');
    }
  }

  /// Masse salariale d'un mois : salaire de l'époque de chaque employé présent ce mois-là.
  static int totalSalaries(String month) =>
      employees().where((e) => e.worksIn(month)).fold<int>(0, (a, e) => a + salaryFor(e.id, month));

  /// Coût réel des employés pour un mois : salaires + primes − retenues (pour le résultat du mois).
  static int totalCost(String month) => employees().fold<int>(0, (a, e) => a + PayrollRepo.month(e, month).due);

  /// Somme des lignes actives d'un type venant du pointage, pour un employé et un mois.
  static int fromAttendance(int employeeId, String month, String kind) => _db.select(
        "SELECT COALESCE(SUM(amount), 0) AS t FROM pay_moves WHERE employee_id = ? AND month = ? AND kind = ? AND origin = 'pointage' AND cancelled = 0",
        [employeeId, month, kind],
      ).first['t'] as int;

  /// Met la prime (doubles journées) ou la retenue (absences) du mois au montant [amount] calculé depuis le pointage.
  /// L'ancienne ligne venant du pointage est annulée (tracée) et remplacée : jamais de double comptage.
  static void setFromAttendance({
    required int userId,
    required Employee employee,
    required String month,
    required String kind,
    required int amount,
    required String note,
  }) {
    assert(kind == 'prime' || kind == 'retenue');
    final old = _db.select(
      "SELECT id FROM pay_moves WHERE employee_id = ? AND month = ? AND kind = ? AND origin = 'pointage' AND cancelled = 0",
      [employee.id, month, kind],
    );
    for (final r in old) {
      cancelLine(r['id'] as int, userId, 'recalcul depuis le pointage');
    }
    if (amount > 0) {
      record(userId: userId, employee: employee, kind: kind, amount: amount, month: month, note: note, origin: 'pointage');
    }
  }

  /// Total restant à payer pour un mois, tous employés.
  static int totalRemaining(String month) => employees()
      .where((e) => e.worksIn(month))
      .fold<int>(0, (a, e) => a + (PayrollRepo.month(e, month).remaining > 0 ? PayrollRepo.month(e, month).remaining : 0));

  /// Ce qui reste dû aux employés pour les mois passés (6 derniers mois), hors mois en cours.
  static int totalOverdue(String month) => employees().fold<int>(
      0, (a, e) => a + unpaidBefore(e, month).fold<int>(0, (b, u) => b + (u.remaining > 0 ? u.remaining : 0)));
}

// ============================================================================ charges fixes et objectif du mois

/// Titre de charge (Loyer, Électricité…). Pas de montant fixe : on saisit le montant à chaque paiement.
class MonthlyCharge {
  MonthlyCharge({required this.id, required this.label, required this.active, this.lastAt, this.lastAmount = 0, this.monthTotal = 0});
  final int id;
  String label;
  bool active;

  /// Dernier paiement (date et montant) et total payé ce mois-ci.
  final DateTime? lastAt;
  final int lastAmount;
  final int monthTotal;
}

/// Paiement d'une charge (c'est une dépense ; annulable).
class ChargePayment {
  ChargePayment({required this.expenseId, required this.at, required this.amount, required this.label, required this.source, required this.cancelled, required this.cancelReason});
  final int expenseId;
  final DateTime at;
  final int amount;
  final String label;
  final String source;
  final bool cancelled;
  final String cancelReason;
}

/// Résultat du mois : la marge sur les ventes (ventes − achats) doit couvrir les salaires, les charges payées
/// et les autres dépenses.
class MonthGoal {
  MonthGoal({
    required this.month,
    required this.sales,
    required this.goodsCost,
    required this.charges,
    required this.salaries,
    required this.otherExpenses,
    required this.daysLeft,
    required this.daysElapsed,
  });

  final DateTime month;

  /// Ventes payées du mois.
  final int sales;

  /// Marchandise : réceptions du mois + dépenses « Matière » et « Emballages ».
  final int goodsCost;
  final int charges;
  final int salaries;

  /// Entretien, divers… (ni marchandise, ni salaires, ni fournisseurs).
  final int otherExpenses;
  final int daysLeft;
  final int daysElapsed;

  int get margin => sales - goodsCost;
  int get target => charges + salaries + otherExpenses;
  int get remaining => target - margin;
  int get profit => margin - target;
  double get progress => target <= 0 ? 1 : (margin / target).clamp(0, 1).toDouble();

  /// Taux de marge observé (marge / ventes), pour traduire la marge à faire en ventes à faire.
  double get marginRate => sales <= 0 ? 0 : margin / sales;

  /// Marge à faire chaque jour restant pour atteindre l'objectif.
  int get marginPerDay => remaining <= 0 || daysLeft <= 0 ? 0 : (remaining / daysLeft).ceil();

  /// Chiffre d'affaires quotidien nécessaire, au taux de marge actuel.
  int get salesPerDay => marginRate <= 0 ? 0 : (marginPerDay / marginRate).ceil();
}

/// Jours écoulés et jours restants (aujourd'hui compris) dans le mois de [month].
({int left, int elapsed}) monthDays(DateTime month, DateTime today) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  if (today.isBefore(start)) return (left: daysInMonth, elapsed: 0);
  if (!today.isBefore(end)) return (left: 0, elapsed: daysInMonth);
  return (left: daysInMonth - today.day + 1, elapsed: today.day);
}

class ChargesRepo {
  /// Titres de charges, avec le dernier paiement et le total du mois en cours.
  static List<MonthlyCharge> all() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month).toIso8601String();
    final to = DateTime(now.year, now.month + 1).toIso8601String();
    return _db
        .select(
          'SELECT c.*, '
          '(SELECT created_at FROM expenses WHERE charge_id = c.id AND cancelled = 0 ORDER BY created_at DESC LIMIT 1) AS last_at, '
          '(SELECT amount FROM expenses WHERE charge_id = c.id AND cancelled = 0 ORDER BY created_at DESC LIMIT 1) AS last_amount, '
          '(SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE charge_id = c.id AND cancelled = 0 AND created_at >= ? AND created_at < ?) AS month_total '
          'FROM monthly_charges c ORDER BY c.active DESC, c.id',
          [from, to],
        )
        .map((r) => MonthlyCharge(
              id: r['id'] as int,
              label: r['label'] as String,
              active: (r['active'] as int) == 1,
              lastAt: r['last_at'] == null ? null : DateTime.parse(r['last_at'] as String),
              lastAmount: (r['last_amount'] as int?) ?? 0,
              monthTotal: (r['month_total'] as num).toInt(),
            ))
        .toList();
  }

  static void add(int userId, String label) {
    _db.execute('INSERT INTO monthly_charges (label, amount, active) VALUES (?, 0, 1)', [label]);
    AppDb.I.audit(userId, 'charges', 'Titre ajouté : $label');
  }

  static void save(int userId, MonthlyCharge c) {
    _db.execute('UPDATE monthly_charges SET label = ?, active = ? WHERE id = ?', [c.label, c.active ? 1 : 0, c.id]);
    AppDb.I.audit(userId, 'charges', 'Titre modifié : ${c.label}${c.active ? '' : ' (masqué)'}');
  }

  /// Paie une charge : montant saisi au moment du paiement, depuis le coffre ou la caisse.
  static void pay({required int userId, required MonthlyCharge charge, required int amount, required String source, String note = ''}) {
    final id = _payOut(
      userId: userId,
      label: note.isEmpty ? charge.label : '${charge.label} · $note',
      category: 'Charges',
      amount: amount,
      source: source,
    );
    _db.execute('UPDATE expenses SET charge_id = ? WHERE id = ?', [charge.id, id]);
    AppDb.I.audit(userId, 'charges',
        '${charge.label}${note.isEmpty ? '' : ' · $note'} · ${fmtDa(amount)} · ${source == 'coffre' ? 'du coffre' : 'de la caisse'}');
  }

  /// Paiements d'une charge, plus récents en premier (annulés compris).
  static List<ChargePayment> history(int chargeId) => _db
      .select('SELECT * FROM expenses WHERE charge_id = ? ORDER BY created_at DESC, id DESC', [chargeId])
      .map((r) => ChargePayment(
            expenseId: r['id'] as int,
            at: DateTime.parse(r['created_at'] as String),
            amount: r['amount'] as int,
            label: r['label'] as String,
            source: r['source'] as String,
            cancelled: (r['cancelled'] as int) == 1,
            cancelReason: (r['cancel_reason'] as String?) ?? '',
          ))
      .toList();

  /// Charges payées sur un mois (loyer, factures… et dépenses « Énergie » saisies à la clôture).
  static int paidBetween(DateTime from, DateTime to) => (_db.select(
        "SELECT COALESCE(SUM(amount), 0) AS t FROM expenses WHERE cancelled = 0 AND (charge_id IS NOT NULL OR category IN ('Charges', 'Énergie')) "
        'AND created_at >= ? AND created_at < ?',
        [from.toIso8601String(), to.toIso8601String()],
      ).first['t'] as num)
          .toInt();

  static MonthGoal goal(DateTime month, {DateTime? now}) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final f = start.toIso8601String();
    final t = end.toIso8601String();
    int one(String sql) => (_db.select(sql, [f, t]).first['t'] as num).toInt();
    final sales = one("SELECT COALESCE(SUM(total), 0) AS t FROM sales WHERE status = 'paid' AND created_at >= ? AND created_at < ?");
    final purchases = one('SELECT COALESCE(SUM(total), 0) AS t FROM purchases WHERE cancelled = 0 AND opening = 0 AND created_at >= ? AND created_at < ?');
    final goodsExpenses = one(
        "SELECT COALESCE(SUM(amount), 0) AS t FROM expenses WHERE cancelled = 0 AND category IN ('Matière', 'Emballages') AND created_at >= ? AND created_at < ?");
    final other = one(
        "SELECT COALESCE(SUM(amount), 0) AS t FROM expenses WHERE cancelled = 0 AND category IN ('Entretien', 'Divers') AND created_at >= ? AND created_at < ?");
    final days = monthDays(start, now ?? DateTime.now());
    final daysLeft = days.left;
    final elapsed = days.elapsed;
    return MonthGoal(
      month: start,
      sales: sales,
      goodsCost: purchases + goodsExpenses,
      charges: paidBetween(start, end),
      salaries: PayrollRepo.totalCost(monthKey(start)),
      otherExpenses: other,
      daysLeft: daysLeft,
      daysElapsed: elapsed,
    );
  }
}
