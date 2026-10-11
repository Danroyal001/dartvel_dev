/// Collecting a release build's symbols into a versioned bundle.
///
/// `dartvel build android --release` leaves three things a crash from it can
/// be read with, each in a place its own tool chose:
///
///  * R8's `mapping.txt`, under `build/app/outputs/mapping/<variant>/`;
///  * Flutter's `--split-debug-info` files, `build/debug-info/app.<abi>.symbols`;
///  * Gradle's `native-debug-symbols.zip`, for native frames.
///
/// None of them is kept anywhere that survives the next build, and each is
/// specific to the build that wrote it. This gathers the current build's into
/// `build/symbols/<release>/` with a manifest, which is what
/// `dartvel symbols upload` sends.
library dartvel_cli.build.symbols_bundle;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show
        DVSymbolFile,
        DVSymbolKind,
        DVSymbolsManifest,
        dvSymbolReleaseOk,
        dvSymbolSha256;
import 'package:path/path.dart' as p;

/// The release string crash reports carry: the pubspec `version` as written,
/// or `unversioned`. One definition for the runtime the client generator
/// writes and the bundle this collects, because a bundle filed under a
/// different string finds none of its symbols when a crash arrives.
String dvCrashReleaseFrom(Object? pubspecVersion) =>
    pubspecVersion == null ? 'unversioned' : '$pubspecVersion';

/// What was collected.
final class DVSymbolsCollection {
  const DVSymbolsCollection({
    required this.directory,
    required this.manifest,
    required this.warnings,
  });

  /// `build/symbols/<release>`; it does not exist when [isEmpty].
  final String directory;
  final DVSymbolsManifest manifest;

  /// Things the person should know: a missing mapping, a stale file left out.
  final List<String> warnings;

  bool get isEmpty => manifest.files.isEmpty;
}

/// Gathers the symbols the build that began at [builtSince] wrote.
///
/// Files older than [builtSince] are left out and said so: Flutter's
/// debug-info directory is not emptied between builds, so last week's `.symbols`
/// sit beside this week's, and a bundle that took them all would hold a file
/// for a different build under this release's name.
///
/// [buildIdOf] reads the ELF build id of a Dart symbols file -- what a stack
/// trace's header names, so the right file is chosen among several
/// architectures. The caller supplies it (the server half has the decoder).
DVSymbolsCollection dvCollectAndroidSymbols({
  required String root,
  required String release,
  required DateTime builtSince,
  required String? Function(List<int> bytes) buildIdOf,
  DateTime? now,
}) {
  if (!dvSymbolReleaseOk(release)) {
    throw ArgumentError.value(release, 'release',
        'is not usable as a directory name for a symbols bundle');
  }
  final String bundle = p.join(root, 'build', 'symbols', release);
  final List<String> warnings = <String>[];
  final List<DVSymbolFile> files = <DVSymbolFile>[];
  final List<(File, String)> toCopy = <(File, String)>[];

  bool current(File file, String label) {
    if (file.lastModifiedSync().toUtc().isBefore(builtSince.toUtc())) {
      warnings.add('Left out $label (${p.relative(file.path, from: root)}): it '
          'is older than this build, so it belongs to a different one.');
      return false;
    }
    return true;
  }

  // R8 mapping: a release variant, and the newest if there are several.
  final Directory mappings =
      Directory(p.join(root, 'build', 'app', 'outputs', 'mapping'));
  File? mapping;
  if (mappings.existsSync()) {
    final List<File> candidates = <File>[
      for (final FileSystemEntity variant in mappings.listSync())
        if (variant is Directory &&
            p.basename(variant.path).toLowerCase().endsWith('release') &&
            File(p.join(variant.path, 'mapping.txt')).existsSync())
          File(p.join(variant.path, 'mapping.txt')),
    ]..sort((File a, File b) =>
        b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (candidates.isNotEmpty && current(candidates.first, 'the R8 mapping')) {
      mapping = candidates.first;
    }
  }
  if (mapping != null) {
    toCopy.add((mapping, 'mapping.txt'));
    files.add(_describe(mapping, 'mapping.txt', DVSymbolKind.r8Mapping));
  }

  // Dart: Flutter's --split-debug-info output.
  final Directory debugInfo = Directory(p.join(root, 'build', 'debug-info'));
  final RegExp symbolsName = RegExp(r'^app\.([A-Za-z0-9_-]+)\.symbols$');
  if (debugInfo.existsSync()) {
    final List<File> symbols = <File>[
      for (final FileSystemEntity entity in debugInfo.listSync())
        if (entity is File && symbolsName.hasMatch(p.basename(entity.path)))
          entity,
    ]..sort((File a, File b) => a.path.compareTo(b.path));
    for (final File file in symbols) {
      if (!current(file, 'a Dart symbols file')) continue;
      final String name = p.basename(file.path);
      final String platformAndAbi = symbolsName.firstMatch(name)!.group(1)!;
      final List<int> bytes = file.readAsBytesSync();
      toCopy.add((file, name));
      files.add(DVSymbolFile(
        name: name,
        kind: DVSymbolKind.dartSymbols,
        sha256: dvSymbolSha256(bytes),
        bytes: bytes.length,
        // `android-arm64` -> `arm64`.
        arch: platformAndAbi.contains('-')
            ? platformAndAbi.substring(platformAndAbi.indexOf('-') + 1)
            : platformAndAbi,
        buildId: buildIdOf(bytes),
      ));
    }
  }

  // Native: Gradle's unstripped .so files.
  final Directory natives = Directory(
      p.join(root, 'build', 'app', 'outputs', 'native-debug-symbols'));
  if (natives.existsSync()) {
    for (final FileSystemEntity variant in natives.listSync()) {
      if (variant is! Directory ||
          !p.basename(variant.path).toLowerCase().endsWith('release')) {
        continue;
      }
      final File zip = File(p.join(variant.path, 'native-debug-symbols.zip'));
      if (zip.existsSync() && current(zip, 'the native debug symbols')) {
        toCopy.add((zip, 'native-debug-symbols.zip'));
        files.add(_describe(
            zip, 'native-debug-symbols.zip', DVSymbolKind.nativeDebug));
        break;
      }
    }
  }

  if (mapping == null) {
    warnings.add('No R8 mapping.txt from this build: Java and Kotlin frames '
        'from this release will be unreadable. R8 writes it when minification '
        'is on, which Flutter\'s release build does unless --no-shrink was '
        'passed.');
  }

  final DVSymbolsManifest manifest = DVSymbolsManifest(
    release: release,
    createdAt: (now ?? DateTime.now()).toUtc(),
    files: files,
  );
  if (files.isEmpty) {
    warnings.add('Nothing to bundle: this build left no mapping, no Dart '
        'symbols (is --obfuscate on?) and no native symbols.');
    return DVSymbolsCollection(
        directory: bundle, manifest: manifest, warnings: warnings);
  }

  // One bundle per release: a rebuild replaces it, so the manifest never
  // lists a file the directory no longer has.
  final Directory target = Directory(bundle);
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  for (final (File source, String name) in toCopy) {
    source.copySync(p.join(bundle, name));
  }
  File(p.join(bundle, DVSymbolsManifest.fileName))
      .writeAsStringSync(const JsonEncoder.withIndent('  ')
          .convert(manifest.toJson()));
  return DVSymbolsCollection(
      directory: bundle, manifest: manifest, warnings: warnings);
}

DVSymbolFile _describe(File file, String name, DVSymbolKind kind) {
  final List<int> bytes = file.readAsBytesSync();
  return DVSymbolFile(
    name: name,
    kind: kind,
    sha256: dvSymbolSha256(bytes),
    bytes: bytes.length,
  );
}

const String _gradleStart = '// dartvel.symbols: start';
const String _gradleEnd = '// dartvel.symbols: end';

/// [gradle] (the app module's build script) asking the release build for the
/// native debug symbols zip when [include], and without it otherwise.
///
/// Gradle writes `native-debug-symbols.zip` only on request. SYMBOL_TABLE is
/// the smaller of the two levels that make it (FULL carries DWARF) and is
/// what turns a native frame from an address into a function name.
String dvAndroidGradleWithNativeSymbols(
  String gradle, {
  required bool include,
  required bool kotlinScript,
}) {
  final String stripped = _stripGradle(gradle);
  if (!include) return stripped;
  final String separator = stripped.endsWith('\n') ? '' : '\n';
  final String body = kotlinScript
      ? 'android {\n'
          '    buildTypes {\n'
          '        getByName("release") {\n'
          '            ndk {\n'
          '                debugSymbolLevel = "SYMBOL_TABLE"\n'
          '            }\n'
          '        }\n'
          '    }\n'
          '}\n'
      : "android {\n"
          "    buildTypes {\n"
          "        release {\n"
          "            ndk {\n"
          "                debugSymbolLevel = 'SYMBOL_TABLE'\n"
          "            }\n"
          "        }\n"
          "    }\n"
          "}\n";
  return '$stripped$separator\n$_gradleStart\n'
      '// Native debug symbols for crash reports. Written by dartvel build from\n'
      '// dartvel.crashes.symbols in pubspec.yaml; removed when that is.\n'
      '$body$_gradleEnd\n';
}

String _stripGradle(String gradle) {
  final int start = gradle.indexOf(_gradleStart);
  if (start < 0) return gradle;
  final int end = gradle.indexOf(_gradleEnd, start);
  if (end < 0) return gradle;
  int cut = start;
  if (cut >= 2 && gradle.substring(cut - 2, cut) == '\n\n') cut -= 1;
  int after = end + _gradleEnd.length;
  if (after < gradle.length && gradle[after] == '\n') after += 1;
  return gradle.substring(0, cut) + gradle.substring(after);
}
