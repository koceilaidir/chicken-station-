/// Erreur matériel avec un message lisible par l'utilisateur (en français).
class HardwareException implements Exception {
  const HardwareException(this.message);
  final String message;

  @override
  String toString() => message;
}
