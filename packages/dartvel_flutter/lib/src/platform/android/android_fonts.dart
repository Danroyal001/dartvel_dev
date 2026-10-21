/// The installed fonts on Android: the files in the system font folders.
///
/// Android has no public font enumeration before API 29
/// (`SystemFonts.getAvailableFonts`), and that one is a Java set of `Font`
/// objects whose files are the ones in `/system/fonts` and the product and
/// vendor partitions anyway. Those folders are world-readable, so the faces
/// are read from the files there (font_file.dart) in Dart, with no JNI at
/// all. Written and unit-tested off Android (the reader); not yet run on a
/// device. A font downloaded through Google Play's downloadable fonts is not
/// installed on the device in this sense and is not listed.
library;

import 'dart:async';

import '../font_files_io.dart';

class DVAndroidFonts {
  const DVAndroidFonts._();

  /// Where Android keeps its fonts: the system image, and the product and
  /// vendor partitions OEMs add theirs to.
  static const List<String> directories = <String>[
    '/system/fonts',
    '/product/fonts',
    '/system/product/fonts',
    '/vendor/fonts',
  ];

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('fonts.faces', (Object? _) => <String, Object?>{
          'faces': DVFontFiles.facesIn(DVFontFiles.filesUnder(directories)),
        });
    bind('fonts.read', DVFontFiles.read);
  }
}
