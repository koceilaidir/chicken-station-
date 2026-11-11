import 'package:flutter/foundation.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/repos.dart';

/// Utilisateur connecté (code PIN) et ses droits.
class Session extends ChangeNotifier {
  Session._();
  static final Session I = Session._();

  AppUser? _user;
  AppUser? get user => _user;
  bool get loggedIn => _user != null;

  bool can(String perm) => _user?.can(perm) ?? false;

  void login(AppUser u) {
    _user = u;
    AppDb.I.audit(u.id, 'connexion');
    notifyListeners();
  }

  void logout() {
    final u = _user;
    if (u != null) AppDb.I.audit(u.id, 'deconnexion');
    _user = null;
    notifyListeners();
  }

  /// Au démarrage de l'appli : si quelqu'un était resté connecté (PC éteint, coupure de courant…),
  /// sa session est fermée dans le journal. L'appli démarre toujours sur l'écran des codes PIN.
  static void closeLeftoverSession() {
    final db = AppDb.I.db;
    final r = db.select(
      "SELECT user_id, action, at FROM audit WHERE action IN ('connexion', 'deconnexion', 'deconnexion_auto', 'demarrage', 'arret') "
      'ORDER BY id DESC LIMIT 1',
    );
    if (r.isNotEmpty && r.first['action'] == 'connexion') {
      AppDb.I.audit(r.first['user_id'] as int?, 'deconnexion_auto', "L'appli a été fermée sans déconnexion");
    }
    AppDb.I.audit(null, 'demarrage', "Démarrage de l'appli");
  }

  /// Déconnexion automatique (inactivité).
  void lockForInactivity(int minutes) {
    final u = _user;
    if (u == null) return;
    AppDb.I.audit(u.id, 'deconnexion_auto', 'Aucune activité pendant $minutes min');
    _user = null;
    notifyListeners();
  }

  /// Oublie l'utilisateur sans rien écrire (la base vient d'être remplacée par une sauvegarde).
  void clear() {
    _user = null;
    notifyListeners();
  }

  /// Recharge l'utilisateur (après modification de ses droits).
  void refresh() {
    final u = _user;
    if (u == null) return;
    _user = UserRepo.byId(u.id);
    if (_user == null || !_user!.active) _user = null;
    notifyListeners();
  }
}
