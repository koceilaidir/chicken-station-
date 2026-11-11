import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repos.dart';
import '../data/user_policy.dart';
import '../state/session.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Réglages › Utilisateurs : création, code PIN, modèle de droits, droits un par un.
/// Toutes les règles (qui peut modifier qui, quels droits donner) sont dans [UserPolicy].
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser> _users = [];
  int? _selId;
  final _name = TextEditingController();

  AppUser get _me => Session.I.user!;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  AppUser? get _sel => _users.where((u) => u.id == _selId).firstOrNull;

  int get _admins => UserRepo.activeAdmins();

  void _reload() {
    _users = UserRepo.all();
    if (_sel == null) _selId = _users.isEmpty ? null : _users.first.id;
    _name.text = _sel?.name ?? '';
    setState(() {});
  }

  void _select(AppUser u) {
    setState(() {
      _selId = u.id;
      _name.text = u.name;
    });
  }

  void _save(AppUser u) {
    UserRepo.save(u);
    Session.I.refresh();
    setState(() {});
  }

  /// Affiche la raison du refus ; renvoie true si l'action est permise.
  bool _allowed(String? reason) {
    if (reason == null) return true;
    toast(context, reason, error: true);
    return false;
  }

  Future<String?> _askPin(String title) async {
    final a = await askText(context, title, hint: '4 chiffres');
    if (a == null) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(a)) {
      if (mounted) toast(context, 'Le code PIN doit faire exactement 4 chiffres.', error: true);
      return null;
    }
    if (!mounted) return null;
    final b = await askText(context, 'Retapez le code PIN', hint: '4 chiffres');
    if (b != a) {
      if (mounted) toast(context, 'Les deux codes ne correspondent pas.', error: true);
      return null;
    }
    return a;
  }

  Future<void> _add() async {
    final perms = UserPolicy.defaultPermsFor(_me);
    final name = await askText(context, 'Nouvel utilisateur', hint: 'Nom (ex. Caissier 3)');
    if (name == null || name.isEmpty) return;
    final pin = await _askPin('Code PIN de $name');
    if (pin == null) return;
    _selId = UserRepo.create(name, pin, perms.length == Perm.presets['caissier']!.length ? 'caissier' : 'perso', perms);
    _reload();
  }

  Future<void> _changePin(AppUser u) async {
    if (!UserPolicy.canEditIdentity(_me, u)) {
      _allowed(UserPolicy.blockReason(_me, u));
      return;
    }
    final pin = await _askPin('Nouveau code PIN de ${u.name}');
    if (pin == null) return;
    UserRepo.setPin(u.id, pin);
    if (mounted) toast(context, 'Code PIN de ${u.name} changé');
  }

  void _setActive(AppUser u, bool v) {
    if (!v && !_allowed(UserPolicy.removeBlockReason(_me, u, activeAdmins: _admins))) return;
    if (v && !_allowed(UserPolicy.blockReason(_me, u))) return;
    u.active = v;
    _save(u);
  }

  void _applyRole(AppUser u, String role) {
    if (role == 'perso') return;
    if (!_allowed(UserPolicy.roleBlockReason(_me, u, role, activeAdmins: _admins))) return;
    u.role = role;
    u.perms = role == 'admin' ? Perm.all.toSet() : Perm.presets[role]!.toSet();
    _save(u);
  }

  void _toggle(AppUser u, String perm, bool v) {
    if (!_allowed(UserPolicy.toggleBlockReason(_me, u, perm, v, activeAdmins: _admins))) return;
    if (u.role == 'admin') u.perms = Perm.all.toSet();
    if (v) {
      u.perms.add(perm);
    } else {
      u.perms.remove(perm);
    }
    u.role = 'perso';
    _save(u);
  }

  Future<void> _delete(AppUser u) async {
    if (!_allowed(UserPolicy.removeBlockReason(_me, u, activeAdmins: _admins))) return;
    final ok = await confirm(
      context,
      'Supprimer ${u.name} ?',
      "Il ne pourra plus se connecter et disparaît de la liste. Ses ventes et son activité passées restent dans l'historique, avec son nom.",
      ok: 'Supprimer',
    );
    if (!ok) return;
    UserRepo.delete(u);
    _selId = null;
    _reload();
    if (mounted) toast(context, '${u.name} supprimé.');
  }

  String _rightsLabel(AppUser x) => x.role == 'admin' ? 'tous les droits' : '${x.perms.length} droits';

  @override
  Widget build(BuildContext context) {
    final u = _sel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        children: [
          const PageHeader(overline: 'Réglages', title: 'Utilisateurs'),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: MediaQuery.sizeOf(context).width < 1150 ? 230 : 280,
                  child: IosCard(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            children: [
                              for (final x in _users) _userTile(x),
                            ],
                          ),
                        ),
                        SecondaryButton(label: '+ Nouvel utilisateur', onPressed: _add),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: u == null ? const IosCard(child: Text('Aucun utilisateur')) : _editor(u)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userTile(AppUser x) {
    final admin = x.role == 'admin';
    final locked = !UserPolicy.canEditIdentity(_me, x);
    final me = x.id == _me.id;
    return Material(
      color: x.id == _selId ? AppColors.yellowSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: CircleAvatar(
          backgroundColor: admin ? AppColors.text : const Color(0xFFE9E9EE),
          child: Text(x.initials,
              style: TextStyle(fontWeight: FontWeight.w800, color: admin ? AppColors.yellow : const Color(0xFF3A3A3C))),
        ),
        title: Text('${x.name}${me ? ' (vous)' : ''}',
            style: TextStyle(fontWeight: FontWeight.w700, color: x.active ? AppColors.text : AppColors.textSecondary)),
        subtitle: Text('${Perm.roleLabels[x.role] ?? x.role} · ${_rightsLabel(x)}${x.active ? '' : ' · désactivé'}'),
        trailing: locked ? const Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondary) : null,
        onTap: () => _select(x),
      ),
    );
  }

  Widget _notice(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _editor(AppUser u) {
    final me = _me;
    final identity = UserPolicy.canEditIdentity(me, u);
    final rights = UserPolicy.canEditRights(me, u);
    final block = UserPolicy.blockReason(me, u);
    final removable = UserPolicy.removeBlockReason(me, u, activeAdmins: _admins) == null;
    return IosCard(
      child: ListView(
        children: [
          if (block != null)
            _notice(Icons.lock_outline, '$block Vous pouvez seulement consulter ce compte.')
          else if (u.id == me.id)
            _notice(Icons.person_outline,
                "C'est votre compte : vous pouvez changer votre nom et votre code PIN. Vos droits ne peuvent être modifiés que par un autre administrateur."),
          const Text('Nom', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          IgnorePointer(
            ignoring: !identity,
            child: FieldBox(
              controller: _name,
              onChanged: (v) {
                if (!identity || v.trim().isEmpty) return;
                u.name = v.trim();
                _save(u);
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (identity) SecondaryButton(label: 'Changer le code PIN', onPressed: () => _changePin(u)),
              if (rights && removable)
                SizedBox(
                  height: 44,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.redText,
                      backgroundColor: AppColors.redSoft,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _delete(u),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Actif', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  Switch(
                    value: u.active,
                    activeTrackColor: AppColors.green,
                    onChanged: rights && (removable || !u.active) ? (v) => _setActive(u, v) : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Modèle de droits', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Opacity(
            opacity: rights ? 1 : 0.55,
            child: IgnorePointer(
              ignoring: !rights,
              child: IosSegmented<String>(
                values: const ['caissier', 'gerant', 'admin', 'perso'],
                selected: Perm.roleLabels.containsKey(u.role) ? u.role : 'perso',
                label: (r) => Perm.roleLabels[r] ?? r,
                onChanged: (role) => _applyRole(u, role),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              for (final g in Perm.groups.entries)
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel(g.key),
                      for (final p in g.value)
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(Perm.labels[p] ?? p),
                          subtitle: rights && !UserPolicy.canGrant(me, p)
                              ? const Text("Vous n'avez pas ce droit", style: TextStyle(fontSize: 11))
                              : null,
                          value: u.can(p),
                          activeTrackColor: AppColors.green,
                          onChanged: rights && UserPolicy.canGrant(me, p) ? (v) => _toggle(u, p, v) : null,
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            "Règles : seul un administrateur modifie un administrateur ; on ne donne jamais un droit qu'on n'a pas ; "
            'personne ne modifie ses propres droits. Chaque changement est noté dans le journal d\'activité.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
