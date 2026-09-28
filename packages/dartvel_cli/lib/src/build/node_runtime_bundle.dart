/// Node, copied into a desktop bundle for the modules that run in it.
///
/// An npm package or a WebAssembly binary a desktop client calls runs in
/// Node, and the person running the application should not have to install
/// it. When a module the project mounts from a path declares an operation
/// `real` on native and is of a Node-carried kind, `dartvel build` copies
/// the host's Node into the bundle, where the module's carrier looks first.
/// A project that calls no such module gets no Node: nothing ships that
/// nothing calls.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// What [dvBundleNodeRuntime] did.
class DVNodeBundle {
  const DVNodeBundle({this.modules = const <String>[], this.problem});

  /// The modules that needed Node. Empty when none did.
  final List<String> modules;

  /// Why Node could not be bundled for them.
  final String? problem;
}

/// Copies [node] into [bundle] when a module of [root] runs in Node on the
/// device. On Linux the copy is `lib/node`; elsewhere it sits beside the
/// executable, which is where the carrier also looks.
DVNodeBundle dvBundleNodeRuntime(String root, String bundle,
    {required String? node, bool linux = true}) {
  final List<String> modules = _nodeModules(root);
  if (modules.isEmpty) return const DVNodeBundle();
  if (node == null || !File(node).existsSync()) {
    return DVNodeBundle(
      modules: modules,
      problem: '${modules.join(', ')} run in Node on the desktop, and this '
          'host has no node to bundle. Install Node and build again.',
    );
  }
  final File target = File(linux
      ? p.join(bundle, 'lib', 'node')
      : p.join(bundle, Platform.isWindows ? 'node.exe' : 'node'))
    ..parent.createSync(recursive: true);
  File(node).copySync(target.path);
  if (!Platform.isWindows) {
    Process.runSync('chmod', <String>['755', target.path]);
  }
  return DVNodeBundle(modules: modules);
}

/// The host's Node, as dartvel build copies it.
String? dvHostNode() {
  final ProcessResult r =
      Process.runSync(Platform.isWindows ? 'where' : 'which', <String>['node']);
  if (r.exitCode != 0) return null;
  final String path = '${r.stdout}'.trim().split('\n').first.trim();
  return path.isEmpty ? null : File(path).resolveSymbolicLinksSync();
}

List<String> _nodeModules(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const <String>[];
  final Object? doc = loadYaml(pubspec.readAsStringSync());
  final Object? modules =
      doc is Map && doc['dartvel'] is Map ? doc['dartvel']['modules'] : null;
  if (modules is! Map) return const <String>[];
  final List<String> out = <String>[];
  for (final MapEntry<Object?, Object?> entry in modules.entries) {
    final Object? body = entry.value;
    final Object? source = body is Map ? body['source'] : null;
    final Object? path = source is Map ? source['path'] : null;
    if (path is! String) continue;
    final File file = File(p.join(root, path, 'pubspec.yaml'));
    if (!file.existsSync()) continue;
    final Object? module = () {
      final Object? d = loadYaml(file.readAsStringSync());
      return d is Map && d['dartvel'] is Map ? d['dartvel']['module'] : null;
    }();
    if (module is! Map) continue;
    if (module['kind'] != 'npm' && module['kind'] != 'wasm') continue;
    final Object? ops = module['operations'];
    if (ops is Map &&
        ops.values.any((Object? o) => o is Map && o['native'] == 'real')) {
      out.add('${module['id'] ?? entry.key}');
    }
  }
  return out;
}
