import 'package:flutter/material.dart';

import 'db.dart';

/// Une ligne du journal d'activité.
class ActivityEvent {
  ActivityEvent({
    required this.at,
    required this.userId,
    required this.userName,
    required this.action,
    required this.detail,
    this.amount,
    this.number,
  });

  final DateTime at;
  final int? userId;
  final String userName;
  final String action;
  final String detail;

  /// Pour les ventes : montant et numéro de ticket.
  final int? amount;
  final int? number;

  ActivityKind get kind => ActivityKind.of(action);
}

/// Familles d'actions, pour filtrer et colorer le journal.
enum ActivityKind {
  ventes('Ventes', Icons.receipt_long_outlined, Color(0xFF1E7A34), ['vente']),
  alertes('Annulations et tiroir', Icons.warning_amber_rounded, Color(0xFFC4000F),
      ['annulation_ticket', 'tiroir_sans_vente', 'fond_corrige', 'pin_incorrect']),
  argent('Argent', Icons.payments_outlined, Color(0xFF8A6A00),
      ['ouverture_journee', 'cloture_journee', 'depense', 'depense_annulee', 'coffre']),
  connexions('Connexions', Icons.login, Color(0xFF6E6E73),
      ['connexion', 'deconnexion', 'deconnexion_auto', 'demarrage', 'arret']),
  menu('Menu', Icons.restaurant_menu, Color(0xFF0A60C2),
      ['famille_ajoutee', 'famille_modifiee', 'famille_supprimee', 'produit_ajoute', 'produit_modifie', 'produit_supprime', 'ordre_menu']),
  stock('Achats et paie', Icons.shopping_basket_outlined, Color(0xFF0E7C86), [
    'stock_reception', 'stock_inventaire', 'stock_perte', 'stock_ingredient', 'fiche_technique',
    'fournisseur', 'fournisseur_paiement', 'employe', 'paie', 'charges',
  ]),
  admin('Administration', Icons.admin_panel_settings_outlined, Color(0xFF5E3DB3), [
    'utilisateur_cree', 'utilisateur_modifie', 'utilisateur_supprime', 'pin_modifie', 'materiel', 'reglages',
    'sauvegarde', 'sauvegarde_echec', 'restauration',
  ]);

  const ActivityKind(this.label, this.icon, this.color, this.actions);
  final String label;
  final IconData icon;
  final Color color;
  final List<String> actions;

  static ActivityKind of(String action) {
    for (final k in values) {
      if (k.actions.contains(action)) return k;
    }
    return admin;
  }
}

/// Libellés lisibles des actions enregistrées.
const activityLabels = <String, String>{
  'vente': 'Vente',
  'annulation_ticket': 'Annulation',
  'tiroir_sans_vente': 'Tiroir ouvert sans vente',
  'fond_corrige': 'Fond du matin corrigé',
  'pin_incorrect': 'Code PIN incorrect',
  'ouverture_journee': 'Ouverture de la journée',
  'cloture_journee': 'Clôture de la journée',
  'depense': 'Dépense',
  'depense_annulee': 'Dépense annulée',
  'coffre': 'Mouvement du coffre',
  'connexion': 'Connexion',
  'deconnexion': 'Déconnexion',
  'deconnexion_auto': 'Déconnexion automatique',
  'demarrage': "Démarrage de l'appli",
  'arret': "Arrêt de l'appli",
  'reglages': 'Réglages modifiés',
  'stock_reception': "Bon d'achat",
  'stock_inventaire': 'Inventaire',
  'stock_perte': 'Perte / casse',
  'stock_ingredient': 'Article',
  'fiche_technique': 'Fiche technique',
  'fournisseur': 'Fournisseur',
  'fournisseur_paiement': 'Paiement fournisseur',
  'employe': 'Employé',
  'paie': 'Paie',
  'charges': 'Charges du mois',
  'famille_ajoutee': 'Famille ajoutée',
  'famille_modifiee': 'Famille modifiée',
  'famille_supprimee': 'Famille supprimée',
  'produit_ajoute': 'Produit ajouté',
  'produit_modifie': 'Produit modifié',
  'produit_supprime': 'Produit supprimé',
  'ordre_menu': 'Ordre du menu',
  'utilisateur_cree': 'Utilisateur créé',
  'utilisateur_modifie': 'Utilisateur modifié',
  'utilisateur_supprime': 'Utilisateur supprimé',
  'pin_modifie': 'Code PIN changé',
  'materiel': 'Matériel',
  'sauvegarde': 'Sauvegarde',
  'sauvegarde_echec': 'Sauvegarde ratée',
  'restauration': 'Sauvegarde restaurée',
};

/// Résumé de l'activité d'un utilisateur sur une période.
class UserActivity {
  UserActivity({required this.userId, required this.name, required this.role});

  final int userId;
  final String name;
  final String role;
  int sales = 0;
  int salesTotal = 0;
  int cancellations = 0;
  int drawerOpenings = 0;
  int wrongPins = 0;
  int actions = 0;
  DateTime? lastSeen;

  bool get hasAlerts => cancellations > 0 || drawerOpenings > 0 || wrongPins > 0;
}

class ActivityRepo {
  /// Journal (plus récent en premier) : actions enregistrées + ventes.
  static List<ActivityEvent> events({
    required DateTime from,
    required DateTime to,
    int? userId,
    ActivityKind? kind,
    int limit = 500,
  }) {
    final db = AppDb.I.db;
    final parts = <String>[];
    final args = <Object?>[];

    final wantSales = kind == null || kind == ActivityKind.ventes;
    final wantAudit = kind != ActivityKind.ventes;

    if (wantAudit) {
      var q = 'SELECT a.at AS at, a.user_id AS user_id, u.name AS user_name, a.action AS action, a.detail AS detail, '
          'NULL AS amount, NULL AS number FROM audit a LEFT JOIN users u ON u.id = a.user_id WHERE a.at >= ? AND a.at < ?';
      args.addAll([from.toIso8601String(), to.toIso8601String()]);
      if (userId != null) {
        q += ' AND a.user_id = ?';
        args.add(userId);
      }
      if (kind != null) {
        q += ' AND a.action IN (${List.filled(kind.actions.length, '?').join(', ')})';
        args.addAll(kind.actions);
      }
      parts.add(q);
    }
    if (wantSales) {
      var q = "SELECT s.created_at AS at, s.user_id AS user_id, u.name AS user_name, 'vente' AS action, "
          "s.mode || ' · ' || (CASE s.payment WHEN 'card' THEN 'TPE' WHEN 'attente' THEN 'non payée' ELSE 'Espèces' END) || "
          "(CASE s.status WHEN 'cancelled' THEN ' · annulé ensuite' WHEN 'pending' THEN ' · en attente de paiement' ELSE '' END) AS detail, "
          's.total AS amount, s.number AS number FROM sales s LEFT JOIN users u ON u.id = s.user_id '
          'WHERE s.created_at >= ? AND s.created_at < ?';
      args.addAll([from.toIso8601String(), to.toIso8601String()]);
      if (userId != null) {
        q += ' AND s.user_id = ?';
        args.add(userId);
      }
      parts.add(q);
    }
    final sql = '${parts.join(' UNION ALL ')} ORDER BY at DESC LIMIT ?';
    args.add(limit);
    return db
        .select(sql, args)
        .map((r) => ActivityEvent(
              at: DateTime.parse(r['at'] as String),
              userId: r['user_id'] as int?,
              userName: (r['user_name'] as String?) ?? 'Système',
              action: r['action'] as String,
              detail: (r['detail'] as String?) ?? '',
              amount: r['amount'] as int?,
              number: r['number'] as int?,
            ))
        .toList();
  }

  /// Résumé par utilisateur sur la période.
  static List<UserActivity> perUser({required DateTime from, required DateTime to}) {
    final db = AppDb.I.db;
    final f = from.toIso8601String();
    final t = to.toIso8601String();
    final map = <int, UserActivity>{};
    for (final r in db.select('SELECT id, name, role FROM users ORDER BY id')) {
      map[r['id'] as int] = UserActivity(userId: r['id'] as int, name: r['name'] as String, role: r['role'] as String);
    }
    for (final r in db.select(
      "SELECT user_id, COUNT(*) AS n, COALESCE(SUM(total), 0) AS t FROM sales "
      "WHERE status = 'paid' AND created_at >= ? AND created_at < ? GROUP BY user_id",
      [f, t],
    )) {
      final u = map[r['user_id']];
      if (u == null) continue;
      u.sales = r['n'] as int;
      u.salesTotal = r['t'] as int;
    }
    for (final r in db.select(
      'SELECT user_id, action, COUNT(*) AS n, MAX(at) AS last FROM audit WHERE at >= ? AND at < ? GROUP BY user_id, action',
      [f, t],
    )) {
      final u = map[r['user_id']];
      if (u == null) continue;
      final n = r['n'] as int;
      u.actions += n;
      switch (r['action']) {
        case 'annulation_ticket':
          u.cancellations += n;
        case 'tiroir_sans_vente':
          u.drawerOpenings += n;
        case 'pin_incorrect':
          u.wrongPins += n;
        case 'connexion':
          final last = DateTime.parse(r['last'] as String);
          if (u.lastSeen == null || last.isAfter(u.lastSeen!)) u.lastSeen = last;
      }
    }
    // Dernière connexion, même hors période.
    for (final r in db.select("SELECT user_id, MAX(at) AS last FROM audit WHERE action = 'connexion' GROUP BY user_id")) {
      final u = map[r['user_id']];
      if (u == null || u.lastSeen != null) continue;
      u.lastSeen = DateTime.parse(r['last'] as String);
    }
    return map.values.toList();
  }
}
