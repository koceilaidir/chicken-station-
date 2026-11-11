import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'hardware_exception.dart';

/// Structure DOC_INFO_1W de winspool.
final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

typedef _OpenPrinterNative = Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);
typedef _OpenPrinterDart = int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);
typedef _StartDocNative = Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>);
typedef _StartDocDart = int Function(int, int, Pointer<_DocInfo1>);
typedef _HandleBoolNative = Int32 Function(IntPtr);
typedef _HandleBoolDart = int Function(int);
typedef _WritePrinterNative = Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Uint32>);
typedef _WritePrinterDart = int Function(int, Pointer<Void>, int, Pointer<Uint32>);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// Envoie des octets bruts (ESC/POS) à une imprimante installée dans Windows,
/// en passant par le spouleur avec le type de données « RAW ».
/// Le pilote ne transforme rien : l'imprimante reçoit exactement nos commandes.
class WinRawPrinter {
  static final DynamicLibrary _spool = DynamicLibrary.open('winspool.drv');
  static final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');

  static final _openPrinter = _spool.lookupFunction<_OpenPrinterNative, _OpenPrinterDart>('OpenPrinterW');
  static final _startDoc = _spool.lookupFunction<_StartDocNative, _StartDocDart>('StartDocPrinterW');
  static final _startPage = _spool.lookupFunction<_HandleBoolNative, _HandleBoolDart>('StartPagePrinter');
  static final _write = _spool.lookupFunction<_WritePrinterNative, _WritePrinterDart>('WritePrinter');
  static final _endPage = _spool.lookupFunction<_HandleBoolNative, _HandleBoolDart>('EndPagePrinter');
  static final _endDoc = _spool.lookupFunction<_HandleBoolNative, _HandleBoolDart>('EndDocPrinter');
  static final _closePrinter = _spool.lookupFunction<_HandleBoolNative, _HandleBoolDart>('ClosePrinter');
  static final _getLastError = _kernel.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  /// Imprime [data] sur l'imprimante Windows nommée [printerName].
  /// Lève une [HardwareException] avec un message en français en cas d'échec.
  static void printRaw(String printerName, Uint8List data, {String docName = 'Chicken Station'}) {
    if (printerName.trim().isEmpty) {
      throw const HardwareException('Aucune imprimante ticket choisie.');
    }
    if (data.isEmpty) return;

    final pName = printerName.toNativeUtf16();
    final pDocName = docName.toNativeUtf16();
    final pType = 'RAW'.toNativeUtf16();
    final phPrinter = calloc<IntPtr>();
    final docInfo = calloc<_DocInfo1>();
    final buffer = calloc<Uint8>(data.length);
    final written = calloc<Uint32>();

    try {
      if (_openPrinter(pName, phPrinter, nullptr) == 0) {
        throw HardwareException(
          'Imprimante « $printerName » introuvable dans Windows (code ${_getLastError()}).',
        );
      }
      final handle = phPrinter.value;
      try {
        docInfo.ref.pDocName = pDocName;
        docInfo.ref.pOutputFile = nullptr;
        docInfo.ref.pDatatype = pType;

        if (_startDoc(handle, 1, docInfo) == 0) {
          throw HardwareException(
            "Windows refuse le travail d'impression (code ${_getLastError()}). "
            "Vérifiez que l'imprimante est allumée et n'est pas en pause.",
          );
        }
        _startPage(handle);
        buffer.asTypedList(data.length).setAll(0, data);
        final ok = _write(handle, buffer.cast<Void>(), data.length, written);
        _endPage(handle);
        _endDoc(handle);
        if (ok == 0 || written.value != data.length) {
          throw HardwareException(
            'Envoi incomplet à l\'imprimante (${written.value}/${data.length} octets, code ${_getLastError()}).',
          );
        }
      } finally {
        _closePrinter(handle);
      }
    } finally {
      calloc.free(pName);
      calloc.free(pDocName);
      calloc.free(pType);
      calloc.free(phPrinter);
      calloc.free(docInfo);
      calloc.free(buffer);
      calloc.free(written);
    }
  }
}
