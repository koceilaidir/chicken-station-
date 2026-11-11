import 'dart:typed_data';

enum PosAlign { left, center, right }

/// Pages de code proposées pour les accents français.
/// Le numéro est celui envoyé à l'imprimante avec la commande ESC t n.
class CodePage {
  const CodePage(this.number, this.label);
  final int number;
  final String label;

  static const windows1252 = CodePage(16, 'Windows-1252 (n°16)');
  static const cp858 = CodePage(19, 'PC858 avec € (n°19)');
  static const cp850 = CodePage(2, 'PC850 (n°2)');
  static const cp437 = CodePage(0, 'PC437 sans accents (n°0)');

  static const all = [windows1252, cp858, cp850, cp437];

  static CodePage byNumber(int n) =>
      all.firstWhere((c) => c.number == n, orElse: () => windows1252);
}

/// Construit les octets ESC/POS d'un ticket (imprimantes thermiques 80 mm).
class EscPos {
  EscPos({this.width = 48, int codePage = 16}) : _codePage = codePage {
    _b.add(const [0x1B, 0x40]); // ESC @ : remise à zéro
    setCodePage(codePage);
  }

  /// Nombre de caractères par ligne en taille normale (48 en 80 mm, 32 en 58 mm).
  final int width;
  final BytesBuilder _b = BytesBuilder();
  int _codePage;
  int _sizeW = 1;
  PosAlign _align = PosAlign.left;
  final StringBuffer _pending = StringBuffer();
  final List<String> _preview = [];

  /// Aperçu texte du ticket (mode simulation).
  String get preview => [..._preview, if (_pending.isNotEmpty) _pending.toString()].join('\n');

  EscPos setCodePage(int n) {
    _codePage = n;
    _b.add([0x1B, 0x74, n]); // ESC t n
    return this;
  }

  EscPos align(PosAlign a) {
    _align = a;
    _b.add([0x1B, 0x61, a.index]); // ESC a n
    return this;
  }

  EscPos bold(bool on) {
    _b.add([0x1B, 0x45, on ? 1 : 0]); // ESC E n
    return this;
  }

  /// Taille des caractères : largeur et hauteur de 1 à 8.
  EscPos size(int w, int h) {
    final ww = w.clamp(1, 8).toInt();
    final hh = h.clamp(1, 8).toInt();
    _sizeW = ww;
    _b.add([0x1D, 0x21, ((ww - 1) << 4) | (hh - 1)]); // GS ! n
    return this;
  }

  EscPos text(String s) {
    _b.add(encode(s, _codePage));
    _pending.write(s);
    return this;
  }

  EscPos line([String s = '']) {
    text(s);
    _b.addByte(0x0A);
    _flushPreview();
    return this;
  }

  void _flushPreview() {
    var t = _pending.toString();
    _pending.clear();
    // Les caractères agrandis sont simulés en les espaçant.
    if (_sizeW > 1) t = t.split('').join(' ');
    if (t.length < width) {
      if (_align == PosAlign.center) {
        t = ' ' * ((width - t.length) ~/ 2) + t;
      } else if (_align == PosAlign.right) {
        t = ' ' * (width - t.length) + t;
      }
    }
    _preview.add(t);
  }

  /// Ligne avec un texte à gauche et un texte à droite.
  EscPos columns(String left, String right) {
    final w = width ~/ _sizeW;
    final space = w - right.length;
    var l = left;
    if (space <= 1) {
      return line(right);
    }
    if (l.length > space - 1) {
      l = l.substring(0, space - 1);
    }
    return line(l.padRight(space) + right);
  }

  /// Image noir et blanc (GS v 0) : [bits] = 1 bit par point, [widthBytes] octets par ligne.
  /// Centrée selon l'alignement courant. Dans l'aperçu, remplacée par [label].
  EscPos image(Uint8List bits, int widthBytes, int height, {String label = '[ logo ]'}) {
    _b.add([0x1D, 0x76, 0x30, 0x00, widthBytes & 0xFF, widthBytes >> 8, height & 0xFF, height >> 8]);
    _b.add(bits);
    _b.addByte(0x0A);
    _pending.write(label);
    _flushPreview();
    return this;
  }

  EscPos separator([String ch = '-']) => line(ch * (width ~/ _sizeW));

  EscPos feed(int lines) {
    _b.add([0x1B, 0x64, lines.clamp(0, 255).toInt()]); // ESC d n
    if (lines > 0) _preview.add('');
    return this;
  }

  /// Avance le papier puis coupe (coupe partielle).
  EscPos cut() {
    _b.add(const [0x1D, 0x56, 0x42, 0x00]); // GS V 66 0
    _preview.add('- - - - - - - - - - - - (coupe) - - - - - - - - - - - -');
    return this;
  }

  /// Impulsion d'ouverture du tiroir-caisse branché sur l'imprimante.
  /// [pin] 0 = broche 2, 1 = broche 5.
  EscPos openDrawer({int pin = 0}) {
    _b.add([0x1B, 0x70, pin == 1 ? 1 : 0, 0x19, 0xFA]); // ESC p m t1 t2
    _preview.add('[ ouverture du tiroir-caisse ]');
    return this;
  }

  EscPos raw(List<int> bytes) {
    _b.add(bytes);
    return this;
  }

  Uint8List bytes() => _b.toBytes();

  // ---------------------------------------------------------------------------
  // Encodage du texte selon la page de code.

  static const Map<int, int> _win1252Extra = {
    0x20AC: 0x80, // €
    0x201A: 0x82,
    0x201E: 0x84,
    0x2026: 0x85, // …
    0x2018: 0x91,
    0x2019: 0x92, // ’
    0x201C: 0x93,
    0x201D: 0x94,
    0x2013: 0x96, // –
    0x2014: 0x97, // —
    0x0152: 0x8C, // Œ
    0x0153: 0x9C, // œ
    0x0178: 0x9F, // Ÿ
  };

  static const Map<int, int> _cp850 = {
    0x00C7: 0x80, // Ç
    0x00FC: 0x81, // ü
    0x00E9: 0x82, // é
    0x00E2: 0x83, // â
    0x00E4: 0x84, // ä
    0x00E0: 0x85, // à
    0x00E7: 0x87, // ç
    0x00EA: 0x88, // ê
    0x00EB: 0x89, // ë
    0x00E8: 0x8A, // è
    0x00EF: 0x8B, // ï
    0x00EE: 0x8C, // î
    0x00C9: 0x90, // É
    0x00F4: 0x93, // ô
    0x00F6: 0x94, // ö
    0x00FB: 0x96, // û
    0x00F9: 0x97, // ù
    0x00C0: 0xB7, // À
    0x00C2: 0xB6, // Â
    0x00CA: 0xD2, // Ê
    0x00C8: 0xD4, // È
    0x00CE: 0xD7, // Î
    0x00D4: 0xE2, // Ô
    0x00DB: 0xEA, // Û
    0x00D9: 0xEB, // Ù
    0x00AB: 0xAE, // «
    0x00BB: 0xAF, // »
    0x00B0: 0xF8, // °
  };

  static const Map<int, String> _fallback = {
    0x0153: 'oe',
    0x0152: 'OE',
    0x20AC: 'EUR',
    0x2019: "'",
    0x2018: "'",
    0x201C: '"',
    0x201D: '"',
    0x2013: '-',
    0x2014: '-',
    0x2026: '...',
    0x00AB: '"',
    0x00BB: '"',
  };

  static const Map<int, String> _stripAccent = {
    0x00E9: 'e', 0x00E8: 'e', 0x00EA: 'e', 0x00EB: 'e',
    0x00E0: 'a', 0x00E2: 'a', 0x00E4: 'a',
    0x00E7: 'c', 0x00EE: 'i', 0x00EF: 'i',
    0x00F4: 'o', 0x00F6: 'o', 0x00F9: 'u', 0x00FB: 'u', 0x00FC: 'u',
    0x00C9: 'E', 0x00C8: 'E', 0x00CA: 'E', 0x00C0: 'A', 0x00C2: 'A',
    0x00C7: 'C', 0x00CE: 'I', 0x00D4: 'O', 0x00D9: 'U', 0x00DB: 'U',
  };

  static Uint8List encode(String s, int codePage) {
    final out = <int>[];
    void fallback(int r) {
      final f = _fallback[r] ?? _stripAccent[r];
      if (f != null) {
        out.addAll(f.codeUnits);
      } else {
        out.add(0x3F); // ?
      }
    }

    for (final r in s.runes) {
      if (r == 0x00A0 || r == 0x202F) {
        out.add(0x20); // espaces insécables -> espace
        continue;
      }
      if (r < 0x80) {
        out.add(r);
        continue;
      }
      switch (codePage) {
        case 16: // Windows-1252
          if (r >= 0xA0 && r <= 0xFF) {
            out.add(r);
          } else if (_win1252Extra.containsKey(r)) {
            out.add(_win1252Extra[r]!);
          } else {
            fallback(r);
          }
        case 19: // PC858 = PC850 + €
          if (r == 0x20AC) {
            out.add(0xD5);
          } else if (_cp850.containsKey(r)) {
            out.add(_cp850[r]!);
          } else {
            fallback(r);
          }
        case 2: // PC850
          if (_cp850.containsKey(r)) {
            out.add(_cp850[r]!);
          } else {
            fallback(r);
          }
        default: // PC437 ou inconnu : sans accents
          fallback(r);
      }
    }
    return Uint8List.fromList(out);
  }
}
