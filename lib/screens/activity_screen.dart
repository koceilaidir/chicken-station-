import 'package:flutter/material.dart';

import '../data/activity.dart';
import '../data/models.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

enum _Period {
  today("Aujourd'hui"),
  yesterday('Hier'),
  week('7 jours'),
  month('Ce mois'),
  lastMonth('Mois dernier'),
  days90('3 mois');

  const _Period(this.label);
  final String label;

  (DateTime, DateTime) range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (this) {
      _Period.today => (today, tomorrow),
      _Period.yesterday => (today.subtract(const Duration(days: 1)), today),
      _Period.week => (today.subtract(const Duration(days: 6)), tomorrow),
      _Period.month => (DateTime(now.year, now.month), tomorrow),
      _Period.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
      _Period.days90 => (today.subtract(const Duration(days: 89)), tomorrow),
    };
  }
}

/// Journal d'activité pour l'administrateur : tout ce qui se passe, et le résumé de chaque utilisateur.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _limit = 500;

  _Period _period = _Period.today;
  int? _userId;
  ActivityKind? _kind;

  @override
  Widget build(BuildContext context) {
    final (from, to) = _period.range();
    final users = ActivityRepo.perUser(from: from, to: to);
    final events = ActivityRepo.events(from: from, to: to, userId: _userId, kind: _kind, limit: _limit);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        PageHeader(
          title: 'Activité',
          subtitle: 'Qui a fait quoi, et quand',
          actions: [
            IosSegmented<_Period>(
              expand: false,
              values: _Period.values,
              selected: _period,
              label: (p) => p.label,
              onChanged: (p) => setState(() => _period = p),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SectionLabel('Par utilisateur'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _UserCard(
              selected: _userId == null,
              title: 'Tout le monde',
              lines: [
                '${fmtNum(users.fold<int>(0, (a, u) => a + u.sales))} ventes',
                fmtDa(users.fold<int>(0, (a, u) => a + u.salesTotal)),
              ],
              onTap: () => setState(() => _userId = null),
            ),
            for (final u in users.where((u) => u.actions > 0 || u.sales > 0 || u.lastSeen != null))
              _UserCard(
                selected: _userId == u.userId,
                title: u.name,
                subtitle: Perm.roleLabels[u.role] ?? u.role,
                lines: [
                  '${fmtNum(u.sales)} ventes · ${fmtDa(u.salesTotal)}',
                  u.lastSeen == null ? 'Jamais connecté' : 'Dernière connexion ${_ago(u.lastSeen!)}',
                ],
                alert: u.hasAlerts
                    ? [
                        if (u.cancellations > 0) '${u.cancellations} annulation(s)',
                        if (u.drawerOpenings > 0) '${u.drawerOpenings} tiroir(s) sans vente',
                        if (u.wrongPins > 0) '${u.wrongPins} PIN raté(s)',
                      ].join(' · ')
                    : null,
                onTap: () => setState(() => _userId = u.userId),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(label: const Text('Tout'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
            for (final k in ActivityKind.values)
              ChoiceChip(
                avatar: Icon(k.icon, size: 16, color: k.color),
                label: Text(k.label),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: 12),
        IosCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Rien sur cette période.', style: TextStyle(color: AppColors.textSecondary))),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._rows(events),
                    if (events.length >= _limit)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Seuls les 500 derniers événements sont affichés : choisissez une période plus courte ou un filtre.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  List<Widget> _rows(List<ActivityEvent> events) {
    final out = <Widget>[];
    DateTime? day;
    for (final e in events) {
      final d = DateTime(e.at.year, e.at.month, e.at.day);
      if (day == null || d != day) {
        day = d;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: SectionLabel(fmtLongDate(d)),
        ));
      }
      out.add(_EventRow(e));
    }
    return out;
  }

  static String _ago(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return "aujourd'hui à ${fmtTime(d)}";
    if (diff == 1) return 'hier à ${fmtTime(d)}';
    return 'le ${fmtDate(d)}';
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.selected,
    required this.title,
    required this.lines,
    required this.onTap,
    this.subtitle,
    this.alert,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final List<String> lines;
  final String? alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.yellowSoft : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.yellow : Colors.transparent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 4),
              for (final l in lines) Text(l, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              if (alert != null) ...[
                const SizedBox(height: 4),
                Text(alert!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.redText)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e);
  final ActivityEvent e;

  @override
  Widget build(BuildContext context) {
    final k = e.kind;
    final title = e.action == 'vente'
        ? 'Vente · ticket n°${e.number ?? ''} · ${fmtDa(e.amount ?? 0)}'
        : activityLabels[e.action] ?? e.action;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F3)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(fmtTime(e.at), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: k.color.withAlpha(30), shape: BoxShape.circle),
            child: Icon(k.icon, size: 16, color: k.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (e.detail.isNotEmpty)
                  Text(e.detail, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(e.userName, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
