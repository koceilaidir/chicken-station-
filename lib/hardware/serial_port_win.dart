import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'hardware_exception.dart';

/// Structure DCB de Windows (réglages du port série). 28 octets.
final class _Dcb extends Struct {
  @Uint32()
  external int dcbLength;
  @Uint32()
  external int baudRate;
  @Uint32()
  external int flags;
  @Uint16()
  external int reserved;
  @Uint16()
  external int xonLim;
  @Uint16()
  external int xoffLim;
  @Uint8()
  external int byteSize;
  @Uint8()
  external int parity;
  @Uint8()
  external int stopBits;
  @Int8()
  external int xonChar;
  @Int8()
  external int xoffChar;
  @Int8()
  external int errorChar;
  @Int8()
  external int eofChar;
  @Int8()
  external int evtChar;
  @Uint16()
  external int reserved1;
}

/// Structure COMMTIMEOUTS de Windows.
final class _CommTimeouts extends Struct {
  @Uint32()
  external int readIntervalTimeout;
  @Uint32()
  external int readTotalTimeoutMultiplier;
  @Uint32()
  external int readTotalTimeoutConstant;
  @Uint32()
  external int writeTotalTimeoutMultiplier;
  @Uint32()
  external int writeTotalTimeoutConstant;
}

typedef _CreateFileNative = IntPtr Function(
    Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr);
typedef _CreateFileDart = int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int);
typedef _CommStateNative = Int32 Function(IntPtr, Pointer<_Dcb>);
typedef _CommStateDart = int Function(int, Pointer<_Dcb>);
typedef _TimeoutsNative = Int32 Function(IntPtr, Pointer<_CommTimeouts>);
typedef _TimeoutsDart = int Function(int, Pointer<_CommTimeouts>);
typedef _WriteFileNative = Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>, Pointer<Void>);
typedef _WriteFileDart = int Function(int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Void>);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// Écrit des octets sur un port série (COM) — utilisé pour l'écran client.
class SerialPortWin {
  static final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');

  static final _createFile = _kernel.lookupFunction<_CreateFileNative, _CreateFileDart>('CreateFileW');
  static final _getCommState = _kernel.lookupFunction<_CommStateNative, _CommStateDart>('GetCommState');
  static final _setCommState = _kernel.lookupFunction<_CommStateNative, _CommStateDart>('SetCommState');
  static final _setTimeouts = _kernel.lookupFunction<_TimeoutsNative, _TimeoutsDart>('SetCommTimeouts');
  static final _writeFile = _kernel.lookupFunction<_WriteFileNative, _WriteFileDart>('WriteFile');
  static final _closeHandle = _kernel.lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  static final _getLastError = _kernel.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  static const _genericRead = 0x80000000;
  static const _genericWrite = 0x40000000;
  static const _openExisting = 3;
  static const _errorFileNotFound = 2;
  static const _errorAccessDenied = 5;

  /// Ouvre [port] (ex. « COM3 »), le règle en [baud] 8N1 sans contrôle de flux,
  /// envoie [data] puis referme le port.
  static void write(String port, int baud, Uint8List data) {
    final name = port.trim().toUpperCase();
    if (name.isEmpty) {
      throw const HardwareException("Aucun port COM choisi pour l'écran client.");
    }
    // Le préfixe \\.\ est obligatoire au-delà de COM9 et fonctionne pour tous.
    final path = name.startsWith(r'\\.\') ? name : '\\\\.\\$name';
    final pPath = path.toNativeUtf16();
    final dcb = calloc<_Dcb>();
    final timeouts = calloc<_CommTimeouts>();
    final buffer = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final written = calloc<Uint32>();

    try {
      final handle = _createFile(pPath, _genericRead | _genericWrite, 0, nullptr, _openExisting, 0, 0);
      if (handle == -1 || handle == 0) {
        final err = _getLastError();
        if (err == _errorAccessDenied) {
          throw HardwareException(
            '$name est déjà utilisé par un autre logiciel. Fermez Front Cash (ou tout logiciel de caisse) puis réessayez.',
          );
        }
        if (err == _errorFileNotFound) {
          throw HardwareException("$name n'existe pas sur ce PC. Choisissez un autre port.");
        }
        throw HardwareException("Impossible d'ouvrir $name (code $err).");
      }
      try {
        dcb.ref.dcbLength = sizeOf<_Dcb>();
        if (_getCommState(handle, dcb) == 0) {
          throw HardwareException('Lecture des réglages de $name impossible (code ${_getLastError()}).');
        }
        dcb.ref.dcbLength = sizeOf<_Dcb>();
        dcb.ref.baudRate = baud;
        dcb.ref.byteSize = 8;
        dcb.ref.parity = 0; // aucune
        dcb.ref.stopBits = 0; // 1 bit de stop
        // fBinary=1, DTR activé, RTS activé, aucun contrôle de flux.
        dcb.ref.flags = 0x1 | (1 << 4) | (1 << 12);
        if (_setCommState(handle, dcb) == 0) {
          throw HardwareException('Réglage de $name à $baud bauds refusé (code ${_getLastError()}).');
        }

        timeouts.ref.readIntervalTimeout = 50;
        timeouts.ref.readTotalTimeoutMultiplier = 0;
        timeouts.ref.readTotalTimeoutConstant = 200;
        timeouts.ref.writeTotalTimeoutMultiplier = 10;
        timeouts.ref.writeTotalTimeoutConstant = 1000;
        _setTimeouts(handle, timeouts);

        if (data.isNotEmpty) {
          buffer.asTypedList(data.length).setAll(0, data);
          final ok = _writeFile(handle, buffer.cast<Void>(), data.length, written, nullptr);
          if (ok == 0 || written.value != data.length) {
            throw HardwareException(
              'Envoi incomplet sur $name (${written.value}/${data.length} octets, code ${_getLastError()}).',
            );
          }
        }
      } finally {
        _closeHandle(handle);
      }
    } finally {
      calloc.free(pPath);
      calloc.free(dcb);
      calloc.free(timeouts);
      calloc.free(buffer);
      calloc.free(written);
    }
  }
}
