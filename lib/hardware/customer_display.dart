import 'dart:typed_data';

import 'escpos.dart';
import 'hardware_config.dart';

/// Construit les octets à envoyer à l'écran client selon son protocole.
class CustomerDisplay {
  /// [amount] : montant affiché, ex. « 450.00 ».
  /// [line1] / [line2] : texte des afficheurs 2 lignes (20 caractères max).
  static Uint8List frame(
    DisplayProtocol protocol, {
    required String amount,
    String line1 = 'CHICKEN STATION',
    String? line2,
  }) {
    final b = BytesBuilder();
    final l2 = line2 ?? 'TOTAL ${amount.padLeft(10)}';
    switch (protocol) {
      case DisplayProtocol.led8:
        b.add(const [0x1B, 0x40]); // ESC @ : initialisation
        b.add(const [0x0C]); // effacer
        b.add(const [0x1B, 0x73, 0x32]); // ESC s '2' : voyant « Total »
        b.add(const [0x1B, 0x51, 0x41]); // ESC Q A : afficher le nombre
        b.add(_ascii(amount));
        b.add(const [0x0D]);
      case DisplayProtocol.cd5220:
        b.add(const [0x0C]); // effacer
        b.add(const [0x1B, 0x51, 0x41]); // ESC Q A : ligne du haut
        b.add(_ascii(_fit(line1)));
        b.add(const [0x0D]);
        b.add(const [0x1B, 0x51, 0x42]); // ESC Q B : ligne du bas
        b.add(_ascii(_fit(l2)));
        b.add(const [0x0D]);
      case DisplayProtocol.epson:
        b.add(const [0x1B, 0x40]); // ESC @
        b.add(const [0x0C]); // effacer
        b.add(_ascii(_fit(line1)));
        b.add(const [0x1F, 0x24, 0x01, 0x02]); // US $ 1 2 : début ligne 2
        b.add(_ascii(_fit(l2)));
    }
    return b.toBytes();
  }

  /// Efface l'écran (entre deux clients).
  static Uint8List clear(DisplayProtocol protocol) {
    switch (protocol) {
      case DisplayProtocol.led8:
        return Uint8List.fromList(const [0x1B, 0x40, 0x0C]);
      case DisplayProtocol.cd5220:
        return Uint8List.fromList(const [0x0C]);
      case DisplayProtocol.epson:
        return Uint8List.fromList(const [0x1B, 0x40, 0x0C]);
    }
  }

  static String _fit(String s) => s.length > 20 ? s.substring(0, 20) : s.padRight(20);

  static Uint8List _ascii(String s) => EscPos.encode(s, 0);
}
