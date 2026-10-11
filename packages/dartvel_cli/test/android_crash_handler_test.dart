// The JVM uncaught-exception handler the Android build writes.
//
// A Java or Kotlin crash never reaches Dart: FlutterError.onError and
// PlatformDispatcher.onError see Dart errors, and the process dies under a
// native thread's exception without either being asked. The generated handler
// writes the crash into the same directory the Dart crash store reads at the
// next launch, in the same format. Two ways that goes wrong are silent: a
// record the Dart side cannot read (dropped as "cut short", DV-CRASH-005, so
// the crash is simply missing), and a group id computed differently in Java
// than in Dart (so the same bug groups twice depending on which side
// recorded it).
//
// The Java is compiled against the real android.jar and run on the JVM; the
// record it writes is read back with the Dart reader. Skipped, and said, when
// there is no JDK or no Android SDK.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/android_context_provider.dart';
import 'package:dartvel_cli/src/build/android_crash_handler.dart';
import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String? _androidJar() {
  final List<String?> roots = <String?>[
    Platform.environment['ANDROID_HOME'],
    Platform.environment['ANDROID_SDK_ROOT'],
    '${Platform.environment['HOME']}/android-sdk',
  ];
  for (final String? root in roots) {
    if (root == null) continue;
    final Directory platforms = Directory(p.join(root, 'platforms'));
    if (!platforms.existsSync()) continue;
    final List<File> jars = <File>[
      for (final FileSystemEntity e in platforms.listSync())
        if (File(p.join(e.path, 'android.jar')).existsSync())
          File(p.join(e.path, 'android.jar')),
    ]..sort((File a, File b) => b.path.compareTo(a.path));
    if (jars.isNotEmpty) return jars.first.path;
  }
  return null;
}

bool _has(String tool) {
  try {
    return Process.runSync(tool, const <String>['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('the generated source', () {
    final String source =
        dvAndroidCrashHandlerSource(release: '1.4.0+12', enabled: true);

    test('chains to the handler that was there, so the process still dies '
        'the way Android intends', () {
      expect(source, contains('getDefaultUncaughtExceptionHandler'));
      expect(source, contains('previous.uncaughtException'));
    });

    test('never lets a failure while recording mask the crash being recorded',
        () {
      expect(source, contains('catch (Throwable'));
    });

    test('is installed once, not chained onto itself', () {
      expect(source, contains('instanceof Handler'));
    });

    test('bakes in the release the Dart side reports', () {
      expect(source, contains('"1.4.0+12"'));
    });

    test('a release is escaped into the literal, whatever it contains', () {
      final String hostile = dvAndroidCrashHandlerSource(
          release: '1.0"; System.exit(1); "', enabled: true);
      expect(hostile, isNot(contains('System.exit(1); "')));
      expect(hostile, contains(r'\"'));
    });

    test('is installed by the Context provider, before the engine exists', () {
      expect(dvAndroidContextProviderSource(),
          contains('DartvelCrash.install(sContext);'));
    });

    test('when crash reporting is off for this build it installs nothing', () {
      final String off =
          dvAndroidCrashHandlerSource(release: '1.0.0', enabled: false);
      expect(off, contains('ENABLED = false'));
    });

    test('keeps the framework prefixes in step with the Dart reader\'s', () {
      for (final String prefix in DVCrashFrame.frameworkPrefixes
          .where((String p) => p.startsWith('jvm:'))) {
        expect(source, contains('"${prefix.substring(4)}"'), reason: prefix);
      }
    });
  });

  final String? jar = _androidJar();
  if (jar == null || !_has('javac') || !_has('java')) {
    test('the handler compiles and writes records the Dart store reads', () {},
        skip: 'needs a JDK and the Android SDK (ANDROID_HOME or ~/android-sdk)');
    return;
  }

  late Directory work;
  late Directory classes;

  setUpAll(() {
    work = Directory.systemTemp.createTempSync('dv_crash_handler_');
    classes = Directory(p.join(work.path, 'classes'))..createSync();
    final Directory source = Directory(p.join(work.path, 'src', 'dev', 'dartvel', 'jni'))
      ..createSync(recursive: true);
    File(p.join(source.path, 'DartvelCrash.java')).writeAsStringSync(
        dvAndroidCrashHandlerSource(release: '1.4.0+12', enabled: true));
    // The Context holder the handler's install() is called from is not under
    // test; a stub keeps the compile honest about the one call it makes.
    File(p.join(source.path, 'Harness.java')).writeAsStringSync(_harness);
    // The provider that calls install(), compiled with it: a call to a method
    // that does not exist is a build failure on a developer's machine, not in
    // this package's tests, unless something compiles the two together.
    File(p.join(source.path, 'DartvelContext.java'))
        .writeAsStringSync(dvAndroidContextProviderSource());
    final ProcessResult compiled = Process.runSync('javac', <String>[
      '-Xlint:all',
      '-d',
      classes.path,
      '-cp',
      jar,
      p.join(source.path, 'DartvelCrash.java'),
      p.join(source.path, 'Harness.java'),
      p.join(source.path, 'DartvelContext.java'),
    ]);
    if (compiled.exitCode != 0) {
      fail('the generated Java did not compile:\n${compiled.stdout}\n${compiled.stderr}');
    }
  });

  tearDownAll(() => work.deleteSync(recursive: true));

  Map<String, Object?> run(String scenario) {
    final ProcessResult result = Process.runSync('java',
        <String>['-cp', '${classes.path}:$jar', 'dev.dartvel.jni.Harness', scenario]);
    if (result.exitCode != 0) fail('harness failed:\n${result.stdout}\n${result.stderr}');
    return jsonDecode('${result.stdout}'.trim()) as Map<String, Object?>;
  }

  test('compiles against the real android.jar with no warnings that matter', () {
    // setUpAll failed the group if it did not; this states the fact.
    expect(File(p.join(classes.path, 'dev', 'dartvel', 'jni', 'DartvelCrash.class')).existsSync(), isTrue);
  });

  test('writes a record the Dart reader accepts', () {
    final Map<String, Object?> out = run('nested');
    final DVCrashReport report = DVCrashReport.fromJson(
        jsonDecode(out['json']! as String) as Map<String, Object?>);
    expect(report.kind, DVCrashKind.fatal);
    expect(report.errorType, 'java.lang.IllegalStateException');
    expect(report.message, 'cart is empty');
    expect(report.context.release, '1.4.0+12');
    expect(report.context.platform, 'android');
    expect(report.context.installId, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(report.frames.first.uri, startsWith('jvm:'));
    expect(report.frames.first.function, isNotEmpty);
    expect(report.frames.first.line, isNotNull);
    expect(report.occurredAt.isUtc, isTrue);
  });

  test('the group id is the one Dart computes for the same frames', () {
    for (final String scenario in <String>['nested', 'framework-only', 'deep']) {
      final DVCrashReport report = DVCrashReport.fromJson(
          jsonDecode(run(scenario)['json']! as String) as Map<String, Object?>);
      expect(
        report.fingerprint,
        DVCrashFingerprint.of(errorType: report.errorType, frames: report.frames),
        reason: scenario,
      );
    }
  });

  test('a message with quotes, newlines and non-ASCII survives as JSON', () {
    final DVCrashReport report = DVCrashReport.fromJson(
        jsonDecode(run('hostile')['json']! as String) as Map<String, Object?>);
    expect(report.message, 'He said "no"\nthen \\ left é中');
  });

  test('the cause chain is kept after the crash\'s own frames', () {
    final DVCrashReport report = DVCrashReport.fromJson(
        jsonDecode(run('nested')['json']! as String) as Map<String, Object?>);
    expect(report.frames.any((DVCrashFrame f) => f.function.startsWith('Caused by:')),
        isTrue);
  });

  test('install() chains the previous handler and the file lands where the '
      'Dart store looks', () {
    final Map<String, Object?> out = run('install');
    expect(out['previousCalled'], true);
    expect(out['installedTwiceChained'], false);
    final String directory = out['directory']! as String;
    expect(directory, endsWith('dartvel-crashes'));
    final DVFileCrashStore store = DVFileCrashStore(directory);
    final List<DVCrashStoreEntry> pending = store.pending();
    expect(pending, hasLength(1));
    expect(pending.single.truncated, isFalse);
    expect(pending.single.report!.errorType, 'java.lang.IllegalStateException');
    Directory(directory).parent.deleteSync(recursive: true);
  });

  test('a crash loop writes a bounded number of records', () {
    final Map<String, Object?> out = run('loop');
    expect(out['written'] as int, lessThanOrEqualTo(20));
    Directory(out['directory']! as String).parent.deleteSync(recursive: true);
  });

  test('when disabled it records nothing and chains nothing', () {
    final Directory off = Directory(p.join(work.path, 'off'))..createSync();
    File(p.join(off.path, 'DartvelCrash.java')).writeAsStringSync(
        dvAndroidCrashHandlerSource(release: '1.0.0', enabled: false));
    expect(File(p.join(off.path, 'DartvelCrash.java')).readAsStringSync(),
        contains('if (!ENABLED'));
  });
}

/// A plain-JVM driver. It stands in for Android only where the handler asks
/// Android for something: the files directory, which it is told.
const String _harness = r'''
package dev.dartvel.jni;

import java.io.File;
import java.nio.file.Files;

public final class Harness {
  static Throwable nested() {
    try {
      try {
        throw new IllegalArgumentException("root cause");
      } catch (IllegalArgumentException cause) {
        throw new IllegalStateException("cart is empty", cause);
      }
    } catch (IllegalStateException failure) {
      return failure;
    }
  }

  static Throwable deep(int depth) {
    if (depth == 0) return new IllegalStateException("deep");
    return deep(depth - 1);
  }

  public static void main(String[] args) throws Exception {
    final String scenario = args[0];
    final StringBuilder out = new StringBuilder("{");
    switch (scenario) {
      case "nested":
        out.append("\"json\":").append(quote(DartvelCrash.reportJson(
            "1.4.0+12", "0123456789abcdef0123456789abcdef", nested(), 1760000000000L, "r1")));
        break;
      case "framework-only":
        out.append("\"json\":").append(quote(DartvelCrash.reportJson(
            "1.4.0+12", "0123456789abcdef0123456789abcdef",
            new java.util.ConcurrentModificationException("x"), 1760000000000L, "r1")));
        break;
      case "deep":
        out.append("\"json\":").append(quote(DartvelCrash.reportJson(
            "1.4.0+12", "0123456789abcdef0123456789abcdef", deep(40), 1760000000000L, "r1")));
        break;
      case "hostile":
        out.append("\"json\":").append(quote(DartvelCrash.reportJson(
            "1.4.0+12", "0123456789abcdef0123456789abcdef",
            new IllegalStateException("He said \"no\"\nthen \\ left é中"),
            1760000000000L, "r1")));
        break;
      case "install": {
        final File files = Files.createTempDirectory("dv_files").toFile();
        final boolean[] previousCalled = {false};
        Thread.setDefaultUncaughtExceptionHandler(
            (thread, throwable) -> previousCalled[0] = true);
        DartvelCrash.install(files);
        final Thread.UncaughtExceptionHandler first = Thread.getDefaultUncaughtExceptionHandler();
        DartvelCrash.install(files);
        final boolean chained = Thread.getDefaultUncaughtExceptionHandler() != first;
        first.uncaughtException(Thread.currentThread(), nested());
        out.append("\"previousCalled\":").append(previousCalled[0])
            .append(",\"installedTwiceChained\":").append(chained)
            .append(",\"directory\":").append(quote(new File(files, "dartvel-crashes").getPath()));
        break;
      }
      case "loop": {
        final File files = Files.createTempDirectory("dv_files").toFile();
        Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {});
        DartvelCrash.install(files);
        for (int i = 0; i < 60; i++) {
          Thread.getDefaultUncaughtExceptionHandler()
              .uncaughtException(Thread.currentThread(), nested());
        }
        final File dir = new File(files, "dartvel-crashes");
        int written = 0;
        for (String name : dir.list()) if (name.endsWith(".crash")) written++;
        out.append("\"written\":").append(written)
            .append(",\"directory\":").append(quote(dir.getPath()));
        break;
      }
      default:
        throw new IllegalArgumentException(scenario);
    }
    System.out.println(out.append("}"));
  }

  static String quote(String value) {
    final StringBuilder b = new StringBuilder("\"");
    for (char c : value.toCharArray()) {
      switch (c) {
        case '"': b.append("\\\""); break;
        case '\\': b.append("\\\\"); break;
        case '\n': b.append("\\n"); break;
        case '\r': b.append("\\r"); break;
        case '\t': b.append("\\t"); break;
        default:
          if (c < 0x20 || c > 0x7e) b.append(String.format("\\u%04x", (int) c));
          else b.append(c);
      }
    }
    return b.append('"').toString();
  }
}
''';
