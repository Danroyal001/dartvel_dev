/// The extension point for build targets the CLI does not build itself.
///
/// See `DVBuildTarget` for the contract and the README section "Build
/// targets from a package" for how a project gets one.
library;

import 'dartvel_impl.dart' as impl;
import 'src/build/build_target.dart';

export 'src/build/build_target.dart';
export 'src/build/render_backends.dart' show DVRenderBackend;
export 'src/build/runtime_packages.dart'
    show
        DVRuntimePackage,
        dvRuntimeManifestFile,
        dvReadRuntimeManifest,
        dvPaidRuntimes,
        dvRuntimesProPackage;
export 'src/build/target_packages.dart'
    show DVTargetPackage, dvTargetManifestFile, dvReadTargetManifest;
export 'src/utils/toolchain.dart'
    show ToolRequirement, InstallMethod, dartvelToolchainRoot;
export 'src/commands/build_command.dart' show resolveToolchainHome;

/// Registers [targets] and runs the Dartvel CLI with [arguments].
///
/// What a target package's executable calls. The CLI is the same one the
/// project already runs, so every free target and every other command
/// behaves exactly as it does without the package.
Future<void> dvRunWithTargets(
  List<String> arguments,
  List<DVBuildTarget> targets,
) async {
  for (final DVBuildTarget target in targets) {
    if (DVBuildTargets.lookup(target.name) == null) {
      DVBuildTargets.register(target);
    }
  }
  await impl.main(arguments);
}
