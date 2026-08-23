import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Copies files to the native Windows file-drop clipboard (CF_HDROP).
///
/// This avoids starting PowerShell/.NET for every WhatsApp invoice. The
/// clipboard owns the global-memory handle after SetClipboardData succeeds,
/// so the copied file list remains available after this method returns.
class WindowsFileClipboard {
  const WindowsFileClipboard._();

  static const int _cfHDrop = 15;
  static const int _gmemMoveable = 0x0002;
  static const int _gmemZeroInit = 0x0040;
  static const int _dropFilesHeaderBytes = 20;

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final int Function(Pointer<Void>) _openClipboard = _user32
      .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'OpenClipboard',
      );
  static final int Function() _closeClipboard = _user32
      .lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
  static final int Function() _emptyClipboard = _user32
      .lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');
  static final Pointer<Void> Function(int, Pointer<Void>) _setClipboardData =
      _user32.lookupFunction<
        Pointer<Void> Function(Uint32, Pointer<Void>),
        Pointer<Void> Function(int, Pointer<Void>)
      >('SetClipboardData');

  static final Pointer<Void> Function(int, int) _globalAlloc = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Uint32, IntPtr),
        Pointer<Void> Function(int, int)
      >('GlobalAlloc');
  static final Pointer<Void> Function(Pointer<Void>) _globalLock = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('GlobalLock');
  static final int Function(Pointer<Void>) _globalUnlock = _kernel32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('GlobalUnlock');
  static final Pointer<Void> Function(Pointer<Void>) _globalFree = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('GlobalFree');

  static Future<bool> copyFiles(List<String> filePaths) async {
    if (!Platform.isWindows || filePaths.isEmpty) return false;

    final absolutePaths = filePaths
        .map((path) => File(path).absolute.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (absolutePaths.isEmpty) return false;

    // CF_HDROP contains a DROPFILES header followed by a double-null-
    // terminated UTF-16 list of file paths.
    final pathUnits = <int>[];
    for (final path in absolutePaths) {
      pathUnits
        ..addAll(path.codeUnits)
        ..add(0);
    }
    pathUnits.add(0);

    final totalBytes = _dropFilesHeaderBytes + (pathUnits.length * 2);
    final handle = _globalAlloc(_gmemMoveable | _gmemZeroInit, totalBytes);
    if (handle == nullptr) return false;

    var clipboardOpened = false;
    var ownershipTransferred = false;
    try {
      final memory = _globalLock(handle);
      if (memory == nullptr) return false;
      try {
        final bytes = memory.cast<Uint8>().asTypedList(totalBytes);
        final data = ByteData.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );

        data.setUint32(0, _dropFilesHeaderBytes, Endian.little); // pFiles
        data.setInt32(4, 0, Endian.little); // pt.x
        data.setInt32(8, 0, Endian.little); // pt.y
        data.setInt32(12, 0, Endian.little); // fNC
        data.setInt32(16, 1, Endian.little); // fWide (UTF-16)

        for (var i = 0; i < pathUnits.length; i++) {
          data.setUint16(
            _dropFilesHeaderBytes + (i * 2),
            pathUnits[i],
            Endian.little,
          );
        }
      } finally {
        _globalUnlock(handle);
      }

      // Another Windows application can briefly own the clipboard. Retry for
      // a short bounded period instead of launching a heavyweight fallback.
      for (var attempt = 0; attempt < 12; attempt++) {
        if (_openClipboard(nullptr) != 0) {
          clipboardOpened = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (!clipboardOpened) return false;
      if (_emptyClipboard() == 0) return false;

      final result = _setClipboardData(_cfHDrop, handle);
      if (result == nullptr) return false;

      ownershipTransferred = true;
      return true;
    } finally {
      if (clipboardOpened) {
        _closeClipboard();
      }
      if (!ownershipTransferred) {
        _globalFree(handle);
      }
    }
  }
}
