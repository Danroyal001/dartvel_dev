// A JVM library becomes a module reached over JNI on Android.
//
// The jar is compiled here with javac and read back as the JVM reads it,
// from its class files. What is checked: the static methods whose types can
// cross, the ones that cannot with the reason, the carrier calling through
// package:jni with each string released after the call, and the Android
// part of the plugin declaring the library for Gradle. That the generated
// module builds into an APK is checked by tool/ci/jvm_module_android_check.dart
// against the Android SDK, which is too heavy for this suite.
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/jvm_module.dart';
import 'package:dartvel_cli/src/modules/foreign/jvm_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String jar() {
  final Directory dir = Directory.systemTemp.createTempSync('dv_jvm_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File java = File(p.join(dir.path, 'com', 'acme', 'Scanner.java'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
package com.acme;

public class Scanner {
  public static int add(int a, int b) { return a + b; }
  public static long big(long a) { return a * 2; }
  public static String greet(String name) { return "Hello " + name; }
  public static boolean ready() { return true; }
  public static double scale(double x, float f) { return x * f; }
  public static int[] many() { return new int[0]; }
  public static int pick(int a) { return a; }
  public static int pick(long a) { return (int) a; }
  public int count() { return 1; }
  static int hidden() { return 0; }
}
''');
  final ProcessResult javac = Process.runSync(
      'javac', <String>['--release', '11', '-d', p.join(dir.path, 'out'), java.path]);
  expect(javac.exitCode, 0, reason: '${javac.stderr}');
  final String out = p.join(dir.path, 'acme.jar');
  expect(Process.runSync('jar', <String>['cf', out, '-C', p.join(dir.path, 'out'), '.']).exitCode, 0);
  return out;
}

void main() {
  test('public static methods are read from the class files', () {
    final DVJvmSurface surface = dvScanJar(jar());
    final Map<String, DVJvmMethod> m = <String, DVJvmMethod>{
      for (final DVJvmMethod x in surface.methods) x.operation.name: x,
    };
    expect(m.keys, unorderedEquals(<String>['add', 'big', 'greet', 'ready', 'scale']));
    expect(m['add']!.descriptor, '(II)I');
    expect(m['add']!.className, 'com/acme/Scanner');
    expect(m['add']!.operation.parameterList, 'int a0, int a1');
    expect(m['greet']!.operation.returnType, 'String');
    expect(m['scale']!.paramJni, <String>['double', 'float']);
    expect(surface.skipped['many'], contains('object other than a String'));
    expect(surface.skipped['pick'], contains('overloaded'));
    expect(surface.skipped['count'], contains('instance method'));
    expect(surface.skipped.containsKey('hidden'), isFalse);
  });

  test('the module calls through package:jni and declares the library for '
      'Gradle', () {
    final DVGeneratedModule module = dvWriteForeignModule(dvJvmModuleSpec(
      id: 'scanner',
      source: 'maven:com.acme:scanner@4.2.0',
      surface: dvScanJar(jar()),
      artifact: const DVMavenArtifact('com.acme:scanner:4.2.0'),
    ));
    final String pubspec = module.files['pubspec.yaml']!;
    expect(pubspec, contains('targets: [android]'));
    expect(pubspec, contains('ffiPlugin: true'));
    expect(pubspec, contains('''
      add:
        native: real
        web: unavailable
        backend: unavailable'''));
    final String carrier = module.files['lib/src/carrier_native.dart']!;
    expect(carrier, contains("JClass.forName('com/acme/Scanner')"));
    expect(carrier, contains("staticMethodId('add', '(II)I')"));
    expect(carrier, contains('JValueInt(a0)'));
    expect(carrier, contains('ja0.release();'));
    expect(carrier, isNot(contains('MethodChannel')));
    expect(module.files['android/build.gradle'],
        contains("implementation 'com.acme:scanner:4.2.0'"));
  });

  test('a jar with many classes needs to be told which', () {
    expect(() => dvScanJar(jar(), only: <String>['com.acme.Missing']),
        throwsA(isA<DVDartSurfaceRefused>()));
  });
}
