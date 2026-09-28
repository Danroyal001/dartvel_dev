// `dartvel add maven:<group>:<artifact>` and a local jar: resolved,
// checked against the sha1 Maven Central publishes, wrapped and pinned.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:dartvel_cli/src/modules/foreign/resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

List<int> jarBytes() {
  final Directory dir = Directory.systemTemp.createTempSync('dv_add_jvm_src_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final File java = File(p.join(dir.path, 'com', 'acme', 'Scanner.java'))
    ..createSync(recursive: true)
    ..writeAsStringSync('package com.acme;\npublic class Scanner {\n'
        '  public static int add(int a, int b) { return a + b; }\n}\n');
  expect(Process.runSync('javac', <String>['--release', '11', '-d', p.join(dir.path, 'out'), java.path]).exitCode, 0);
  final String out = p.join(dir.path, 'a.jar');
  expect(Process.runSync('jar', <String>['cf', out, '-C', p.join(dir.path, 'out'), '.']).exitCode, 0);
  return File(out).readAsBytesSync();
}

class _Central extends DVSourceFetcher {
  _Central(this.jar, {this.sha});
  final List<int> jar;
  final String? sha;
  final List<String> asked = <String>[];

  @override
  Future<String> getText(Uri url) async {
    asked.add('$url');
    if ('$url'.endsWith('maven-metadata.xml')) {
      return '<metadata><versioning><release>4.2.0</release></versioning></metadata>';
    }
    return sha ?? sha1.convert(jar).toString();
  }

  @override
  Future<List<int>> getBytes(Uri url) async {
    asked.add('$url');
    if ('$url'.endsWith('.jar')) return jar;
    throw const DVSourceUnresolved('404');
  }
}

String project() {
  final Directory root = Directory.systemTemp.createTempSync('dv_add_jvm_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      'name: shop\nenvironment:\n  sdk: ^3.13.0\ndartvel:\n  app:\n    name: Shop\n');
  return root.path;
}

Future<int> run(String root, List<String> args, DVSourceFetcher f) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(AddCommand(root: root, fetcher: f));
  try {
    await runner.run(<String>['add', ...args]);
  } on DVAddRefused {
    return 1;
  }
  return 0;
}

void main() {
  test('maven: takes the release, checks the sha1 and declares the coordinate',
      () async {
    final String root = project();
    final _Central central = _Central(jarBytes());
    expect(await run(root, <String>['maven:com.acme:scanner'], central), 0);
    expect(central.asked,
        contains('https://repo1.maven.org/maven2/com/acme/scanner/4.2.0/scanner-4.2.0.jar'));
    final String module = p.join(root, 'modules', 'dv_scanner_module');
    expect(File(p.join(module, 'android', 'build.gradle')).readAsStringSync(),
        contains("implementation 'com.acme:scanner:4.2.0'"));
    final YamlMap pubspec =
        loadYaml(File(p.join(module, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    expect(pubspec['dartvel']['module']['kind'], 'jvm');
    expect(DVModuleLock.read(root).pins['dv_scanner_module']!.source,
        'maven:com.acme:scanner@4.2.0');
  });

  test('an artifact whose sha1 is not Central\'s is refused', () async {
    final String root = project();
    expect(
        await run(root, <String>['maven:com.acme:scanner@4.2.0'],
            _Central(jarBytes(), sha: '0' * 40)),
        1);
    expect(Directory(p.join(root, 'modules')).existsSync(), isFalse);
  });

  test('a local jar is carried in the module as bytes', () async {
    final String root = project();
    final List<int> bytes = jarBytes();
    File(p.join(root, 'libs', 'scanner.jar'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    expect(await run(root, <String>['libs/scanner.jar'], _Central(<int>[])), 0);
    final File carried = File(p.join(
        root, 'modules', 'dv_scanner_module', 'android', 'libs', 'scanner.jar'));
    expect(carried.readAsBytesSync(), bytes);
  });
}
