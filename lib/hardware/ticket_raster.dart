import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'escpos.dart';

/// Redessine un ticket avec une vraie police sans empattement (Segoe UI, celle de Windows)
/// et l'envoie à l'imprimante comme une image noir et blanc.
/// Plus lisible que les polices intégrées des imprimantes, surtout en cuisine.
class TicketRaster {
  /// Largeur imprimable en points : 576 en 80 mm, 384 en 58 mm.
  static int dotsFor(int charsPerLine) => charsPerLine <= 32 ? 384 : 576;

  static const _font = 'Segoe UI';
  static const _margin = 8.0;

  /// Octets ESC/POS du ticket dessiné ([items] vient de [EscPos.items]).
  static Future<Uint8List> render(List<TicketItem> items, int dots) async {
    final out = BytesBuilder()..add(const [0x1B, 0x40]); // ESC @
    final block = <TicketItem>[];
    Future<void> flush() async {
      if (block.isEmpty) return;
      out.add(await _image(block, dots));
      block.clear();
    }

    for (final it in items) {
      switch (it) {
        case TicketCut():
          await flush();
          out.add(const [0x1B, 0x64, 0x04, 0x1D, 0x56, 0x42, 0x00]); // avance + coupe
        case TicketRaw(:final bytes):
          await flush();
          out.add(bytes);
        default:
          block.add(it);
      }
    }
    await flush();
    return out.toBytes();
  }

  // ------------------------------------------------------------------ dessin

  static double _fontSize(int dots, int sizeH) {
    final base = dots >= 576 ? 25.0 : 19.0;
    return switch (sizeH) {
      1 => base,
      2 => base * 1.55,
      _ => base * 2.1,
    };
  }

  static TextPainter _painter(String text, double size, bool bold, double maxWidth, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _font,
          fontFamilyFallback: const ['Arial', 'Tahoma'],
          fontSize: size,
          height: 1.18,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: const Color(0xFF000000),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
    return tp;
  }

  /// Dessine un bloc d'éléments et renvoie la commande raster (GS v 0) par bandes.
  static Future<Uint8List> _image(List<TicketItem> block, int dots) async {
    final width = dots.toDouble();
    final inner = width - 2 * _margin;

    // 1. Mise en page : hauteur de chaque élément.
    final ops = <(double, void Function(Canvas, double))>[];
    for (final it in block) {
      switch (it) {
        case TicketText(:final text, :final right, :final align, :final bold, :final sizeW, :final sizeH):
          final size = _fontSize(dots, sizeH > sizeW ? sizeH : sizeW);
          if (text.trim().isEmpty && right == null) {
            ops.add((size * 0.7, (_, __) {}));
            break;
          }
          if (right != null) {
            final r = _painter(right, size, true, inner, TextAlign.right);
            final l = _painter(text, size, bold, inner - r.width - 14, TextAlign.left);
            final h = (l.height > r.height ? l.height : r.height) + 4;
            ops.add((
              h,
              (c, y) {
                l.paint(c, Offset(_margin, y + 2));
                r.paint(c, Offset(width - _margin - r.width, y + 2));
              }
            ));
          } else {
            final ta = switch (align) {
              PosAlign.center => TextAlign.center,
              PosAlign.right => TextAlign.right,
              PosAlign.left => TextAlign.left,
            };
            final p = _painter(text, size, bold, inner, ta);
            ops.add((
              p.height + 4,
              (c, y) {
                final x = switch (align) {
                  PosAlign.center => (width - p.width) / 2,
                  PosAlign.right => width - _margin - p.width,
                  PosAlign.left => _margin,
                };
                p.paint(c, Offset(x, y + 2));
              }
            ));
          }
        case TicketSeparator(:final ch):
          final strong = ch == '=';
          ops.add((
            strong ? 18.0 : 14.0,
            (c, y) {
              final paint = Paint()
                ..color = const Color(0xFF000000)
                ..strokeWidth = strong ? 3 : 1.6;
              final mid = y + (strong ? 9 : 7);
              if (strong) {
                c.drawLine(Offset(_margin, mid), Offset(width - _margin, mid), paint);
              } else {
                for (var x = _margin; x < width - _margin; x += 10) {
                  c.drawLine(Offset(x, mid), Offset(x + 5, mid), paint);
                }
              }
            }
          ));
        case TicketImage(:final bits, :final widthBytes, :final height, :final align):
          final img = await _bitsToImage(bits, widthBytes, height);
          final w = widthBytes * 8.0;
          ops.add((
            height + 6.0,
            (c, y) {
              final x = align == PosAlign.center ? (width - w) / 2 : (align == PosAlign.right ? width - w - _margin : _margin);
              c.drawImage(img, Offset(x, y + 3), Paint());
            }
          ));
        case TicketFeed(:final lines):
          ops.add((lines * 22.0, (_, __) {}));
        default:
          break;
      }
    }
    final height = ops.fold<double>(0, (a, o) => a + o.$1).ceil().clamp(1, 20000).toInt();

    // 2. Dessin sur fond blanc.
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, width, height.toDouble()));
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    var y = 0.0;
    for (final o in ops) {
      o.$2(canvas, y);
      y += o.$1;
    }
    final image = await rec.endRecording().toImage(dots, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return Uint8List(0);

    // 3. Noir et blanc, puis bandes de 128 lignes (certaines imprimantes ont un petit tampon).
    final wb = dots ~/ 8;
    final rgba = data.buffer.asUint8List();
    final out = BytesBuilder();
    for (var top = 0; top < height; top += 128) {
      final rows = (height - top) < 128 ? height - top : 128;
      out.add([0x1D, 0x76, 0x30, 0x00, wb & 0xFF, wb >> 8, rows & 0xFF, rows >> 8]);
      final band = Uint8List(wb * rows);
      for (var r = 0; r < rows; r++) {
        final rowStart = (top + r) * dots * 4;
        for (var xb = 0; xb < wb; xb++) {
          var byte = 0;
          for (var k = 0; k < 8; k++) {
            final i = rowStart + (xb * 8 + k) * 4;
            final lum = (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
            if (lum < 150) byte |= 0x80 >> k;
          }
          band[r * wb + xb] = byte;
        }
      }
      out.add(band);
    }
    return out.toBytes();
  }

  /// Logo (1 bit par point) → image pour le dessin.
  static Future<ui.Image> _bitsToImage(Uint8List bits, int widthBytes, int height) async {
    final w = widthBytes * 8;
    final px = Uint8List(w * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < w; x++) {
        final on = (bits[y * widthBytes + (x >> 3)] & (0x80 >> (x & 7))) != 0;
        final i = (y * w + x) * 4;
        final v = on ? 0 : 255;
        px[i] = v;
        px[i + 1] = v;
        px[i + 2] = v;
        px[i + 3] = 255;
      }
    }
    final buf = await ui.ImmutableBuffer.fromUint8List(px);
    final desc = ui.ImageDescriptor.raw(buf, width: w, height: height, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
