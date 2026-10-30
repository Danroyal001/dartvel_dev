// Shared support for the differential tools in tools/: the repository root,
// the Dart executable, processes with timeouts, JSON written the way the
// original Python tools wrote it, SHA-256, and the pub package of the Dart
// oracle. Imports only dart: libraries, so every tool runs with
// `dart tools/<name>.dart` and no `pub get`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The dartr checkout: the parent of `tools/`.
String get root {
  final script = File.fromUri(Platform.script).absolute.path;
  var tools = File(script).parent;
  if (_basename(tools.path) == 'common') tools = tools.parent;
  return tools.parent.path;
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

/// The `dart` to compare with: `DARTR_DART`, then fvm's default SDK, then
/// `dart` on PATH.
String dartBinary() {
  final configured = Platform.environment['DARTR_DART'];
  if (configured != null && configured.isNotEmpty) return configured;
  final home = Platform.environment['HOME'] ?? '';
  final direct = '$home/fvm/default/bin/cache/dart-sdk/bin/dart';
  if (File(direct).existsSync()) return direct;
  return 'dart';
}

/// The Dart SDK source checkout (`dart-lang/sdk` at the tag dartr ports):
/// `DARTR_DART_SDK_SOURCE`, else `third_party/dart-sdk`.
String sdkSource() {
  final configured = Platform.environment['DARTR_DART_SDK_SOURCE'];
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute.path;
  }
  return '$root/third_party/dart-sdk';
}

class ToolError implements Exception {
  final String message;
  ToolError(this.message);
  @override
  String toString() => message;
}

class RunResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  RunResult(this.exitCode, this.stdout, this.stderr);
}

/// Runs [executable] with [arguments], writes [input] to its stdin, and
/// kills it after [timeout] seconds (Python's `subprocess.run(timeout=)`).
Future<RunResult> runProcess(
  String executable,
  List<String> arguments, {
  String? input,
  int? timeout,
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final stdout = process.stdout.transform(utf8.decoder).join();
  final stderr = process.stderr.transform(utf8.decoder).join();
  if (input != null) process.stdin.add(utf8.encode(input));
  // A process that exits without reading its stdin closes the pipe.
  unawaited(process.stdin.close().catchError((_) {}));
  var exit = process.exitCode;
  if (timeout != null) {
    exit = exit.timeout(
      Duration(seconds: timeout),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw ToolError(
          'Timed out after $timeout seconds: $executable ${arguments.join(' ')}',
        );
      },
    );
  }
  final code = await exit;
  return RunResult(code, await stdout, await stderr);
}

/// Python's `subprocess.check_output`: stdout, or an error on a non-zero
/// exit. [mergeStderr] is `stderr=subprocess.STDOUT`.
Future<String> checkOutput(
  String executable,
  List<String> arguments, {
  int? timeout,
  bool mergeStderr = false,
}) async {
  final result = await runProcess(executable, arguments, timeout: timeout);
  if (result.exitCode != 0) {
    throw ToolError(
      "Command '$executable ${arguments.join(' ')}' returned non-zero exit "
      'status ${result.exitCode}.\n${result.stderr}',
    );
  }
  return mergeStderr ? result.stdout + result.stderr : result.stdout;
}

/// `dart --version`, checked to be 3.13.3, the SDK dartr ports.
Future<String> pinnedDartVersion() async {
  final version = (await checkOutput(
    dartBinary(),
    ['--version'],
    timeout: 30,
    mergeStderr: true,
  )).trim();
  if (!version.contains('3.13.3 ')) {
    throw ToolError('Expected Dart 3.13.3: $version');
  }
  return version;
}

/// `json.dumps(value, indent=indent)` of Python: `ensure_ascii`, `", "`
/// and `": "` separators, and floats as Python prints them. The tools'
/// evidence files keep the bytes the Python tools wrote.
String pyJson(Object? value, {int? indent}) {
  final out = StringBuffer();
  void write(Object? value, int level) {
    if (value == null) {
      out.write('null');
    } else if (value is bool) {
      out.write(value ? 'true' : 'false');
    } else if (value is int) {
      out.write(value);
    } else if (value is double) {
      out.write(_pyFloat(value));
    } else if (value is String) {
      _pyString(out, value);
    } else if (value is List) {
      if (value.isEmpty) {
        out.write('[]');
        return;
      }
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (indent != null) {
          out.write(i == 0 ? '\n' : ',\n');
          out.write(' ' * (indent * (level + 1)));
        } else if (i > 0) {
          out.write(', ');
        }
        write(value[i], level + 1);
      }
      if (indent != null) out.write('\n${' ' * (indent * level)}');
      out.write(']');
    } else if (value is Map) {
      if (value.isEmpty) {
        out.write('{}');
        return;
      }
      out.write('{');
      var first = true;
      for (var entry in value.entries) {
        if (indent != null) {
          out.write(first ? '\n' : ',\n');
          out.write(' ' * (indent * (level + 1)));
        } else if (!first) {
          out.write(', ');
        }
        first = false;
        _pyString(out, entry.key.toString());
        out.write(': ');
        write(entry.value, level + 1);
      }
      if (indent != null) out.write('\n${' ' * (indent * level)}');
      out.write('}');
    } else {
      throw ArgumentError('Not JSON: $value');
    }
  }

  write(value, 0);
  return out.toString();
}

String _pyFloat(double value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
  if (value == value.truncateToDouble() && value.abs() < 1e16) {
    return '${value.toInt()}.0';
  }
  return value.toString();
}

void _pyString(StringBuffer out, String value) {
  out.write('"');
  for (var unit in value.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      default:
        if (unit < 0x20 || unit > 0x7e) {
          // Python escapes every non-ASCII UTF-16 code unit (a surrogate
          // pair stays a pair).
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
}

/// Python's `Path` ordering: by path segments, then by length.
int comparePaths(String a, String b) {
  final x = a.split('/');
  final y = b.split('/');
  for (var i = 0; i < x.length && i < y.length; i++) {
    final c = x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

/// The files under [dir] whose name ends with [suffix], recursively,
/// following links (Python's `Path.rglob`), sorted like Python sorts paths.
List<String> filesUnder(String dir, String suffix) {
  final files = Directory(dir)
      .listSync(recursive: true, followLinks: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith(suffix))
      .toList();
  files.sort(comparePaths);
  return files;
}

/// Python's `shutil.copytree`, following links.
void copyTree(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (var entity in Directory(from).listSync(followLinks: true)) {
    final target = '$to/${_basename(entity.path)}';
    if (entity is Directory) {
      copyTree(entity.path, target);
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

/// Python's `Path.resolve()` (not strict): the symbolic links of the longest
/// existing prefix are resolved, the rest is kept.
String resolvePath(String path) {
  final absolute = File(path).absolute.path;
  final segments = absolute.split('/');
  final rest = <String>[];
  while (segments.length > 1) {
    final prefix = segments.join('/');
    if (FileSystemEntity.typeSync(prefix) != FileSystemEntityType.notFound) {
      final resolved = Directory(prefix).resolveSymbolicLinksSync();
      return _normalize([resolved, ...rest].join('/'));
    }
    rest.insert(0, segments.removeLast());
  }
  return _normalize('/${rest.join('/')}');
}

String _normalize(String path) {
  final out = <String>[];
  for (var segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(segment);
    }
  }
  return '/${out.join('/')}';
}

/// SHA-256 of [bytes] as lowercase hex (FIPS 180-4).
String sha256Hex(Uint8List bytes) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  final h = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  final length = bytes.length;
  final padded = Uint8List(((length + 9 + 63) ~/ 64) * 64);
  padded.setRange(0, length, bytes);
  padded[length] = 0x80;
  final bits = length * 8;
  for (var i = 0; i < 8; i++) {
    padded[padded.length - 1 - i] = (bits >> (8 * i)) & 0xff;
  }
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
  final w = List<int>.filled(64, 0);
  final data = ByteData.sublistView(padded);
  for (var chunk = 0; chunk < padded.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = data.getUint32(chunk + 4 * i);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ ((~e & 0xffffffff) & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff;
    h[1] = (h[1] + b) & 0xffffffff;
    h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff;
    h[4] = (h[4] + e) & 0xffffffff;
    h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff;
    h[7] = (h[7] + hh) & 0xffffffff;
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}

/// Prepares the pub package of the Dart oracle `tools/<name>` (`oracle` or
/// `diagnostics_oracle`) under `target/oracle/<name>-package`: its
/// pubspec, with the `analyzer`, `_fe_analyzer_shared` and `linter`
/// overrides pointing into [sdkSource], and its lock file; `dart pub get`
/// runs there when the pubspec changed. Returns the package config; run
/// the oracle's `bin/` sources with `--packages=<it>`.
///
/// The package lives under `target/` so that neither `tools/<name>` nor its
/// committed `pubspec.lock` changes when the SDK checkout is elsewhere.
Future<String> oraclePackageConfig({String name = 'oracle'}) async {
  final configured = Platform.environment['DARTR_ORACLE_PACKAGE_CONFIG'];
  if (name == 'oracle' && configured != null && configured.isNotEmpty) {
    return File(configured).absolute.path;
  }
  final sdk = sdkSource();
  for (var package in ['analyzer', '_fe_analyzer_shared', 'linter']) {
    if (!File('$sdk/pkg/$package/pubspec.yaml').existsSync()) {
      throw ToolError(
        'No Dart SDK source checkout at $sdk (pkg/$package is missing). '
        'Set DARTR_DART_SDK_SOURCE to a checkout of dart-lang/sdk at tag '
        '3.13.3 with pkg/analyzer, pkg/_fe_analyzer_shared and pkg/linter, '
        'or run tools/fetch_sdk.sh.',
      );
    }
  }
  final source = '$root/tools/$name';
  final package = '$root/target/oracle/$name-package';
  Directory(package).createSync(recursive: true);
  final pubspec = File('$source/pubspec.yaml')
      .readAsStringSync()
      .replaceAll('../../third_party/dart-sdk/', '$sdk/');
  final pubspecFile = File('$package/pubspec.yaml');
  final config = File('$package/.dart_tool/package_config.json');
  final changed =
      !pubspecFile.existsSync() || pubspecFile.readAsStringSync() != pubspec;
  if (changed) pubspecFile.writeAsStringSync(pubspec);
  final lock = File('$package/pubspec.lock');
  if (!lock.existsSync()) {
    File('$source/pubspec.lock').copySync(lock.path);
  }
  if (changed || !config.existsSync()) {
    final result = await runProcess(dartBinary(), [
      'pub',
      'get',
    ], workingDirectory: package);
    if (result.exitCode != 0) {
      throw ToolError(
        '`dart pub get` failed in $package:\n${result.stdout}${result.stderr}',
      );
    }
  }
  return config.path;
}

/// Python's `==` on decoded JSON values: lists in order, maps by keys.
bool jsonEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}
