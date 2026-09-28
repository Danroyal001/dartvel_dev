// A plain Dart package becomes a module the parent calls as DV.Modules.<id>.
//
// Checked by running what is generated, not by reading it: the module and
// the package it wraps are written to disk, resolved with a package config,
// run on the VM -- which is the backend environment -- and compiled for the
// browser. A package that needs dart:io must compile for the web anyway,
// with its operations throwing DVModuleUnavailable there, because a module
// that breaks the web build of every application that adds it is worse than
// no module.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_package_module.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _pure = r'''
/// Turns [text] into a slug.
String slug(String text, {String separator = '-'}) =>
    text.trim().toLowerCase().split(RegExp(r'\s+')).join(separator);

Future<int> countWords(String text) async => text.split(' ').length;
''';

const String _io = r'''
import 'dart:io';

/// The separator this platform's paths use.
String separator() => Platform.pathSeparator;

bool isBlank(String? text) => text == null || text.trim().isEmpty;
''';

/// A scratch directory under this package's .dart_tool, so the package
/// config written for a probe can point at this package's own resolution.
Directory scratch() {
  final Directory dir = Directory(p.join(Directory.current.path, '.dart_tool',
      'dv_dart_module_probe', 'p${DateTime.now().microsecondsSinceEpoch}'))
    ..createSync(recursive: true);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Directory vendor(Directory root, String name, String code) {
  final Directory dir = Directory(p.join(root.path, name))..createSync();
  File(p.join(dir.path, 'pubspec.yaml'))
      .writeAsStringSync('name: $name\nversion: 1.0.0\n');
  File(p.join(dir.path, 'lib', '$name.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(code);
  return dir;
}

/// Writes [module] into [root] and a package config resolving it, the
/// package it wraps, and everything this package resolves.
String install(Directory root, DVGeneratedModule module, Directory package) {
  final Directory into = Directory(p.join(root.path, module.packageName));
  for (final MapEntry<String, String> f in module.files.entries) {
    File(p.join(into.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  final Map<String, Object?> own = jsonDecode(File(p.join(
          Directory.current.path, '.dart_tool', 'package_config.json'))
      .readAsStringSync()) as Map<String, Object?>;
  final List<Object?> packages = <Object?>[
    for (final Object? entry in own['packages']! as List<Object?>)
      <String, Object?>{
        ...(entry! as Map<String, Object?>),
        'rootUri': _absolute((entry as Map<String, Object?>)['rootUri']! as String),
      },
    <String, Object?>{
      'name': module.packageName,
      'rootUri': into.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.13',
    },
    <String, Object?>{
      'name': p.basename(package.path),
      'rootUri': package.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.13',
    },
  ];
  final File config = File(p.join(root.path, 'package_config.json'))
    ..writeAsStringSync(jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': packages,
    }));
  return config.path;
}

String _absolute(String rootUri) {
  final Uri base = Directory(p.join(Directory.current.path, '.dart_tool')).uri;
  return base.resolve(rootUri).toString();
}

void main() {
  test('every operation declares an outcome in every environment', () {
    final Directory root = scratch();
    final DVForeignModuleSpec spec = dvDartPackageModuleSpec(
      id: 'paths',
      source: 'path:paths',
      surface: dvScanDartPackage(vendor(root, 'paths', _io).path),
      dependency: '{path: ../paths}',
    );
    final DVGeneratedModule module = dvWriteForeignModule(spec);
    final YamlMap ops = (loadYaml(module.files['pubspec.yaml']!)
        as YamlMap)['dartvel']['module']['operations'] as YamlMap;
    expect(ops['separator'],
        <String, String>{'native': 'real', 'web': 'unavailable', 'backend': 'real'});
    expect(ops['isBlank'],
        <String, String>{'native': 'real', 'web': 'unavailable', 'backend': 'real'});
    expect(spec.outcomes['separator']![DVModuleEnvironment.web],
        DVModuleOutcome.unavailable);
  });

  test('noop is only for an operation with nothing to return', () {
    final Directory root = scratch();
    expect(
      () => dvWriteForeignModule(dvDartPackageModuleSpec(
        id: 'paths',
        source: 'path:paths',
        surface: dvScanDartPackage(vendor(root, 'paths', _io).path),
        dependency: '{path: ../paths}',
        elsewhere: DVModuleOutcome.noop,
      )),
      throwsA(isA<DVModuleGenerationRefused>()
          .having((DVModuleGenerationRefused e) => e.code, 'code', 'DV-MODULE-017')),
    );
  });

  test('the module runs the package on the backend', () async {
    final Directory root = scratch();
    final Directory pkg = vendor(root, 'textkit', _pure);
    final DVGeneratedModule module = dvWriteForeignModule(
      dvDartPackageModuleSpec(
        id: 'textkit',
        source: 'path:textkit',
        surface: dvScanDartPackage(pkg.path),
        dependency: '{path: ../textkit}',
      ),
    );
    final String config = install(root, module, pkg);
    final File probe = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'package:dv_textkit_module/dv_textkit_module.dart';

Future<void> main() async {
  const TextkitModule m = TextkitModule();
  print(m.slug('  Hello Big World ', separator: '_'));
  print(await m.countWords('a b c'));
}
''');
    final ProcessResult run = await Process.run(Platform.resolvedExecutable,
        <String>['--packages=$config', probe.path]);
    expect('${run.stdout}${run.stderr}', contains('hello_big_world\n3'),
        reason: '${run.stdout}${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a package that needs dart:io still compiles for the web, and throws '
      'there', () async {
    final Directory root = scratch();
    final Directory pkg = vendor(root, 'paths', _io);
    final DVGeneratedModule module = dvWriteForeignModule(
      dvDartPackageModuleSpec(
        id: 'paths',
        source: 'path:paths',
        surface: dvScanDartPackage(pkg.path),
        dependency: '{path: ../paths}',
      ),
    );
    final String config = install(root, module, pkg);
    final File probe = File(p.join(root.path, 'web_probe.dart'))
      ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart' show DVModuleUnavailable;
import 'package:dv_paths_module/dv_paths_module.dart';

void main() {
  try {
    const PathsModule().separator();
    print('ran');
  } on DVModuleUnavailable catch (e) {
    print('\$e');
  }
}
''');
    final String out = p.join(root.path, 'out.js');
    final ProcessResult compiled = await Process.run(
        Platform.resolvedExecutable,
        <String>['compile', 'js', '--packages=$config', '-o', out, probe.path]);
    expect(compiled.exitCode, 0, reason: '${compiled.stdout}${compiled.stderr}');
    // The browser bundle carries the web carrier's failure, not dart:io.
    final String js = File(out).readAsStringSync();
    expect(js, contains('DV-MODULE-013'));
    expect(js, isNot(contains('pathSeparator')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
