import 'db.dart';
import 'purchasing.dart';
import '../ui/format.dart';

/// Pointage d'un employé pour une journée : on ne pointe que les exceptions.
/// Un jour sans pointage = journée normale (le salaire du mois la paie déjà).
class AttKind {
  static const absent = 'absent';
  static const demi = 'demi';
  static const double_ = 'double';

  /// Anciennes valeurs (versions 0.6.0) : comptées comme une journée normale.
  static const journee = 'journee';
  static const repos = 'repos';

  /// Boutons proposés.
  static const all = [absent, demi, double_];

  static const labels = {
    absent: 'Absent',
    demi: 'Demi',
    double_: 'Double',
    journee: 'Journée',
    repos: 'Repos',
  };
}

/// Bilan du pointage d'un employé sur un mois, au prix de sa journée.
class AttRecap {
  AttRecap({required this.absent, required this.demi, required this.doubles, required this.dayRate});

  final int absent;
  final int demi;
  final int doubles;

  /// Prix d'une journée (fiche de l'employé).
  final int dayRate;

  /// Journées manquées : une absence = 1, une demi-journée = 0,5.
  double get missedDays => absent + demi * 0.5;

  /// Retenue : absences × journée + demis × demi-journée.
  int get suggestedDeduction => absent * dayRate + demi * (dayRate / 2).round();

  /// Prime : chaque double journée = une journée en plus.
  int get suggestedBonus => doubles * dayRate;

  bool get isEmpty => absent == 0 && demi == 0 && doubles == 0;
}

class AttendanceRepo {
  static String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parse(String day) => DateTime.parse(day);

  // ---------------------------------------------------------------- pointage

  /// La caisse a-t-elle été ouverte ce jour-là ?
  static bool shopOpened(String day) =>
      AppDb.I.db.select('SELECT 1 FROM days WHERE substr(opened_at, 1, 10) = ? LIMIT 1', [day]).isNotEmpty;

  /// Pointage du jour : employé → type.
  static Map<int, String> forDay(String day) => {
        for (final r in AppDb.I.db.select('SELECT employee_id, kind FROM attendance WHERE day = ?', [day]))
          r['employee_id'] as int: r['kind'] as String,
      };

  /// Pointe (ou dépointe avec [kind] null). Chaque changement est inscrit au journal d'activité.
  static void set(int userId, Employee e, String day, String? kind) {
    final before = AppDb.I.db.select('SELECT kind FROM attendance WHERE employee_id = ? AND day = ?', [e.id, day]);
    final old = before.isEmpty ? null : before.first['kind'] as String;
    if (old == kind) return;
    if (kind == null) {
      AppDb.I.db.execute('DELETE FROM attendance WHERE employee_id = ? AND day = ?', [e.id, day]);
    } else {
      AppDb.I.db.execute(
        'INSERT OR REPLACE INTO attendance (employee_id, day, kind, user_id, updated_at) VALUES (?, ?, ?, ?, ?)',
        [e.id, day, kind, userId, DateTime.now().toIso8601String()],
      );
    }
    String label(String? k) => k == null ? 'non pointé' : AttKind.labels[k]!;
    AppDb.I.audit(userId, 'pointage', '${e.name} · ${fmtDate(parse(day))} : ${old == null ? '' : '${label(old)} → '}${label(kind)}');
  }

  /// Pointage d'un employé jour par jour sur un mois (« 2026-11 »).
  static Map<String, String> month(int employeeId, String month) => {
        for (final r in AppDb.I.db.select(
          "SELECT day, kind FROM attendance WHERE employee_id = ? AND day LIKE ? ORDER BY day",
          [employeeId, '$month-%'],
        ))
          r['day'] as String: r['kind'] as String,
      };

  /// Bilan du mois : seules les absences, demis et doubles comptent.
  static AttRecap recap(Employee e, String monthKey) {
    final marks = month(e.id, monthKey).values;
    int n(String k) => marks.where((m) => m == k).length;
    return AttRecap(
      absent: n(AttKind.absent),
      demi: n(AttKind.demi),
      doubles: n(AttKind.double_),
      dayRate: e.dayRate,
    );
  }
}
