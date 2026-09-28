/// A plain Dart package, as a module.
///
/// The cheapest carrier there is: the module calls the package directly, in
/// every environment the package can run in. Where it cannot -- a package
/// that needs `dart:io` has no browser, one that needs Flutter has no
/// backend -- the module declares what happens instead, and the carrier for
/// that environment never imports the package, so the application still
/// builds there.
library;

import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;

import 'dart_surface.dart';
import 'module_writer.dart';

/// The module spec for a Dart package whose surface is [surface].
///
/// [dependency] is the YAML value the module's pubspec depends on the
/// package with: `^1.2.3`, `{path: ../textkit}`, a git map. [elsewhere] is
/// what an operation does in an environment the package cannot run in,
/// `unavailable` or `noop`; it is written into the module's pubspec per
/// operation, so it is a declaration rather than a default.
DVForeignModuleSpec dvDartPackageModuleSpec({
  required String id,
  required String source,
  required DVDartSurface surface,
  required String dependency,
  DVModuleOutcome elsewhere = DVModuleOutcome.unavailable,
}) {
  final DVDartPlatformNeeds needs = surface.needs;
  final Map<DVModuleEnvironment, bool> runs = <DVModuleEnvironment, bool>{
    DVModuleEnvironment.native: needs.native,
    DVModuleEnvironment.web: needs.web,
    DVModuleEnvironment.backend: needs.backend,
  };
  final DVCarrierSource direct = DVCarrierSource(
    imports: <String>["import '${surface.library}' as source;"],
    body: (DVModuleOperation op) => 'source.${op.name}(${op.argumentList})',
  );
  return DVForeignModuleSpec(
    id: id,
    kind: 'dartPackage',
    source: source,
    description: '${surface.packageName} ${surface.version}, as a Dartvel '
        'module.',
    operations: surface.operations,
    outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
      for (final DVModuleOperation op in surface.operations)
        op.name: <DVModuleEnvironment, DVModuleOutcome>{
          for (final DVModuleEnvironment env in dvModuleEnvironments)
            env: runs[env]! ? DVModuleOutcome.real : elsewhere,
        },
    },
    carriers: <DVModuleEnvironment, DVCarrierSource>{
      for (final DVModuleEnvironment env in dvModuleEnvironments)
        if (runs[env]!) env: direct,
    },
    dependencies: <String, String>{surface.packageName: dependency},
    skipped: surface.skipped,
    // The package's own types are re-exported only when every environment
    // can import it: re-exporting a dart:io package would put dart:io into
    // the web build of everything that imports the module.
    exports: runs.values.every((bool r) => r)
        ? <String>[surface.library]
        : const <String>[],
  );
}
