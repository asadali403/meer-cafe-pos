import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Sends raw bytes (ESC/POS) to a Windows printer queue through the spooler
/// (OpenPrinter / StartDocPrinter "RAW" / WritePrinter). No printer driver
/// processing is involved, so the "Generic / Text Only" driver is enough.
class RawPrinter {
  RawPrinter._();

  /// Throws a [RawPrinterException] when the job could not be sent.
  static Future<void> send(String printerName, Uint8List data, {String jobName = 'Meer Cafe POS'}) =>
      Isolate.run(() => _send(printerName, data, jobName));

  static void _send(String printerName, Uint8List data, String jobName) {
    final lib = DynamicLibrary.open('winspool.drv');
    final openPrinter = lib.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
        int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>('OpenPrinterW');
    final closePrinter = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('ClosePrinter');
    final startDoc = lib.lookupFunction<Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>),
        int Function(int, int, Pointer<_DocInfo1>)>('StartDocPrinterW');
    final endDoc = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDocPrinter');
    final startPage = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPagePrinter');
    final endPage = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPagePrinter');
    final writePrinter = lib.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>('WritePrinter');

    final arena = Arena();
    try {
      final handle = arena<IntPtr>();
      if (openPrinter(printerName.toNativeUtf16(allocator: arena), handle, nullptr) == 0) {
        throw RawPrinterException('Printer "$printerName" could not be opened. Is it installed and switched on?');
      }
      final h = handle.value;
      try {
        final doc = arena<_DocInfo1>()
          ..ref.pDocName = jobName.toNativeUtf16(allocator: arena)
          ..ref.pOutputFile = nullptr
          ..ref.pDatatype = 'RAW'.toNativeUtf16(allocator: arena);
        if (startDoc(h, 1, doc) == 0) throw RawPrinterException('The printer refused the print job.');
        try {
          startPage(h);
          final buf = arena<Uint8>(data.length);
          buf.asTypedList(data.length).setAll(0, data);
          final written = arena<Uint32>();
          final ok = writePrinter(h, buf, data.length, written);
          endPage(h);
          if (ok == 0 || written.value != data.length) {
            throw RawPrinterException('Sending to the printer failed (${written.value}/${data.length} bytes).');
          }
        } finally {
          endDoc(h);
        }
      } finally {
        closePrinter(h);
      }
    } finally {
      arena.releaseAll();
    }
  }
}

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

class RawPrinterException implements Exception {
  final String message;
  RawPrinterException(this.message);
  @override
  String toString() => message;
}
