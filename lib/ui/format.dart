/// Formats d'affichage (dinars, dates) en français.

String _two(int n) => n.toString().padLeft(2, '0');

/// 1450 -> « 1 450 »
String fmtNum(int n) {
  final neg = n < 0;
  final s = n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return neg ? '-$s' : s;
}

/// 1450 -> « 1 450 DA »
String fmtDa(int n) => '${fmtNum(n)} DA';

/// -50 -> « −50 », 150 -> « +150 », 0 -> « 0 »
String fmtSigned(int n) => n > 0 ? '+${fmtNum(n)}' : (n < 0 ? '−${fmtNum(-n)}' : '0');

/// Montant pour l'écran client : 1450 -> « 1450.00 »
String fmtDisplay(int n) => '$n.00';

String fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String fmtDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String fmtDateTime(DateTime d) => '${fmtDate(d)} ${fmtTime(d)}';

const monthNames = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

const dayNames = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

String fmtLongDate(DateTime d) => '${dayNames[d.weekday - 1]} ${d.day} ${monthNames[d.month - 1]} ${d.year}';

/// Lit un montant tapé par l'utilisateur (« 10 500 », « 10500 DA »…).
int? parseAmount(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9-]'), '');
  if (digits.isEmpty || digits == '-') return null;
  return int.tryParse(digits);
}

/// Quantité de stock : 2 -> « 2 », 1.5 -> « 1,5 », 0.125 -> « 0,125 ».
String fmtQty(double q) {
  if ((q - q.roundToDouble()).abs() < 0.0005) return fmtNum(q.round());
  var s = q.toStringAsFixed(3);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s.replaceAll('.', ',');
}

/// Lit une quantité tapée (« 1,5 », « 0.250 », « 2 »). null si invalide.
double? parseQty(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// « 2026-11 » pour un mois.
String monthKey(DateTime d) => '${d.year}-${_two(d.month)}';

/// « novembre 2026 ».
String fmtMonth(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';
