import 'models.dart';

/// Règles de gestion des utilisateurs : qui peut modifier qui, et quels droits il peut donner.
///
/// 1. Seul un administrateur peut modifier, désactiver ou supprimer un administrateur.
/// 2. On ne peut jamais donner un droit qu'on n'a pas soi-même (pas d'escalade).
/// 3. Un non-administrateur ne peut gérer que des comptes dont TOUS les droits sont aussi les siens.
/// 4. Personne ne change ses propres droits, ni ne se désactive ou se supprime
///    (on ne peut ni se donner plus, ni se bloquer par erreur). Son nom et son code PIN, oui.
/// 5. Il reste toujours au moins un administrateur actif.
class UserPolicy {
  static bool isAdmin(AppUser u) => u.role == 'admin';

  /// Raison pour laquelle [actor] ne peut pas gérer le compte de [target], ou null s'il le peut.
  static String? blockReason(AppUser actor, AppUser target) {
    if (!actor.can(Perm.users)) return "Vous n'avez pas le droit de gérer les utilisateurs.";
    if (actor.id == target.id) return null;
    if (isAdmin(actor)) return null;
    if (isAdmin(target)) return 'Seul un administrateur peut modifier un compte administrateur.';
    if (!actor.perms.containsAll(target.perms)) {
      return "${target.name} a des droits que vous n'avez pas : seul un administrateur peut modifier ce compte.";
    }
    return null;
  }

  static bool canManage(AppUser actor, AppUser target) => blockReason(actor, target) == null;

  /// Nom et code PIN : son propre compte, ou un compte qu'on gère.
  static bool canEditIdentity(AppUser actor, AppUser target) =>
      actor.id == target.id || canManage(actor, target);

  /// Droits, modèle, activation, suppression : jamais sur soi-même.
  static bool canEditRights(AppUser actor, AppUser target) => actor.id != target.id && canManage(actor, target);

  /// [actor] peut-il donner (ou retirer) ce droit ?
  static bool canGrant(AppUser actor, String perm) => isAdmin(actor) || actor.perms.contains(perm);

  /// [actor] peut-il appliquer ce modèle de droits ?
  static bool canApplyRole(AppUser actor, String role) {
    if (role == 'admin') return isAdmin(actor);
    final preset = Perm.presets[role];
    if (preset == null) return false;
    return preset.every((p) => canGrant(actor, p));
  }

  /// Droits donnés à un nouvel utilisateur créé par [actor] : caissier, limité à ce qu'il possède.
  static Set<String> defaultPermsFor(AppUser actor) =>
      Perm.presets['caissier']!.where((p) => canGrant(actor, p)).toSet();

  /// Raison pour laquelle on ne peut pas désactiver / supprimer [target], ou null.
  static String? removeBlockReason(AppUser actor, AppUser target, {required int activeAdmins}) {
    if (actor.id == target.id) return 'Vous ne pouvez pas désactiver ou supprimer votre propre compte.';
    final r = blockReason(actor, target);
    if (r != null) return r;
    if (isAdmin(target) && target.active && activeAdmins <= 1) return 'Il faut garder au moins un administrateur.';
    return null;
  }

  /// Raison pour laquelle on ne peut pas changer ce droit chez [target], ou null.
  static String? toggleBlockReason(AppUser actor, AppUser target, String perm, bool value, {required int activeAdmins}) {
    if (actor.id == target.id) return 'Vous ne pouvez pas modifier vos propres droits.';
    final r = blockReason(actor, target);
    if (r != null) return r;
    if (!canGrant(actor, perm)) return "Vous ne pouvez pas donner un droit que vous n'avez pas.";
    if (!value && isAdmin(target) && activeAdmins <= 1) {
      return 'Il faut garder au moins un administrateur avec tous les droits.';
    }
    return null;
  }

  /// Raison pour laquelle on ne peut pas appliquer ce modèle à [target], ou null.
  static String? roleBlockReason(AppUser actor, AppUser target, String role, {required int activeAdmins}) {
    if (actor.id == target.id) return 'Vous ne pouvez pas modifier vos propres droits.';
    final r = blockReason(actor, target);
    if (r != null) return r;
    if (!canApplyRole(actor, role)) {
      return role == 'admin'
          ? 'Seul un administrateur peut nommer un administrateur.'
          : "Ce modèle contient des droits que vous n'avez pas.";
    }
    if (isAdmin(target) && role != 'admin' && activeAdmins <= 1) return 'Il faut garder au moins un administrateur.';
    return null;
  }
}
