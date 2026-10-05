/// The web files a web-server binary carries, as an index and their bytes.
///
/// The binary used to carry its web app as one gzip stream and write every
/// file of it into its data directory when it started: a 50 MB site cost the
/// time to inflate 50 MB before the first request, and 50 MB of files on a
/// disk that was only ever meant to hold the database. A pack is read in
/// place instead. Opening it reads the index, which is kilobytes; a file's
/// bytes are read from the executable with a positioned read when a request
/// asks for that file, and never before. What the process holds is what
/// requests have needed.
///
/// Each file is stored the smallest way the build found: brotli (or zstd, or
/// gzip) for text, WebAssembly and fonts, as it is for a PNG or a woff2 that
/// is compressed already. A client that accepts the stored encoding is sent
/// those bytes untouched; [DVAssetPack.read] decodes for one that does not.
/// Identical files are stored once, so the engine a site and its Studio both
/// load costs its size once.
///
/// Layout, from the pack's first byte:
///
///     "DVASSET1"          8 bytes
///     index length        u32, little-endian
///     index               UTF-8 JSON (below)
///     data                every distinct stored file, back to back
///
/// The index is `{"build": id, "entries": [[path, offset, storedLength,
/// size, encoding, hash, flags], ...]}`, with offsets from the start of data.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

const String _magic = 'DVASSET1';

/// How a file's bytes are kept, and the `Content-Encoding` that names them.
enum DVAssetEncoding {
  identity('identity'),
  br('br'),
  zstd('zstd'),
  gzip('gzip');

  const DVAssetEncoding(this.token);

  /// The `Content-Encoding` / `Accept-Encoding` token.
  final String token;
}

/// Turns stored bytes back into the file they encode, given its [size].
typedef DVAssetDecoder = Uint8List Function(Uint8List stored, int size);

/// The decoders a process has. gzip is dart:io's; brotli and zstd come from
/// the native server library, which registers them when it is loaded.
abstract final class DVAssetCodecs {
  static final Map<DVAssetEncoding, DVAssetDecoder> _decoders =
      <DVAssetEncoding, DVAssetDecoder>{
    DVAssetEncoding.gzip: (Uint8List stored, int size) =>
        Uint8List.fromList(gzip.decode(stored)),
  };

  /// Makes [encoding] decodable in this process.
  static void register(DVAssetEncoding encoding, DVAssetDecoder decoder) {
    if (encoding == DVAssetEncoding.identity) {
      throw ArgumentError.value(encoding, 'encoding', 'identity needs no decoder');
    }
    _decoders[encoding] = decoder;
  }

  /// The decoder for [encoding], or null when this process has none.
  static DVAssetDecoder? decoder(DVAssetEncoding encoding) => _decoders[encoding];
}

/// Extensions of formats that are compressed already: encoding them again
/// costs build time and saves a few bytes at best.
const Set<String> _compressedAlready = <String>{
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'heic', 'ico',
  'woff', 'woff2',
  'zip', 'gz', 'tgz', 'br', 'zst', 'xz', 'bz2', '7z', 'rar',
  'mp4', 'm4v', 'mov', 'webm', 'mkv', 'mp3', 'm4a', 'aac', 'ogg', 'oga',
  'opus', 'flac', 'pdf', 'dill',
};

/// Whether the file at [path] is worth encoding at all.
bool dvAssetWorthEncoding(String path) {
  final String name = path.split('/').last.toLowerCase();
  final int dot = name.lastIndexOf('.');
  if (dot < 0) return true;
  return !_compressedAlready.contains(name.substring(dot + 1));
}

/// One file going into a pack.
///
/// [stored] is [bytes] encoded with [encoding], when the build encoded it;
/// the pack keeps whichever is smaller. [protected] marks a file only an
/// authorised caller may be sent, which no cache shared between callers may
/// keep.
final class DVAssetPackEntry {
  DVAssetPackEntry(
    this.path,
    this.bytes, {
    this.stored,
    this.encoding = DVAssetEncoding.identity,
    this.protected = false,
  });

  final String path;
  final Uint8List bytes;
  final Uint8List? stored;
  final DVAssetEncoding encoding;
  final bool protected;
}

const int _protectedFlag = 1;

/// A file in an opened pack.
final class DVPackedAsset {
  const DVPackedAsset._({
    required this.path,
    required int offset,
    required this.storedLength,
    required this.size,
    required this.encoding,
    required this.hash,
    required this.protected,
  }) : _offset = offset;

  /// Its path, relative to the root it was packed from, with `/`.
  final String path;

  /// Where its stored bytes start in the executable.
  final int _offset;

  /// How many bytes it is stored as.
  final int storedLength;

  /// How many bytes it is.
  final int size;

  /// How it is stored.
  final DVAssetEncoding encoding;

  /// The first 128 bits of the SHA-256 of its content, in hex: the same for
  /// the same bytes in every build, whatever they are stored as.
  final String hash;

  /// Whether only an authorised caller may be sent it.
  final bool protected;
}

/// A pack, opened in place inside a file.
final class DVAssetPack {
  DVAssetPack._(this._file, this.buildId, this._entries);

  final String _file;

  /// Names this pack's content: a different file anywhere in it is a
  /// different id. What a runtime cache of it is keyed by.
  final String buildId;

  final Map<String, DVPackedAsset> _entries;

  RandomAccessFile? _open;

  /// Every path carried.
  Iterable<String> get paths => _entries.keys;

  /// Every file carried.
  Iterable<DVPackedAsset> get assets => _entries.values;

  /// The file at [path], or null.
  DVPackedAsset? operator [](String path) => _entries[path];

  /// The pack at [offset] in [file], [length] bytes long, or null when the
  /// bytes there are not one. Reads the index and nothing else.
  static DVAssetPack? open(String file, {required int offset, required int length}) {
    final RandomAccessFile raf;
    try {
      raf = File(file).openSync();
    } on FileSystemException {
      return null;
    }
    try {
      if (length < 12) return null;
      raf.setPositionSync(offset);
      final Uint8List head = raf.readSync(12);
      if (head.length < 12 || ascii.decode(head.sublist(0, 8), allowInvalid: true) != _magic) {
        return null;
      }
      final int indexLength = ByteData.sublistView(head).getUint32(8, Endian.little);
      if (indexLength > length - 12) return null;
      final Object? index = jsonDecode(utf8.decode(raf.readSync(indexLength)));
      if (index is! Map || index['entries'] is! List || index['build'] is! String) {
        return null;
      }
      final int data = offset + 12 + indexLength;
      final int dataLength = length - 12 - indexLength;
      final Map<String, DVPackedAsset> entries = <String, DVPackedAsset>{};
      for (final Object? row in index['entries'] as List) {
        if (row is! List || row.length < 7) return null;
        final int at = row[1] as int;
        final int stored = row[2] as int;
        if (at < 0 || stored < 0 || at + stored > dataLength) return null;
        final int encoding = row[4] as int;
        if (encoding < 0 || encoding >= DVAssetEncoding.values.length) return null;
        final String path = row[0] as String;
        entries[path] = DVPackedAsset._(
          path: path,
          offset: data + at,
          storedLength: stored,
          size: row[3] as int,
          encoding: DVAssetEncoding.values[encoding],
          hash: row[5] as String,
          protected: (row[6] as int) & _protectedFlag != 0,
        );
      }
      return DVAssetPack._(file, index['build'] as String, entries);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on FileSystemException {
      return null;
    } finally {
      raf.closeSync();
    }
  }

  /// [asset]'s bytes as they are stored, or the part of them from [start] to
  /// [end]: what a client that accepts [DVPackedAsset.encoding] is sent.
  ///
  /// A positioned read of exactly that range. Synchronous, and so never
  /// interleaved with another read of the same file by this isolate.
  Uint8List readStored(DVPackedAsset asset, {int start = 0, int? end}) {
    final int stop = RangeError.checkValidRange(start, end, asset.storedLength);
    if (stop == start) return Uint8List(0);
    final RandomAccessFile file = _open ??= File(_file).openSync();
    file.setPositionSync(asset._offset + start);
    final Uint8List bytes = file.readSync(stop - start);
    if (bytes.length != stop - start) {
      throw FileSystemException(
          'the executable ended inside ${asset.path}', _file);
    }
    return bytes;
  }

  /// [asset]'s content, decoded when it is stored encoded.
  ///
  /// Throws [UnsupportedError] for an encoding this process cannot decode.
  Uint8List read(DVPackedAsset asset) {
    final Uint8List stored = readStored(asset);
    if (asset.encoding == DVAssetEncoding.identity) return stored;
    final DVAssetDecoder? decode = DVAssetCodecs.decoder(asset.encoding);
    if (decode == null) {
      throw UnsupportedError(
          '${asset.path} is stored as ${asset.encoding.token} and this process '
          'has no ${asset.encoding.token} decoder');
    }
    final Uint8List decoded = decode(stored, asset.size);
    if (decoded.length != asset.size) {
      throw FormatException('${asset.path} decoded to ${decoded.length} bytes, '
          'not the ${asset.size} it was packed as');
    }
    return decoded;
  }

  /// Lets go of the executable. The next read opens it again.
  void close() {
    _open?.closeSync();
    _open = null;
  }
}

/// [entries] as a pack.
///
/// Throws [ArgumentError] for a path that is empty, absolute, has a
/// backslash or a `..` segment, or is carried twice.
Uint8List dvWriteAssetPack(List<DVAssetPackEntry> entries) {
  final BytesBuilder data = BytesBuilder(copy: false);
  // Stored bytes already written, by what they are: a file carried twice,
  // under two paths, is written once.
  final Map<String, int> written = <String, int>{};
  final List<List<Object>> rows = <List<Object>>[];
  final Set<String> seen = <String>{};
  final List<DVAssetPackEntry> sorted = List<DVAssetPackEntry>.of(entries)
    ..sort((DVAssetPackEntry a, DVAssetPackEntry b) => a.path.compareTo(b.path));
  for (final DVAssetPackEntry entry in sorted) {
    final String path = entry.path;
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains(r'\') ||
        path.split('/').any((String s) => s == '..' || s.isEmpty)) {
      throw ArgumentError.value(path, 'path', 'not a path inside the site');
    }
    if (!seen.add(path)) {
      throw ArgumentError.value(path, 'path', 'carried twice');
    }
    final String hash = sha256.convert(entry.bytes).toString().substring(0, 32);
    final Uint8List? encoded = entry.stored;
    final bool keepEncoded = encoded != null &&
        entry.encoding != DVAssetEncoding.identity &&
        encoded.length < entry.bytes.length;
    final Uint8List stored = keepEncoded ? encoded : entry.bytes;
    final DVAssetEncoding encoding = keepEncoded ? entry.encoding : DVAssetEncoding.identity;
    final String key = '$hash/${encoding.index}/${stored.length}';
    final int offset = written.putIfAbsent(key, () {
      final int at = data.length;
      data.add(stored);
      return at;
    });
    rows.add(<Object>[
      path,
      offset,
      stored.length,
      entry.bytes.length,
      encoding.index,
      hash,
      entry.protected ? _protectedFlag : 0,
    ]);
  }
  final String build = sha256
      .convert(utf8.encode(jsonEncode(<Object>[
        for (final List<Object> row in rows) <Object>[row[0], row[4], row[5], row[6]],
      ])))
      .toString()
      .substring(0, 16);
  final Uint8List index = utf8.encode(jsonEncode(<String, Object>{
    'build': build,
    'entries': rows,
  }));
  final Uint8List head = Uint8List(12);
  head.setRange(0, 8, ascii.encode(_magic));
  ByteData.sublistView(head).setUint32(8, index.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(head)
        ..add(index)
        ..add(data.takeBytes()))
      .takeBytes();
}
