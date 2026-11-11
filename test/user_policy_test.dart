import 'package:chicken_station/data/models.dart';
import 'package:chicken_station/data/user_policy.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser user(int id, String name, String role, Iterable<String> perms, {bool active = true}) => AppUser(
      id: id,
      name: name,
      pinHash: '',
      role: role,
      perms: perms.toSet(),
      active: active,
    );

void main() {
  final admin = user(1, 'Administrateur', 'admin', Perm.all);
  final admin2 = user(2, 'Patron', 'admin', Perm.all);
  // Comme « Sofiane » : beaucoup de droits dont « Gérer les utilisateurs », mais pas administrateur.
  final sofiane = user(3, 'Sofiane', 'perso', Perm.all.where((p) => p != Perm.materiel && p != Perm.sauvegarde));
  final gerant = user(4, 'Gérant', 'gerant', {...Perm.presets['gerant']!, Perm.users});
  final caissier = user(5, 'Caissier', 'caissier', Perm.presets['caissier']!);
  final technicien = user(6, 'Technicien', 'perso', {Perm.vendre, Perm.materiel});

  group('administrateur', () {
    test('gère tout le monde, sauf ses propres droits', () {
      for (final t in [admin2, sofiane, gerant, caissier, technicien]) {
        expect(UserPolicy.canManage(admin, t), isTrue, reason: t.name);
        expect(UserPolicy.canEditRights(admin, t), isTrue, reason: t.name);
      }
      expect(UserPolicy.canEditIdentity(admin, admin), isTrue);
      expect(UserPolicy.canEditRights(admin, admin), isFalse);
    });

    test('peut donner tous les droits et nommer un administrateur', () {
      for (final p in Perm.all) {
        expect(UserPolicy.canGrant(admin, p), isTrue, reason: p);
      }
      expect(UserPolicy.roleBlockReason(admin, caissier, 'admin', activeAdmins: 1), isNull);
    });

    test('a aussi les droits ajoutés plus tard', () {
      final old = user(9, 'Ancien admin', 'admin', {Perm.vendre});
      expect(old.can(Perm.sauvegarde), isTrue);
      expect(old.can(Perm.activite), isTrue);
    });

    test('ne peut pas se supprimer ni se désactiver', () {
      expect(UserPolicy.removeBlockReason(admin, admin, activeAdmins: 2), isNotNull);
    });

    test('le dernier administrateur est protégé', () {
      expect(UserPolicy.removeBlockReason(admin2, admin, activeAdmins: 1), isNotNull);
      expect(UserPolicy.removeBlockReason(admin2, admin, activeAdmins: 2), isNull);
      expect(UserPolicy.roleBlockReason(admin2, admin, 'gerant', activeAdmins: 1), isNotNull);
      expect(UserPolicy.toggleBlockReason(admin2, admin, Perm.vendre, false, activeAdmins: 1), isNotNull);
    });
  });

  group('utilisateur qui gère les utilisateurs sans être administrateur', () {
    test("ne peut pas toucher au compte de l'administrateur", () {
      expect(UserPolicy.canManage(sofiane, admin), isFalse);
      expect(UserPolicy.canEditIdentity(sofiane, admin), isFalse);
      expect(UserPolicy.canEditRights(sofiane, admin), isFalse);
      expect(UserPolicy.removeBlockReason(sofiane, admin, activeAdmins: 2), isNotNull);
      expect(UserPolicy.toggleBlockReason(sofiane, admin, Perm.vendre, false, activeAdmins: 2), isNotNull);
      expect(UserPolicy.roleBlockReason(sofiane, admin, 'caissier', activeAdmins: 2), isNotNull);
    });

    test('ne peut pas modifier ses propres droits (ni se donner Matériel)', () {
      expect(UserPolicy.canEditIdentity(sofiane, sofiane), isTrue);
      expect(UserPolicy.canEditRights(sofiane, sofiane), isFalse);
      expect(UserPolicy.toggleBlockReason(sofiane, sofiane, Perm.materiel, true, activeAdmins: 1), isNotNull);
      expect(UserPolicy.roleBlockReason(sofiane, sofiane, 'admin', activeAdmins: 1), isNotNull);
      expect(UserPolicy.removeBlockReason(sofiane, sofiane, activeAdmins: 1), isNotNull);
    });

    test("ne peut pas donner un droit qu'il n'a pas", () {
      expect(UserPolicy.canGrant(sofiane, Perm.materiel), isFalse);
      expect(UserPolicy.canGrant(sofiane, Perm.sauvegarde), isFalse);
      expect(UserPolicy.toggleBlockReason(sofiane, caissier, Perm.materiel, true, activeAdmins: 1), isNotNull);
      expect(UserPolicy.toggleBlockReason(sofiane, caissier, Perm.annuler, true, activeAdmins: 1), isNull);
    });

    test('ne peut pas nommer un administrateur', () {
      expect(UserPolicy.canApplyRole(sofiane, 'admin'), isFalse);
      expect(UserPolicy.roleBlockReason(sofiane, caissier, 'admin', activeAdmins: 1), isNotNull);
      expect(UserPolicy.roleBlockReason(sofiane, caissier, 'gerant', activeAdmins: 1), isNull);
    });

    test('ne gère pas quelqu\'un qui a un droit qu\'il n\'a pas', () {
      expect(UserPolicy.canManage(sofiane, technicien), isFalse);
      expect(UserPolicy.canEditIdentity(sofiane, technicien), isFalse);
      expect(UserPolicy.removeBlockReason(sofiane, technicien, activeAdmins: 1), isNotNull);
    });

    test('gère normalement un caissier', () {
      expect(UserPolicy.canManage(sofiane, caissier), isTrue);
      expect(UserPolicy.canEditRights(sofiane, caissier), isTrue);
      expect(UserPolicy.removeBlockReason(sofiane, caissier, activeAdmins: 1), isNull);
    });

    test('un gérant ne peut pas appliquer un modèle plus fort que lui', () {
      final petitGerant = user(7, 'Petit gérant', 'perso', {Perm.vendre, Perm.users});
      expect(UserPolicy.canApplyRole(petitGerant, 'caissier'), isTrue);
      expect(UserPolicy.canApplyRole(petitGerant, 'gerant'), isFalse);
      expect(UserPolicy.canManage(petitGerant, gerant), isFalse);
    });

    test('un nouvel utilisateur ne reçoit que des droits que le créateur possède', () {
      final sansVente = user(8, 'Compta', 'perso', {Perm.users, Perm.coffre});
      expect(UserPolicy.defaultPermsFor(sansVente), isEmpty);
      expect(UserPolicy.defaultPermsFor(gerant), {Perm.vendre});
      expect(UserPolicy.defaultPermsFor(admin), Perm.presets['caissier']!.toSet());
    });
  });

  group('utilisateur sans le droit « Gérer les utilisateurs »', () {
    test('ne gère personne', () {
      for (final t in [admin, sofiane, gerant, technicien]) {
        expect(UserPolicy.canManage(caissier, t), isFalse, reason: t.name);
        expect(UserPolicy.canEditRights(caissier, t), isFalse, reason: t.name);
      }
      expect(UserPolicy.canEditRights(caissier, caissier), isFalse);
    });
  });
}
