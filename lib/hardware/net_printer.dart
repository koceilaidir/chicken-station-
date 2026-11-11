import 'dart:io';
import 'dart:typed_data';

import 'hardware_exception.dart';

/// Imprimante réseau (cuisine) : on ouvre une connexion TCP sur le port 9100
/// (« RAW » / JetDirect) et on envoie directement les octets ESC/POS.
class NetPrinter {
  static Future<void> send(
    String ip,
    int port,
    Uint8List data, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final host = ip.trim();
    if (host.isEmpty) {
      throw const HardwareException("Aucune adresse IP pour l'imprimante cuisine.");
    }
    Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (e) {
      throw HardwareException(
        'Imprimante cuisine injoignable à $host:$port. Vérifiez le câble réseau et l\'adresse IP '
        '(${e.osError?.message ?? e.message}).',
      );
    }
    try {
      socket.add(data);
      await socket.flush();
    } on SocketException catch (e) {
      throw HardwareException('Envoi interrompu vers la cuisine (${e.message}).');
    } finally {
      await socket.close();
      socket.destroy();
    }
  }

  /// Vérifie seulement que l'imprimante répond (sans rien imprimer).
  static Future<bool> ping(String ip, int port) async {
    try {
      final s = await Socket.connect(ip.trim(), port, timeout: const Duration(seconds: 2));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
