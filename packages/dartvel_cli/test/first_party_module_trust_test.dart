// A first-party module, added the documented way, passes the build's
// declaration check.
//
// It did not: an application that mounted dartvel_google_analytics and
// dartvel_meta_pixel exactly as their READMEs say stopped at `dartvel build`
// with DV-MODULE-001 for every secret and host the modules use, and a demand
// to pin a package that is part of the framework release itself. Nobody had
// run the check over the framework's own modules, so the first application to
// mount them found out. This runs it over every module in modules/, through
// `dartvel add`, and over the grant the READMEs print.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/commands/version_command.dart'
    show dartvelCliVersion;
import 'package:dartvel_cli/src/module_trust/capabilities.dart';
import 'package:dartvel_cli/src/module_trust/capability_analysis.dart';
import 'package:dartvel_cli/src/module_trust/module_trust.dart';
import 'package:dartvel_cli/src/modules/first_party.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

String _repository() {
  final Uri? library = Isolate.resolvePackageUriSync(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'));
  if (library == null) fail('dartvel_cli could not resolve its own package URI');
  return p.normalize(p.join(p.dirname(library.toFilePath()), '..', '..', '..'));
}

String _app({String modules = ''}) {
  final Directory root = Directory.systemTemp.createTempSync('dv_fp_trust_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core: ^$dartvelCliVersion
dartvel:
  app:
    name: Shop$modules
''');
  return root.path;
}

/// What `pub get` writes, pointing each package at [roots].
void _resolve(String app, Map<String, String> roots) {
  File(p.join(app, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        for (final MapEntry<String, String> e in roots.entries)
          <String, Object?>{
            'name': e.key,
            'rootUri': Uri.directory(e.value).toString(),
            'packageUri': 'lib/',
          },
      ],
    }));
}

/// Every first-party module and dartvel_core, from this checkout: what an
/// application resolves with a git or path override on the framework.
Map<String, String> _framework() => <String, String>{
      'dartvel_core': p.join(_repository(), 'packages', 'dartvel_core'),
      for (final DVFirstPartyModule m in dvFirstPartyModules)
        m.package: p.join(_repository(), 'modules', m.package),
    };

Future<void> _add(String app, String name) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(AddCommand(root: app));
  await runner.run(<String>['add', name]);
}

/// The modules whose every capability is fixed by the module itself.
///
/// dartvel_woocommerce is not one: it calls the application's own store, at
/// the address the application configures, which no module can declare. Its
/// egress needs a grant the application names, which this check does not
/// read yet.
final List<DVFirstPartyModule> _fixed = <DVFirstPartyModule>[
  for (final DVFirstPartyModule m in dvFirstPartyModules)
    if (m.package != 'dartvel_woocommerce') m,
];

void main() {
  group('every first-party module, added with dartvel add, may build', () {
    for (final DVFirstPartyModule module in _fixed) {
      test(module.package, () async {
        final String app = _app();
        await _add(app, module.name);
        _resolve(app, _framework());
        final DVModuleTrustReport report = dvEvaluateModuleTrust(app);
        expect(report.lines(), isEmpty);
        expect(report.ok, isTrue);
      });
    }
  });

  test('the grant the READMEs print for Google Analytics and Meta Pixel',
      () {
    final String app = _app(modules: '''

  modules:
    googleAnalytics:
      package: dartvel_google_analytics
      backendPolicy: public
      config: { measurementId: G-ABC123XYZ9, consent: analytics }
      grant:
        secrets: [GA4_MEASUREMENT_ID, GA4_API_SECRET]
        egress: [www.google-analytics.com, region1.google-analytics.com]
    metaPixel:
      package: dartvel_meta_pixel
      backendPolicy: public
      config: { pixelId: "1234567890" }
      grant:
        secrets: [META_PIXEL_ID, META_CONVERSIONS_API_TOKEN]
        egress: [graph.facebook.com]''');
    _resolve(app, _framework());
    final DVModuleTrustReport report = dvEvaluateModuleTrust(app);
    expect(report.lines(), isEmpty);
  });

  test('without the grant, each use is refused by name', () {
    final String app = _app(modules: '''

  modules:
    metaPixel:
      package: dartvel_meta_pixel
      backendPolicy: public''');
    _resolve(app, _framework());
    final List<String> lines = dvEvaluateModuleTrust(app).lines();
    expect(lines.join('\n'), contains('META_CONVERSIONS_API_TOKEN'));
    expect(lines.join('\n'), contains('graph.facebook.com'));
    expect(lines.join('\n'), isNot(contains('named at runtime')));
  });

  test('a module calls nothing the build cannot read', () {
    for (final DVFirstPartyModule module in _fixed) {
      final DVModuleCodeAnalysis code = dvAnalyseModuleProject(
          p.join(_repository(), 'modules', module.package));
      expect(code.unresolved.map((DVModuleCodeUse u) => '$u'), isEmpty,
          reason: module.package);
      expect(code.ownNetwork, isEmpty, reason: module.package);
    }
  });

  test('the catalogue grants exactly what each module declares', () {
    for (final DVFirstPartyModule module in _fixed) {
      final String root = p.join(_repository(), 'modules', module.package);
      final Object? section = dvModuleDartvelSection(root)['module'];
      final DVModuleCapabilities declared = dvParseModuleCapabilities(
        section is Map ? section['capabilities'] : null,
        where: module.package,
      ).capabilities;
      expect(module.secrets.toSet(), declared.secrets, reason: module.package);
      expect(module.egress.toSet(), declared.egress, reason: module.package);
      // And the code uses what is declared, no more and no less.
      final DVModuleCodeAnalysis code = dvAnalyseModuleProject(root);
      expect(code.uses.secrets, declared.secrets, reason: module.package);
      expect(code.uses.egress, declared.egress, reason: module.package);
    }
  });

  group('pinning', () {
    test('a first-party module resolved with the framework needs no pin',
        () {
      // Released with the framework, from the same checkout or the same
      // release as dartvel_core: its identity is the framework's.
      final String app = _app();
      _resolve(app, _framework());
      File(p.join(app, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  modules:
    metaPixel:
      package: dartvel_meta_pixel
      grant:
        secrets: [META_PIXEL_ID, META_CONVERSIONS_API_TOKEN]
        egress: [graph.facebook.com]
''');
      expect(dvEvaluateModuleTrust(app).lines().join('\n'),
          isNot(contains('not pinned')));
    });

    test('a package of the same name from anywhere else still needs one', () {
      final String app = _app();
      final Directory copy =
          Directory(p.join(app, 'elsewhere', 'dartvel_meta_pixel'))
            ..createSync(recursive: true);
      final String source =
          p.join(_repository(), 'modules', 'dartvel_meta_pixel');
      File(p.join(source, 'pubspec.yaml'))
          .copySync(p.join(copy.path, 'pubspec.yaml'));
      Directory(p.join(copy.path, 'lib')).createSync();
      _resolve(app, <String, String>{
        ..._framework(),
        'dartvel_meta_pixel': copy.path,
      });
      File(p.join(app, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  modules:
    metaPixel:
      package: dartvel_meta_pixel
''');
      expect(dvEvaluateModuleTrust(app).lines().join('\n'),
          contains('not pinned'));
    });

    test('a first-party module at another version than the framework needs '
        'a pin', () {
      final String app = _app();
      final Directory copy = Directory(p.join(app, 'fw'))..createSync();
      // A checkout laid out like the framework's, at another version.
      final Directory module =
          Directory(p.join(copy.path, 'modules', 'dartvel_meta_pixel'))
            ..createSync(recursive: true);
      final YamlMap original = loadYaml(File(p.join(_repository(), 'modules',
              'dartvel_meta_pixel', 'pubspec.yaml'))
          .readAsStringSync()) as YamlMap;
      File(p.join(module.path, 'pubspec.yaml')).writeAsStringSync(
          'name: dartvel_meta_pixel\nversion: 0.0.1\n'
          'dartvel:\n  module:\n    id: ${original['dartvel']['module']['id']}\n');
      Directory(p.join(module.path, 'lib')).createSync();
      Directory(p.join(copy.path, 'packages', 'dartvel_core'))
          .createSync(recursive: true);
      File(p.join(copy.path, 'packages', 'dartvel_core', 'pubspec.yaml'))
          .writeAsStringSync('name: dartvel_core\nversion: 9.9.9\n');
      _resolve(app, <String, String>{
        'dartvel_core': p.join(copy.path, 'packages', 'dartvel_core'),
        'dartvel_meta_pixel': module.path,
      });
      File(p.join(app, 'pubspec.yaml')).writeAsStringSync('''
name: shop
dartvel:
  modules:
    metaPixel:
      package: dartvel_meta_pixel
''');
      expect(dvEvaluateModuleTrust(app).lines().join('\n'),
          contains('not pinned'));
    });
  });
}
