import 'dart:isolate';
import 'dart:typed_data';

import 'customer_display.dart';
import 'escpos.dart';
import 'hardware_config.dart';
import 'net_printer.dart';
import 'serial_port_win.dart';
import 'win_raw_printer.dart';

/// Point d'entrée unique vers le matériel de la caisse.
/// Les appels Windows bloquants tournent dans un isolate séparé
/// pour ne jamais figer l'écran.
/// Ce qui a été « imprimé » ou affiché en mode simulation.
class SimulatedOutput {
  SimulatedOutput(this.device, this.text) : at = DateTime.now();
  final String device; // 'ticket', 'cuisine', 'tiroir', 'ecran'
  final String text;
  final DateTime at;
}

class HardwareService {
  HardwareService(this.config);

  /// Instance unique utilisée par toute l'appli.
  static late HardwareService I;

  HardwareConfig config;

  /// Appelé à chaque sortie simulée (l'appli affiche alors un aperçu).
  void Function(SimulatedOutput out)? onSimulated;

  bool get simulate => config.simulate;

  void _sim(String device, String text) => onSimulated?.call(SimulatedOutput(device, text));

  // ---------------------------------------------------------------- envois bas niveau

  Future<void> sendToTicketPrinter(Uint8List data, {String preview = ''}) {
    if (simulate) {
      _sim('ticket', preview);
      return Future<void>.value();
    }
    final name = config.ticketPrinterName;
    return Isolate.run(() => WinRawPrinter.printRaw(name, data));
  }

  Future<void> sendToKitchen(Uint8List data, {String preview = ''}) {
    if (simulate) {
      _sim('cuisine', preview);
      return Future<void>.value();
    }
    return NetPrinter.send(config.kitchenIp, config.kitchenPort, data);
  }

  Future<void> sendToDisplay(Uint8List data, {String? port, int? baud, String preview = ''}) {
    if (simulate) {
      _sim('ecran', preview);
      return Future<void>.value();
    }
    final p = port ?? config.displayPort;
    final b = baud ?? config.displayBaud;
    return Isolate.run(() => SerialPortWin.write(p, b, data));
  }

  /// Imprime un ticket construit avec [EscPos] (réel ou simulé).
  Future<void> printTicket(EscPos ticket) => sendToTicketPrinter(ticket.bytes(), preview: ticket.preview);

  /// Envoie un bon en cuisine (réel ou simulé).
  Future<void> printKitchen(EscPos ticket) => sendToKitchen(ticket.bytes(), preview: ticket.preview);

  EscPos newTicket() => EscPos(width: config.charsPerLine, codePage: config.codePage);

  EscPos newKitchenTicket() => EscPos(width: config.charsPerLine, codePage: config.kitchenCodePage);

  // ---------------------------------------------------------------- actions

  Future<void> openDrawer() {
    if (simulate) {
      _sim('tiroir', 'Le tiroir-caisse s\'ouvre.');
      return Future<void>.value();
    }
    final data = newTicket().openDrawer(pin: config.drawerPin).bytes();
    return sendToTicketPrinter(data);
  }

  Future<void> showAmount(String amount) => sendToDisplay(
        CustomerDisplay.frame(config.displayProtocol, amount: amount),
        preview: amount,
      );

  Future<void> clearDisplay() =>
      sendToDisplay(CustomerDisplay.clear(config.displayProtocol), preview: '');

  // ---------------------------------------------------------------- tickets de test

  Future<void> printTicketTest() => printTicket(buildTicketTest());

  Future<void> printCodePageTest() => printTicket(buildCodePageTest());

  Future<void> printKitchenTest() => printKitchen(buildKitchenTest());

  EscPos buildTicketTest() {
    final now = DateTime.now();
    final p = EscPos(width: config.charsPerLine, codePage: config.codePage)
      ..align(PosAlign.center)
      ..size(2, 2)
      ..bold(true)
      ..line('CHICKEN STATION')
      ..size(1, 1)
      ..bold(false)
      ..line('Burger & Tacos')
      ..line('TICKET DE TEST')
      ..line(_date(now))
      ..align(PosAlign.left)
      ..separator()
      ..columns('2 x Cheeseburger', '800')
      ..columns('1 x Tacos Poulet mariné', '500')
      ..columns('1 x Barquette de frites', '150')
      ..separator()
      ..bold(true)
      ..size(1, 2)
      ..columns('TOTAL', '1 450 DA')
      ..size(1, 1)
      ..bold(false)
      ..columns('Espèces reçues', '2 000')
      ..columns('Rendu', '550')
      ..separator()
      ..line('Accents : é è ê à â ç ô û ù î « » €')
      ..line('Page de code : ${CodePage.byNumber(config.codePage).label}')
      ..line('Largeur : ${config.charsPerLine} caractères')
      ..line('1234567890' * (config.charsPerLine ~/ 10))
      ..align(PosAlign.center)
      ..line('Merci et à bientôt !')
      ..feed(4)
      ..cut();
    return p;
  }

  /// Imprime la même phrase avec chaque page de code :
  /// on garde celle dont les accents sortent correctement.
  EscPos buildCodePageTest() {
    final p = EscPos(width: config.charsPerLine, codePage: 16)
      ..align(PosAlign.center)
      ..bold(true)
      ..line('ESSAI DES PAGES DE CODE')
      ..bold(false)
      ..line('Gardez la ligne où les accents sont justes')
      ..align(PosAlign.left)
      ..separator();
    for (final cp in CodePage.all) {
      p
        ..setCodePage(cp.number)
        ..line('[${cp.number}] Crème brûlée, façon été')
        ..line('     à â ç é è ê ë î ï ô ù û € « »')
        ..setCodePage(16)
        ..line('     = ${cp.label}')
        ..line();
    }
    p
      ..feed(4)
      ..cut();
    return p;
  }

  EscPos buildKitchenTest() {
    final now = DateTime.now();
    final p = EscPos(width: config.charsPerLine, codePage: config.kitchenCodePage)
      ..align(PosAlign.center)
      ..bold(true)
      ..size(2, 2)
      ..line('CUISINE')
      ..size(1, 1)
      ..line('BON DE TEST')
      ..align(PosAlign.left)
      ..size(2, 2)
      ..line('N° 001   ${_time(now)}')
      ..size(1, 2)
      ..line('SUR PLACE')
      ..size(1, 1)
      ..bold(false)
      ..separator('=')
      ..bold(true)
      ..size(1, 2)
      ..line('2  CHEESEBURGER')
      ..line('1  TACOS POULET MARINÉ')
      ..size(1, 1)
      ..line('   >> SANS OIGNON')
      ..size(1, 2)
      ..line('1  BARQUETTE DE FRITES')
      ..size(1, 1)
      ..bold(false)
      ..separator('=')
      ..line('Imprimé par : test matériel')
      ..feed(4)
      ..cut();
    return p;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  static String _date(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year} ${_time(d)}';
}

/// Combinaisons essayées par l'« essai automatique » de l'écran client.
/// Chaque essai affiche un numéro différent : celui qui apparaît indique le bon réglage.
class DisplayTrial {
  const DisplayTrial(this.number, this.protocol, this.baud);
  final int number;
  final DisplayProtocol protocol;
  final int baud;

  String get amount => '$number.00';
  String get label => '$number.00  →  ${protocol.label}, $baud bauds';

  static const all = [
    DisplayTrial(1, DisplayProtocol.led8, 2400),
    DisplayTrial(2, DisplayProtocol.led8, 9600),
    DisplayTrial(3, DisplayProtocol.cd5220, 9600),
    DisplayTrial(4, DisplayProtocol.cd5220, 2400),
    DisplayTrial(5, DisplayProtocol.epson, 9600),
    DisplayTrial(6, DisplayProtocol.led8, 4800),
    DisplayTrial(7, DisplayProtocol.led8, 19200),
  ];
}
