import 'package:flutter/material.dart';

import '../data/repos.dart';
import '../state/session.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'day_dialogs.dart';

/// Coffre maison : argent emporté chaque soir, fond ramené chaque matin,
/// paiements faits depuis la maison et retraits du patron.
class SafeScreen extends StatefulWidget {
  const SafeScreen({super.key});

  @override
  State<SafeScreen> createState() => _SafeScreenState();
}

class _SafeScreenState extends State<SafeScreen> {
  Future<void> _manualMove({required bool income}) async {
    final label = TextEditingController();
    final amount = TextEditingController();
    var kind = income ? 'versement' : 'retrait_patron';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(scrollable: true, 
          title: Text(income ? 'Ajouter de l\'argent au coffre' : 'Sortir de l\'argent du coffre'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!income)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final k in const {
                        'retrait_patron': 'Retrait du patron',
                        'loyer': 'Loyer',
                        'salaire': 'Salaire',
                        'facture': 'Facture',
                        'autre': 'Autre',
                      }.entries)
                        ChoiceChip(label: Text(k.value), selected: kind == k.key, onSelected: (_) => setD(() => kind = k.key)),
                    ],
                  ),
                const SizedBox(height: 10),
                FieldBox(controller: label, hint: 'Libellé', autofocus: true),
                const SizedBox(height: 10),
                FieldBox(controller: amount, hint: 'Montant en DA', numeric: true),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Retour')),
            FilledButton(
              onPressed: () {
                final v = parseAmount(amount.text);
                if (v == null || v <= 0) return;
                final text = label.text.trim().isEmpty ? (income ? 'Versement' : 'Sortie') : label.text.trim();
                SafeRepo.add(Session.I.user!.id, text, income ? v : -v, kind);
                Navigator.pop(c, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) setState(() {});
  }

  Future<void> _startingBalance() async {
    final v = await askText(context, "Argent déjà présent au coffre aujourd'hui",
        hint: 'Montant en DA (comptez les billets du coffre)', ok: 'Enregistrer');
    final amount = v == null ? null : parseAmount(v);
    if (amount == null || amount < 0 || !mounted) return;
    // Le solde de départ s'ajoute aux mouvements déjà faits (ex. fond de caisse sorti ce matin).
    SafeRepo.add(Session.I.user!.id, 'Solde de départ du coffre', amount, 'depart');
    setState(() {});
    toast(context, 'Solde de départ enregistré : le coffre est maintenant suivi correctement.');
  }

  @override
  Widget build(BuildContext context) {
    final balance = SafeRepo.balance();
    final moves = SafeRepo.recent();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          title: 'Coffre maison',
          subtitle: 'Argent de la boutique gardé à la maison',
          actions: [
            SecondaryButton(label: 'Dépense payée du coffre', onPressed: () async {
              if (await addExpenseDialog(context, dayId: DayRepo.current()?.id, defaultSource: 'coffre')) setState(() {});
            }),
            SecondaryButton(label: '+ Versement', onPressed: () => _manualMove(income: true)),
            PrimaryButton(label: '− Sortie', onPressed: () => _manualMove(income: false)),
          ],
        ),
        const SizedBox(height: 16),
        if (!SafeRepo.hasStartingBalance()) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.redText),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Le coffre part de 0 dans l'appli. Indiquez l'argent qu'il contenait déjà, sinon le solde sera faux "
                    '(il peut même devenir négatif à la sortie du fond de caisse).',
                    style: TextStyle(color: AppColors.redText, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                PrimaryButton(label: 'Saisir le solde de départ', onPressed: _startingBalance),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        StatTile(
          label: 'Argent au coffre',
          value: fmtDa(balance),
          sub: 'Emporté chaque soir − fond ramené chaque matin − paiements depuis la maison',
          valueColor: balance < 0 ? AppColors.redText : null,
          highlight: true,
        ),
        const SizedBox(height: 16),
        IosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Mouvements'),
              if (moves.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 10), child: Text('Aucun mouvement pour le moment.')),
              for (final m in moves)
                KeyValueRow(
                  m.label,
                  '${m.amount > 0 ? '+' : '−'}${fmtNum(m.amount.abs())}',
                  sub: fmtDateTime(m.createdAt),
                  valueColor: m.amount > 0 ? AppColors.greenText : AppColors.text,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
