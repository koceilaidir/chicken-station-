import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repos.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Ouverture de la journée : saisie du fond de caisse ramené (avec fond conseillé).
Future<Day?> openDayDialog(BuildContext context) async {
  final s = DayRepo.suggestedFund();
  final ctrl = TextEditingController(text: '${s.suggested}');
  final fund = await showDialog<int>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Ouvrir la journée'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fond de caisse ramené ce matin', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            FieldBox(controller: ctrl, numeric: true, big: true, autofocus: true),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fond conseillé : ${fmtDa(s.suggested)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Monnaie de rendu ${fmtDa(s.change)} + dépenses moyennes des 4 derniers '
                    '${dayNames[DateTime.now().weekday - 1]}s ${fmtDa(s.avgExpenses)} + 10 % de marge, arrondi au 500 supérieur.',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF5C4700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text('Ce montant est retiré du coffre maison.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Retour')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.text),
          onPressed: () {
            final v = parseAmount(ctrl.text);
            if (v == null || v < 0) return;
            Navigator.pop(c, v);
          },
          child: const Text('Ouvrir la caisse'),
        ),
      ],
    ),
  );
  if (fund == null) return null;
  return DayRepo.open(Session.I.user!.id, fund);
}

/// Saisie d'une dépense (payée depuis la caisse ou depuis le coffre).
Future<bool> addExpenseDialog(BuildContext context, {int? dayId, String defaultSource = 'caisse'}) async {
  final label = TextEditingController();
  final amount = TextEditingController();
  var category = ExpenseRepo.categories.first;
  var source = defaultSource;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Nouvelle dépense'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FieldBox(controller: label, hint: 'Libellé (ex. pain, légumes, gaz)', autofocus: true),
              const SizedBox(height: 10),
              FieldBox(controller: amount, hint: 'Montant en DA', numeric: true),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cat in ExpenseRepo.categories)
                    ChoiceChip(
                      label: Text(cat),
                      selected: category == cat,
                      onSelected: (_) => setD(() => category = cat),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              IosSegmented<String>(
                values: const ['caisse', 'coffre'],
                selected: source,
                label: (v) => v == 'caisse' ? 'Payé depuis la caisse' : 'Payé depuis le coffre',
                onChanged: (v) => setD(() => source = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
          FilledButton(
            onPressed: () {
              final v = parseAmount(amount.text);
              if (label.text.trim().isEmpty || v == null || v <= 0) return;
              ExpenseRepo.add(
                dayId: dayId,
                userId: Session.I.user!.id,
                label: label.text.trim(),
                category: category,
                amount: v,
                source: source,
              );
              Navigator.pop(c, true);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}
