/// The installed fonts on macOS: CoreText's font URLs, over dart:ffi.
///
/// `CTFontManagerCopyAvailableFontURLs` lists the file of every font the
/// system makes available (system, /Library/Fonts, ~/Library/Fonts and fonts
/// activated by a font manager), and each file's faces are read from its own
/// tables (font_file.dart), as on Windows. Written against the documented C
/// API; not yet run on a Mac, since this repository's macOS runners are
/// unavailable (GitHub Actions is billing-locked on the account).
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../font_files_io.dart';

typedef _CopyUrlsN = Pointer<Void> Function();
typedef _CountN = IntPtr Function(Pointer<Void>);
typedef _CountD = int Function(Pointer<Void>);
typedef _AtN = Pointer<Void> Function(Pointer<Void>, IntPtr);
typedef _AtD = Pointer<Void> Function(Pointer<Void>, int);
typedef _PathN = Uint8 Function(Pointer<Void>, Uint8, Pointer<Uint8>, IntPtr);
typedef _PathD = int Function(Pointer<Void>, int, Pointer<Uint8>, int);
typedef _ReleaseN = Void Function(Pointer<Void>);
typedef _ReleaseD = void Function(Pointer<Void>);

class DVMacosFonts {
  const DVMacosFonts._();

  static const Set<String> implemented = <String>{'fonts.faces', 'fonts.read'};

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    final DynamicLibrary coreText;
    final DynamicLibrary coreFoundation;
    try {
      coreText = DynamicLibrary.open('/System/Library/Frameworks/CoreText.framework/CoreText');
      coreFoundation = DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
    } on ArgumentError {
      return;
    }
    bind('fonts.faces', (Object? _) => <String, Object?>{
          'faces': DVFontFiles.facesIn(fontFiles(coreText, coreFoundation)),
        });
    bind('fonts.read', DVFontFiles.read);
  }

  /// Every available font's file, once each.
  static List<String> fontFiles(DynamicLibrary coreText, DynamicLibrary coreFoundation) {
    final Pointer<Void> Function() copyUrls =
        coreText.lookupFunction<_CopyUrlsN, _CopyUrlsN>('CTFontManagerCopyAvailableFontURLs');
    final _CountD count = coreFoundation.lookupFunction<_CountN, _CountD>('CFArrayGetCount');
    final _AtD at = coreFoundation.lookupFunction<_AtN, _AtD>('CFArrayGetValueAtIndex');
    final _PathD path = coreFoundation.lookupFunction<_PathN, _PathD>('CFURLGetFileSystemRepresentation');
    final _ReleaseD release = coreFoundation.lookupFunction<_ReleaseN, _ReleaseD>('CFRelease');

    final Pointer<Void> urls = copyUrls();
    if (urls == nullptr) return const <String>[];
    const int capacity = 4096;
    final Pointer<Uint8> buffer = calloc<Uint8>(capacity);
    final Set<String> files = <String>{};
    try {
      final int total = count(urls);
      for (int i = 0; i < total; i++) {
        final Pointer<Void> url = at(urls, i);
        if (url == nullptr || path(url, 1, buffer, capacity) == 0) continue;
        files.add(buffer.cast<Utf8>().toDartString());
      }
    } finally {
      calloc.free(buffer);
      release(urls);
    }
    return files.toList();
  }
}
