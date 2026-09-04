/// `dartvel doctor`, on the modules a project declares.
///
/// A declaration that says "mount store at /store" and a build that cannot
/// was a log line during generation and an exit code of zero: the
/// application shipped without the section, green. A partner rotates a
/// signing key, the manifest stops verifying, and nothing that watches a
/// build notices.
///
/// The kiosk policy has been checked this way for a while -- a declaration
/// that cannot be honoured fails the check rather than being carried on from
/// -- and mounting is the same kind of promise.
library;

import '../graph/module_mounts.dart';

class DVModuleCheck {
  const DVModuleCheck({required this.ok, required this.lines});

  /// Whether the project may ship as declared.
  final bool ok;

  /// What to print. Empty when the project declares no modules.
  final List<String> lines;

  /// Reads the modules the project at [root] declares.
  static DVModuleCheck run(String root) {
    final List<DVModuleMount> mounts = dvDiscoverModuleMounts(root);
    if (mounts.isEmpty) {
      return const DVModuleCheck(ok: true, lines: <String>[]);
    }

    final List<String> lines = <String>['Modules'];
    var ok = true;
    for (final DVModuleMount mount in mounts) {
      final String routes = mount.deployment == DVModuleDeployment.backendOnly
          ? 'no pages, by declaration'
          : '${mount.routes.length} route(s)';
      lines.add('  ${mount.mounted ? '[ok]' : '[!]'} ${mount.id} at '
          '${mount.mount} (${mount.deployment.name}, $routes)');
      for (final String problem in mount.problems) {
        // A module that still mounts has a problem worth saying and not
        // worth refusing to ship over: a mode that fell back to its default
        // is a sentence somebody should read, not a broken application.
        lines.add('    ${mount.mounted ? '[~]' : '[!]'} $problem');
      }
      if (!mount.mounted) ok = false;
    }
    return DVModuleCheck(ok: ok, lines: lines);
  }
}
