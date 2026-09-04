/// The configuration a bundle build needs and cannot make for itself.
///
/// A terminal build hands the project to the embedder, which runs `flutter
/// build bundle`. For a project with build hooks — which every Dartvel
/// application has, because the Rust runtime is one — that step reads the
/// compiler configuration those hooks need, and looks for it at
/// `<asset dir>/linux/x64/<mode>/CMakeCache.txt`:
///
///     Target dart_build failed: Error: Could not read compiler
///     configurations for build hooks, expected
///     build/flutter_assets/linux/x64/debug/CMakeCache.txt to exist.
///
/// Nothing writes it there. The desktop build writes one, two directories
/// away, at `build/linux/x64/<mode>/CMakeCache.txt`.
///
/// So a Dartvel application could not be built for a terminal at all, and the
/// job that proves the terminal works has been rendering the embedder's own
/// sample instead — which proves the embedder and says nothing about Dartvel.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class DVNativeAssetsConfig {
  const DVNativeAssetsConfig({required this.ready, this.reason = ''});

  /// Whether the bundle build will find what it needs.
  final bool ready;

  /// Why not, when it will not.
  final String reason;
}

/// Puts the desktop build's compiler configuration where the bundle build
/// looks for it.
///
/// A copy rather than a link: the asset directory is rebuilt often and a
/// dangling symlink reads to Flutter as a missing file, which is the error
/// this exists to prevent wearing a different hat. Copied every time, because
/// a desktop build that ran again wrote a different cache and a stale one
/// would compile the hooks with somebody else's compiler.
DVNativeAssetsConfig dvConfigureNativeAssets(
  String root, {
  required String mode,
  String architecture = 'x64',
  String assetDir = 'build/flutter_assets',
}) {
  final File source =
      File(p.join(root, 'build', 'linux', architecture, mode, 'CMakeCache.txt'));
  if (!source.existsSync()) {
    return DVNativeAssetsConfig(
      ready: false,
      reason: 'There is no ${p.relative(source.path, from: root)}, so the '
          'bundle build has no compiler configuration for this project\'s '
          'build hooks. It is written by the desktop build: run '
          '`flutter build linux --$mode` first, or let dartvel build do it.',
    );
  }

  final File destination = File(
      p.join(root, assetDir, 'linux', architecture, mode, 'CMakeCache.txt'));
  destination.parent.createSync(recursive: true);
  source.copySync(destination.path);
  return const DVNativeAssetsConfig(ready: true);
}
