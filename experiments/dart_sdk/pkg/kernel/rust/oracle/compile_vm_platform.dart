// Builds the VM platform for the round-trip oracle's corpus (not a mirrored
// file; see ../README.md). It makes the same front-end calls as
// pkg/front_end/tool/compile_platform.dart (`compilePlatformInternal` in
// tool/entry_points.dart), with the same arguments, but installs only the VM
// target: the stock tool also installs dart2js, dartdevc and dart2wasm, whose
// packages pull in third_party code this checkout does not have.
//
// Usage: same as compile_platform.dart.
import 'dart:io';

import 'package:front_end/src/base/compiler_context.dart' show CompilerContext;
import 'package:front_end/src/base/file_system_dependency_tracker.dart';
import 'package:front_end/src/kernel/utils.dart' show writeComponentToFile;
import 'package:front_end/src/kernel_generator_impl.dart'
    show InternalCompilerResult, generateKernelInternal;
import 'package:kernel/verifier.dart' show VerificationStage, verifyComponent;
import 'package:vm/modular/target/install.dart' as vm_target_install;

import '../../../front_end/tool/command_line.dart'
    show runProtectedFromAbort, withGlobalOptions;

Future<void> main(List<String> arguments) async {
  vm_target_install.installAdditionalTargets();
  await runProtectedFromAbort<void>(() async {
    final FileSystemDependencyTracker tracker =
        new FileSystemDependencyTracker();
    await withGlobalOptions(
      "compile_platform",
      arguments,
      false,
      tracker: tracker,
      (CompilerContext c, List<String> restArguments) async {
        c.compilingPlatform = true;
        final Uri outlineOutput = Uri.base.resolveUri(
          new Uri.file(restArguments[4]),
        );
        final InternalCompilerResult result = await generateKernelInternal(
          c,
          buildSummary: true,
          buildComponent: true,
        );
        new File.fromUri(outlineOutput).writeAsBytesSync(result.summary!);
        verifyComponent(
          c.options.target,
          VerificationStage.afterModularTransformations,
          result.component!,
        );
        await writeComponentToFile(result.component!, c.options.output!);
      },
    );
  });
}
