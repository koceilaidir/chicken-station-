import 'package:sqlite3/sqlite3.dart';

/// Droits possibles d'un utilisateur.
class Perm {
  static const vendre = 'vendre';
  static const annuler = 'annuler';
  static const tiroir = 'tiroir';
  static const recette = 'recette';
  static const cloture = 'cloture';
  static const coffre = 'coffre';
  static const depense = 'depense';
  static const fournisseurs = 'fournisseurs';
  static const paie = 'paie';
  static const pointage = 'pointage';
  static const stock = 'stock';
  static const reception = 'reception';
  static const inventaire = 'inventaire';
  static const menu = 'menu';
  static const users = 'users';
  static const materiel = 'materiel';
  static const sauvegarde = 'sauvegarde';
  static const activite = 'activite';

  static const all = [
    vendre, annuler, tiroir, recette, cloture, coffre, depense,
    fournisseurs, paie, pointage, stock, reception, inventaire, menu, users, materiel,
    sauvegarde, activite,
  ];

  static const labels = {
    vendre: 'Encaisser des ventes',
    annuler: 'Annuler un ticket',
    tiroir: 'Ouvrir le tiroir sans vente',
    recette: 'Voir la recette du jour',
    cloture: 'Ouvrir et clôturer la journée',
    coffre: 'Voir le coffre et les écarts',
    depense: 'Enregistrer une dépense',
    fournisseurs: 'Payer les fournisseurs',
    paie: 'Salaires et acomptes',
    pointage: 'Pointer les employés',
    stock: "Voir les achats",
    reception: "Saisir les bons d'achat",
    inventaire: "Faire l'inventaire",
    menu: 'Modifier le menu et les prix',
    users: 'Gérer les utilisateurs',
    materiel: 'Réglages du matériel',
    sauvegarde: 'Sauvegarder et restaurer les données',
    activite: "Voir le journal d'activité",
  };

  static const groups = <String, List<String>>{
    'Caisse': [vendre, annuler, tiroir],
    'Argent': [recette, cloture, coffre, depense],
    'Achats et paie': [stock, reception, fournisseurs, paie, pointage],
    'Administration': [menu, materiel, sauvegarde, activite],
  };

  static const presets = <String, List<String>>{
    'caissier': [vendre],
    'gerant': [vendre, annuler, tiroir, recette, cloture, depense, fournisseurs, stock, reception, inventaire, pointage],
    'admin': all,
  };

  static const roleLabels = {
    'caissier': 'Caissier',
    'gerant': 'Gérant',
    'admin': 'Administrateur',
    'perso': 'Personnalisé',
  };
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.pinHash,
    required this.role,
    required this.perms,
    required this.active,
  });

  final int id;
  String name;
  String pinHash;
  String role;
  Set<String> perms;
  bool active;

  /// Un administrateur a tous les droits, y compris ceux ajoutés dans les versions futures.
  bool can(String p) => role == 'admin' || perms.contains(p);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  factory AppUser.fromRow(Row r) => AppUser(
        id: r['id'] as int,
        name: r['name'] as String,
        pinHash: r['pin_hash'] as String,
        role: r['role'] as String,
        perms: (r['perms'] as String).split(',').where((s) => s.isNotEmpty).toSet(),
        active: (r['active'] as int) == 1,
      );
}

class Family {
  Family({required this.id, required this.name, required this.rank, this.photo, required this.active});

  final int id;
  String name;
  int rank;
  String? photo;
  bool active;

  factory Family.fromRow(Row r) => Family(
        id: r['id'] as int,
        name: r['name'] as String,
        rank: r['rank'] as int,
        photo: r['photo'] as String?,
        active: (r['active'] as int) == 1,
      );
}

class Product {
  Product({
    required this.id,
    required this.familyId,
    required this.name,
    required this.price,
    required this.description,
    this.photo,
    required this.rank,
    required this.active,
  });

  final int id;
  int familyId;
  String name;
  int price;
  String description;
  String? photo;
  int rank;
  bool active;

  factory Product.fromRow(Row r) => Product(
        id: r['id'] as int,
        familyId: r['family_id'] as int,
        name: r['name'] as String,
        price: r['price'] as int,
        description: (r['description'] as String?) ?? '',
        photo: r['photo'] as String?,
        rank: r['rank'] as int,
        active: (r['active'] as int) == 1,
      );
}

/// Ligne du bon en cours (pas encore en base).
class CartLine {
  CartLine({required this.product, this.qty = 1, this.note = ''});
  final Product product;
  int qty;
  String note;
  int get total => product.price * qty;
}

class Day {
  Day({
    required this.id,
    required this.openedAt,
    required this.openingFund,
    this.closedAt,
    this.counted,
    this.expected,
    this.diff,
    this.reason,
    this.takenHome,
    this.closedBy,
  });

  final int id;
  final DateTime openedAt;
  final int openingFund;
  final DateTime? closedAt;
  final int? counted;
  final int? expected;
  final int? diff;
  final String? reason;
  final int? takenHome;
  final String? closedBy;

  bool get isOpen => closedAt == null;

  factory Day.fromRow(Row r) => Day(
        id: r['id'] as int,
        openedAt: DateTime.parse(r['opened_at'] as String),
        openingFund: r['opening_fund'] as int,
        closedAt: r['closed_at'] == null ? null : DateTime.parse(r['closed_at'] as String),
        counted: r['counted'] as int?,
        expected: r['expected'] as int?,
        diff: r['diff'] as int?,
        reason: r['reason'] as String?,
        takenHome: r['taken_home'] as int?,
        closedBy: r['closed_by_name'] as String?,
      );
}

class Expense {
  Expense({
    required this.id,
    required this.createdAt,
    required this.label,
    required this.category,
    required this.amount,
    required this.source,
    required this.userName,
    this.cancelled = false,
    this.cancelReason = '',
  });

  final int id;
  final DateTime createdAt;
  final String label;
  final String category;
  final int amount;
  final String source; // 'caisse' ou 'coffre'
  final String userName;
  final bool cancelled;
  final String cancelReason;

  factory Expense.fromRow(Row r) => Expense(
        id: r['id'] as int,
        createdAt: DateTime.parse(r['created_at'] as String),
        label: r['label'] as String,
        category: r['category'] as String,
        amount: r['amount'] as int,
        source: r['source'] as String,
        userName: (r['user_name'] as String?) ?? '',
        cancelled: ((r['cancelled'] as int?) ?? 0) == 1,
        cancelReason: (r['cancel_reason'] as String?) ?? '',
      );
}

class SafeMove {
  SafeMove({required this.id, required this.createdAt, required this.label, required this.amount, required this.kind});

  final int id;
  final DateTime createdAt;
  final String label;
  final int amount; // positif = entre dans le coffre
  final String kind;

  factory SafeMove.fromRow(Row r) => SafeMove(
        id: r['id'] as int,
        createdAt: DateTime.parse(r['created_at'] as String),
        label: r['label'] as String,
        amount: r['amount'] as int,
        kind: r['kind'] as String,
      );
}

/// Résumé d'une journée pour la clôture et le rapport Z.
class DaySummary {
  DaySummary({
    required this.day,
    required this.tickets,
    required this.cashSales,
    required this.cardSales,
    required this.cancelledCount,
    required this.cancelledTotal,
    required this.cashExpenses,
    required this.byFamily,
  });

  final Day day;
  final int tickets;
  final int cashSales;
  final int cardSales;
  final int cancelledCount;
  final int cancelledTotal;
  final int cashExpenses;
  final Map<String, int> byFamily;

  int get totalSales => cashSales + cardSales;
  int get expectedInDrawer => day.openingFund + cashSales - cashExpenses;
  int get averageTicket => tickets == 0 ? 0 : (totalSales / tickets).round();
}
