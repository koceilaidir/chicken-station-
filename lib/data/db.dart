import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

String hashPin(String pin) => sha256.convert(utf8.encode('chicken-station:$pin')).toString();

String nowIso() => DateTime.now().toIso8601String();

/// Base de données locale SQLite (fichier chicken_station.db dans le dossier de l'appli).
/// Les montants sont toujours en dinars entiers.
class AppDb {
  AppDb._(this.db, this.dir, this.dbPath);

  final Database db;

  /// Dossier de données de l'appli (base + photos).
  final String dir;

  /// Fichier de la base SQLite.
  final String dbPath;

  static AppDb? _current;

  /// Base ouverte. Remplacée après une restauration de sauvegarde.
  static AppDb get I => _current!;
  static bool get isOpen => _current != null;

  /// Dossier de données de l'appli, même si la base n'a pas pu s'ouvrir.
  static Future<String> dataDir() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    return support.path;
  }

  static Future<String> defaultDbPath() async => '${await dataDir()}${Platform.pathSeparator}chicken_station.db';

  String get photosDir => '$dir${Platform.pathSeparator}photos';

  /// Chemin complet d'une photo enregistrée (ou null).
  String? photoPath(String? name) {
    if (name == null || name.isEmpty) return null;
    return '$photosDir${Platform.pathSeparator}$name';
  }

  static Future<void> open() async {
    final dir = await dataDir();
    final dbPath = await defaultDbPath();
    final db = sqlite3.open(dbPath);
    try {
      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA journal_mode = WAL;');
      final app = AppDb._(db, dir, dbPath);
      await Directory(app.photosDir).create(recursive: true);
      app._migrate();
      await app._seedIfEmpty();
      await app._seedIngredientsIfEmpty();
      await app._syncLibraryPhotos();
      _current = app;
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  /// Ferme la base (avant de la remplacer par une sauvegarde).
  void close() {
    if (identical(_current, this)) _current = null;
    db.dispose();
  }

  /// Aucune journée ni vente : appli neuve (on propose de charger une sauvegarde).
  bool get isFresh =>
      (db.select('SELECT COUNT(*) AS n FROM days').first['n'] as int) == 0 &&
      (db.select('SELECT COUNT(*) AS n FROM sales').first['n'] as int) == 0;

  void _migrate() {
    if (db.userVersion < 1) _createV1();
    if (db.userVersion < 2) {
      // v2 : sauvegarde et journal d'activité. Les administrateurs reçoivent les deux nouveaux droits.
      db.execute('''
        UPDATE users SET perms = perms || ',${Perm.sauvegarde},${Perm.activite}'
          WHERE (',' || perms || ',') LIKE '%,${Perm.users},%'
            AND (',' || perms || ',') NOT LIKE '%,${Perm.sauvegarde},%';
        CREATE INDEX IF NOT EXISTS idx_audit_at ON audit(at);
        CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at);
      ''');
      db.userVersion = 2;
    }
    if (db.userVersion < 3) {
      // v3 : utilisateurs supprimés (cachés partout, mais leur nom reste dans l'historique).
      db.execute('ALTER TABLE users ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0;');
      db.userVersion = 3;
    }
    if (db.userVersion < 4) {
      // v4 : réglages, stock et fiches techniques, fournisseurs, employés, charges fixes du mois.
      db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS ingredients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          unit TEXT NOT NULL,
          photo TEXT,
          stock REAL NOT NULL DEFAULT 0,
          min_stock REAL NOT NULL DEFAULT 0,
          cost INTEGER NOT NULL DEFAULT 0,
          active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS recipes (
          product_id INTEGER NOT NULL,
          ingredient_id INTEGER NOT NULL,
          qty REAL NOT NULL,
          PRIMARY KEY (product_id, ingredient_id)
        );
        CREATE TABLE IF NOT EXISTS stock_moves (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at TEXT NOT NULL,
          user_id INTEGER,
          ingredient_id INTEGER NOT NULL,
          qty REAL NOT NULL,
          kind TEXT NOT NULL,
          ref_id INTEGER,
          note TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS suppliers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          phone TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '',
          active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS purchases (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at TEXT NOT NULL,
          user_id INTEGER,
          supplier_id INTEGER,
          total INTEGER NOT NULL,
          note TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS purchase_lines (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          purchase_id INTEGER NOT NULL,
          ingredient_id INTEGER NOT NULL,
          qty REAL NOT NULL,
          unit_price INTEGER NOT NULL,
          total INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS supplier_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at TEXT NOT NULL,
          user_id INTEGER,
          supplier_id INTEGER NOT NULL,
          amount INTEGER NOT NULL,
          expense_id INTEGER,
          note TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS employees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          job TEXT NOT NULL DEFAULT '',
          phone TEXT NOT NULL DEFAULT '',
          salary INTEGER NOT NULL DEFAULT 0,
          active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS pay_moves (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at TEXT NOT NULL,
          user_id INTEGER,
          employee_id INTEGER NOT NULL,
          month TEXT NOT NULL,
          kind TEXT NOT NULL,
          amount INTEGER NOT NULL,
          expense_id INTEGER,
          note TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS monthly_charges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          label TEXT NOT NULL,
          amount INTEGER NOT NULL,
          active INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_moves_ing ON stock_moves(ingredient_id);
        CREATE INDEX IF NOT EXISTS idx_pay_emp ON pay_moves(employee_id, month);
      ''');
      db.userVersion = 4;
    }
    if (db.userVersion < 5) {
      // v5 : une erreur de saisie se corrige par une annulation tracée (jamais un effacement),
      // et le salaire a un historique : changer un salaire ne réécrit pas les mois passés.
      final month = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
      db.execute('''
        ALTER TABLE expenses ADD COLUMN cancelled INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE expenses ADD COLUMN cancel_reason TEXT NOT NULL DEFAULT '';
        ALTER TABLE pay_moves ADD COLUMN cancelled INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE supplier_payments ADD COLUMN cancelled INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE purchases ADD COLUMN cancelled INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE employees ADD COLUMN start_month TEXT NOT NULL DEFAULT '';
        ALTER TABLE employees ADD COLUMN end_month TEXT NOT NULL DEFAULT '';
        CREATE TABLE IF NOT EXISTS employee_salaries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          employee_id INTEGER NOT NULL,
          from_month TEXT NOT NULL,
          amount INTEGER NOT NULL,
          UNIQUE (employee_id, from_month)
        );
        INSERT OR IGNORE INTO employee_salaries (employee_id, from_month, amount)
          SELECT id, '2000-01', salary FROM employees;
        UPDATE employees SET start_month = '2000-01' WHERE start_month = '';
        UPDATE employees SET end_month = '$month' WHERE active = 0 AND end_month = '';
      ''');
      db.userVersion = 5;
    }
    if (db.userVersion < 6) {
      // v6 : mois à partir duquel la paie est suivie dans l'appli (avant : réglé hors appli).
      db.execute("ALTER TABLE employees ADD COLUMN tracked_from TEXT NOT NULL DEFAULT '';");
      db.execute('UPDATE employees SET tracked_from = start_month');
      db.userVersion = 6;
    }
    if (db.userVersion < 7) {
      // v7 : plus de stock calculé, seulement l'historique des achats. Huile d'olive ajoutée aux articles.
      if (db.select("SELECT 1 FROM ingredients WHERE name LIKE 'Huile d%olive%'").isEmpty) {
        db.execute("INSERT INTO ingredients (name, unit, photo, stock, min_stock, cost, active) VALUES ('Huile d''olive', 'L', NULL, 0, 0, 0, 1)");
      }
      db.userVersion = 7;
    }
    if (db.userVersion < 8) {
      // v8 : les charges fixes ne sont plus que des titres (Loyer, Électricité…) ; le montant se saisit
      // à chaque paiement, comme une dépense liée à ce titre.
      db.execute('ALTER TABLE expenses ADD COLUMN charge_id INTEGER;');
      if ((db.select('SELECT COUNT(*) AS n FROM monthly_charges').first['n'] as int) == 0) {
        for (final t in ['Loyer', 'Électricité', 'Gaz', 'Eau', 'Internet', 'Téléphone', 'Impôts']) {
          db.execute('INSERT INTO monthly_charges (label, amount, active) VALUES (?, 0, 1)', [t]);
        }
      }
      db.userVersion = 8;
    }
    if (db.userVersion < 9) {
      // Crédit fournisseur d'avant l'appli : compte dans la dette, pas dans les achats du mois.
      db.execute('ALTER TABLE purchases ADD COLUMN opening INTEGER NOT NULL DEFAULT 0;');
      db.userVersion = 9;
    }
  }

  void _createV1() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        perms TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE IF NOT EXISTS families (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        rank INTEGER NOT NULL,
        photo TEXT,
        active INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        family_id INTEGER NOT NULL REFERENCES families(id),
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        photo TEXT,
        rank INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE IF NOT EXISTS days (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_at TEXT NOT NULL,
        opened_by INTEGER,
        opening_fund INTEGER NOT NULL,
        closed_at TEXT,
        closed_by INTEGER,
        counted INTEGER,
        expected INTEGER,
        diff INTEGER,
        reason TEXT,
        taken_home INTEGER
      );
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_id INTEGER NOT NULL REFERENCES days(id),
        number INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        user_id INTEGER,
        mode TEXT NOT NULL,
        payment TEXT NOT NULL,
        total INTEGER NOT NULL,
        cash_given INTEGER,
        status TEXT NOT NULL DEFAULT 'paid',
        cancel_reason TEXT,
        cancelled_by INTEGER
      );
      CREATE TABLE IF NOT EXISTS sale_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sales(id),
        product_id INTEGER,
        family_name TEXT NOT NULL,
        name TEXT NOT NULL,
        unit_price INTEGER NOT NULL,
        qty INTEGER NOT NULL,
        total INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      );
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_id INTEGER,
        created_at TEXT NOT NULL,
        user_id INTEGER,
        label TEXT NOT NULL,
        category TEXT NOT NULL,
        amount INTEGER NOT NULL,
        source TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS safe_moves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT NOT NULL,
        user_id INTEGER,
        label TEXT NOT NULL,
        amount INTEGER NOT NULL,
        kind TEXT NOT NULL,
        day_id INTEGER
      );
      CREATE TABLE IF NOT EXISTS audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at TEXT NOT NULL,
        user_id INTEGER,
        action TEXT NOT NULL,
        detail TEXT NOT NULL DEFAULT ''
      );
      CREATE INDEX IF NOT EXISTS idx_sales_day ON sales(day_id);
      CREATE INDEX IF NOT EXISTS idx_lines_sale ON sale_lines(sale_id);
      CREATE INDEX IF NOT EXISTS idx_exp_day ON expenses(day_id);
    ''');
    db.userVersion = 1;
  }

  /// Première installation : utilisateur administrateur + menu tiré de data/seed.
  Future<void> _seedIfEmpty() async {
    final users = db.select('SELECT COUNT(*) AS n FROM users').first['n'] as int;
    if (users == 0) {
      db.execute(
        'INSERT INTO users (name, pin_hash, role, perms, active) VALUES (?, ?, ?, ?, 1)',
        ['Administrateur', hashPin('1234'), 'admin', Perm.all.join(',')],
      );
    }
    final families = db.select('SELECT COUNT(*) AS n FROM families').first['n'] as int;
    if (families > 0) return;

    final raw = await rootBundle.loadString('data/seed/menu_seed.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    db.execute('BEGIN');
    try {
      for (final f in (seed['families'] as List).cast<Map<String, dynamic>>()) {
        final famPhoto = await _importAssetPhoto(f['photo'] as String?);
        db.execute(
          'INSERT INTO families (name, rank, photo, active) VALUES (?, ?, ?, 1)',
          [f['name'], f['rank'], famPhoto],
        );
        final familyId = db.lastInsertRowId;
        for (final p in (f['products'] as List).cast<Map<String, dynamic>>()) {
          final photo = await _importAssetPhoto(p['photo'] as String?);
          db.execute(
            'INSERT INTO products (family_id, name, price, description, photo, rank, active) '
            'VALUES (?, ?, ?, ?, ?, ?, 1)',
            [familyId, p['name'], p['price_da'], p['description'] ?? '', photo, p['rank']],
          );
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Ingrédients de départ (data/seed) avec photo et unité, stock à 0.
  Future<void> _seedIngredientsIfEmpty() async {
    if (db.select("SELECT value FROM settings WHERE key = 'ingredients_seeded'").isNotEmpty) return;
    final seed = jsonDecode(await rootBundle.loadString('data/seed/menu_seed.json')) as Map<String, dynamic>;
    final list = ((seed['ingredients'] ?? const []) as List).cast<Map<String, dynamic>>();
    db.execute('BEGIN');
    try {
      for (final i in list) {
        // Déjà présent (ex. ajouté par une mise à jour) : pas de doublon.
        if (db.select('SELECT 1 FROM ingredients WHERE name = ?', [i['name']]).isNotEmpty) continue;
        final photo = await _importAssetPhoto(i['photo'] as String?);
        db.execute(
          'INSERT INTO ingredients (name, unit, photo, stock, min_stock, cost, active) VALUES (?, ?, ?, 0, 0, 0, 1)',
          [i['name'], i['unit'] ?? 'pièce', photo],
        );
      }
      db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('ingredients_seeded', '1')");
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Ajoute à la base d'images les photos du menu livrées avec l'appli qui n'y sont pas encore
  /// (ex. les boissons ajoutées après la première installation). Ne remplace jamais une photo existante.
  Future<void> _syncLibraryPhotos() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final asset in manifest.listAssets()) {
        if (!asset.startsWith('data/seed/photos/menu/') && !asset.startsWith('data/seed/photos/ingredients/')) continue;
        await _importAssetPhoto(asset.substring('data/seed/'.length));
      }
    } catch (_) {
      // Sans importance : les photos pourront être importées à la main.
    }
  }

  /// Copie une photo de data/seed vers le dossier photos de l'appli.
  /// Renvoie le nom du fichier enregistré.
  Future<String?> _importAssetPhoto(String? relPath) async {
    if (relPath == null || relPath.isEmpty) return null;
    final name = relPath.replaceAll('photos/', '').replaceAll('/', '_');
    final target = File(photoPath(name)!);
    if (await target.exists()) return name;
    try {
      final data = await rootBundle.load('data/seed/$relPath');
      await target.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Copie une photo choisie par l'utilisateur (clé USB…) dans la base d'images.
  Future<String> importPhotoFile(String sourcePath) async {
    final src = File(sourcePath);
    final base = sourcePath.split(RegExp(r'[\\/]')).last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    var name = 'import_$base';
    var i = 1;
    while (await File(photoPath(name)!).exists()) {
      name = 'import_${i}_$base';
      i++;
    }
    await src.copy(photoPath(name)!);
    return name;
  }

  /// Toutes les photos disponibles dans la base d'images.
  List<String> listPhotos() {
    final d = Directory(photosDir);
    if (!d.existsSync()) return [];
    final names = d
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .where((n) => n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png'))
        .toList()
      ..sort();
    return names;
  }

  /// Remet l'appli à zéro pour démarrer pour de vrai : efface ventes, journées, coffre, dépenses,
  /// fournisseurs, bons d'achat, employés, paie et journal d'activité.
  /// Garde : le menu (familles, produits, photos), les utilisateurs, les réglages et le matériel,
  /// la liste des articles d'achat et les titres de charges.
  void resetAllButMenu(int userId, String userName) {
    const tables = [
      'sale_lines', 'sales', 'expenses', 'safe_moves', 'days',
      'purchase_lines', 'purchases', 'supplier_payments', 'suppliers',
      'pay_moves', 'employee_salaries', 'employees', 'stock_moves', 'audit',
    ];
    db.execute('BEGIN');
    try {
      for (final t in tables) {
        db.execute('DELETE FROM $t;');
      }
      final seq = db.select("SELECT name FROM sqlite_master WHERE name = 'sqlite_sequence'");
      if (seq.isNotEmpty) {
        db.execute("DELETE FROM sqlite_sequence WHERE name IN (${tables.map((t) => "'$t'").join(', ')});");
      }
      db.execute('UPDATE ingredients SET cost = 0;');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    audit(userId, 'reinitialisation', 'Appli remise à zéro par $userName (menu, utilisateurs et réglages gardés)');
  }

  void audit(int? userId, String action, [String detail = '']) {
    db.execute('INSERT INTO audit (at, user_id, action, detail) VALUES (?, ?, ?, ?)', [nowIso(), userId, action, detail]);
  }
}
