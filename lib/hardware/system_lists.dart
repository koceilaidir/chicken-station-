import 'dart:convert';
import 'dart:io';

/// Listes lues dans Windows : imprimantes installées et ports COM présents.
class SystemLists {
  /// Noms des imprimantes installées (Panneau de configuration > Imprimantes).
  static Future<List<String>> printers() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; '
            'Get-Printer | Select-Object -ExpandProperty Name',
      ], stdoutEncoding: utf8);
      if (r.exitCode != 0) return [];
      return _lines(r.stdout);
    } catch (_) {
      return [];
    }
  }

  /// Ports série présents (COM1, COM3…), lus dans le registre Windows.
  static Future<List<String>> comPorts() async {
    try {
      final r = await Process.run('reg', ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM']);
      final ports = RegExp(r'\b(COM\d+)\b')
          .allMatches('${r.stdout}')
          .map((m) => m.group(1)!)
          .toSet()
          .toList()
        ..sort((a, b) => int.parse(a.substring(3)).compareTo(int.parse(b.substring(3))));
      return ports;
    } catch (_) {
      return [];
    }
  }

  static List<String> _lines(Object? out) => '$out'
      .split(RegExp(r'\r?\n'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
