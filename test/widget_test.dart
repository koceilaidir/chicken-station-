import 'dart:convert';
import 'dart:typed_data';

import 'package:chicken_station/data/secure_box.dart';
import 'package:chicken_station/hardware/escpos.dart';
import 'package:chicken_station/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('format des montants', () {
    expect(fmtNum(1450), '1 450');
    expect(fmtDa(50950), '50 950 DA');
    expect(fmtSigned(-50), '−50');
    expect(fmtSigned(150), '+150');
    expect(parseAmount('10 500 DA'), 10500);
  });

  test('accents en Windows-1252', () {
    expect(EscPos.encode('é', 16), [0xE9]);
    expect(EscPos.encode('€', 16), [0x80]);
    expect(EscPos.encode('é', 19), [0x82]);
  });

  test('ChaCha20 : vecteur officiel RFC 7539', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final nonce = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0x4a, 0, 0, 0, 0]);
    final text = Uint8List.fromList(utf8.encode(
        "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."));
    final out = chacha20(key, nonce, text);
    String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    expect(hex(out.sublist(0, 16)), '6e2e359a2568f98041ba0728dd0d6981');
    expect(hex(out.sublist(out.length - 8)), '8eedf2785e42874d');
    expect(chacha20(key, nonce, out), text);
  });

  test('sauvegarde : chiffrée, relue à l\'identique', () {
    final entries = {
      'meta.json': Uint8List.fromList(utf8.encode('{"a":1}')),
      'chicken_station.db': Uint8List.fromList(List<int>.generate(100000, (i) => i % 251)),
      'photos/burger.jpg': Uint8List.fromList([1, 2, 3]),
    };
    final sealed = sealBackup(entries);
    // Le contenu n'apparaît pas en clair dans le fichier.
    expect(utf8.decode(sealed, allowMalformed: true).contains('meta.json'), isFalse);
    final back = openBackup(sealed);
    expect(back.keys.toSet(), entries.keys.toSet());
    for (final k in entries.keys) {
      expect(back[k], entries[k]);
    }
  });

  test('sauvegarde modifiée ou étrangère : refusée', () {
    final sealed = sealBackup({'meta.json': Uint8List.fromList([1, 2, 3])});
    final tampered = Uint8List.fromList(sealed)..[30] ^= 0x01;
    expect(() => openBackup(tampered), throwsA(isA<BackupFormatException>()));
    expect(() => openBackup(Uint8List.fromList(utf8.encode('pas une sauvegarde du tout, juste du texte'))),
        throwsA(isA<BackupFormatException>()));
  });
}
