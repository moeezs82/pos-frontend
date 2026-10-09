import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Sends raw bytes (ZPL / TSPL / ESC-POS) straight to an installed Windows
/// printer queue, bypassing the printer driver's page rendering.
///
/// This is what lets a USB label printer such as the Black Copper BC-LP1300
/// be driven in its native ZPL or TSPL language without an IP address. The
/// spooler job is created with the `RAW` datatype, so Windows passes the bytes
/// to the port untouched.
///
/// Presentation/hardware only: nothing here touches sales, stock or accounting.
class WindowsRawPrinter {
  const WindowsRawPrinter._();

  static bool get isSupported => Platform.isWindows;

  static final DynamicLibrary _winspool = DynamicLibrary.open('winspool.drv');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)
      _openPrinter = _winspool.lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
          int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>(
    'OpenPrinterW',
  );
  static final int Function(int, int, Pointer<Void>) _startDocPrinter =
      _winspool.lookupFunction<
          Uint32 Function(IntPtr, Uint32, Pointer<Void>),
          int Function(int, int, Pointer<Void>)>('StartDocPrinterW');
  static final int Function(int) _startPagePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'StartPagePrinter',
  );
  static final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
      _writePrinter = _winspool.lookupFunction<
          Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>(
    'WritePrinter',
  );
  static final int Function(int) _endPagePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'EndPagePrinter',
  );
  static final int Function(int) _endDocPrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'EndDocPrinter',
  );
  static final int Function(int) _closePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
    'ClosePrinter',
  );
  static final int Function() _getLastError = _kernel32
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  /// Writes [data] to the Windows printer called [printerName] as one RAW job.
  ///
  /// Throws an [Exception] with a user-readable message on any failure.
  static void send({
    required String printerName,
    required Uint8List data,
    String jobName = 'CounterIQ Barcode Labels',
  }) {
    if (!isSupported) {
      throw Exception('Raw printing to an installed printer is only available on Windows.');
    }
    if (data.isEmpty) {
      throw Exception('There is nothing to send to the printer.');
    }

    final namePtr = printerName.toNativeUtf16();
    final handlePtr = calloc<IntPtr>();
    Pointer<Uint8>? buffer;
    Pointer<Uint32>? written;
    Pointer<Utf16>? docNamePtr;
    Pointer<Utf16>? dataTypePtr;
    Pointer<IntPtr>? docInfo;
    var handle = 0;
    var docStarted = false;
    var pageStarted = false;

    try {
      if (_openPrinter(namePtr, handlePtr, nullptr) == 0) {
        throw Exception(
          'Windows could not open the printer "$printerName" (error ${_getLastError()}). '
          'Check that it is installed and powered on.',
        );
      }
      handle = handlePtr.value;

      // DOC_INFO_1W { LPWSTR pDocName; LPWSTR pOutputFile; LPWSTR pDatatype; }
      docNamePtr = jobName.toNativeUtf16();
      dataTypePtr = 'RAW'.toNativeUtf16();
      docInfo = calloc<IntPtr>(3);
      docInfo[0] = docNamePtr.address;
      docInfo[1] = 0;
      docInfo[2] = dataTypePtr.address;

      if (_startDocPrinter(handle, 1, docInfo.cast<Void>()) == 0) {
        throw Exception(
          'Windows refused to start the print job (error ${_getLastError()}).',
        );
      }
      docStarted = true;

      if (_startPagePrinter(handle) == 0) {
        throw Exception(
          'Windows refused to start the label page (error ${_getLastError()}).',
        );
      }
      pageStarted = true;

      buffer = calloc<Uint8>(data.length);
      buffer.asTypedList(data.length).setAll(0, data);
      written = calloc<Uint32>();

      if (_writePrinter(handle, buffer, data.length, written) == 0 ||
          written.value != data.length) {
        throw Exception(
          'Windows could not send the label data to "$printerName" (error ${_getLastError()}).',
        );
      }
    } finally {
      if (handle != 0) {
        if (pageStarted) _endPagePrinter(handle);
        if (docStarted) _endDocPrinter(handle);
        _closePrinter(handle);
      }
      calloc.free(namePtr);
      calloc.free(handlePtr);
      if (buffer != null) calloc.free(buffer);
      if (written != null) calloc.free(written);
      if (docNamePtr != null) calloc.free(docNamePtr);
      if (dataTypePtr != null) calloc.free(dataTypePtr);
      if (docInfo != null) calloc.free(docInfo);
    }
  }
}
