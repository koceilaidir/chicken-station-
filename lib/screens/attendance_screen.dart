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
    final closed = AttendanceRepo.closedReason(_key);
    final weekly = AttendanceRepo.weeklyClosed.contains(_day.weekday);
    final marks = AttendanceRepo.forDay(_key);
    final staff = _staff;
    final unmarked = staff.where((e) => !marks.containsKey(e.id)).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          title: 'Pointage',
          subtitle: 'Qui a travaillé, et combien : sert au calcul de la paie en fin de mois',
          actions: [SecondaryButton(label: 'Jours de fermeture', onPressed: _weeklyDialog)],
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
        if (closed != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.store_mall_directory_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$closed. Personne n\'est compté absent ce jour-là.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (!weekly)
                  TextButton(
                    onPressed: () {
                      AttendanceRepo.setClosed(_uid, _key, false);
                      setState(() {});
                    },
                    child: const Text('Rouvrir ce jour'),
                  ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  unmarked == 0 ? 'Tout le monde est pointé.' : '$unmarked employé(s) pas encore pointé(s).',
                  style: TextStyle(color: unmarked == 0 ? AppColors.greenText : AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
              if (unmarked > 0)
                SecondaryButton(
                  label: 'Tous en journée',
                  onPressed: () {
                    for (final e in staff) {
                      if (!marks.containsKey(e.id)) AttendanceRepo.set(_uid, e, _key, AttKind.journee);
                    }
                    setState(() {});
                  },
                ),
              const SizedBox(width: 8),
              SecondaryButton(label: 'Fast-food fermé ce jour', onPressed: _closeDay),
            ],
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
          'Demi = une demi-journée · Double = deux services · Repos = jour de repos prévu (pas une absence). '
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
    Widget cell(String t, {bool bold = false, Color? color, double w = 74}) => SizedBox(
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
                  for (final h in ['Journées', 'Demi', 'Doubles', 'Repos', 'Absences', 'Non pointés'])
                    cell(h, color: AppColors.textSecondary, w: h == 'Non pointés' ? 90 : 74),
                ]),
                const Divider(),
                for (final e in staff)
                  Builder(builder: (_) {
                    final r = AttendanceRepo.recap(e, mk);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(width: 170, child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                        cell('${r.journee}'),
                        cell('${r.demi}'),
                        cell('${r.doubles}', color: r.doubles > 0 ? AppColors.greenText : null, bold: r.doubles > 0),
                        cell('${r.repos}'),
                        cell('${r.absent}', color: r.absent > 0 ? AppColors.redText : null, bold: r.absent > 0),
                        cell('${r.unmarked}', w: 90, color: r.unmarked > 0 ? AppColors.redText : null, bold: r.unmarked > 0),
                      ]),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Jours de fermeture ce mois : ${AttendanceRepo.recap(staff.first, mk).closedDays}. '
            'Les primes (doubles) et retenues (absences) se valident dans Dépenses › Employés, au moment de la paie.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _closeDay() async {
    final reason = await askText(context, 'Fast-food fermé le ${fmtDate(_day)}', hint: 'Raison (facultatif) : fête, travaux…', ok: 'Marquer fermé');
    if (reason == null || !mounted) return;
    AttendanceRepo.setClosed(_uid, _key, true, reason: reason);
    setState(() {});
  }

  Future<void> _weeklyDialog() async {
    const names = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    final sel = {...AttendanceRepo.weeklyClosed};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Fermé chaque semaine'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cochez les jours où le fast-food ne travaille jamais. Ces jours ne comptent pas comme absence. '
                  'Pour une fermeture exceptionnelle (fête…), utilisez « Fast-food fermé ce jour ».',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < 7; i++)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(names[i]),
                    value: sel.contains(i + 1),
                    onChanged: (v) => setD(() => v == true ? sel.add(i + 1) : sel.remove(i + 1)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    AttendanceRepo.setWeeklyClosed(_uid, sel);
    setState(() {});
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
    AttKind.journee: (AppColors.greenSoft, AppColors.greenText),
    AttKind.double_: (AppColors.greenText, Colors.white),
    AttKind.repos: (Color(0xFFE8E8ED), AppColors.text),
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
