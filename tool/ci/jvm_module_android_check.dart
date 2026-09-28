/// Checks that a JVM library added with `dartvel add` builds into an
/// Android application, and that the APK carries the library and the JNI
/// runtime the module calls it through.
///
///     dart tool/ci/jvm_module_android_check.dart [work-dir]
///
/// Needs Flutter, a JDK and an Android SDK. Heavy: a Gradle build.
///
/// 1. Compiles a small Java class into a jar.
/// 2. Creates a Flutter application for Android and runs this checkout's
///    `dartvel add` on the jar, which generates the module under modules/.
/// 3. Writes a main.dart that calls the module, and builds a debug APK.
/// 4. Opens the APK: its dex must hold the class, and its native libraries
///    the JNI runtime package:jni ships.
///
/// Only dart:io, so it runs from a checkout with nothing resolved.
library;

import 'dart:io';

Future<void> main(List<String> args) async {
  final String repo = Directory.current.path;
  final Directory work = args.isNotEmpty
      ? (Directory(args.first)..createSync(recursive: true))
      : Directory.systemTemp.createTempSync('dv_jvm_android_');
  final List<String> failures = <String>[];
  void check(bool ok, String what) {
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $what');
    if (!ok) failures.add(what);
  }

  Future<ProcessResult> run(String exe, List<String> a, {String? cwd}) async {
    stdout.writeln('\$ $exe ${a.join(' ')}');
    final ProcessResult r = await Process.run(exe, a,
        workingDirectory: cwd ?? work.path, runInShell: false);
    if (r.exitCode != 0) {
      stderr.writeln('${r.stdout}\n${r.stderr}');
    }
    return r;
  }

  // 1. The library.
  final Directory src = Directory('${work.path}/java/com/acme')
    ..createSync(recursive: true);
  File('${src.path}/Scanner.java').writeAsStringSync('''
package com.acme;

public class Scanner {
  public static int add(int a, int b) { return a + b; }
  public static String greet(String name) { return "Hello " + name; }
}
''');
  check(
      (await run('javac', <String>[
        '--release', '11', '-d', '${work.path}/classes',
        '${src.path}/Scanner.java',
      ]))
              .exitCode ==
          0,
      'javac compiled the library');
  check(
      (await run('jar', <String>[
        'cf', '${work.path}/scanner.jar', '-C', '${work.path}/classes', '.',
      ]))
              .exitCode ==
          0,
      'jar packed it');

  // 2. The application and the module.
  final String app = '${work.path}/app';
  if (!Directory(app).existsSync()) {
    check(
        (await run('flutter', <String>[
          'create', '--platforms', 'android', '--project-name', 'jvm_probe',
          app,
        ]))
                .exitCode ==
            0,
        'flutter create made the application');
  }
  Directory('$app/libs').createSync(recursive: true);
  File('${work.path}/scanner.jar').copySync('$app/libs/scanner.jar');
  final Directory modules = Directory('$app/modules');
  if (modules.existsSync()) modules.deleteSync(recursive: true);
  final File lock = File('$app/dartvel.module.lock');
  if (lock.existsSync()) lock.deleteSync();
  check(
      (await run(Platform.resolvedExecutable, <String>[
        'run', '$repo/packages/dartvel_cli/bin/dartvel.dart', 'add',
        'libs/scanner.jar',
      ], cwd: app))
              .exitCode ==
          0,
      'dartvel add generated the module');

  File('$app/lib/main.dart').writeAsStringSync('''
import 'package:dv_scanner_module/dv_scanner_module.dart';
import 'package:flutter/material.dart';

void main() {
  const ScannerModule scanner = ScannerModule();
  runApp(MaterialApp(
    home: Text('\${scanner.add(40, 2)} \${scanner.greet('Android')}'),
  ));
}
''');
  // This checkout's dartvel_core, which carries what a generated module
  // imports whether or not it has been published yet.
  File('$app/pubspec_overrides.yaml').writeAsStringSync(
      'dependency_overrides:\n  dartvel_core:\n    path: $repo/packages/dartvel_core\n');
  check((await run('flutter', <String>['pub', 'get'], cwd: app)).exitCode == 0,
      'pub resolved the module');

  // 3. The build.
  final ProcessResult built = await Process.run(
    'flutter',
    <String>['build', 'apk', '--debug', '--target-platform', 'android-arm64'],
    workingDirectory: app,
    environment: <String, String>{
      'GRADLE_OPTS': '-Xmx2g -Dorg.gradle.daemon=false',
    },
  );
  stdout.writeln(built.stdout);
  if (built.exitCode != 0) stderr.writeln(built.stderr);
  check(built.exitCode == 0, 'flutter build apk succeeded');

  // 4. The APK.
  final String apk = '$app/build/app/outputs/flutter-apk/app-debug.apk';
  if (File(apk).existsSync()) {
    final ProcessResult list = await run('unzip', <String>['-l', apk]);
    final String entries = '${list.stdout}';
    check(entries.contains('libdartjni.so'),
        'the APK carries package:jni\'s runtime (libdartjni.so)');
    final Directory dex = Directory('${work.path}/dex')..createSync();
    await run('unzip', <String>['-o', '-q', apk, 'classes*.dex', '-d', dex.path]);
    bool found = false;
    for (final FileSystemEntity f in dex.listSync()) {
      if (f is File &&
          String.fromCharCodes(f.readAsBytesSync()).contains('Lcom/acme/Scanner;')) {
        found = true;
      }
    }
    check(found, 'the APK\'s dex holds com.acme.Scanner');
  } else {
    check(false, 'the APK is at $apk');
  }

  if (failures.isNotEmpty) {
    stderr.writeln('jvm module on Android: ${failures.length} check(s) '
        'failed: ${failures.join('; ')}');
    exit(1);
  }
  stdout.writeln('jvm module on Android: every check passed.');
}
