import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repos.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Comptabilité › Écarts de caisse : chaque clôture ajoute son écart,
/// le cumul repart de 0 chaque mois, l'historique reste consultable.
class VarianceScreen extends StatefulWidget {
  const VarianceScreen({super.key});

  @override
  State<VarianceScreen> createState() => _VarianceScreenState();
}

class _VarianceScreenState extends State<VarianceScreen> {
  late DateTime _end; // 1er jour du dernier mois affiché
  int _len = 1;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _end = DateTime(n.year, n.month);
  }

  DateTime _addMonths(DateTime d, int m) => DateTime(d.year, d.month + m);

  bool get _isCurrent {
    final n = DateTime.now();
    return _end.year == n.year && _end.month == n.month;
  }

  String _monthLabel(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final start = _addMonths(_end, -(_len - 1));
    final days = DayRepo.closedBetween(start, _addMonths(_end, 1));
    final diffs = days.map((d) => d.diff ?? 0).toList();
    final net = diffs.fold<int>(0, (a, b) => a + b);
    final short = diffs.where((x) => x < 0).fold<int>(0, (a, b) => a + b);
    final surplus = diffs.where((x) => x > 0).fold<int>(0, (a, b) => a + b);
    final exact = diffs.where((x) => x == 0).length;
    final period = _len == 1 ? _monthLabel(_end) : '${_monthLabel(start)} → ${_monthLabel(_end)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          overline: 'Comptabilité',
          title: 'Écarts de caisse',
          actions: [
            IosSegmented<int>(
              expand: false,
              values: const [1, 3, 6],
              selected: _len,
              label: (n) => '$n mois',
              onChanged: (n) => setState(() => _len = n),
            ),
            IconButton.filledTonal(
              onPressed: () => setState(() => _end = _addMonths(_end, -1)),
              icon: const Icon(Icons.chevron_left),
            ),
            SizedBox(width: 190, child: Text(period, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton.filledTonal(
              onPressed: _isCurrent ? null : () => setState(() => _end = _addMonths(_end, 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (_isCurrent && _len == 1) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(14)),
            child: Text(
              'Le compteur est reparti de 0 le 1er ${monthNames[_end.month - 1]}. Les mois précédents restent consultables avec la flèche ‹.',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5C4700)),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Écart cumulé',
                value: '${fmtSigned(net)} DA',
                valueColor: net < 0 ? AppColors.redText : (net > 0 ? AppColors.greenText : null),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: StatTile(label: 'Total des manques', value: '${fmtSigned(short)} DA', valueColor: AppColors.redText)),
            const SizedBox(width: 12),
            Expanded(child: StatTile(label: 'Total des surplus', value: '${fmtSigned(surplus)} DA', valueColor: AppColors.greenText)),
            const SizedBox(width: 12),
            Expanded(child: StatTile(label: 'Clôtures justes', value: '$exact / ${days.length}')),
          ],
        ),
        const SizedBox(height: 16),
        IosCard(child: _len == 1 ? _dailyTable(days) : _monthlyTable(start, days)),
      ],
    );
  }

  Widget _dailyTable(List<Day> days) {
    if (days.isEmpty) return const Text('Aucune clôture sur cette période.');
    final asc = days.reversed.toList();
    var run = 0;
    final rows = <TableRow>[];
    for (final d in asc) {
      run += d.diff ?? 0;
      rows.add(_row([
        fmtDate(d.openedAt),
        d.closedBy ?? '',
        fmtDa(d.expected ?? 0),
        '${fmtSigned(d.diff ?? 0)} DA',
        '${fmtSigned(run)} DA',
        (d.reason ?? '').isEmpty ? '—' : d.reason!,
      ], diff: d.diff ?? 0, cumul: run));
    }
    return Table(
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(1), 4: FlexColumnWidth(1.1), 5: FlexColumnWidth(1.6)},
      children: [_header(['Date', 'Clôturé par', 'Attendu', 'Écart', 'Cumul du mois', 'Motif']), ...rows.reversed],
    );
  }

  Widget _monthlyTable(DateTime start, List<Day> days) {
    final rows = <TableRow>[];
    for (var i = _len - 1; i >= 0; i--) {
      final m = _addMonths(start, i);
      final inMonth = days.where((d) => d.openedAt.year == m.year && d.openedAt.month == m.month).toList();
      final diffs = inMonth.map((d) => d.diff ?? 0);
      final net = diffs.fold<int>(0, (a, b) => a + b);
      final short = diffs.where((x) => x < 0).fold<int>(0, (a, b) => a + b);
      final surplus = diffs.where((x) => x > 0).fold<int>(0, (a, b) => a + b);
      rows.add(_row([
        _monthLabel(m) + (i == _len - 1 && _isCurrent ? ' (en cours)' : ''),
        '${inMonth.length}',
        '${diffs.where((x) => x == 0).length}',
        '${fmtSigned(short)} DA',
        '${fmtSigned(surplus)} DA',
        '${fmtSigned(net)} DA',
      ], diff: short, cumul: surplus));
    }
    return Table(children: [_header(['Mois', 'Clôtures', 'Justes', 'Manques', 'Surplus', 'Écart du mois']), ...rows]);
  }

  TableRow _header(List<String> cols) => TableRow(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.separator))),
        children: [
          for (final c in cols)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text(c.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
        ],
      );

  TableRow _row(List<String> cells, {required int diff, required int cumul}) {
    Color colorFor(int v) => v < 0 ? AppColors.redText : (v > 0 ? AppColors.greenText : AppColors.textSecondary);
    return TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3)))),
      children: [
        for (var i = 0; i < cells.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Text(
              cells[i],
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: i == 0 || i >= 3 ? FontWeight.w700 : FontWeight.w400,
                color: i == 3 ? colorFor(diff) : (i == 4 ? colorFor(cumul) : AppColors.text),
              ),
            ),
          ),
      ],
    );
  }
}
