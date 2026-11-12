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
    builder: (c) => AlertDialog(scrollable: true, 
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

/// Paiement depuis la caisse : la journée doit être ouverte.
/// Renvoie la source à utiliser ('caisse' ou 'coffre'), ou null si on revient en arrière.
Future<String?> ensureCashOpen(BuildContext context, String source) async {
  if (source != 'caisse' || DayRepo.current() != null) return source;
  final choice = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(scrollable: true, 
      title: const Text("La caisse n'est pas ouverte"),
      content: const SizedBox(
        width: 420,
        child: Text("Pour payer avec l'argent de la caisse, ouvrez d'abord la journée avec le fond du matin. "
            'Sinon, payez avec l\'argent du coffre.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Retour')),
        TextButton(onPressed: () => Navigator.pop(c, 'coffre'), child: const Text('Payer depuis le coffre')),
        FilledButton(onPressed: () => Navigator.pop(c, 'open'), child: const Text('Ouvrir la caisse')),
      ],
    ),
  );
  if (choice != 'open') return choice;
  if (!context.mounted) return null;
  if (!Session.I.can(Perm.cloture)) {
    toast(context, "Vous n'avez pas le droit d'ouvrir la journée.", error: true);
    return null;
  }
  final d = await openDayDialog(context);
  return d == null ? null : 'caisse';
}

/// Au démarrage de session : rappelle d'ouvrir la caisse si ce n'est pas fait.
Future<void> remindOpenDay(BuildContext context) async {
  if (DayRepo.current() != null || !Session.I.can(Perm.cloture)) return;
  final open = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(scrollable: true, 
      title: const Text("La caisse n'est pas ouverte"),
      content: const SizedBox(
        width: 420,
        child: Text("Ouvrir la journée maintenant avec le fond du matin ? Sans journée ouverte, on ne peut pas encaisser."),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ouvrir la caisse')),
      ],
    ),
  );
  if (open == true && context.mounted) {
    final d = await openDayDialog(context);
    if (d != null && context.mounted) toast(context, 'Journée ouverte avec un fond de ${fmtDa(d.openingFund)}');
  }
}

/// Saisie d'une dépense (payée depuis la caisse ou depuis le coffre).
Future<bool> addExpenseDialog(BuildContext context, {int? dayId, String defaultSource = 'caisse', bool divers = false}) async {
  final label = TextEditingController();
  final amount = TextEditingController();
  var category = divers ? 'Divers' : ExpenseRepo.categories.first;
  var source = defaultSource;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(scrollable: true, 
        title: Text(divers ? 'Dépense divers' : 'Nouvelle dépense'),
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
              if (!divers) ...[Wrap(
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
              const SizedBox(height: 12)],
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
            onPressed: () async {
              final v = parseAmount(amount.text);
              if (label.text.trim().isEmpty || v == null || v <= 0) {
                toast(c, 'Tapez le titre et le montant.', error: true);
                return;
              }
              final src = await ensureCashOpen(c, source);
              if (src == null || !c.mounted) return;
              final day = DayRepo.current();
              if (src == 'caisse' && day != null && v > DayRepo.summary(day).expectedInDrawer) {
                toast(c, 'Il n\'y a que ${fmtDa(DayRepo.summary(day).expectedInDrawer)} dans la caisse.', error: true);
                return;
              }
              ExpenseRepo.add(
                dayId: src == 'caisse' ? (day?.id ?? dayId) : (dayId ?? day?.id),
                userId: Session.I.user!.id,
                label: label.text.trim(),
                category: category,
                amount: v,
                source: src,
              );
              if (c.mounted) Navigator.pop(c, true);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Journée travaillée sur papier (panne du PC) : on la saisit après coup, déjà clôturée.
Future<bool> catchUpDayDialog(BuildContext context) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => const _CatchUpDialog());
  return ok ?? false;
}

class _ExpLine {
  final label = TextEditingController();
  final amount = TextEditingController();
  int get v => parseAmount(amount.text) ?? 0;
}

class _CatchUpDialog extends StatefulWidget {
  const _CatchUpDialog();

  @override
  State<_CatchUpDialog> createState() => _CatchUpDialogState();
}

class _CatchUpDialogState extends State<_CatchUpDialog> {
  DateTime _date = DateTime.now().subtract(const Duration(days: 1));
  final _fund = TextEditingController();
  final _tickets = TextEditingController();
  final _counted = TextEditingController();
  final _card = TextEditingController();
  final _taken = TextEditingController();
  bool _takenEdited = false;
  bool _withCard = false;
  final _exp = <_ExpLine>[_ExpLine()];

  int _n(TextEditingController c) => parseAmount(c.text) ?? 0;
  int get _expTotal => _exp.fold<int>(0, (a, e) => a + e.v);
  int get _cash => _n(_counted) - _n(_fund) + _expTotal;

  void _changed() {
    if (!_takenEdited) _taken.text = _counted.text;
    setState(() {});
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now.subtract(const Duration(days: 1)),
    );
    if (d != null) setState(() => _date = d);
  }

  void _save() {
    final expenses = [
      for (final e in _exp)
        if (e.v > 0) (label: e.label.text.trim().isEmpty ? 'Dépense' : e.label.text.trim(), amount: e.v),
    ];
    try {
      final d = DayRepo.catchUp(
        userId: Session.I.user!.id,
        date: _date,
        fund: _n(_fund),
        tickets: _n(_tickets),
        counted: _n(_counted),
        card: _withCard ? _n(_card) : 0,
        expenses: expenses,
        takenHome: _taken.text.trim().isEmpty ? _n(_counted) : _n(_taken),
      );
      toast(context, 'Journée du ${fmtDate(d.openedAt)} enregistrée.');
      Navigator.pop(context, true);
    } catch (e) {
      toast(context, e is StateError ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final isYesterday = _date.year == yesterday.year && _date.month == yesterday.month && _date.day == yesterday.day;
    const label = TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600);
    Widget field(String title, TextEditingController c, String hint) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: label),
              const SizedBox(height: 4),
              FieldBox(controller: c, hint: hint, numeric: true, onChanged: (_) => _changed()),
            ],
          ),
        );
    return AlertDialog(scrollable: true, 
      title: const Text('Rattraper une journée'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pour une journée travaillée sur papier (panne du PC). Elle est enregistrée déjà clôturée : '
                'recette, dépenses et coffre seront justes. Le pointage se fait dans la page Pointage.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Jour :  ', style: label),
                  ChoiceChip(label: const Text('Hier'), selected: isYesterday, onSelected: (_) => setState(() => _date = yesterday)),
                  ChoiceChip(
                    avatar: const Icon(Icons.calendar_today, size: 16),
                    label: Text(isYesterday ? 'Autre jour' : fmtLongDate(_date)),
                    selected: !isYesterday,
                    onSelected: (_) => _pickDate(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                field('Fond du matin', _fund, 'DA'),
                const SizedBox(width: 10),
                field('Nombre de tickets', _tickets, 'ex. 48'),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                field('Argent dans la caisse le soir', _counted, 'DA (fond compris)'),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Emporté au coffre', style: label),
                      const SizedBox(height: 4),
                      FieldBox(
                        controller: _taken,
                        hint: 'DA (tout par défaut)',
                        numeric: true,
                        onChanged: (_) => setState(() => _takenEdited = true),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              const Text('Dépenses payées avec la caisse', style: label),
              for (final e in _exp)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: FieldBox(controller: e.label, hint: 'ex. Pain')),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: FieldBox(controller: e.amount, hint: 'DA', numeric: true, onChanged: (_) => _changed())),
                      IconButton(
                        onPressed: _exp.length <= 1 ? null : () => setState(() => _exp.remove(e)),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _exp.add(_ExpLine())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une dépense'),
                ),
              ),
              if (_withCard)
                Row(children: [field('Payé par TPE', _card, 'DA')])
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => setState(() => _withCard = true), child: const Text('+ Paiements par TPE')),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    KeyValueRow('Recette en espèces', fmtDa(_cash < 0 ? 0 : _cash),
                        sub: 'argent du soir ${fmtDa(_n(_counted))} − fond ${fmtDa(_n(_fund))} + dépenses ${fmtDa(_expTotal)}'),
                    if (_withCard && _n(_card) > 0) KeyValueRow('Recette TPE', fmtDa(_n(_card))),
                    KeyValueRow('Recette du jour', fmtDa((_cash < 0 ? 0 : _cash) + (_withCard ? _n(_card) : 0)), bold: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
        FilledButton(onPressed: _save, child: const Text('Enregistrer la journée')),
      ],
    );
  }
}
