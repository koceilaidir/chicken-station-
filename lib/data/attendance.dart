import 'db.dart';
import 'purchasing.dart';
import 'settings.dart';
import '../ui/format.dart';

/// Pointage d'un employé pour une journée.
class AttKind {
  static const journee = 'journee';
  static const demi = 'demi';
  static const double_ = 'double';
  static const repos = 'repos';
  static const absent = 'absent';

  /// Ordre d'affichage des boutons.
  static const all = [absent, demi, journee, double_, repos];

  static const labels = {
    absent: 'Absent',
    demi: 'Demi',
    journee: 'Journée',
    double_: 'Double',
    repos: 'Repos',
  };
}

/// Bilan du pointage d'un employé sur un mois.
class AttRecap {
  AttRecap({
    required this.openDays,
    required this.openDaysWholeMonth,
    required this.closedDays,
    required this.journee,
    required this.demi,
    required this.doubles,
    required this.repos,
    required this.absent,
    required this.unmarked,
    required this.salary,
  });

  /// Jours où le fast-food était ouvert (jusqu'à aujourd'hui pour le mois en cours), pendant son contrat.
  final int openDays;

  /// Jours ouverts sur tout le mois : sert à calculer la valeur d'une journée.
  final int openDaysWholeMonth;
  final int closedDays;
  final int journee;
  final int demi;
  final int doubles;
  final int repos;
  final int absent;

  /// Jours ouverts passés sans pointage : à compléter, jamais comptés comme absence.
  final int unmarked;
  final int salary;

  /// Valeur d'une journée = salaire du mois ÷ jours d'ouverture du mois.
  int get dayValue => openDaysWholeMonth <= 0 ? 0 : (salary / openDaysWholeMonth).round();

  /// Journées manquées : une absence = 1, une demi-journée = 0,5.
  double get missedDays => absent + demi * 0.5;

  /// Journées en plus : chaque double journée = 1 journée de plus.
  int get extraDays => doubles;

  int get suggestedDeduction => (missedDays * dayValue).round();
  int get suggestedBonus => extraDays * dayValue;

  /// Journées travaillées (demi = 0,5 ; double = 2).
  double get workedDays => journee + demi * 0.5 + doubles * 2;
}

class AttendanceRepo {
  static String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parse(String day) => DateTime.parse(day);

  // ---------------------------------------------------------------- jours de fermeture

  /// Jours de la semaine où le fast-food est toujours fermé (1 = lundi … 7 = dimanche).
  static Set<int> get weeklyClosed =>
      Settings.get('weekly_closed').split(',').where((s) => s.isNotEmpty).map(int.parse).toSet();

  static void setWeeklyClosed(int userId, Set<int> days) {
    Settings.set('weekly_closed', (days.toList()..sort()).join(','));
    const names = ['', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    AppDb.I.audit(userId, 'pointage',
        'Fermeture chaque semaine : ${days.isEmpty ? 'aucune' : (days.toList()..sort()).map((d) => names[d]).join(', ')}');
  }

  /// Raison de la fermeture ce jour-là, ou null si le fast-food était ouvert.
  static String? closedReason(String day) {
    final r = AppDb.I.db.select('SELECT reason FROM closed_days WHERE day = ?', [day]);
    if (r.isNotEmpty) {
      final reason = r.first['reason'] as String;
      return reason.isEmpty ? 'Fermé' : reason;
    }
    if (weeklyClosed.contains(parse(day).weekday)) return 'Fermé chaque semaine';
    return null;
  }

  static bool isClosed(String day) => closedReason(day) != null;

  /// Marque un jour précis comme fermé (fête, travaux…) ou le rouvre.
  static void setClosed(int userId, String day, bool closed, {String reason = ''}) {
    if (closed) {
      AppDb.I.db.execute(
        'INSERT OR REPLACE INTO closed_days (day, reason, user_id, created_at) VALUES (?, ?, ?, ?)',
        [day, reason, userId, DateTime.now().toIso8601String()],
      );
    } else {
      AppDb.I.db.execute('DELETE FROM closed_days WHERE day = ?', [day]);
    }
    AppDb.I.audit(userId, 'pointage', '${fmtDate(parse(day))} : ${closed ? 'fermé${reason.isEmpty ? '' : ' ($reason)'}' : 'ouvert'}');
  }

  // ---------------------------------------------------------------- pointage

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

  /// Bilan du mois. Les jours fermés ne comptent jamais comme absence ; les jours non pointés non plus.
  static AttRecap recap(Employee e, String monthKey, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final y = int.parse(monthKey.substring(0, 4));
    final m = int.parse(monthKey.substring(5, 7));
    final days = DateTime(y, m + 1, 0).day;
    final marks = month(e.id, monthKey);
    var openWhole = 0, open = 0, closed = 0, unmarked = 0;
    final count = <String, int>{for (final k in AttKind.all) k: 0};
    final todayKey = key(now);
    for (var d = 1; d <= days; d++) {
      final dk = key(DateTime(y, m, d));
      final isClosed = AttendanceRepo.isClosed(dk);
      if (isClosed) {
        closed++;
      } else {
        openWhole++;
      }
      if (!e.worksIn(monthKey)) continue;
      final kind = marks[dk];
      if (kind != null) count[kind] = count[kind]! + 1;
      if (isClosed || dk.compareTo(todayKey) > 0) continue;
      open++;
      if (kind == null) unmarked++;
    }
    return AttRecap(
      openDays: open,
      openDaysWholeMonth: openWhole,
      closedDays: closed,
      journee: count[AttKind.journee]!,
      demi: count[AttKind.demi]!,
      doubles: count[AttKind.double_]!,
      repos: count[AttKind.repos]!,
      absent: count[AttKind.absent]!,
      unmarked: unmarked,
      salary: PayrollRepo.month(e, monthKey).salary,
    );
  }
}
