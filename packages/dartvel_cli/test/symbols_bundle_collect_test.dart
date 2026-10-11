// Collecting a release build's symbols into a versioned bundle.
//
// The layout is Gradle's and Flutter's: R8 writes
// build/app/outputs/mapping/<variant>/mapping.txt, Flutter's
// --split-debug-info writes build/debug-info/app.<abi>.symbols, and Gradle
// writes build/app/outputs/native-debug-symbols/<variant>/*.zip. The ways
// this goes wrong are silent: a debug-info directory is not emptied between
// builds, so last week's symbols sit beside this week's and a bundle that
// takes everything in it holds a file for a different build; and a bundle
// filed under a release string that differs from the one the app reports
// finds none of its symbols when a crash arrives.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/symbols_bundle.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVSymbolKind, DVSymbolsManifest, dvSymbolSha256;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  nativeSymbolsGradleTests();
  late Directory root;
  final DateTime buildStarted = DateTime.utc(2026, 10, 11, 12);

  setUp(() => root = Directory.systemTemp.createTempSync('dv_symbols_collect_'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String relative, List<int> bytes, {DateTime? modified}) {
    final File file = File(p.join(root.path, relative))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    file.setLastModifiedSync(modified ?? buildStarted.add(const Duration(minutes: 3)));
    return file;
  }

  DVSymbolsCollection collect({String release = '1.4.0+12'}) =>
      dvCollectAndroidSymbols(
        root: root.path,
        release: release,
        builtSince: buildStarted,
        buildIdOf: (List<int> bytes) => 'id-${bytes.length}',
        now: DateTime.utc(2026, 10, 11, 13),
      );

  test('the release is the pubspec version, as the app reports it', () {
    expect(dvCrashReleaseFrom('1.4.0+12'), '1.4.0+12');
    expect(dvCrashReleaseFrom(null), 'unversioned');
  });

  test('gathers the mapping, the Dart symbols and the native symbols', () {
    write('build/app/outputs/mapping/release/mapping.txt', utf8.encode('map'));
    write('build/debug-info/app.android-arm64.symbols', <int>[1, 2, 3]);
    write('build/debug-info/app.android-arm.symbols', <int>[4, 5]);
    write('build/app/outputs/native-debug-symbols/release/native-debug-symbols.zip',
        <int>[9, 9, 9, 9]);

    final DVSymbolsCollection result = collect();
    expect(result.warnings, isEmpty);
    expect(result.directory, p.join(root.path, 'build', 'symbols', '1.4.0+12'));

    final DVSymbolsManifest manifest = DVSymbolsManifest.fromJson(
        jsonDecode(File(p.join(result.directory, 'manifest.json')).readAsStringSync())
            as Map<String, Object?>);
    expect(manifest.release, '1.4.0+12');
    expect(manifest.firstOfKind(DVSymbolKind.r8Mapping)!.name, 'mapping.txt');
    expect(manifest.ofKind(DVSymbolKind.dartSymbols).map((f) => f.name).toSet(),
        <String>{'app.android-arm64.symbols', 'app.android-arm.symbols'});
    expect(manifest.firstOfKind(DVSymbolKind.nativeDebug)!.name,
        'native-debug-symbols.zip');
  });

  test('records the architecture, build id, size and hash of each file', () {
    write('build/debug-info/app.android-arm64.symbols', <int>[1, 2, 3]);
    final DVSymbolsManifest manifest = collect().manifest;
    final file = manifest.firstOfKind(DVSymbolKind.dartSymbols)!;
    expect(file.arch, 'arm64');
    expect(file.buildId, 'id-3');
    expect(file.bytes, 3);
    expect(file.sha256, dvSymbolSha256(<int>[1, 2, 3]));
    // And the copy in the bundle is the file, not a stub.
    expect(File(p.join(root.path, 'build', 'symbols', '1.4.0+12',
            'app.android-arm64.symbols')).readAsBytesSync(),
        <int>[1, 2, 3]);
  });

  test('leaves out symbols from an earlier build', () {
    write('build/debug-info/app.android-arm64.symbols', <int>[1, 2, 3]);
    write('build/debug-info/app.android-x64.symbols', <int>[7, 7],
        modified: buildStarted.subtract(const Duration(days: 7)));
    write('build/app/outputs/mapping/release/mapping.txt', utf8.encode('stale'),
        modified: buildStarted.subtract(const Duration(days: 7)));

    final DVSymbolsCollection result = collect();
    expect(result.manifest.ofKind(DVSymbolKind.dartSymbols).map((f) => f.name),
        <String>['app.android-arm64.symbols']);
    expect(result.manifest.firstOfKind(DVSymbolKind.r8Mapping), isNull);
    expect(result.warnings.join('\n'), contains('older than this build'));
  });

  test('says what is missing rather than writing a bundle that looks whole', () {
    write('build/debug-info/app.android-arm64.symbols', <int>[1]);
    final String warnings = collect().warnings.join('\n');
    expect(warnings, contains('mapping.txt'));
    expect(warnings, contains('Java and Kotlin'));
  });

  test('no symbols at all is an empty collection with a reason, not a bundle',
      () {
    final DVSymbolsCollection result = collect();
    expect(result.isEmpty, isTrue);
    expect(result.warnings, isNotEmpty);
    expect(Directory(p.join(root.path, 'build', 'symbols')).existsSync(), isFalse);
  });

  test('building the same release again replaces the bundle, not adds to it',
      () {
    write('build/debug-info/app.android-arm64.symbols', <int>[1, 2, 3]);
    collect();
    File(p.join(root.path, 'build', 'debug-info', 'app.android-arm64.symbols'))
        .deleteSync();
    write('build/debug-info/app.android-arm.symbols', <int>[4]);
    final DVSymbolsCollection second = collect();
    expect(second.manifest.files.map((f) => f.name), <String>['app.android-arm.symbols']);
    expect(File(p.join(second.directory, 'app.android-arm64.symbols')).existsSync(),
        isFalse);
  });

  test('a release that is not a safe directory name is refused', () {
    write('build/debug-info/app.android-arm64.symbols', <int>[1]);
    expect(() => collect(release: '../../etc'), throwsArgumentError);
  });

  test('a flavoured variant\'s mapping is found', () {
    write('build/app/outputs/mapping/prodRelease/mapping.txt', utf8.encode('m'));
    expect(collect().manifest.firstOfKind(DVSymbolKind.r8Mapping), isNotNull);
  });

  test('a debug variant\'s mapping is never taken for a release', () {
    write('build/app/outputs/mapping/debug/mapping.txt', utf8.encode('m'));
    expect(collect().manifest.firstOfKind(DVSymbolKind.r8Mapping), isNull);
  });
}

// Gradle writes native-debug-symbols.zip only when the build asks for it.
void nativeSymbolsGradleTests() {
  group('the native debug symbols Gradle setting', () {
    const String groovy = 'android {\n    namespace "com.example.app"\n}\n';
    const String kotlin = 'android {\n    namespace = "com.example.app"\n}\n';

    test('asks the release build for symbol tables, once', () {
      final String once = dvAndroidGradleWithNativeSymbols(groovy,
          include: true, kotlinScript: false);
      expect(once, contains("debugSymbolLevel = 'SYMBOL_TABLE'"));
      expect(dvAndroidGradleWithNativeSymbols(once, include: true, kotlinScript: false),
          once);
    });

    test('uses Kotlin syntax in a .kts script', () {
      final String out = dvAndroidGradleWithNativeSymbols(kotlin,
          include: true, kotlinScript: true);
      expect(out, contains('debugSymbolLevel = "SYMBOL_TABLE"'));
      expect(out, contains('getByName("release")'));
    });

    test('comes back out exactly', () {
      final String with_ = dvAndroidGradleWithNativeSymbols(groovy,
          include: true, kotlinScript: false);
      expect(
          dvAndroidGradleWithNativeSymbols(with_, include: false, kotlinScript: false),
          groovy);
    });
  });
}
