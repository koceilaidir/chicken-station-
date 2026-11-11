import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Format des fichiers de sauvegarde Chicken Station (.csbak).
///
///   « CSBK » (4 octets) · version (1 octet) · sel aléatoire (16 octets)
///   · données compressées puis chiffrées (ChaCha20)
///   · sceau HMAC-SHA256 (32 octets) sur tout ce qui précède.
///
/// Le fichier ne s'ouvre qu'avec l'appli : sans la clé il est illisible, et la moindre
/// modification (ou un fichier abîmé) est détectée grâce au sceau.

class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _magic = [0x43, 0x53, 0x42, 0x4B]; // CSBK
const _version = 1;
const _headerLength = 4 + 1 + 16;
const _macLength = 32;

// Clé de l'appli, découpée en deux moitiés mélangées pour ne pas apparaître en clair dans l'exe.
const _ka = <int>[73, 204, 126, 96, 221, 66, 222, 220, 56, 44, 59, 53, 154, 171, 35, 134, 195, 225, 90, 10, 154, 126, 74, 50, 248, 108, 183, 131, 124, 87, 18, 251];
const _kb = <int>[221, 167, 74, 52, 139, 255, 193, 0, 231, 73, 232, 146, 25, 25, 180, 50, 38, 97, 187, 182, 196, 197, 2, 239, 81, 120, 193, 17, 132, 10, 175, 6];

List<int> _appKey() => [for (var i = 0; i < 32; i++) _ka[i] ^ _kb[i]];

({Uint8List enc, Uint8List mac}) _deriveKeys(List<int> salt) {
  final h = Hmac(sha256, _appKey());
  final enc = h.convert([...utf8.encode('chicken-station/enc'), ...salt]).bytes;
  final mac = h.convert([...utf8.encode('chicken-station/mac'), ...salt]).bytes;
  return (enc: Uint8List.fromList(enc), mac: Uint8List.fromList(mac));
}

/// Emballe, compresse, chiffre et scelle des fichiers (nom → contenu).
Uint8List sealBackup(Map<String, Uint8List> entries) {
  final plain = gzip.encode(packEntries(entries));
  final rnd = Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
  final keys = _deriveKeys(salt);
  final cipher = chacha20(keys.enc, Uint8List.sublistView(salt, 0, 12), Uint8List.fromList(plain));

  final out = BytesBuilder(copy: false)
    ..add(_magic)
    ..addByte(_version)
    ..add(salt)
    ..add(cipher);
  final body = out.takeBytes();
  final mac = Hmac(sha256, keys.mac).convert(body).bytes;
  final result = Uint8List(body.length + _macLength)
    ..setRange(0, body.length, body)
    ..setRange(body.length, body.length + _macLength, mac);
  return result;
}

/// Vérifie le sceau, déchiffre et déballe une sauvegarde.
Map<String, Uint8List> openBackup(Uint8List data) {
  if (data.length < _headerLength + _macLength) {
    throw BackupFormatException("Ce fichier n'est pas une sauvegarde Chicken Station.");
  }
  for (var i = 0; i < 4; i++) {
    if (data[i] != _magic[i]) throw BackupFormatException("Ce fichier n'est pas une sauvegarde Chicken Station.");
  }
  if (data[4] != _version) {
    throw BackupFormatException('Sauvegarde faite par une version plus récente de l\'appli. Mettez l\'appli à jour.');
  }
  final salt = Uint8List.sublistView(data, 5, _headerLength);
  final keys = _deriveKeys(salt);
  final bodyEnd = data.length - _macLength;
  final expected = Hmac(sha256, keys.mac).convert(Uint8List.sublistView(data, 0, bodyEnd)).bytes;
  var diff = 0;
  for (var i = 0; i < _macLength; i++) {
    diff |= expected[i] ^ data[bodyEnd + i];
  }
  if (diff != 0) {
    throw BackupFormatException('Sauvegarde abîmée ou modifiée : elle ne peut pas être chargée.');
  }
  final plain = chacha20(keys.enc, Uint8List.sublistView(salt, 0, 12), Uint8List.sublistView(data, _headerLength, bodyEnd));
  final List<int> unpacked;
  try {
    unpacked = gzip.decode(plain);
  } catch (_) {
    throw BackupFormatException('Sauvegarde abîmée : décompression impossible.');
  }
  return unpackEntries(Uint8List.fromList(unpacked));
}

/// [nombre u32] puis pour chaque fichier : [taille du nom u16][nom utf8][taille u32][contenu].
Uint8List packEntries(Map<String, Uint8List> entries) {
  final b = BytesBuilder(copy: false);
  final head = ByteData(4)..setUint32(0, entries.length);
  b.add(head.buffer.asUint8List());
  for (final e in entries.entries) {
    final name = utf8.encode(e.key);
    final h = ByteData(2)..setUint16(0, name.length);
    b.add(h.buffer.asUint8List());
    b.add(name);
    final l = ByteData(4)..setUint32(0, e.value.length);
    b.add(l.buffer.asUint8List());
    b.add(e.value);
  }
  return b.takeBytes();
}

Map<String, Uint8List> unpackEntries(Uint8List data) {
  final view = ByteData.sublistView(data);
  final result = <String, Uint8List>{};
  try {
    var p = 0;
    final count = view.getUint32(p);
    p += 4;
    for (var i = 0; i < count; i++) {
      final nameLen = view.getUint16(p);
      p += 2;
      final name = utf8.decode(Uint8List.sublistView(data, p, p + nameLen));
      p += nameLen;
      final len = view.getUint32(p);
      p += 4;
      result[name] = Uint8List.sublistView(data, p, p + len);
      p += len;
    }
  } catch (_) {
    throw BackupFormatException('Sauvegarde abîmée : contenu illisible.');
  }
  return result;
}

// ---------------------------------------------------------------------------- ChaCha20 (RFC 7539)

int _rotl(int v, int n) => ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF;

void _qr(Uint32List x, int a, int b, int c, int d) {
  x[a] = x[a] + x[b];
  x[d] = _rotl(x[d] ^ x[a], 16);
  x[c] = x[c] + x[d];
  x[b] = _rotl(x[b] ^ x[c], 12);
  x[a] = x[a] + x[b];
  x[d] = _rotl(x[d] ^ x[a], 8);
  x[c] = x[c] + x[d];
  x[b] = _rotl(x[b] ^ x[c], 7);
}

int _le32(Uint8List b, int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

/// Chiffre ou déchiffre (même opération). Clé 32 octets, nonce 12 octets.
Uint8List chacha20(Uint8List key, Uint8List nonce, Uint8List input, {int counter = 1}) {
  final state = Uint32List(16);
  state[0] = 0x61707865;
  state[1] = 0x3320646e;
  state[2] = 0x79622d32;
  state[3] = 0x6b206574;
  for (var i = 0; i < 8; i++) {
    state[4 + i] = _le32(key, i * 4);
  }
  for (var i = 0; i < 3; i++) {
    state[13 + i] = _le32(nonce, i * 4);
  }
  final out = Uint8List(input.length);
  final x = Uint32List(16);
  final ks = ByteData(64);
  var block = counter;
  for (var off = 0; off < input.length; off += 64) {
    state[12] = block;
    block++;
    x.setAll(0, state);
    for (var r = 0; r < 10; r++) {
      _qr(x, 0, 4, 8, 12);
      _qr(x, 1, 5, 9, 13);
      _qr(x, 2, 6, 10, 14);
      _qr(x, 3, 7, 11, 15);
      _qr(x, 0, 5, 10, 15);
      _qr(x, 1, 6, 11, 12);
      _qr(x, 2, 7, 8, 13);
      _qr(x, 3, 4, 9, 14);
    }
    for (var i = 0; i < 16; i++) {
      ks.setUint32(i * 4, (x[i] + state[i]) & 0xFFFFFFFF, Endian.little);
    }
    final n = min(64, input.length - off);
    for (var j = 0; j < n; j++) {
      out[off + j] = input[off + j] ^ ks.getUint8(j);
    }
  }
  return out;
}
