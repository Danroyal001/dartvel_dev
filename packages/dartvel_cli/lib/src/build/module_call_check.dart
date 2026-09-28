/// DV-MODULE-013 and DV-MODULE-014, at build time.
///
/// A generated module declares, per operation, what happens on a device, in
/// a browser and on the backend. A call the build can see is checked against
/// that declaration for the environment being built: a call reaching an
/// operation declared `unavailable` there is `DV-MODULE-013`, and one
/// reaching an operation that declares nothing there is `DV-MODULE-014`.
/// The runtime still throws `DVModuleUnavailable` for a call nothing could
/// see; this is the one the build can, which should never reach a device.
///
/// Call sites are read lexically, `DV.Modules.<id>.<operation>(`, with
/// comments removed. Code under the backend directory is the backend; the
/// rest of `lib/` is the client, generated code excepted.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../graph/module_mounts.dart';

class DVModuleCallCheck {
  const DVModuleCallCheck(this.lines);

  /// One line per refused call.
  final List<String> lines;

  bool get ok => lines.isEmpty;

  /// Checks the calls in [root] that the build for [environments] compiles.
  static DVModuleCallCheck run(
    String root,
    Set<DVModuleEnvironment> environments, {
    String backendDir = 'lib/backend',
  }) {
    final Map<String, Map<String, Map<String, String>>> declared =
        <String, Map<String, Map<String, String>>>{};
    for (final DVModuleMount mount in dvDiscoverModuleMounts(root)) {
      if (mount.surface == null) continue;
      final Map<String, Map<String, String>>? ops = _operations(root, mount);
      if (ops != null) declared[mount.id] = ops;
    }
    if (declared.isEmpty) return const DVModuleCallCheck(<String>[]);

    final List<String> lines = <String>[];
    final Directory lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return const DVModuleCallCheck(<String>[]);
    final String backend = p.normalize(p.join(root, backendDir));
    final String generated = p.join(root, 'lib', 'dartvel_client');
    final List<File> files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => !p.isWithin(generated, f.path))
        .toList()
      ..sort((File a, File b) => a.path.compareTo(b.path));
    final RegExp call =
        RegExp(r'DV\s*\.\s*Modules\s*\.\s*(\w+)\s*\.\s*(\w+)\s*\(');
    for (final File file in files) {
      final bool isBackend = p.isWithin(backend, file.path);
      final Set<DVModuleEnvironment> here = environments
          .where((DVModuleEnvironment e) =>
              isBackend == (e == DVModuleEnvironment.backend))
          .toSet();
      if (here.isEmpty) continue;
      final List<String> source =
          _withoutComments(file.readAsStringSync()).split('\n');
      for (int i = 0; i < source.length; i++) {
        for (final RegExpMatch m in call.allMatches(source[i])) {
          final Map<String, Map<String, String>>? ops = declared[m.group(1)];
          final Map<String, String>? op = ops?[m.group(2)];
          if (op == null) continue;
          for (final DVModuleEnvironment env in here) {
            final String where =
                '${p.relative(file.path, from: root).replaceAll('\\', '/')}:${i + 1}';
            final DVModuleOutcome? outcome = DVModuleOutcome.parse(op[env.name]);
            if (outcome == null) {
              lines.add('   DV-MODULE-014 $where calls '
                  '${m.group(1)}.${m.group(2)}, which declares nothing for '
                  '${env.name}.');
            } else if (outcome == DVModuleOutcome.unavailable) {
              lines.add('   DV-MODULE-013 $where calls '
                  '${m.group(1)}.${m.group(2)}, which is unavailable on '
                  '${env.name}. Call it from where it is real, or move the '
                  'call behind a backend function.');
            }
          }
        }
      }
    }
    return DVModuleCallCheck(lines);
  }

  static Map<String, Map<String, String>>? _operations(
      String root, DVModuleMount mount) {
    final File pubspec = File(p.join(root, mount.sourcePath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    Object? ops;
    if (doc is Map && doc['dartvel'] is Map) {
      final Object? module = (doc['dartvel'] as Map)['module'];
      if (module is Map) ops = module['operations'];
    }
    if (ops is! Map) return null;
    return <String, Map<String, String>>{
      for (final MapEntry<Object?, Object?> e in ops.entries)
        '${e.key}': <String, String>{
          if (e.value is Map)
            for (final MapEntry<Object?, Object?> o
                in (e.value as Map).entries)
              '${o.key}': '${o.value}',
        },
    };
  }

  static String _withoutComments(String code) => code
      .replaceAllMapped(RegExp(r'/\*[\s\S]*?\*/'),
          (Match m) => '\n' * '\n'.allMatches(m.group(0)!).length)
      .replaceAll(RegExp(r'//[^\n]*'), '');
}
