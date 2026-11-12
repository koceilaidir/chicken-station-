import 'package:flutter/material.dart';

import '../data/attendance.dart';
import '../data/models.dart';
import '../data/purchasing.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Pointage des employés (admin et gérant) : une ligne par employé, un bouton par type de journée.
/// Les jours de fermeture ne comptent jamais comme absence. Le bilan du mois sert au moment de la paie.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  static const perms = [Perm.pointage];

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _day = DateTime.now();

  int get _uid => Session.I.user!.id;
  String get _key => AttendanceRepo.key(_day);
  bool get _isToday => _key == AttendanceRepo.key(DateTime.now());

  void _shift(int days) {
    final next = DateTime(_day.year, _day.month, _day.day + days);
    if (next.isAfter(DateTime.now())) return;
    setState(() => _day = next);
  }

  List<Employee> get _staff =>
      PayrollRepo.employees().where((e) => e.worksIn(monthKey(_day)) && (e.active || e.endMonth.isNotEmpty)).toList();

  @override
  Widget build(BuildContext context) {
    final opened = AttendanceRepo.shopOpened(_key);
    final marks = AttendanceRepo.forDay(_key);
    final staff = _staff;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        const PageHeader(
          title: 'Pointage',
          subtitle: 'Pointez seulement les absences, demi-journées et doubles. Rien de pointé = journée normale.',
        ),
        const SizedBox(height: 14),
        // Choix du jour
        IosCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Column(
                  children: [
                    Text(_isToday ? "Aujourd'hui" : fmtLongDate(_day),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    if (_isToday) Text(fmtLongDate(_day), style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              IconButton(onPressed: _isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: opened ? AppColors.greenSoft : AppColors.fill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            opened
                ? 'Caisse ouverte ce jour : les employés non pointés ont fait leur journée normale.'
                : "Caisse pas ouverte ce jour. Si le fast-food a quand même travaillé (panne…), pointez comme d'habitude.",
            style: TextStyle(fontWeight: FontWeight.w600, color: opened ? AppColors.greenText : AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 12),
        IosCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              if (staff.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun employé. Ajoutez-les dans Dépenses › Employés.', style: TextStyle(color: AppColors.textSecondary)),
                ),
              for (final e in staff)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3)))),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: 200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            Text(e.job.isEmpty ? 'Employé' : e.job, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      _KindPicker(
                        value: marks[e.id],
                        onChanged: (k) {
                          AttendanceRepo.set(_uid, e, _key, k);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Absent = journée retirée · Demi = demi-journée retirée · Double = journée ajoutée, au prix de la journée de chacun. '
          'Touchez à nouveau un bouton choisi pour l\'enlever.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        _monthRecap(staff),
      ],
    );
  }

  Widget _monthRecap(List<Employee> staff) {
    final mk = monthKey(_day);
    if (staff.isEmpty) return const SizedBox.shrink();
    Widget cell(String t, {bool bold = false, Color? color, double w = 84}) => SizedBox(
          width: w,
          child: Text(t,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color, fontSize: 13)),
        );
    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Bilan de ${fmtMonth(_day)}'),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const SizedBox(width: 170, child: Text('Employé', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                  for (final h in ['Absences', 'Demi', 'Doubles', 'Journée', 'Retenue', 'Prime'])
                    cell(h, color: AppColors.textSecondary),
                ]),
                const Divider(),
                for (final e in staff)
                  Builder(builder: (_) {
                    final r = AttendanceRepo.recap(e, mk);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(width: 170, child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        cell('${r.absent}', color: r.absent > 0 ? AppColors.redText : null, bold: r.absent > 0),
                        cell('${r.demi}', color: r.demi > 0 ? AppColors.redText : null, bold: r.demi > 0),
                        cell('${r.doubles}', color: r.doubles > 0 ? AppColors.greenText : null, bold: r.doubles > 0),
                        cell(e.dayRate > 0 ? fmtDa(e.dayRate) : '—', color: e.dayRate > 0 ? null : AppColors.redText),
                        cell(r.suggestedDeduction > 0 ? '− ${fmtDa(r.suggestedDeduction)}' : '0',
                            color: r.suggestedDeduction > 0 ? AppColors.redText : null),
                        cell(r.suggestedBonus > 0 ? '+ ${fmtDa(r.suggestedBonus)}' : '0',
                            color: r.suggestedBonus > 0 ? AppColors.greenText : null),
                      ]),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'La retenue et la prime se valident dans Dépenses › Employés, au moment de la paie. '
            'Prix de la journée : sur la fiche de chaque employé.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Boutons Absent · Demi · Journée · Double · Repos. Rien de choisi = non pointé.
class _KindPicker extends StatelessWidget {
  const _KindPicker({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  static const _colors = {
    AttKind.absent: (AppColors.redSoft, AppColors.redText),
    AttKind.demi: (AppColors.yellowSoft, AppColors.text),
    AttKind.double_: (AppColors.greenText, Colors.white),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final k in AttKind.all)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(value == k ? null : k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: value == k ? _colors[k]!.$1 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    AttKind.labels[k]!,
                    style: TextStyle(
                      fontWeight: value == k ? FontWeight.w800 : FontWeight.w500,
                      color: value == k ? _colors[k]!.$2 : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
