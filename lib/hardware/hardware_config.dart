import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Protocoles possibles pour l'écran client (afficheur sur la caisse).
enum DisplayProtocol {
  /// Afficheur à chiffres LED (8 chiffres + voyants « Total », « Prix »…).
  led8('Afficheur LED 8 chiffres'),

  /// Afficheur texte 2 lignes compatible CD5220.
  cd5220('Afficheur 2 lignes CD5220'),

  /// Afficheur texte 2 lignes compatible Epson ESC/POS.
  epson('Afficheur 2 lignes Epson');

  const DisplayProtocol(this.label);
  final String label;
}

/// Réglages du matériel, enregistrés dans un fichier JSON sur le PC.
class HardwareConfig {
  HardwareConfig({
    this.ticketPrinterName = '',
    this.codePage = 16,
    this.charsPerLine = 48,
    this.kitchenIp = '',
    this.kitchenPort = 9100,
    this.kitchenCodePage = 16,
    this.drawerPin = 0,
    this.displayPort = '',
    this.displayBaud = 2400,
    this.displayProtocol = DisplayProtocol.led8,
  });

  String ticketPrinterName;
  int codePage;
  int charsPerLine;
  String kitchenIp;
  int kitchenPort;
  int kitchenCodePage;
  int drawerPin;
  String displayPort;
  int displayBaud;
  DisplayProtocol displayProtocol;

  Map<String, dynamic> toJson() => {
        'ticketPrinterName': ticketPrinterName,
        'codePage': codePage,
        'charsPerLine': charsPerLine,
        'kitchenIp': kitchenIp,
        'kitchenPort': kitchenPort,
        'kitchenCodePage': kitchenCodePage,
        'drawerPin': drawerPin,
        'displayPort': displayPort,
        'displayBaud': displayBaud,
        'displayProtocol': displayProtocol.name,
      };

  factory HardwareConfig.fromJson(Map<String, dynamic> j) {
    DisplayProtocol proto;
    try {
      proto = DisplayProtocol.values.byName((j['displayProtocol'] ?? 'led8') as String);
    } catch (_) {
      proto = DisplayProtocol.led8;
    }
    return HardwareConfig(
      ticketPrinterName: (j['ticketPrinterName'] ?? '') as String,
      codePage: (j['codePage'] ?? 16) as int,
      charsPerLine: (j['charsPerLine'] ?? 48) as int,
      kitchenIp: (j['kitchenIp'] ?? '') as String,
      kitchenPort: (j['kitchenPort'] ?? 9100) as int,
      kitchenCodePage: (j['kitchenCodePage'] ?? 16) as int,
      drawerPin: (j['drawerPin'] ?? 0) as int,
      displayPort: (j['displayPort'] ?? '') as String,
      displayBaud: (j['displayBaud'] ?? 2400) as int,
      displayProtocol: proto,
    );
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}hardware.json');
  }

  static Future<HardwareConfig> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return HardwareConfig();
      final data = jsonDecode(await f.readAsString());
      if (data is Map<String, dynamic>) return HardwareConfig.fromJson(data);
    } catch (_) {
      // Fichier illisible : on repart des valeurs par défaut.
    }
    return HardwareConfig();
  }

  Future<String> save() async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
    return f.path;
  }
}
