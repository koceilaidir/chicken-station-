import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repos.dart';

import '../hardware/customer_display.dart';
import '../hardware/escpos.dart';
import '../hardware/hardware_config.dart';
import '../hardware/hardware_service.dart';
import '../hardware/system_lists.dart';
import '../ui/theme.dart';

class _Status {
  const _Status(this.ok, this.message);
  final bool ok;
  final String message;
}

class _LogEntry {
  _LogEntry(this.ok, this.text) : time = DateTime.now();
  final bool ok;
  final String text;
  final DateTime time;
}

/// Écran « Matériel » : réglage et test des 4 périphériques de la caisse.
/// À valider à 100 % avant de retirer l'ancien logiciel.
class HardwareScreen extends StatefulWidget {
  const HardwareScreen({super.key});

  @override
  State<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends State<HardwareScreen> {
  HardwareConfig? _cfg;
  late HardwareService _svc;
  List<String> _printers = [];
  List<String> _ports = [];
  bool _loadingLists = false;

  final Set<String> _busy = {};
  final Map<String, _Status> _status = {};
  final List<_LogEntry> _log = [];

  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '450.00');

  bool _autoRunning = false;
  int? _autoCurrent;

  static const _bauds = [1200, 2400, 4800, 9600, 19200, 38400];
  static const _widths = [48, 42, 32];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = HardwareService.I;
    final cfg = _svc.config;
    _ipCtrl.text = cfg.kitchenIp;
    _portCtrl.text = '${cfg.kitchenPort}';
    if (!mounted) return;
    setState(() => _cfg = cfg);
    await _refreshLists();
  }

  Future<void> _refreshLists() async {
    setState(() => _loadingLists = true);
    final printers = await SystemLists.printers();
    final ports = await SystemLists.comPorts();
    if (!mounted) return;
    setState(() {
      _printers = printers;
      _ports = ports;
      _loadingLists = false;
    });
    _addLog(true, '${printers.length} imprimante(s) et ${ports.length} port(s) COM trouvés.');
  }

  Future<void> _save() async {
    final cfg = _cfg;
    if (cfg == null) return;
    _svc.config = cfg;
    try {
      await cfg.save();
      _logSave();
    } catch (e) {
      _addLog(false, 'Enregistrement des réglages impossible : $e');
    }
  }

  Timer? _saveLog;

  /// Une seule ligne dans le journal pour une série de réglages rapprochés.
  void _logSave() {
    _saveLog?.cancel();
    _saveLog = Timer(const Duration(seconds: 5), () => logActivity('materiel', 'Réglages du matériel modifiés'));
  }

  void _update(void Function(HardwareConfig c) change) {
    final cfg = _cfg;
    if (cfg == null) return;
    setState(() => change(cfg));
    _save();
  }

  void _addLog(bool ok, String text) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, _LogEntry(ok, text));
      if (_log.length > 40) _log.removeLast();
    });
  }

  Future<void> _run(String key, String label, Future<void> Function() action) async {
    setState(() => _busy.add(key));
    try {
      await action();
      _status[key] = _Status(true, '$label : envoyé');
      _addLog(true, label);
    } catch (e) {
      _status[key] = _Status(false, '$e');
      _addLog(false, '$label — $e');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _testAll() async {
    await _run('ticket', 'Ticket test imprimé', _svc.printTicketTest);
    await _run('kitchen', 'Bon cuisine test envoyé', _svc.printKitchenTest);
    await _run('drawer', 'Ouverture du tiroir envoyée', _svc.openDrawer);
    await _run('display', 'Montant envoyé à l\'écran client', () => _svc.showAmount(_amountCtrl.text.trim()));
  }

  Future<void> _autoDisplay() async {
    final cfg = _cfg;
    if (cfg == null || _autoRunning) return;
    setState(() => _autoRunning = true);
    _addLog(true, 'Essai automatique de l\'écran client sur ${cfg.displayPort} : regardez l\'écran.');
    try {
      for (final t in DisplayTrial.all) {
        if (!mounted) return;
        setState(() => _autoCurrent = t.number);
        try {
          await _svc.sendToDisplay(
            CustomerDisplay.frame(t.protocol, amount: t.amount, line2: 'ESSAI ${t.number}'),
            baud: t.baud,
            preview: t.amount,
          );
        } catch (e) {
          _status['display'] = _Status(false, '$e');
          _addLog(false, 'Essai automatique arrêté — $e');
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    } finally {
      if (mounted) {
        setState(() {
          _autoRunning = false;
          _autoCurrent = null;
        });
      }
    }
  }

  void _applyTrial(DisplayTrial t) {
    _update((c) {
      c.displayProtocol = t.protocol;
      c.displayBaud = t.baud;
    });
    _status['display'] = _Status(true, 'Réglage retenu : ${t.protocol.label}, ${t.baud} bauds');
    _addLog(true, 'Écran client réglé sur ${t.protocol.label}, ${t.baud} bauds.');
  }

  // ======================================================================== UI

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    if (cfg == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        _header(),
        const SizedBox(height: 16),
        _simulationCard(cfg),
        const SizedBox(height: 16),
        _twoColumns(_ticketCard(cfg), _kitchenCard(cfg)),
        const SizedBox(height: 16),
        _twoColumns(_drawerCard(cfg), _displayCard(cfg)),
        const SizedBox(height: 16),
        _logCard(),
      ],
    );
  }

  Widget _header() {
    final okCount = ['ticket', 'kitchen', 'drawer', 'display'].where((k) => _status[k]?.ok == true).length;
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Matériel', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
              SizedBox(height: 2),
              Text("Fermez Front Cash avant de tester : il peut bloquer l'écran client et le tiroir.",
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: okCount == 4 ? AppColors.greenSoft : AppColors.fill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text('$okCount sur 4 tests réussis',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: okCount == 4 ? AppColors.greenText : AppColors.text)),
        ),
        const SizedBox(width: 10),
        SecondaryButton(label: _loadingLists ? 'Recherche…' : 'Actualiser', onPressed: _loadingLists ? null : _refreshLists),
        const SizedBox(width: 10),
        PrimaryButton(label: 'Tout tester', onPressed: _busy.isEmpty ? _testAll : null),
      ],
    );
  }

  Widget _simulationCard(HardwareConfig cfg) {
    return IosCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cfg.simulate ? AppColors.yellowSoft : AppColors.greenSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(cfg.simulate ? Icons.science_outlined : Icons.power_outlined, color: AppColors.text),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cfg.simulate ? 'Mode simulation activé' : 'Matériel réel',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(
                  cfg.simulate
                      ? "Tickets, bons cuisine, tiroir et écran client s'affichent à l'écran. Rien n'est envoyé au matériel."
                      : 'Tout est envoyé aux imprimantes, au tiroir et à l\'écran client.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: cfg.simulate,
            activeTrackColor: AppColors.yellow,
            onChanged: (v) {
              _update((c) => c.simulate = v);
              _addLog(true, v ? 'Mode simulation activé.' : 'Mode simulation désactivé : matériel réel.');
            },
          ),
        ],
      ),
    );
  }

  Widget _twoColumns(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(children: [a, const SizedBox(height: 16), b]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)],
        );
      },
    );
  }

  // ------------------------------------------------------------------ cartes

  Widget _ticketCard(HardwareConfig cfg) {
    final printers = {..._printers, if (cfg.ticketPrinterName.isNotEmpty) cfg.ticketPrinterName}.toList();
    return _DeviceCard(
      icon: Icons.receipt_long_outlined,
      title: 'Imprimante ticket',
      subtitle: 'POSLUX 80 mm · USB · devant la caisse',
      status: _status['ticket'],
      children: [
        _label('Imprimante Windows'),
        _Dropdown<String>(
          value: cfg.ticketPrinterName.isEmpty ? null : cfg.ticketPrinterName,
          hint: printers.isEmpty ? 'Aucune imprimante trouvée' : 'Choisir…',
          items: printers,
          text: (s) => s,
          onChanged: (v) => _update((c) => c.ticketPrinterName = v ?? ''),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Page de code (accents)'),
                  _Dropdown<int>(
                    value: cfg.codePage,
                    items: CodePage.all.map((c) => c.number).toList(),
                    text: (n) => CodePage.byNumber(n).label,
                    onChanged: (v) => _update((c) => c.codePage = v ?? 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Largeur'),
                  _Dropdown<int>(
                    value: _widths.contains(cfg.charsPerLine) ? cfg.charsPerLine : 48,
                    items: _widths,
                    text: (n) => '$n caractères',
                    onChanged: (v) => _update((c) => c.charsPerLine = v ?? 48),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Imprimer un ticket test',
                busy: _busy.contains('ticket'),
                onPressed: () => _run('ticket', 'Ticket test imprimé', _svc.printTicketTest),
              ),
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              label: 'Essai des accents',
              onPressed: () => _run('codepage', 'Essai des pages de code imprimé', _svc.printCodePageTest),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kitchenCard(HardwareConfig cfg) {
    return _DeviceCard(
      icon: Icons.soup_kitchen_outlined,
      title: 'Imprimante cuisine',
      subtitle: 'POSLUX 80 mm · réseau (câble bleu)',
      status: _status['kitchen'],
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Adresse IP'),
                  _TextBox(
                    controller: _ipCtrl,
                    hint: '192.168.1.___',
                    onChanged: (v) => _update((c) => c.kitchenIp = v.trim()),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Port'),
                  _TextBox(
                    controller: _portCtrl,
                    hint: '9100',
                    onChanged: (v) => _update((c) => c.kitchenPort = int.tryParse(v.trim()) ?? 9100),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _label('Page de code cuisine'),
        _Dropdown<int>(
          value: cfg.kitchenCodePage,
          items: CodePage.all.map((c) => c.number).toList(),
          text: (n) => CodePage.byNumber(n).label,
          onChanged: (v) => _update((c) => c.kitchenCodePage = v ?? 16),
        ),
        const SizedBox(height: 8),
        const Text(
          "IP inconnue ? Éteignez l'imprimante, maintenez FEED appuyé et rallumez : "
          "elle imprime une page d'auto-test avec son adresse IP.",
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Imprimer un bon cuisine test',
          busy: _busy.contains('kitchen'),
          onPressed: () => _run('kitchen', 'Bon cuisine test envoyé', _svc.printKitchenTest),
        ),
      ],
    );
  }

  Widget _drawerCard(HardwareConfig cfg) {
    return _DeviceCard(
      icon: Icons.inbox_outlined,
      title: 'Tiroir-caisse',
      subtitle: "riva POS · branché sur l'imprimante ticket (prise RJ11)",
      status: _status['drawer'],
      children: [
        _label('Broche de commande'),
        _Dropdown<int>(
          value: cfg.drawerPin,
          items: const [0, 1],
          text: (n) => n == 0 ? 'Broche 2 (la plus courante)' : 'Broche 5',
          onChanged: (v) => _update((c) => c.drawerPin = v ?? 0),
        ),
        const SizedBox(height: 8),
        const Text(
          "Le tiroir s'ouvre par une commande envoyée à l'imprimante ticket : "
          "réglez d'abord l'imprimante ticket. S'il ne s'ouvre pas, essayez la broche 5.",
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: 'Ouvrir le tiroir',
          busy: _busy.contains('drawer'),
          onPressed: () => _run('drawer', 'Ouverture du tiroir envoyée', _svc.openDrawer),
        ),
      ],
    );
  }

  Widget _displayCard(HardwareConfig cfg) {
    final ports = {..._ports, if (cfg.displayPort.isNotEmpty) cfg.displayPort}.toList();
    return _DeviceCard(
      icon: Icons.tv_outlined,
      title: 'Écran client',
      subtitle: 'Afficheur POSLUX au dos de la caisse',
      status: _status['display'],
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Port COM'),
                  _Dropdown<String>(
                    value: cfg.displayPort.isEmpty ? null : cfg.displayPort,
                    hint: ports.isEmpty ? 'Aucun port trouvé' : 'Choisir…',
                    items: ports,
                    text: (s) => s,
                    onChanged: (v) => _update((c) => c.displayPort = v ?? ''),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Vitesse'),
                  _Dropdown<int>(
                    value: _bauds.contains(cfg.displayBaud) ? cfg.displayBaud : 2400,
                    items: _bauds,
                    text: (n) => '$n bauds',
                    onChanged: (v) => _update((c) => c.displayBaud = v ?? 2400),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Type d\'afficheur'),
                  _Dropdown<DisplayProtocol>(
                    value: cfg.displayProtocol,
                    items: DisplayProtocol.values,
                    text: (p) => p.label,
                    onChanged: (v) => _update((c) => c.displayProtocol = v ?? DisplayProtocol.led8),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Montant'),
                  _TextBox(controller: _amountCtrl, hint: '450.00', onChanged: (_) {}),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Afficher le montant',
                busy: _busy.contains('display'),
                onPressed: () => _run('display', "Montant envoyé à l'écran client",
                    () => _svc.showAmount(_amountCtrl.text.trim())),
              ),
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              label: _autoRunning ? 'Essai n°${_autoCurrent ?? ''}…' : 'Essai automatique',
              onPressed: _autoRunning || cfg.displayPort.isEmpty ? null : _autoDisplay,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel("Essai automatique : quel nombre s'est affiché ?"),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in DisplayTrial.all)
              Tooltip(
                message: '${t.protocol.label}, ${t.baud} bauds',
                child: ActionChip(
                  label: Text(t.amount),
                  backgroundColor: _autoCurrent == t.number ? AppColors.yellow : AppColors.fill,
                  side: BorderSide.none,
                  onPressed: () => _applyTrial(t),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _logCard() {
    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Journal des tests'),
          const SizedBox(height: 8),
          if (_log.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun test pour le moment.', style: TextStyle(color: AppColors.textSecondary)),
            ),
          for (final e in _log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}:${e.time.second.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Icon(e.ok ? Icons.check_circle : Icons.error,
                      size: 16, color: e.ok ? AppColors.green : AppColors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.text, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(s, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
}

// ========================================================================== widgets

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _Status? status;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              _StatusPill(status: s),
            ],
          ),
          if (s != null && !s.ok) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
              child: Text(s.message, style: const TextStyle(fontSize: 12.5, color: AppColors.redText)),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final _Status? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final String text;
    final Color bg;
    final Color fg;
    if (s == null) {
      text = 'Pas testé';
      bg = AppColors.fill;
      fg = AppColors.textSecondary;
    } else if (s.ok) {
      text = 'OK';
      bg = AppColors.greenSoft;
      fg = AppColors.greenText;
    } else {
      text = 'Erreur';
      bg = AppColors.redSoft;
      fg = AppColors.redText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.text,
    required this.onChanged,
    this.hint = 'Choisir…',
  });

  final T? value;
  final List<T> items;
  final String Function(T) text;
  final ValueChanged<T?> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final v = value != null && items.contains(value) ? value : null;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: v,
          isExpanded: true,
          hint: Text(hint, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          borderRadius: BorderRadius.circular(12),
          items: [
            for (final it in items)
              DropdownMenuItem<T>(
                value: it,
                child: Text(text(it), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TextBox extends StatelessWidget {
  const _TextBox({required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: AppColors.fill,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
