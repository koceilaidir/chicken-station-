import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' hide Session;

import '../app_info.dart';
import '../hardware/hardware_config.dart';
import '../hardware/hardware_service.dart';
import '../state/session.dart';
import '../ui/format.dart';
import 'db.dart';
import 'secure_box.dart';

const backupExtension = 'csbak';
const _prefix = 'ChickenStation_';
const _dbEntry = 'chicken_station.db';
const _metaEntry = 'meta.json';
const _hardwareEntry = 'hardware.json';
const _photoPrefix = 'photos/';

String get _sep => Platform.pathSeparator;

class BackupException implements Exception {
  BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

// Chiffrement dans un isolate séparé : l'écran ne se fige pas pendant la sauvegarde.
Future<Uint8List> _sealInBackground(Map<String, Uint8List> entries) => Isolate.run(() => sealBackup(entries));

Future<Map<String, Uint8List>> _openInBackground(String path) => Isolate.run(() {
      final data = File(path).readAsBytesSync();
      return openBackup(data);
    });

/// Réglages de la sauvegarde (fichier backup.json à côté de la base).
class BackupConfig {
  BackupConfig({this.folder = '', this.auto = true, this.keep = 60, this.lastAt});

  /// Dossier choisi par l'administrateur (clé USB, OneDrive…).
  String folder;

  /// Sauvegarde automatique à chaque clôture et au démarrage.
  bool auto;

  /// Nombre de sauvegardes gardées dans le dossier (0 = toutes).
  int keep;

  DateTime? lastAt;

  Map<String, dynamic> toJson() => {
        'folder': folder,
        'auto': auto,
        'keep': keep,
        'lastAt': lastAt?.toIso8601String(),
      };

  factory BackupConfig.fromJson(Map<String, dynamic> j) => BackupConfig(
        folder: (j['folder'] ?? '') as String,
        auto: (j['auto'] ?? true) as bool,
        keep: (j['keep'] ?? 60) as int,
        lastAt: j['lastAt'] == null ? null : DateTime.tryParse(j['lastAt'] as String),
      );
}

/// Informations lisibles d'une sauvegarde (contenues dans le fichier chiffré).
class BackupMeta {
  BackupMeta({
    required this.createdAt,
    required this.reason,
    required this.userName,
    required this.appVersion,
    required this.counts,
  });

  final DateTime createdAt;
  final String reason;
  final String userName;
  final String appVersion;
  final Map<String, int> counts;

  Map<String, dynamic> toJson() => {
        'app': 'Chicken Station',
        'appVersion': appVersion,
        'createdAt': createdAt.toIso8601String(),
        'reason': reason,
        'user': userName,
        'counts': counts,
      };

  factory BackupMeta.fromJson(Map<String, dynamic> j) => BackupMeta(
        createdAt: DateTime.parse(j['createdAt'] as String),
        reason: (j['reason'] ?? '') as String,
        userName: (j['user'] ?? '') as String,
        appVersion: (j['appVersion'] ?? '') as String,
        counts: ((j['counts'] ?? const {}) as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
      );
}

/// Fichier de sauvegarde trouvé dans le dossier.
class BackupFile {
  BackupFile(this.path, this.date, this.size, this.label);
  final String path;
  final DateTime date;
  final int size;

  /// « avant restauration », « clôture »… (tiré du nom du fichier).
  final String label;

  String get name => path.split(RegExp(r'[\\/]')).last;
}

/// Sauvegarde déjà déchiffrée et vérifiée, prête à être restaurée.
class OpenedBackup {
  OpenedBackup(this.path, this.meta, this.entries);
  final String path;
  final BackupMeta meta;
  final Map<String, Uint8List> entries;

  bool get hasHardware => entries.containsKey(_hardwareEntry);
  int get photoCount => entries.keys.where((k) => k.startsWith(_photoPrefix)).length;
}

class BackupService {
  static BackupConfig config = BackupConfig();
  static bool _running = false;

  static Future<File> _configFile() async => File('${await AppDb.dataDir()}${_sep}backup.json');

  static Future<void> loadConfig() async {
    try {
      final f = await _configFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) config = BackupConfig.fromJson(j);
      }
    } catch (_) {
      config = BackupConfig();
    }
  }

  static Future<void> saveConfig() async {
    final f = await _configFile();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(config.toJson()));
  }

  static bool get hasFolder => config.folder.isNotEmpty;
  static bool get folderReachable => hasFolder && Directory(config.folder).existsSync();

  /// Message d'alerte à montrer à l'administrateur, ou null si tout va bien.
  static String? healthWarning() {
    if (!hasFolder) return 'Aucun dossier de sauvegarde choisi : allez dans Sauvegarde pour protéger vos données.';
    if (!folderReachable) return 'Dossier de sauvegarde introuvable (clé USB débranchée ?) : ${config.folder}';
    final last = config.lastAt;
    if (last == null) return 'Aucune sauvegarde faite pour le moment.';
    final days = DateTime.now().difference(last).inDays;
    if (days >= 3) return 'Dernière sauvegarde il y a $days jours.';
    return null;
  }

  /// Au démarrage : sauvegarde si la dernière date de plus de 20 heures.
  static bool get dueAtStartup {
    if (!config.auto || !hasFolder) return false;
    final last = config.lastAt;
    return last == null || DateTime.now().difference(last) > const Duration(hours: 20);
  }

  static String _stamp(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}_${_two(d.hour)}-${_two(d.minute)}-${_two(d.second)}';
  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// Contenu de la sauvegarde : base (copie cohérente), photos, réglages du matériel.
  static Future<Map<String, Uint8List>> _collect(String reason) async {
    final app = AppDb.I;
    final tmp = File('${app.dir}${_sep}backup_snapshot.tmp');
    if (await tmp.exists()) await tmp.delete();
    // VACUUM INTO : copie propre de la base, même pendant que l'appli tourne.
    app.db.execute("VACUUM INTO '${tmp.path.replaceAll("'", "''")}'");
    final dbBytes = await tmp.readAsBytes();
    await tmp.delete();

    int count(String table) => app.db.select('SELECT COUNT(*) AS n FROM $table').first['n'] as int;
    final meta = BackupMeta(
      createdAt: DateTime.now(),
      reason: reason,
      userName: Session.I.user?.name ?? '',
      appVersion: appVersion,
      counts: {
        'journees': count('days'),
        'ventes': count('sales'),
        'depenses': count('expenses'),
        'produits': count('products'),
        'utilisateurs': count('users'),
      },
    );
    final entries = <String, Uint8List>{
      _metaEntry: Uint8List.fromList(utf8.encode(jsonEncode(meta.toJson()))),
      _dbEntry: dbBytes,
    };
    final hw = File('${app.dir}${_sep}hardware.json');
    if (await hw.exists()) entries[_hardwareEntry] = await hw.readAsBytes();
    // Photos importées par l'utilisateur. Les photos livrées avec l'appli (menu_…, ingredients_…)
    // sont recréées automatiquement à l'installation : inutile d'alourdir chaque sauvegarde.
    final photos = Directory(app.photosDir);
    if (await photos.exists()) {
      await for (final f in photos.list()) {
        if (f is! File) continue;
        final name = f.path.split(_sep).last;
        if (name.startsWith('menu_') || name.startsWith('ingredients_')) continue;
        entries['$_photoPrefix$name'] = await f.readAsBytes();
      }
    }
    return entries;
  }

  /// Écrit une sauvegarde chiffrée dans [folder] (par défaut le dossier choisi).
  static Future<File> backupNow({required String reason, String? folder}) async {
    if (_running) throw BackupException('Une sauvegarde est déjà en cours.');
    final target = folder ?? config.folder;
    if (target.isEmpty) throw BackupException('Choisissez d\'abord un dossier de sauvegarde.');
    final dir = Directory(target);
    if (!await dir.exists()) {
      throw BackupException('Dossier introuvable : $target\nBranchez la clé USB ou choisissez un autre dossier.');
    }
    _running = true;
    try {
      final entries = await _collect(reason);
      final sealed = await _sealInBackground(entries);
      final now = DateTime.now();
      final slug = _slug(reason);
      final name = '$_prefix${_stamp(now)}${slug.isEmpty ? '' : '_$slug'}.$backupExtension';
      final file = File('${dir.path}$_sep$name');
      final part = File('${file.path}.part');
      await part.writeAsBytes(sealed, flush: true);
      // Vérification : on relit le fichier écrit et on contrôle qu'il redonne exactement la même base.
      final check = await _openInBackground(part.path);
      final original = sha256.convert(entries[_dbEntry]!).toString();
      final reread = check[_dbEntry] == null ? '' : sha256.convert(check[_dbEntry]!).toString();
      if (original != reread) {
        await part.delete();
        throw BackupException('La sauvegarde écrite est illisible (disque ou clé USB défaillant ?). Rien n\'a été gardé.');
      }
      if (await file.exists()) await file.delete();
      await part.rename(file.path);

      if (folder == null) {
        config.lastAt = now;
        await saveConfig();
        await _rotate();
      }
      AppDb.I.audit(Session.I.user?.id, 'sauvegarde', '$reason · $name · ${_size(sealed.length)}');
      return file;
    } finally {
      _running = false;
    }
  }

  /// Sauvegarde automatique : ne bloque jamais, renvoie un message d'erreur ou null.
  static Future<String?> auto(String reason) async {
    if (!config.auto || !hasFolder) return null;
    try {
      await backupNow(reason: reason);
      return null;
    } catch (e) {
      try {
        AppDb.I.audit(Session.I.user?.id, 'sauvegarde_echec', '$reason · $e');
      } catch (_) {}
      return 'Sauvegarde automatique impossible : $e';
    }
  }

  /// Garde seulement les [keep] sauvegardes les plus récentes.
  static Future<void> _rotate() async {
    if (config.keep <= 0) return;
    final files = list();
    for (final f in files.skip(config.keep)) {
      try {
        await File(f.path).delete();
      } catch (_) {}
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  static String sizeLabel(int bytes) => _size(bytes);

  /// Sauvegardes du dossier choisi, plus récentes en premier.
  static List<BackupFile> list([String? folder]) {
    final dir = Directory(folder ?? config.folder);
    if ((folder ?? config.folder).isEmpty || !dir.existsSync()) return [];
    final re = RegExp('^$_prefix(\\d{4})-(\\d{2})-(\\d{2})_(\\d{2})-(\\d{2})-(\\d{2})(?:_([a-z0-9-]+))?\\.$backupExtension\$');
    final out = <BackupFile>[];
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final name = e.path.split(RegExp(r'[\\/]')).last;
      final m = re.firstMatch(name);
      if (m == null) continue;
      final date = DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
      out.add(BackupFile(e.path, date, e.lengthSync(), (m.group(7) ?? '').replaceAll('-', ' ')));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Déchiffre et vérifie une sauvegarde (rien n'est encore remplacé).
  static Future<OpenedBackup> inspect(String path) async {
    final Map<String, Uint8List> entries;
    try {
      entries = await _openInBackground(path);
    } on BackupFormatException catch (e) {
      throw BackupException(e.message);
    } on FileSystemException catch (e) {
      throw BackupException('Lecture du fichier impossible : ${e.message}');
    }
    final metaBytes = entries[_metaEntry];
    final dbBytes = entries[_dbEntry];
    if (metaBytes == null || dbBytes == null) throw BackupException('Sauvegarde incomplète.');
    final meta = BackupMeta.fromJson(jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>);
    return OpenedBackup(path, meta, entries);
  }

  /// Remplace les données de l'appli par la sauvegarde.
  /// Avant cela, l'état actuel est lui-même sauvegardé (sécurité).
  static Future<void> restore(OpenedBackup b, {bool hardware = false, String restoredBy = ''}) async {
    final dir = await AppDb.dataDir();
    final dbPath = await AppDb.defaultDbPath();

    // 1. La base de la sauvegarde doit être saine.
    final check = File('$dir${_sep}restore_check.db');
    await check.writeAsBytes(b.entries[_dbEntry]!, flush: true);
    try {
      final test = sqlite3.open(check.path);
      try {
        final ok = test.select('PRAGMA integrity_check').first.values.first;
        final users = test.select('SELECT COUNT(*) AS n FROM users').first['n'] as int;
        if (ok != 'ok' || users == 0) throw BackupException('La base contenue dans cette sauvegarde est abîmée.');
      } finally {
        test.dispose();
      }
    } on SqliteException {
      await check.delete();
      throw BackupException('La base contenue dans cette sauvegarde est illisible.');
    } on BackupException {
      await check.delete();
      rethrow;
    }

    // 2. Sauvegarde de sécurité de l'état actuel.
    if (AppDb.isOpen) {
      String? safetyFolder = folderReachable ? config.folder : null;
      if (safetyFolder == null) {
        final local = Directory('$dir${_sep}securite');
        await local.create(recursive: true);
        safetyFolder = local.path;
      }
      await backupNow(reason: 'avant restauration', folder: safetyFolder);
      AppDb.I.close();
    } else {
      // Base illisible au démarrage : on la met de côté sans l'effacer.
      final broken = File(dbPath);
      if (await broken.exists()) {
        await broken.rename('$dbPath.abimee-${_stamp(DateTime.now())}');
      }
    }

    // 3. Remplacement de la base.
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
    final current = File(dbPath);
    if (await current.exists()) await current.delete();
    await check.rename(dbPath);

    // 4. Photos et réglages.
    final photos = Directory('$dir${_sep}photos');
    await photos.create(recursive: true);
    for (final e in b.entries.entries) {
      if (!e.key.startsWith(_photoPrefix)) continue;
      final name = e.key.substring(_photoPrefix.length);
      if (name.isEmpty || name.contains('/') || name.contains('\\') || name.contains('..')) continue;
      await File('${photos.path}$_sep$name').writeAsBytes(e.value);
    }
    if (hardware && b.hasHardware) {
      await File('$dir${_sep}hardware.json').writeAsBytes(b.entries[_hardwareEntry]!);
    }

    // 5. Réouverture.
    await AppDb.open();
    // PC neuf : le dossier de la sauvegarde choisie devient le dossier de sauvegarde.
    if (!hasFolder) {
      config.folder = File(b.path).parent.path;
      await saveConfig();
    }
    HardwareService.I = HardwareService(await HardwareConfig.load());
    AppDb.I.audit(
      null,
      'restauration',
      'Sauvegarde du ${fmtDateTime(b.meta.createdAt)} restaurée${restoredBy.isEmpty ? '' : ' par $restoredBy'} · ${b.path.split(RegExp(r'[\\/]')).last}',
    );
  }
}
