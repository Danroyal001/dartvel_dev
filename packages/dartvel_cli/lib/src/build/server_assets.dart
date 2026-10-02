/// The pack a web-server binary carries its site in.
///
/// Every web file goes in under `web/`, and the admin dashboard, when the
/// build has one, under `admin/` with each file marked protected: the binary
/// serves the dashboard only through its grant check and never keeps it in
/// a cache shared between callers. Each file is kept the smallest way the
/// build can find, which is brotli at its highest level from the native
/// library the binary is about to embed (`dartvel.web.server.compression`
/// picks zstd, gzip or none instead). A format compressed already is kept as
/// it is.
///
/// Brotli at level 11 is slow -- the dartvel.dev site's 43 MB take about two
/// minutes on one core -- so files are encoded on several isolates at once,
/// and each encoding is kept under `.dart_tool/dartvel/asset_encodings`
/// by the hash of what it encodes: a rebuild that changed one file encodes
/// one file.
library;

import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_shelf/native_codec.dart';
import 'package:path/path.dart' as p;

import 'admin_mount.dart';
import 'server_binary.dart' show dvServerWebFiles;
import 'docs_mount.dart';

/// How the build encodes a binary's files.
enum DVAssetCompression { brotli, zstd, gzip, none }

/// `dartvel.web.server.compression`: `brotli` (the default), `zstd`, `gzip`,
/// or `none` / `false`. Anything else is the default.
DVAssetCompression dvAssetCompression(Object? declared) => switch (declared) {
      'zstd' => DVAssetCompression.zstd,
      'gzip' => DVAssetCompression.gzip,
      'none' || false => DVAssetCompression.none,
      _ => DVAssetCompression.brotli,
    };

/// What [dvServerAssetPack] made.
final class DVServerAssetsResult {
  const DVServerAssetsResult({
    required this.pack,
    required this.encoded,
    required this.reused,
    required this.storedBytes,
    required this.distinctBytes,
    required this.rawBytes,
    required this.lines,
  });

  /// The pack's bytes.
  final Uint8List pack;

  /// How many files were encoded by this build.
  final int encoded;

  /// How many encodings were an earlier build's.
  final int reused;

  /// Every file as kept, counting a file carried twice twice.
  final int storedBytes;

  /// What the pack holds: a file carried twice counted once.
  final int distinctBytes;

  /// Every file as it is.
  final int rawBytes;

  /// What to tell the person building.
  final List<String> lines;
}

/// The pack for the files of [webRoot] and, when [admin] is enabled, the
/// dashboard in [adminRoot].
Future<DVServerAssetsResult> dvServerAssetPack({
  required String projectRoot,
  required String? webRoot,
  DVAdminMount? admin,
  String? adminRoot,
  DVDocsMount? docs,
  String? docsRoot,
  DVAssetCompression compression = DVAssetCompression.brotli,
  String? codecLibrary,
}) async {
  final List<(String, Uint8List, bool)> files = <(String, Uint8List, bool)>[
    if (webRoot != null && Directory(webRoot).existsSync())
      for (final MapEntry<String, List<int>> f in dvServerWebFiles(webRoot).entries)
        ('web/${f.key}', _bytes(f.value), false),
    if (admin != null && admin.enabled && adminRoot != null && Directory(adminRoot).existsSync())
      for (final FileSystemEntity f in Directory(adminRoot).listSync(recursive: true))
        if (f is File)
          ('admin/${p.relative(f.path, from: adminRoot).replaceAll(r'\', '/')}',
              f.readAsBytesSync(), true),
    if (docs != null && docs.enabled && docsRoot != null && Directory(docsRoot).existsSync())
      for (final FileSystemEntity f in Directory(docsRoot).listSync(recursive: true))
        if (f is File)
          ('docs/${p.relative(f.path, from: docsRoot).replaceAll(r'\', '/')}',
              f.readAsBytesSync(), true),
  ];

  final List<String> lines = <String>[];
  DVAssetEncoding? encoding = switch (compression) {
    DVAssetCompression.brotli => DVAssetEncoding.br,
    DVAssetCompression.zstd => DVAssetEncoding.zstd,
    DVAssetCompression.gzip => DVAssetEncoding.gzip,
    DVAssetCompression.none => null,
  };
  if (encoding == DVAssetEncoding.br || encoding == DVAssetEncoding.zstd) {
    if (!_hasCodec(codecLibrary)) {
      lines.add('The native server library has no ${encoding!.token} encoder; '
          'the web files are kept in gzip. Rebuild it from dartvel_shelf/rust.');
      encoding = DVAssetEncoding.gzip;
    }
  }

  // What each distinct file encodes to, by its hash: the same file carried
  // twice is encoded once.
  final Map<String, Uint8List> byHash = <String, Uint8List>{};
  final Map<String, String> hashes = <String, String>{};
  for (final (String path, Uint8List bytes, bool _) in files) {
    final String hash = sha256.convert(bytes).toString();
    hashes[path] = hash;
    if (encoding != null && dvAssetWorthEncoding(path) && bytes.length >= 64) {
      byHash[hash] = bytes;
    }
  }

  final Map<String, Uint8List?> encoded = <String, Uint8List?>{};
  int reused = 0;
  final Directory cache = Directory(
      p.join(projectRoot, '.dart_tool', 'dartvel', 'asset_encodings'));
  final List<String> missing = <String>[];
  if (encoding != null) {
    for (final String hash in byHash.keys) {
      final File kept = File(p.join(cache.path, '$hash.${encoding.token}'));
      final File none = File('${kept.path}.none');
      if (kept.existsSync()) {
        encoded[hash] = kept.readAsBytesSync();
        reused++;
      } else if (none.existsSync()) {
        encoded[hash] = null;
        reused++;
      } else {
        missing.add(hash);
      }
    }
  }

  if (missing.isNotEmpty && encoding != null) {
    // Largest first, so one big file does not end up alone on the last
    // isolate after the others have finished.
    missing.sort((String a, String b) => byHash[b]!.length - byHash[a]!.length);
    final int workers = max(1, min(missing.length, min(4, Platform.numberOfProcessors)));
    final List<List<String>> shares = <List<String>>[for (int i = 0; i < workers; i++) <String>[]];
    final List<int> load = List<int>.filled(workers, 0);
    for (final String hash in missing) {
      int least = 0;
      for (int i = 1; i < workers; i++) {
        if (load[i] < load[least]) least = i;
      }
      shares[least].add(hash);
      load[least] += byHash[hash]!.length;
    }
    final DVAssetEncoding chosen = encoding;
    final String? library = codecLibrary;
    final List<Map<String, Uint8List?>> results = await Future.wait(<Future<Map<String, Uint8List?>>>[
      for (final List<String> share in shares)
        Isolate.run(() => _encodeAll(<String, Uint8List>{for (final String h in share) h: byHash[h]!},
            chosen, library)),
    ]);
    cache.createSync(recursive: true);
    for (final Map<String, Uint8List?> result in results) {
      for (final MapEntry<String, Uint8List?> e in result.entries) {
        encoded[e.key] = e.value;
        final File kept = File(p.join(cache.path, '${e.key}.${chosen.token}'));
        if (e.value == null) {
          File('${kept.path}.none').writeAsBytesSync(const <int>[]);
        } else {
          kept.writeAsBytesSync(e.value!);
        }
      }
    }
  }

  final List<DVAssetPackEntry> entries = <DVAssetPackEntry>[
    for (final (String path, Uint8List bytes, bool protected) in files)
      DVAssetPackEntry(
        path,
        bytes,
        stored: encoded[hashes[path]],
        encoding: encoded[hashes[path]] == null ? DVAssetEncoding.identity : encoding!,
        protected: protected,
      ),
  ];
  final Uint8List pack = dvWriteAssetPack(entries);

  int raw = 0;
  int stored = 0;
  final Map<String, int> distinct = <String, int>{};
  for (final DVAssetPackEntry entry in entries) {
    final Uint8List? kept = entry.stored;
    final int size = kept != null && kept.length < entry.bytes.length ? kept.length : entry.bytes.length;
    raw += entry.bytes.length;
    stored += size;
    distinct[hashes[entry.path]!] = size;
  }
  final int distinctBytes = distinct.values.fold(0, (int a, int b) => a + b);
  String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
  lines.add('${entries.length} web files, ${mb(raw)} MB, kept in '
      '${mb(distinctBytes)} MB (${encoding?.token ?? 'uncompressed'}; '
      '${missing.length} encoded now, $reused from an earlier build).');
  return DVServerAssetsResult(
    pack: pack,
    encoded: missing.length,
    reused: reused,
    storedBytes: stored,
    distinctBytes: distinctBytes,
    rawBytes: raw,
    lines: lines,
  );
}

Uint8List _bytes(List<int> bytes) => bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

bool _hasCodec(String? library) {
  if (library == null || !File(library).existsSync()) return false;
  try {
    return DVNativeCodec.of(DynamicLibrary.open(library)) != null;
  } on Object {
    return false;
  }
}

/// Each of [files], by hash, encoded with [encoding]; null for one that did
/// not come out smaller. Runs on an isolate of its own.
Map<String, Uint8List?> _encodeAll(
    Map<String, Uint8List> files, DVAssetEncoding encoding, String? library) {
  final DVNativeCodec? codec = encoding == DVAssetEncoding.gzip || library == null
      ? null
      : DVNativeCodec.of(DynamicLibrary.open(library));
  return <String, Uint8List?>{
    for (final MapEntry<String, Uint8List> f in files.entries)
      f.key: switch (encoding) {
        DVAssetEncoding.gzip => (() {
            final Uint8List out = Uint8List.fromList(GZipCodec(level: 9).encode(f.value));
            return out.length < f.value.length ? out : null;
          })(),
        _ => codec!.encode(encoding, f.value),
      },
  };
}
