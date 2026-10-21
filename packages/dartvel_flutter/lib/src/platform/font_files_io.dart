/// Font files on a machine with a filesystem: reading the faces in a list of
/// files, and handing one face's bytes to `DV.Platform.fonts.load`.
///
/// Shared by every native target. Linux asks fontconfig for its faces and
/// only uses [DVFontFiles.read]; Windows, macOS and Android get file paths
/// from the system and read the faces out of the files with
/// [DVFontFiles.facesIn].
library dartvel_flutter.platform.font_files_io;

import 'dart:io';
import 'dart:typed_data';

import 'font_file.dart';

class DVFontFiles {
  const DVFontFiles._();

  /// The files the last listing named. `fonts.read` reads only these: the
  /// binding hands bytes to whoever asks, and "any path on the disk" is not
  /// what it is for.
  static final Set<String> _listed = <String>{};

  /// Records [paths] as listed, so [read] will open them.
  static void remember(Iterable<String> paths) => _listed.addAll(paths);

  /// The faces in each of [paths], as `fonts.faces` entries. A file that is
  /// not a font, cannot be opened or names no family is skipped: one broken
  /// file in a fonts folder is not a reason to list none.
  static List<Map<String, Object?>> facesIn(Iterable<String> paths) {
    final List<Map<String, Object?>> faces = <Map<String, Object?>>[];
    for (final String path in paths) {
      RandomAccessFile? file;
      try {
        file = File(path).openSync();
        final RandomAccessFile open = file;
        final int length = open.lengthSync();
        for (final DVFontFileFace face in dvReadFontFacesWith((int offset, int count) {
          if (offset < 0 || offset >= length) return Uint8List(0);
          open.setPositionSync(offset);
          return open.readSync(count);
        })) {
          faces.add(<String, Object?>{
            'family': face.family,
            'style': face.style,
            'weight': face.weight,
            'italic': face.italic,
            'width': face.width,
            'path': path,
            'index': face.index,
          });
        }
        _listed.add(path);
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } finally {
        file?.closeSync();
      }
    }
    return faces;
  }

  /// The font files directly in, or below, each of [directories] that exist.
  static List<String> filesUnder(Iterable<String> directories) => <String>[
        for (final String directory in directories)
          if (Directory(directory).existsSync())
            for (final FileSystemEntity entry
                in Directory(directory).listSync(recursive: true, followLinks: false))
              if (entry is File && _isFontFile(entry.path)) entry.path,
      ];

  static bool _isFontFile(String path) {
    final String lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf') || lower.endsWith('.ttc') || lower.endsWith('.otc');
  }

  /// `fonts.read`: the bytes of one face, as a font of its own.
  static Future<Uint8List> read(Object? arguments) async {
    final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
    final Object? path = map['path'];
    if (path is! String || !_listed.contains(path)) {
      throw ArgumentError('fonts.read reads only the font files fonts.faces listed, not $path.');
    }
    final Object? index = map['index'];
    final Uint8List bytes = await File(path).readAsBytes();
    return dvExtractFontFace(bytes, index is int ? index : 0);
  }
}
