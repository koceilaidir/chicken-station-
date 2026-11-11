import 'package:chicken_station/data/attendance.dart';
import 'package:chicken_station/data/purchasing.dart';
import 'package:chicken_station/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

MonthGoal goal({
  int sales = 0,
  int goods = 0,
  int charges = 0,
  int salaries = 0,
  int other = 0,
  int left = 10,
}) =>
    MonthGoal(
      month: DateTime(2026, 11),
      sales: sales,
      goodsCost: goods,
      charges: charges,
      salaries: salaries,
      otherExpenses: other,
      daysLeft: left,
      daysElapsed: 30 - left,
    );

void main() {
  group('quantités de stock', () {
    test('affichage', () {
      expect(fmtQty(2), '2');
      expect(fmtQty(1.5), '1,5');
      expect(fmtQty(0.125), '0,125');
      expect(fmtQty(-0.25), '-0,25');
      expect(fmtQty(1200), '1 200');
      expect(fmtQty(2.0004), '2');
    });

    test('saisie avec virgule ou point', () {
      expect(parseQty('1,5'), 1.5);
      expect(parseQty('0.250'), 0.25);
      expect(parseQty(' 2 '), 2);
      expect(parseQty(''), isNull);
      expect(parseQty('abc'), isNull);
    });

    test('mois', () {
      expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
      expect(fmtMonth(DateTime(2026, 11)), 'novembre 2026');
    });
  });

  group('jours du mois', () {
    test('en cours de mois, aujourd\'hui compris', () {
      final d = monthDays(DateTime(2026, 11), DateTime(2026, 11, 11, 15));
      expect(d.elapsed, 11);
      expect(d.left, 20);
    });
    test('février 2028 (bissextile)', () {
      expect(monthDays(DateTime(2028, 2), DateTime(2028, 2, 1)).left, 29);
    });
    test('mois passé et mois futur', () {
      expect(monthDays(DateTime(2026, 10), DateTime(2026, 11, 11)).left, 0);
      expect(monthDays(DateTime(2026, 12), DateTime(2026, 11, 11)).left, 31);
    });
  });

  group('objectif du mois', () {
    test('marge, objectif et reste', () {
      final g = goal(sales: 900000, goods: 360000, charges: 150000, salaries: 240000, other: 10000);
      expect(g.margin, 540000);
      expect(g.target, 400000);
      expect(g.remaining, -140000);
      expect(g.profit, 140000);
      expect(g.progress, 1);
    });

    test('ce qu\'il faut faire par jour', () {
      // 400 000 à couvrir, 200 000 de marge faite, 10 jours : 20 000 de marge par jour.
      final g = goal(sales: 500000, goods: 300000, charges: 160000, salaries: 240000, left: 10);
      expect(g.remaining, 200000);
      expect(g.marginPerDay, 20000);
      // Taux de marge 40 % : 20 000 / 0,4 = 50 000 de ventes par jour.
      expect(g.marginRate, closeTo(0.4, 0.0001));
      expect(g.salesPerDay, 50000);
      expect(g.progress, closeTo(0.5, 0.0001));
    });

    test('aucune vente : pas de division par zéro', () {
      final g = goal(charges: 100000);
      expect(g.marginRate, 0);
      expect(g.salesPerDay, 0);
      expect(g.marginPerDay, 10000);
      expect(g.progress, 0);
    });

    test('rien à couvrir', () {
      final g = goal(sales: 1000);
      expect(g.progress, 1);
      expect(g.marginPerDay, 0);
    });
  });

  group('paie', () {
    test('reste à payer = salaire + primes − acomptes − déjà payé', () {
      final m = PayMonth(salary: 40000, advances: 10000, paid: 0, bonus: 2000);
      expect(m.remaining, 32000);
      expect(PayMonth(salary: 40000, advances: 10000, paid: 30000, bonus: 0).remaining, 0);
    });
  });

  group('présence des employés', () {
    Employee emp({String start = '2026-09', String end = ''}) => Employee(
          id: 1,
          name: 'Karim',
          job: 'cuisinier',
          phone: '',
          salary: 40000,
          active: end.isEmpty,
          startMonth: start,
          endMonth: end,
        );

    test('payé seulement les mois où il travaille', () {
      final e = emp(start: '2026-09', end: '2026-11');
      expect(e.worksIn('2026-08'), isFalse);
      expect(e.worksIn('2026-09'), isTrue);
      expect(e.worksIn('2026-11'), isTrue);
      expect(e.worksIn('2026-12'), isFalse);
    });

    test('encore en poste : tous les mois depuis son arrivée', () {
      final e = emp(start: '2026-10');
      expect(e.worksIn('2027-03'), isTrue);
      expect(e.worksIn('2026-09'), isFalse);
    });

    test('trop versé : reste négatif', () {
      expect(PayMonth(salary: 40000, advances: 25000, paid: 20000, bonus: 0).remaining, -5000);
    });
  });

  group('Pointage et paie', () {
    AttRecap recap({int openWhole = 26, int journee = 0, int demi = 0, int doubles = 0, int absent = 0, int salary = 39000}) => AttRecap(
          openDays: openWhole,
          openDaysWholeMonth: openWhole,
          closedDays: 30 - openWhole,
          journee: journee,
          demi: demi,
          doubles: doubles,
          repos: 0,
          absent: absent,
          unmarked: 0,
          salary: salary,
        );

    test('valeur d\'une journée = salaire ÷ jours d\'ouverture', () {
      expect(recap().dayValue, 1500); // 39 000 ÷ 26
    });

    test('une demi-journée manquée = 0,5 jour retenu', () {
      final r = recap(absent: 1, demi: 2);
      expect(r.missedDays, 2.0);
      expect(r.suggestedDeduction, 3000);
    });

    test('chaque double journée = une journée en prime', () {
      expect(recap(doubles: 3).suggestedBonus, 4500);
    });

    test('jours travaillés : demi 0,5 et double 2', () {
      expect(recap(journee: 20, demi: 2, doubles: 2).workedDays, 25.0);
    });

    test('mois sans jour d\'ouverture : pas de division par zéro', () {
      expect(recap(openWhole: 0).dayValue, 0);
    });

    test('retenue et prime changent ce qui est dû', () {
      final m = PayMonth(salary: 39000, advances: 10000, paid: 0, bonus: 4500, deduction: 3000);
      expect(m.due, 40500);
      expect(m.remaining, 30500);
    });
  });
}
