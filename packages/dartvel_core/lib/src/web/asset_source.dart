/// Where a server reads a site's files from.
///
/// During development and preview the site is a directory. In a web-server
/// binary it is the pack inside the executable, read in place: no file of it
/// is ever written out. Everything that reads the site -- static files, the
/// shell and manifest a page is rendered from, an image's source, Studio's
/// files -- asks [DVAssetSources.at] for its root, so the same code serves
/// both, and a root stays the `String` it always was.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import '../process/asset_pack.dart';

/// One file of a site.
abstract interface class DVAssetFile {
  /// Its path under the site, with `/`.
  String get path;

  /// How many bytes it is.
  int get size;

  /// Names its content: the same bytes have the same hash in every build.
  String get hash;

  /// Whether only an authorised caller may be sent it. Never kept by a cache
  /// shared between callers.
  bool get protected;

  /// How it is kept, and so what [stored] returns.
  DVAssetEncoding get storedEncoding;

  /// How many bytes [stored] returns in all.
  int get storedLength;

  /// Its bytes as kept, or the part from [start] to [end]: what a client that
  /// accepts [storedEncoding] is sent as it is.
  Uint8List stored({int start = 0, int? end});

  /// Its content, decoded when it is kept encoded.
  Uint8List bytes();
}

/// A site's files.
abstract interface class DVAssetSource {
  /// The file at [path] -- relative, with `/`, as [dvAssetPath] returns it --
  /// or null when there is none. A directory is not a file.
  DVAssetFile? file(String path);

  /// Every file's path, relative, with `/`.
  Iterable<String> list();

  /// Whether the files are carried inside this executable.
  bool get embedded;

  /// Names every file this source holds, for a cache of it that outlives the
  /// process; null for a directory, whose files change under it.
  String? get buildId;
}

/// The sources this process serves from, by root.
abstract final class DVAssetSources {
  static final Map<String, DVAssetSource> _registered = <String, DVAssetSource>{};

  /// Serves [root] from [source] rather than from a directory of that name.
  static void register(String root, DVAssetSource source) => _registered[root] = source;

  /// The source for [root]: what was registered for it or for a directory
  /// it is under, or the directory itself.
  static DVAssetSource at(String root) {
    final DVAssetSource? exact = _registered[root];
    if (exact != null) return exact;
    for (final MapEntry<String, DVAssetSource> entry in _registered.entries) {
      for (final String separator in <String>{'/', Platform.pathSeparator}) {
        if (root.startsWith('${entry.key}$separator') && entry.value is DVPackedAssets) {
          final DVPackedAssets packed = entry.value as DVPackedAssets;
          final String under = root.substring(entry.key.length + 1).replaceAll(separator, '/');
          return DVPackedAssets(packed.pack, prefix: '${packed.prefix}$under/');
        }
      }
    }
    return DVDirectoryAssets(root);
  }

  /// Forgets every registration.
  static void clear() => _registered.clear();
}

/// The file a request path names, relative to the site; null for a path that
/// is no file or would leave the site.
///
/// Decoded before it is checked, so `%2e%2e` is the same two dots here as it
/// is to any proxy in front of this. A backslash, a drive letter and a
/// dot-dot are refused outright rather than resolved.
String? dvAssetPath(String requestPath) {
  final String decoded;
  try {
    decoded = Uri.decodeComponent(requestPath);
  } on ArgumentError {
    return null;
  }
  if (decoded.contains(r'\') || decoded.contains('\u0000')) return null;
  final List<String> segments = <String>[];
  for (final String segment in decoded.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..' || segment.contains(':')) return null;
    segments.add(segment);
  }
  if (segments.isEmpty) return null;
  return segments.join('/');
}

/// A site in a directory, as `dartvel dev` and `dartvel preview` serve it.
final class DVDirectoryAssets implements DVAssetSource {
  DVDirectoryAssets(this.root);

  final String root;

  @override
  bool get embedded => false;

  @override
  String? get buildId => null;

  @override
  Iterable<String> list() {
    final Directory directory = Directory(root);
    if (!directory.existsSync()) return const <String>[];
    return <String>[
      for (final FileSystemEntity entity in directory.listSync(recursive: true))
        if (entity is File)
          entity.path.substring(directory.path.length + 1).replaceAll(Platform.pathSeparator, '/'),
    ];
  }

  @override
  DVAssetFile? file(String path) {
    // Callers pass what dvAssetPath returns; refused here as well, because a
    // directory is the one source a dot-dot could actually leave.
    if (path.split('/').any((String s) => s == '..' || s.isEmpty) || path.contains(r'\')) {
      return null;
    }
    final File file = File(<String>[root, ...path.split('/')].join(Platform.pathSeparator));
    final FileStat stat = file.statSync();
    if (stat.type != FileSystemEntityType.file) return null;
    return _DirectoryFile(path, file, stat);
  }
}

/// Hashes of files already read, by path, with the modification time and
/// size they were read at.
final Map<String, (DateTime, int, String)> _directoryHashes = <String, (DateTime, int, String)>{};

final class _DirectoryFile implements DVAssetFile {
  _DirectoryFile(this.path, this._file, this._stat);

  @override
  final String path;
  final File _file;
  final FileStat _stat;

  @override
  int get size => _stat.size;

  @override
  String get hash {
    final (DateTime, int, String)? known = _directoryHashes[_file.path];
    if (known != null && known.$1 == _stat.modified && known.$2 == _stat.size) return known.$3;
    final String made = sha256.convert(bytes()).toString().substring(0, 32);
    _directoryHashes[_file.path] = (_stat.modified, _stat.size, made);
    return made;
  }

  @override
  bool get protected => false;

  @override
  DVAssetEncoding get storedEncoding => DVAssetEncoding.identity;

  @override
  int get storedLength => _stat.size;

  @override
  Uint8List stored({int start = 0, int? end}) {
    final int stop = RangeError.checkValidRange(start, end, _stat.size);
    final RandomAccessFile raf = _file.openSync();
    try {
      raf.setPositionSync(start);
      return raf.readSync(stop - start);
    } finally {
      raf.closeSync();
    }
  }

  @override
  Uint8List bytes() => _file.readAsBytesSync();
}

/// The files under [prefix] in a pack carried by this executable.
final class DVPackedAssets implements DVAssetSource {
  DVPackedAssets(this.pack, {required this.prefix});

  final DVAssetPack pack;

  /// What every path of this source starts with in the pack: `web/`.
  final String prefix;

  @override
  bool get embedded => true;

  @override
  String? get buildId => pack.buildId;

  @override
  Iterable<String> list() => <String>[
        for (final String path in pack.paths)
          if (path.startsWith(prefix)) path.substring(prefix.length),
      ];

  @override
  DVAssetFile? file(String path) {
    final DVPackedAsset? asset = pack['$prefix$path'];
    return asset == null ? null : _PackedFile(path, pack, asset);
  }
}

final class _PackedFile implements DVAssetFile {
  _PackedFile(this.path, this._pack, this._asset);

  @override
  final String path;
  final DVAssetPack _pack;
  final DVPackedAsset _asset;

  @override
  int get size => _asset.size;

  @override
  String get hash => _asset.hash;

  @override
  bool get protected => _asset.protected;

  @override
  DVAssetEncoding get storedEncoding => _asset.encoding;

  @override
  int get storedLength => _asset.storedLength;

  @override
  Uint8List stored({int start = 0, int? end}) => _pack.readStored(_asset, start: start, end: end);

  @override
  Uint8List bytes() => _pack.read(_asset);
}
