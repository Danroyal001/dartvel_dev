/// DV-BIND-005 and DV-BIND-007, at build time.
///
/// A generated module declares, per operation and environment, whether a
/// call is real there, and the targets its device carrier reaches. The
/// binding graph places each real operation on the carrier matrix; this
/// refuses the build when one lands in a cell nothing fills, for the
/// platforms being built and no others. The module call check answers a
/// different question -- whether the application calls an operation where
/// the module says it cannot run -- and this one whether the module's own
/// declaration can be honoured at all.
library;

import '../graph/binding_graph.dart';
import 'build_target.dart';

class DVBindingCheck {
  const DVBindingCheck(this.lines);

  /// One line per refused binding.
  final List<String> lines;

  bool get ok => lines.isEmpty;

  /// Checks the modules [root] mounts against the build for [platforms].
  static DVBindingCheck run(String root, Iterable<String> platforms) {
    final Set<String> environments = <String>{};
    final Set<String> devices = <String>{};
    for (final String platform in platforms) {
      final String base = DVBuildTargets.lookup(platform)?.basePlatform ?? platform;
      if (base == 'web') {
        environments.add('web');
      } else if (platform == 'server' || platform == 'backend') {
        environments.add('backend');
      } else {
        environments.add('native');
        devices.add(base);
      }
    }
    final List<String> lines = <String>[
      for (final DVBindingNode node in DVBindingGraph.read(root).nodes)
        if (node.problem != null &&
            environments.contains(node.environment) &&
            (node.target == null || devices.contains(node.target)))
          '   ${node.problem}',
    ];
    return DVBindingCheck(lines);
  }
}
