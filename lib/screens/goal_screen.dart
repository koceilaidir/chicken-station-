import 'package:flutter/material.dart';

import '../data/purchasing.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'safe_screen.dart';
import 'variance_screen.dart';

/// Compta : résultat du mois, coffre maison et écarts de caisse.
class ComptaScreen extends StatefulWidget {
  const ComptaScreen({super.key});

  @override
  State<ComptaScreen> createState() => _ComptaScreenState();
}

class _ComptaScreenState extends State<ComptaScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: IosSegmented<int>(
              expand: false,
              values: const [0, 1, 2],
              selected: _tab,
              label: (i) => const ['Résultat du mois', 'Coffre', 'Écarts de caisse'][i],
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
        ),
        Expanded(
          child: switch (_tab) {
            0 => const MonthGoalScreen(),
            1 => const SafeScreen(),
            _ => const VarianceScreen(),
          },
        ),
      ],
    );
  }
}

/// Objectif du mois : la marge (ventes − marchandise) doit payer le loyer, les factures et les salaires.
class MonthGoalScreen extends StatefulWidget {
  const MonthGoalScreen({super.key});

  @override
  State<MonthGoalScreen> createState() => _MonthGoalScreenState();
}

class _MonthGoalScreenState extends State<MonthGoalScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrent => monthKey(_month) == monthKey(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final g = ChargesRepo.goal(_month);
    final done = g.remaining <= 0;
    final color = done ? AppColors.greenText : (g.progress >= 0.6 ? const Color(0xFF8A6A00) : AppColors.redText);

    final summary = IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Marge réalisée', style: TextStyle(color: AppColors.textSecondary)),
                    Text(fmtDa(g.margin), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: color)),
                    Text('sur ${fmtDa(g.target)} à couvrir', style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text('${(g.progress * 100).round()} %', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: g.progress,
              minHeight: 14,
              backgroundColor: AppColors.fill,
              color: done ? AppColors.green : AppColors.yellow,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: done ? AppColors.greenSoft : AppColors.yellowSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _advice(g),
              style: TextStyle(fontWeight: FontWeight.w600, color: done ? AppColors.greenText : const Color(0xFF5C4700)),
            ),
          ),
        ],
      ),
    );

    final breakdown = IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Calcul'),
          KeyValueRow('Ventes du mois', fmtDa(g.sales)),
          KeyValueRow('Marchandise achetée', '− ${fmtDa(g.goodsCost)}',
              sub: "bons d'achat (Dépenses › Fournisseurs) + dépenses Matière et Emballages"),
          KeyValueRow('Marge', fmtDa(g.margin), bold: true),
          const SizedBox(height: 8),
          KeyValueRow('Charges payées', fmtDa(g.charges), sub: 'loyer, électricité, factures… payés ce mois (Dépenses › Charges)'),
          KeyValueRow('Salaires du mois', fmtDa(g.salaries), sub: 'salaires + primes − retenues (Dépenses › Employés)'),
          KeyValueRow('Autres dépenses', fmtDa(g.otherExpenses), sub: 'Entretien et Divers du mois'),
          KeyValueRow('À couvrir', fmtDa(g.target), bold: true),
          const SizedBox(height: 8),
          KeyValueRow(
            done ? 'Bénéfice estimé' : 'Manque',
            fmtDa(g.profit.abs()),
            bold: true,
            valueColor: done ? AppColors.greenText : AppColors.redText,
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        PageHeader(
          overline: 'Comptabilité',
          title: 'Résultat du mois',
          actions: [
            IconButton(
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            SizedBox(
              width: 150,
              child: Text(fmtMonth(_month), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              onPressed: _isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (c, cons) => cons.maxWidth < 900
              ? Column(children: [summary, const SizedBox(height: 14), breakdown])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: summary),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: breakdown),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Pour un résultat juste : tapez vos bons d'achat, vos charges (loyer, électricité…) et les salaires dans Dépenses.",
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  String _advice(MonthGoal g) {
    if (g.target <= 0) return 'Ajoutez vos employés et payez vos charges dans Dépenses pour voir le résultat du mois.';
    if (g.remaining <= 0) {
      return 'Les salaires, les charges et les dépenses du mois sont couverts. Bénéfice estimé ${fmtDa(g.profit)}.';
    }
    if (g.daysLeft <= 0) return 'Mois terminé : il a manqué ${fmtDa(g.remaining)} de marge pour tout couvrir.';
    if (g.goodsCost == 0 && g.sales > 0) {
      return 'Il reste ${fmtDa(g.remaining)} à couvrir en ${g.daysLeft} jour(s). Aucun achat de marchandise n\'est encore '
          'enregistré ce mois-ci : la marge affichée est donc trop belle. Tapez vos bons d\'achat (Dépenses › Fournisseurs '
          'ou dépenses « Matière ») pour connaître les ventes à faire par jour.';
    }
    final rate = (g.marginRate * 100).round();
    final sales = g.salesPerDay > 0
        ? ', soit environ ${fmtDa(g.salesPerDay)} de ventes par jour (marge actuelle $rate %)'
        : '';
    return 'Il reste ${fmtDa(g.remaining)} à couvrir en ${g.daysLeft} jour(s) : '
        '${fmtDa(g.marginPerDay)} de marge par jour$sales.';
  }
}
