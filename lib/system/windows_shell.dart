import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Plein écran « kiosque » (la barre des tâches Windows est cachée) et démarrage avec Windows.
/// Appels directs à user32.dll : pas de paquet supplémentaire, rien à modifier dans le lanceur.
class WindowsShell {
  /// Programmes de l'ancienne caisse (Optima / Front Cash) : OSDEV garde le port de l'écran client.
  static const oldPosPrograms = ['OSDEV.exe', 'FrontCash.exe'];

  /// Ferme l'ancienne caisse si elle tourne. Renvoie les programmes fermés.
  static Future<List<String>> closeOldPos() async {
    final closed = <String>[];
    for (final exe in oldPosPrograms) {
      try {
        final r = await Process.run('taskkill', ['/F', '/IM', exe]);
        if (r.exitCode == 0) closed.add(exe);
      } catch (_) {}
    }
    return closed;
  }

  static bool _fullscreen = false;
  static int _savedStyle = 0;
  static final _savedRect = <int>[0, 0, 0, 0];

  static bool get isFullscreen => _fullscreen;

  static const _gwlStyle = -16;
  static const _wsOverlappedWindow = 0x00CF0000;
  static const _swpNoZOrder = 0x0004;
  static const _swpNoOwnerZOrder = 0x0200;
  static const _swpFrameChanged = 0x0020;
  static const _swpShowWindow = 0x0040;
  static const _monitorDefaultToNearest = 2;

  static DynamicLibrary? _lib;
  static DynamicLibrary get _user32 => _lib ??= DynamicLibrary.open('user32.dll');

  static int Function(Pointer<Utf16>, Pointer<Utf16>) get _findWindow =>
      _user32.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>), int Function(Pointer<Utf16>, Pointer<Utf16>)>(
          'FindWindowW');

  static int Function(int, int) get _getWindowLongPtr =>
      _user32.lookupFunction<IntPtr Function(IntPtr, Int32), int Function(int, int)>('GetWindowLongPtrW');

  static int Function(int, int, int) get _setWindowLongPtr =>
      _user32.lookupFunction<IntPtr Function(IntPtr, Int32, IntPtr), int Function(int, int, int)>('SetWindowLongPtrW');

  static int Function(int, int) get _monitorFromWindow =>
      _user32.lookupFunction<IntPtr Function(IntPtr, Uint32), int Function(int, int)>('MonitorFromWindow');

  static int Function(int, Pointer<Uint32>) get _getMonitorInfo =>
      _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>('GetMonitorInfoW');

  static int Function(int, Pointer<Int32>) get _getWindowRect =>
      _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Int32>), int Function(int, Pointer<Int32>)>('GetWindowRect');

  static int Function(int, int, int, int, int, int, int) get _setWindowPos => _user32.lookupFunction<
      Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
      int Function(int, int, int, int, int, int, int)>('SetWindowPos');

  /// Fenêtre principale de l'appli (classe du lanceur Flutter + titre « Chicken Station »).
  static int _hwnd() {
    if (!Platform.isWindows) return 0;
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final title = 'Chicken Station'.toNativeUtf16();
    try {
      var h = _findWindow(cls, title);
      if (h == 0) h = _findWindow(cls, nullptr);
      return h;
    } finally {
      calloc.free(cls);
      calloc.free(title);
    }
  }

  /// Passe en plein écran (true) ou revient en fenêtre normale (false).
  /// Renvoie false si la fenêtre n'a pas été trouvée.
  static bool setFullscreen(bool on) {
    if (!Platform.isWindows || on == _fullscreen) return true;
    final h = _hwnd();
    if (h == 0) return false;
    if (on) {
      _savedStyle = _getWindowLongPtr(h, _gwlStyle);
      final rect = calloc<Int32>(4);
      // MONITORINFO : cbSize, rcMonitor (4), rcWork (4), dwFlags = 40 octets.
      final info = calloc<Uint32>(10);
      try {
        _getWindowRect(h, rect);
        for (var i = 0; i < 4; i++) {
          _savedRect[i] = rect[i];
        }
        info[0] = 40;
        final mon = _monitorFromWindow(h, _monitorDefaultToNearest);
        if (_getMonitorInfo(mon, info) == 0) return false;
        final m = info.cast<Int32>();
        final left = m[1], top = m[2], right = m[3], bottom = m[4];
        _setWindowLongPtr(h, _gwlStyle, _savedStyle & ~_wsOverlappedWindow);
        _setWindowPos(h, 0, left, top, right - left, bottom - top, _swpNoOwnerZOrder | _swpFrameChanged | _swpShowWindow);
      } finally {
        calloc.free(rect);
        calloc.free(info);
      }
    } else {
      _setWindowLongPtr(h, _gwlStyle, _savedStyle == 0 ? (_getWindowLongPtr(h, _gwlStyle) | _wsOverlappedWindow) : _savedStyle);
      final w = _savedRect[2] - _savedRect[0];
      final hgt = _savedRect[3] - _savedRect[1];
      _setWindowPos(
        h,
        0,
        _savedRect[0],
        _savedRect[1],
        w > 200 ? w : 1280,
        hgt > 200 ? hgt : 800,
        _swpNoZOrder | _swpNoOwnerZOrder | _swpFrameChanged | _swpShowWindow,
      );
    }
    _fullscreen = on;
    return true;
  }

  /// Au démarrage, la fenêtre apparaît après la première image : on réessaie quelques fois.
  static Future<void> applyFullscreenAtStartup(bool on) async {
    if (!on) return;
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (setFullscreen(true)) return;
    }
  }

  // ------------------------------------------------------------------ démarrage avec Windows

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'ChickenStation';

  /// L'appli est-elle lancée à l'ouverture de la session Windows ?
  static Future<bool> autostartEnabled() async {
    if (!Platform.isWindows) return false;
    final r = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
    return r.exitCode == 0;
  }

  /// Active ou désactive le lancement automatique (pour l'utilisateur Windows courant).
  static Future<void> setAutostart(bool on) async {
    if (!Platform.isWindows) return;
    final ProcessResult r;
    if (on) {
      final exe = Platform.resolvedExecutable;
      r = await Process.run('reg', ['add', _runKey, '/v', _valueName, '/t', 'REG_SZ', '/d', '"$exe"', '/f']);
    } else {
      r = await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
    }
    if (r.exitCode != 0) {
      throw Exception('Windows a refusé la modification (${(r.stderr as Object?).toString().trim()}).');
    }
  }

  /// Chemin de l'exécutable lancé au démarrage (pour l'afficher).
  static String get executable => Platform.resolvedExecutable;
}
