import '../data/models.dart';
import '../data/settings.dart';
import '../ui/format.dart';
import 'escpos.dart';
import 'hardware_service.dart';
import 'logo_bitmap.dart';

/// Contenu des tickets imprimés par l'appli.
/// (Les champs RC, NIF, adresse… seront réglables dans Réglages › Impressions.)
class Tickets {
  static String get shopName => TicketField.name.value;

  static HardwareService get _hw => HardwareService.I;

  /// Ticket client après paiement.
  static EscPos customer({
    required int number,
    required String mode,
    required String cashier,
    required List<CartLine> lines,
    required String payment,
    int? cashGiven,
  }) {
    final total = lines.fold<int>(0, (a, l) => a + l.total);
    final now = DateTime.now();
    final p = _header()
      ..columns('Ticket n° ${number.toString().padLeft(3, '0')}', fmtDateTime(now))
      ..columns('Caissier : $cashier', mode)
      ..separator();
    for (final l in lines) {
      p.columns('${l.qty} x ${l.product.name}', fmtNum(l.total));
      if (l.qty > 1) p.line('    à ${fmtNum(l.product.price)} DA');
      if (l.note.isNotEmpty) p.line('    + ${l.note}');
    }
    p
      ..separator()
      ..bold(true)
      ..size(1, 2)
      ..columns('TOTAL', '${fmtNum(total)} DA')
      ..size(1, 1)
      ..bold(false);
    if (payment == 'card') {
      p.columns('Payé par carte (TPE)', fmtNum(total));
    } else if (cashGiven != null && cashGiven >= total) {
      p
        ..columns('Espèces reçues', fmtNum(cashGiven))
        ..columns('Rendu', fmtNum(cashGiven - total));
    } else {
      p.columns('Payé en espèces', fmtNum(total));
    }
    _footer(p);
    return p;
  }

  /// En-tête : logo noir et blanc, puis les champs réglables (Réglages › Impressions).
  /// Le nom est déjà dans le logo : il est imprimé en petit, sans agrandissement.
  static EscPos _header() {
    final p = _hw.newTicket()
      ..align(PosAlign.center)
      ..image(logoBits, logoWidthBytes, logoHeight);
    final name = TicketField.name.value;
    if (name.isNotEmpty) {
      p
        ..bold(true)
        ..line(name)
        ..bold(false);
    }
    for (final f in [TicketField.slogan, TicketField.address, TicketField.phone]) {
      final v = f.value;
      if (v.isNotEmpty) p.line(f == TicketField.phone ? 'Tél. $v' : v);
    }
    p
      ..align(PosAlign.left)
      ..separator();
    return p;
  }

  /// Mentions légales (RC, NIF, NIS, Art.) et message de fin.
  static void _footer(EscPos p) {
    p
      ..separator()
      ..align(PosAlign.center);
    final legal = [for (final f in TicketField.legal) if (f.value.isNotEmpty) '${f.label} ${f.value}'];
    for (final l in legal) {
      p.line(l);
    }
    final thanks = TicketField.thanks.value;
    if (thanks.isNotEmpty) {
      if (legal.isNotEmpty) p.feed(1);
      p.line(thanks);
    }
    p
      ..feed(4)
      ..cut();
  }

  /// Ticket d'essai pour vérifier l'en-tête et les mentions.
  static EscPos sample() {
    final p = _header()
      ..columns('Ticket n° 000 · ESSAI', fmtDateTime(DateTime.now()))
      ..separator()
      ..columns('1 x Cheeseburger', '400')
      ..columns('2 x Coca-Cola', '200')
      ..line('    à 100 DA')
      ..separator()
      ..bold(true)
      ..size(1, 2)
      ..columns('TOTAL', '600 DA')
      ..size(1, 1)
      ..bold(false);
    _footer(p);
    return p;
  }

  /// Rapport en cours de journée (sans clôture) : recette, dépenses, ou les deux.
  static EscPos dayReport({
    required DaySummary s,
    required List<Expense> expenses,
    required bool sales,
    required bool spending,
    required String printedBy,
  }) {
    final p = _hw.newTicket()
      ..align(PosAlign.center)
      ..bold(true)
      ..size(1, 2)
      ..line(sales && spending ? 'RECETTE ET DÉPENSES' : (sales ? 'RECETTE DU JOUR' : 'DÉPENSES DU JOUR'))
      ..size(1, 1)
      ..bold(false)
      ..line(shopName)
      ..line('${fmtLongDate(s.day.openedAt)} · imprimé à ${fmtTime(DateTime.now())}')
      ..line('Par : $printedBy · journée non clôturée')
      ..align(PosAlign.left)
      ..separator('=');
    if (sales) {
      p
        ..bold(true)
        ..line('RECETTE')
        ..bold(false)
        ..columns('Tickets', '${s.tickets}')
        ..columns('Espèces', fmtNum(s.cashSales));
      if (s.cardSales > 0) p.columns('TPE', fmtNum(s.cardSales));
      p
        ..columns('Annulations (${s.cancelledCount})', fmtNum(s.cancelledTotal))
        ..bold(true)
        ..columns('TOTAL VENTES', '${fmtNum(s.totalSales)} DA')
        ..bold(false);
      if (s.byFamily.isNotEmpty) {
        p.separator();
        s.byFamily.forEach((f, t) => p.columns(f, fmtNum(t)));
      }
      p.separator('=');
    }
    if (spending) {
      p
        ..bold(true)
        ..line('DÉPENSES')
        ..bold(false);
      for (final e in expenses) {
        p.columns('${fmtTime(e.createdAt)} ${e.label} (${e.source})', fmtNum(e.amount));
      }
      if (expenses.isEmpty) p.line('Aucune dépense');
      final total = expenses.fold<int>(0, (a, e) => a + e.amount);
      p
        ..bold(true)
        ..columns('TOTAL DÉPENSES', '${fmtNum(total)} DA')
        ..bold(false)
        ..columns('dont sorti de la caisse', fmtNum(s.cashExpenses))
        ..separator('=');
    }
    if (sales && spending) {
      p
        ..bold(true)
        ..columns('VENTES - DÉPENSES CAISSE', '${fmtNum(s.totalSales - s.cashExpenses)} DA')
        ..bold(false);
    }
    p
      ..feed(4)
      ..cut();
    return p;
  }

  /// Bon cuisine : gros caractères, sans prix.
  static EscPos kitchen({
    required int number,
    required String mode,
    required String cashier,
    required List<CartLine> lines,
    String? banner,
  }) {
    final now = DateTime.now();
    // Bon cuisine : gros numéro, mode de service, puis les plats en grand pour être lus de loin.
    final p = _hw.newKitchenTicket()
      ..align(PosAlign.center)
      ..bold(true);
    if (banner != null) {
      p
        ..size(1, 2)
        ..line('*** $banner ***');
    }
    p
      ..size(2, 2)
      ..line('N° ${number.toString().padLeft(3, '0')}')
      ..size(1, 2)
      ..line('${mode.toUpperCase()}  ·  ${fmtTime(now)}')
      ..size(1, 1)
      ..bold(false)
      ..line('Caissier : $cashier')
      ..align(PosAlign.left)
      ..separator('=');
    for (final l in lines) {
      p
        ..bold(true)
        ..size(2, 2)
        ..line('${l.qty} x ${l.product.name}')
        ..size(1, 1)
        ..bold(false);
      if (l.note.isNotEmpty) {
        p
          ..bold(true)
          ..line('     » ${l.note}')
          ..bold(false);
      }
    }
    final count = lines.fold<int>(0, (a, l) => a + l.qty);
    p
      ..separator('=')
      ..align(PosAlign.center)
      ..line('$count article(s)')
      ..feed(4)
      ..cut();
    return p;
  }

  /// Rapport de clôture (ticket Z), court : fond, tickets, dépenses de la caisse, argent en caisse avec et sans le fond.
  static EscPos zReport({
    required DaySummary s,
    required int counted,
    required int takenHome,
    required String reason,
    required String closedBy,
    required List<Expense> expenses,
    int drawerOpenings = 0,
  }) {
    final diff = counted - s.expectedInDrawer;
    final fund = s.day.openingFund;
    final cashOut = expenses.where((e) => e.source == 'caisse').toList();
    final p = _hw.newTicket()
      ..align(PosAlign.center)
      ..image(logoBits, logoWidthBytes, logoHeight)
      ..bold(true)
      ..line('CLÔTURE DU ${fmtDate(s.day.openedAt)}')
      ..bold(false)
      ..line('${fmtTime(s.day.openedAt)} -> ${fmtTime(DateTime.now())} · $closedBy')
      ..align(PosAlign.left)
      ..separator('=')
      ..columns('Fond de départ', fmtNum(fund))
      ..columns('Tickets', '${s.tickets}')
      ..columns('Ventes', fmtNum(s.totalSales));
    if (s.cardSales > 0) p.columns('  dont TPE', fmtNum(s.cardSales));
    p.separator();
    if (cashOut.isEmpty) {
      p.columns('Dépenses', '0');
    } else {
      for (final e in cashOut) {
        p.columns(e.label, fmtNum(e.amount));
      }
      p.columns('Total dépenses', fmtNum(s.cashExpenses));
    }
    p
      ..separator('=')
      ..bold(true)
      ..columns('Caisse avec le fond', '${fmtNum(counted)} DA')
      ..columns('Caisse sans le fond', '${fmtNum(counted - fund)} DA')
      ..bold(false);
    if (diff != 0) {
      p.columns('Écart (attendu ${fmtNum(s.expectedInDrawer)})', fmtSigned(diff));
      if (reason.isNotEmpty) p.line('Motif : $reason');
    }
    if (drawerOpenings > 0) p.columns('Tiroir ouvert sans vente', '$drawerOpenings fois');
    p
      ..columns('Emporté au coffre', fmtNum(takenHome))
      ..feed(1)
      ..line('Signature : ..................')
      ..feed(3)
      ..cut();
    return p;
  }
}
