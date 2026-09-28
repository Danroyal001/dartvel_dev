/// Where a Node-carried module finds Node, on a device or on the backend.
///
/// The placement matrix runs npm packages and WebAssembly in Node on the
/// backend and on the desktop. On the desktop the Node is the copy
/// `dartvel build` put beside the application -- `lib/node` in a Linux
/// bundle, beside the executable on macOS and Windows -- so the person
/// running it needs nothing installed. `DARTVEL_NODE` names another, and
/// the one on PATH is the last resort, which is what a backend has.
library;

/// The declaration a Node-carried carrier writes: `_node`, the executable.
const String dvNodeLocator = r'''
/// Node: DARTVEL_NODE, else the copy bundled beside the application, else
/// the one on PATH.
String get _node {
  final String? named = Platform.environment['DARTVEL_NODE'];
  if (named != null && named.isNotEmpty) return named;
  final String dir = File(Platform.resolvedExecutable).parent.path;
  for (final String candidate in <String>[
    '$dir/lib/node',
    '$dir/node',
    '$dir/node.exe',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return 'node';
}''';

/// The desktops a Node-carried module is real on: the ones `dartvel build`
/// bundles Node for. A phone needs nodejs-mobile, which is not built.
const List<String> dvNodeTargets = <String>['linux', 'macos', 'windows'];
