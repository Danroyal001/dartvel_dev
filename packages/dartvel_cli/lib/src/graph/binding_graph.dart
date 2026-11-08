/// The native binding graph: how each call a mounted module declares gets to
/// the place it runs.
///
/// Internal machinery, never a public API: a parent application names a
/// module, never a binding. It is built because generated output has to be
/// inspectable to be trusted, and `dartvel inspect bindings --json` prints
/// it.
///
/// Four dimensions, kept apart. The module's **kind** says what the source
/// was (`ffi`, `jvm`, `npm`, ...). The **binding kind** says how a call
/// crosses -- one of exactly five, [dvBindingKinds]. The **environment and
/// target** say where it is crossing. The **carrier** says how the
/// implementation got there. A C library is `DVFfiBinding` on a device and
/// `DVWasmBinding` in a browser; Swift is `DVFfiBinding` like C. A module of
/// Dart, or a described API carried over `DV.Http`, crosses no foreign
/// boundary and contributes no node: a binding for it would describe a
/// boundary that is not there.
///
/// A cell the matrix cannot fill is either declared by the module -- the
/// operation is `compat`, `noop` or `unavailable` there, and the node lists
/// it under `declared` -- or it is a diagnostic: `DV-BIND-005` when the
/// binding kind cannot exist on that target at all (JNI on iOS, FFI in a
/// browser), `DV-BIND-007` when it could and no carrier is built (Node on a
/// phone, a JVM on a desktop).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'module_mounts.dart';

/// The five binding kinds. A closed set: `tool/ci/reserved_names_check.dart`
/// refuses the per-language and per-platform names that would grow it.
const List<String> dvBindingKinds = <String>[
  'DVFfiBinding',
  'DVJniBinding',
  'DVWebBinding',
  'DVWasmBinding',
  'DVNodeJsBinding',
];

/// The device targets a module that names none is declared for.
const List<String> dvBindingNativeTargets = <String>[
  'android',
  'ios',
  'macos',
  'linux',
  'windows',
];

const List<String> _desktops = <String>['linux', 'macos', 'windows'];

/// One cell of the carrier matrix: the binding kind a call of a module kind
/// crosses in an environment and target, and either the carrier that gets
/// the implementation there or the diagnostic saying why nothing does.
class DVBindingCell {
  const DVBindingCell(this.kind, {this.carrier, this.code, this.reason});

  final String kind;
  final String? carrier;

  /// `DV-BIND-005` or `DV-BIND-007` when nothing carries [kind] here, with
  /// [carrier] null.
  final String? code;

  /// Why nothing carries it, for the diagnostic.
  final String? reason;
}

/// The carrier matrix, as built. [target] is a device target for `native`
/// and null for `web` and `backend`. Null when [moduleKind] crosses no
/// foreign boundary.
DVBindingCell? dvBindingCell(
    String? moduleKind, String environment, String? target) {
  final String where = target == null ? environment : '$environment $target';
  DVBindingCell absent(String kind, String why) => DVBindingCell(kind,
      code: 'DV-BIND-007',
      reason: 'no carrier brings $kind to $where: $why');
  DVBindingCell impossible(String kind, String why) => DVBindingCell(kind,
      code: 'DV-BIND-005', reason: '$kind is unavailable on $where: $why');

  switch (moduleKind) {
    case 'ffi':
      return switch (environment) {
        'native' => const DVBindingCell('DVFfiBinding',
            carrier: 'library compiled for the target by the module\'s '
                'build hook, bound with @Native'),
        'web' => const DVBindingCell('DVWasmBinding',
            carrier: '.wasm compiled from the source when the module was '
                'generated, instantiated by the browser'),
        _ => const DVBindingCell('DVFfiBinding',
            carrier: 'library compiled by the module\'s build hook, loaded '
                'into the backend with @Native'),
      };
    case 'apple':
      if (environment == 'web') {
        return impossible('DVFfiBinding', 'a browser has no C ABI');
      }
      if (environment == 'backend') {
        return const DVBindingCell('DVFfiBinding',
            carrier: 'Swift compiled with swiftc in the module\'s build hook');
      }
      if (target == 'ios' || target == 'macos') {
        return const DVBindingCell('DVFfiBinding',
            carrier: 'Swift or Objective-C compiled with a generated C shim, '
                'bound with @Native');
      }
      if (target == 'linux' || target == 'windows') {
        return const DVBindingCell('DVFfiBinding',
            carrier: 'Swift compiled with swiftc in the module\'s build hook');
      }
      return absent('DVFfiBinding', 'Swift is not built for $target');
    case 'jvm':
      if (environment == 'web') {
        return impossible('DVJniBinding', 'a browser has no JVM');
      }
      if (environment == 'backend') {
        return absent('DVJniBinding',
            'a backend JVM carrier is not built; declare compat or '
            'unavailable');
      }
      if (target == 'android') {
        return const DVBindingCell('DVJniBinding',
            carrier: 'package:jni, the library declared by the module\'s '
                'Android plugin part');
      }
      if (target == 'ios') {
        return impossible('DVJniBinding', 'iOS runs no JVM');
      }
      return absent('DVJniBinding', 'a desktop JVM is not built');
    case 'wasm':
      if (environment == 'web') {
        return const DVBindingCell('DVWasmBinding',
            carrier: 'the browser\'s own WebAssembly');
      }
      if (environment == 'backend') {
        return const DVBindingCell('DVWasmBinding',
            carrier: 'Node\'s WebAssembly, Node on the backend\'s PATH');
      }
      if (_desktops.contains(target)) {
        return const DVBindingCell('DVWasmBinding',
            carrier: 'Node\'s WebAssembly, Node bundled beside the '
                'application by dartvel build');
      }
      return absent('DVWasmBinding',
          'no WebAssembly runtime is embedded without Node');
    case 'npm':
      if (environment == 'web') {
        return const DVBindingCell('DVWebBinding',
            carrier: 'the bundled package, loaded with import() through '
                'dart:js_interop');
      }
      if (environment == 'backend') {
        return const DVBindingCell('DVNodeJsBinding',
            carrier: 'a Node process per call, Node on the backend\'s PATH');
      }
      if (_desktops.contains(target)) {
        return const DVBindingCell('DVNodeJsBinding',
            carrier: 'a Node process per call, Node bundled beside the '
                'application by dartvel build');
      }
      return absent('DVNodeJsBinding', 'Node on phones is not built');
    default:
      // dartPackage, describedApi and a plain Dartvel project are Dart all
      // the way down.
      return null;
  }
}

/// The binding kind a real call of [moduleKind] crosses in [environment],
/// whatever the target: null for a module that is Dart all the way down.
String? dvBindingKind(String? moduleKind, String environment) =>
    dvBindingCell(moduleKind, environment, null)?.kind;

/// Module kinds the matrix knows to be Dart, with no foreign boundary.
const Set<String> _dartKinds = <String>{'dartPackage', 'describedApi'};

/// One binding: a module's calls in one environment and, on a device, one
/// target.
class DVBindingNode {
  const DVBindingNode({
    required this.module,
    required this.moduleKind,
    required this.environment,
    this.target,
    this.kind,
    this.carrier,
    this.operations = const <String>[],
    this.declared = const <String, String>{},
    this.problem,
  });

  /// The module id, `DV.Modules.<id>`.
  final String module;

  /// What generated it: `ffi`, `jvm`, `npm`, `wasm`, `apple`.
  final String moduleKind;

  /// `native`, `web` or `backend`.
  final String environment;

  /// The device target, for `native`.
  final String? target;

  /// The binding kind its real operations cross, or null when none is real
  /// here.
  final String? kind;

  /// How the implementation reaches this place, or null when nothing does.
  final String? carrier;

  /// The operations real here.
  final List<String> operations;

  /// Every other operation, with the outcome the module declares for it.
  final Map<String, String> declared;

  /// DV-BIND-005 or DV-BIND-007, when a real operation has no carrier.
  final String? problem;

  Map<String, Object?> toJson() => <String, Object?>{
        'module': module,
        'moduleKind': moduleKind,
        'environment': environment,
        if (target != null) 'target': target,
        if (kind != null) 'kind': kind,
        if (carrier != null) 'carrier': carrier,
        if (operations.isNotEmpty) 'operations': operations,
        if (declared.isNotEmpty) 'declared': declared,
        if (problem != null) 'problem': problem,
      };
}

/// Every binding of every module a project mounts.
class DVBindingGraph {
  const DVBindingGraph(this.nodes);

  final List<DVBindingNode> nodes;

  /// Every DV-BIND diagnostic, one line each.
  List<String> get problems => <String>[
        for (final DVBindingNode n in nodes)
          if (n.problem != null) n.problem!,
      ];

  /// Reads the modules [root] mounts.
  static DVBindingGraph read(String root) {
    final List<DVBindingNode> nodes = <DVBindingNode>[];
    final List<DVModuleMount> mounts = dvDiscoverModuleMounts(root).toList()
      ..sort((DVModuleMount a, DVModuleMount b) => a.id.compareTo(b.id));
    for (final DVModuleMount mount in mounts) {
      final Map<Object?, Object?>? module = _moduleBlock(root, mount);
      if (module == null) continue;
      final String? moduleKind = module['kind'] as String?;
      if (moduleKind == null || _dartKinds.contains(moduleKind)) continue;
      final Map<String, Map<String, String>> ops = _operations(module);
      final List<String> targets = module['targets'] is List
          ? <String>[for (final Object? t in module['targets'] as List) '$t']
          : dvBindingNativeTargets;
      for (final String env in const <String>['native', 'web', 'backend']) {
        for (final String? target
            in env == 'native' ? targets : const <String?>[null]) {
          nodes.add(_node(mount.id, moduleKind, env, target, ops));
        }
      }
    }
    return DVBindingGraph(nodes);
  }

  static DVBindingNode _node(String id, String moduleKind, String env,
      String? target, Map<String, Map<String, String>> ops) {
    final List<String> real = <String>[];
    final Map<String, String> declared = <String, String>{};
    for (final MapEntry<String, Map<String, String>> op in ops.entries) {
      final String outcome = op.value[env] ?? 'undeclared';
      if (outcome == 'real') {
        real.add(op.key);
      } else {
        declared[op.key] = outcome;
      }
    }
    final DVBindingCell? cell = dvBindingCell(moduleKind, env, target);
    if (real.isEmpty) {
      return DVBindingNode(
          module: id,
          moduleKind: moduleKind,
          environment: env,
          target: target,
          declared: declared);
    }
    final String? problem = cell == null
        ? 'DV-BIND-007: module $id is of kind $moduleKind, which no carrier '
            'is built for, and declares ${real.join(', ')} real on '
            '${target ?? env}.'
        : cell.code == null
            ? null
            : '${cell.code}: module $id declares ${real.join(', ')} real '
                'on ${target ?? env}, and ${cell.reason}.';
    return DVBindingNode(
      module: id,
      moduleKind: moduleKind,
      environment: env,
      target: target,
      kind: cell?.kind,
      carrier: cell?.carrier,
      operations: real,
      declared: declared,
      problem: problem,
    );
  }

  static Map<Object?, Object?>? _moduleBlock(String root, DVModuleMount mount) {
    final File pubspec = File(p.join(root, mount.sourcePath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    if (doc is Map && doc['dartvel'] is Map) {
      final Object? module = (doc['dartvel'] as Map)['module'];
      if (module is Map) return module;
    }
    return null;
  }

  static Map<String, Map<String, String>> _operations(
      Map<Object?, Object?> module) {
    final Object? ops = module['operations'];
    if (ops is! Map) return const <String, Map<String, String>>{};
    return <String, Map<String, String>>{
      for (final MapEntry<Object?, Object?> e in ops.entries)
        '${e.key}': <String, String>{
          if (e.value is Map)
            for (final MapEntry<Object?, Object?> o in (e.value as Map).entries)
              '${o.key}': '${o.value}',
        },
    };
  }
}
