// @DVBoot runs in every entry its code can run in, not only the Flutter app.
//
// The design (docs/proposals/2026-10-12-application-entry.md, "Customizing
// boot") wires boot functions into every entry. Only the app entry was
// built: a web server, a worker and a cron process never ran one, so an
// application with no UI had no boot at all.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> _project(Map<String, String> files) async {
  final Directory root = await Directory.systemTemp.createTemp('dartvel_boot_entries_');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
  for (final MapEntry<String, String> file in files.entries) {
    File(p.join(root.path, file.key))
      ..createSync(recursive: true)
      ..writeAsStringSync(file.value);
  }
  return root;
}

Future<void> _backend(Directory root) => BackendGenerator.generate(
      root: root.path,
      backendDir: 'lib/backend',
      pkgName: 'boot_app',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );

const String _headless = '''
import 'package:dartvel_core/dartvel.dart';

@DVBoot()
void _registerClock(DVBoot boot) { DV.log('clock'); }
''';

const String _ui = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_core/dartvel.dart';

@DVBoot()
void _appearance(DVBoot boot) { DV.log('appearance'); }
''';

void main() {
  test('a headless boot function runs in the server; a UI one stays in the app', () async {
    final Directory root = await _project(<String, String>{'lib/boot/clock.dart': _headless, 'lib/boot/ui.dart': _ui});
    addTearDown(() => root.deleteSync(recursive: true));
    await _backend(root);
    final String steps = File(p.join(root.path, '.dart_tool', 'dartvel_backend_boot.g.dart')).readAsStringSync();
    expect(steps, contains("DV.log('clock')"));
    expect(steps, isNot(contains("DV.log('appearance')")));
    expect(steps, isNot(contains('package:flutter/')));
    final String routes = File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart')).readAsStringSync();
    // Every role boots: the web server (in startBackend), the worker, cron.
    for (final String role in <String>['web', 'worker', 'cron']) {
      expect(routes, contains('framework.dvRunBoot(boot.dartvelBootSteps, core.DVBoot(entry: const core.DVEntry.server(role: core.DVServerRole.$role)'));
    }
  });

  test('entries: narrows where a boot function runs', () async {
    final Directory root = await _project(<String, String>{
      'lib/boot/app_only.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBoot(entries: {DVEntryKind.app})
void _appOnly(DVBoot boot) { DV.log('app only'); }

@DVBoot(entries: <DVEntryKind>{.server})
void _serverOnly(DVBoot boot) { DV.log('server only'); }
''',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    final List<DVBootHook> hooks = ClientGenerator.bootHooks(root: root.path, pkgName: 'boot_app', aliasPrefix: 'boot');
    expect(hooks.map((DVBootHook hook) => hook.runsIn('app')), <bool>[true, false]);
    expect(hooks.map((DVBootHook hook) => hook.runsIn('server')), <bool>[false, true]);
    await _backend(root);
    final String steps = File(p.join(root.path, '.dart_tool', 'dartvel_backend_boot.g.dart')).readAsStringSync();
    expect(steps, contains("DV.log('server only')"));
    expect(steps, isNot(contains("DV.log('app only')")));
  });

  test('a UI file asking for the server entry is refused (DV-RUN-008)', () async {
    final Directory root = await _project(<String, String>{
      'lib/boot/ui.dart': '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_core/dartvel.dart';

@DVBoot(entries: {DVEntryKind.server})
void _wrong(DVBoot boot) { DV.log('wrong'); }
''',
    });
    addTearDown(() => root.deleteSync(recursive: true));
    expect(_backend(root), throwsA(isA<StateError>().having((StateError e) => e.message, 'message', contains('DV-RUN-008'))));
  });
}
