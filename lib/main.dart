import 'package:flutter/material.dart';

import 'screens/hardware_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChickenStationApp());
}

class ChickenStationApp extends StatelessWidget {
  const ChickenStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chicken Station',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AppShell(),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, {this.ready = false});
  final String label;
  final IconData icon;
  final bool ready;
}

/// Coque de l'application : menu à gauche + écran courant.
/// Pour l'instant seul l'écran « Matériel » est prêt (phase 1).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _items = <_NavItem>[
    _NavItem('Caisse', Icons.point_of_sale_outlined),
    _NavItem('Clôture', Icons.check_circle_outline),
    _NavItem('Coffre', Icons.home_outlined),
    _NavItem('Compta', Icons.bar_chart_outlined),
    _NavItem('Stock', Icons.inventory_2_outlined),
    _NavItem('Achats', Icons.account_balance_wallet_outlined),
    _NavItem('Matériel', Icons.print_outlined, ready: true),
    _NavItem('Réglages', Icons.settings_outlined),
  ];

  int _selected = 6;

  void _select(int i) {
    if (!_items[i].ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('« ${_items[i].label} » arrive dans une prochaine étape.')),
      );
      return;
    }
    setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(items: _items, selected: _selected, onSelect: _select),
          const VerticalDivider(width: 1, thickness: 1, color: AppColors.separator),
          const Expanded(child: HardwareScreen()),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.selected, required this.onSelect});

  final List<_NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(13)),
            alignment: Alignment.center,
            child: const Text('CS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.text)),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final item = items[i];
                final active = i == selected;
                final color = active ? AppColors.text : (item.ready ? AppColors.textSecondary : const Color(0xFFAEAEB2));
                return Center(
                  child: Material(
                    color: active ? AppColors.yellowSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onSelect(i),
                      child: SizedBox(
                        width: 74,
                        height: 58,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.icon, size: 22, color: color),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const _MinervaFooter(),
        ],
      ),
    );
  }
}

class _MinervaFooter extends StatelessWidget {
  const _MinervaFooter();

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 9, height: 1.3, color: AppColors.textSecondary);
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Text('Developed by Minerva',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, height: 1.3, fontWeight: FontWeight.w700, color: Color(0xFF3A3A3C))),
          Text('+213 782 05 51 93', textAlign: TextAlign.center, style: small),
          Text('koceilaidir92\n@gmail.com', textAlign: TextAlign.center, style: small),
        ],
      ),
    );
  }
}
