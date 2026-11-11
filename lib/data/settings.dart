import 'db.dart';

/// Réglages de l'appli, enregistrés dans la base (donc compris dans les sauvegardes).
class Settings {
  static String get(String key, [String fallback = '']) {
    final r = AppDb.I.db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? fallback : r.first['value'] as String;
  }

  static void set(String key, String value) {
    AppDb.I.db.execute('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)', [key, value]);
  }

  static bool flag(String key, {bool fallback = false}) {
    final v = get(key);
    if (v.isEmpty) return fallback;
    return v == '1';
  }

  static void setFlag(String key, bool value) => set(key, value ? '1' : '0');

  static int number(String key, int fallback) => int.tryParse(get(key)) ?? fallback;

  static void setNumber(String key, int value) => set(key, '$value');

  // ------------------------------------------------------------------ écran

  /// Appli en plein écran (barre des tâches Windows cachée).
  static bool get fullscreen => flag('fullscreen', fallback: true);
  static set fullscreen(bool v) => setFlag('fullscreen', v);

  /// Verrouillage automatique (retour au code PIN) après X minutes sans toucher l'écran. 0 = jamais.
  static int get idleLockMinutes => number('idle_lock_minutes', 0);
  static set idleLockMinutes(int v) => setNumber('idle_lock_minutes', v);

  // ------------------------------------------------------------------ impressions

  /// Nombre d'exemplaires du rapport Z à la clôture.
  static int get zCopies => number('z_copies', 1);
  static set zCopies(int v) => setNumber('z_copies', v);
}

/// Champs du ticket client. Un champ vide n'est pas imprimé.
class TicketField {
  const TicketField(this.key, this.label, this.fallback, {this.hint = ''});
  final String key;
  final String label;
  final String fallback;
  final String hint;

  String get value => Settings.get('ticket_$key', fallback);
  set value(String v) => Settings.set('ticket_$key', v);

  static const name = TicketField('name', 'Nom de la boutique', 'CHICKEN STATION');
  static const slogan = TicketField('slogan', 'Sous-titre', 'Burger & Tacos');
  static const address = TicketField('address', 'Adresse', '', hint: 'ex. Rue …, Tizi Ouzou');
  static const phone = TicketField('phone', 'Téléphone', '', hint: 'ex. 0555 00 00 00');
  static const rc = TicketField('rc', 'RC', '', hint: 'Registre du commerce');
  static const nif = TicketField('nif', 'NIF', '', hint: "Numéro d'identification fiscale");
  static const nis = TicketField('nis', 'NIS', '', hint: "Numéro d'identification statistique");
  static const art = TicketField('art', 'Art.', '', hint: "Article d'imposition");
  static const thanks = TicketField('thanks', 'Message en bas du ticket', 'Merci et à bientôt !');

  static const header = [name, slogan, address, phone];
  static const legal = [rc, nif, nis, art];
  static const all = [name, slogan, address, phone, rc, nif, nis, art, thanks];
}
