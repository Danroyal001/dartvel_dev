/// Assembling an eLinux application without `flutter-elinux`.
///
/// `flutter-elinux` is pinned to Flutter 3.29.3 and upstream has not committed
/// since 2025-07-09. Its classes subclass `flutter_tools` internals, so moving
/// it to Dartvel's 3.44.5 is a port across fifteen minor versions rather than a
/// version bump.
///
/// It is also not the only route. An eLinux application is:
///
///   * Sony's embedder executable for the display backend,
///   * `libflutter_engine.so`,
///   * the app — `libapp.so` in release, `kernel_blob.bin` in debug,
///   * `icudtl.dat`,
///   * the Flutter asset bundle.
///
/// Every one comes from stock Flutter 3.44.5 plus artifacts already verified
/// against Dartvel's engine, so Dartvel can assemble the bundle itself.
library;

/// Sony builds one embedder executable per display backend.
///
/// They are not interchangeable: a Wayland binary on a DRM-only device fails at
/// startup rather than at build, which is the wrong end of the process to find
/// out.
enum ELinuxBackend {
  wayland('flutter-client'),
  drmGbm('flutter-drm-gbm-backend'),
  drmEglstream('flutter-drm-eglstream-backend');

  const ELinuxBackend(this.executable);

  /// The file Sony's build produces for this backend.
  final String executable;
}

/// Which engine flavour the bundle is built against.
///
/// Worth stating because the modes are not merely optimisation levels here:
/// a release engine has no interpreter and cannot run kernel, so the app is
/// shipped as an AOT shared library instead.
enum ELinuxMode { debug, profile, release }

/// One file in the assembled bundle.
class ELinuxBundleEntry {
  /// Where the file comes from — an artifact name or a build output.
  final String source;

  /// Path inside the bundle, relative to its root.
  final String target;

  const ELinuxBundleEntry({required this.source, required this.target});
}

/// What an assembled eLinux bundle contains.
class ELinuxBundleLayout {
  final ELinuxBackend backend;
  final ELinuxMode mode;
  final List<ELinuxBundleEntry> entries;

  const ELinuxBundleLayout({
    required this.backend,
    required this.mode,
    required this.entries,
  });

  String get embedderExecutable => backend.executable;
}

/// The layout for [backend] in [mode].
ELinuxBundleLayout elinuxBundleLayout({
  required ELinuxBackend backend,
  required ELinuxMode mode,
}) {
  final entries = <ELinuxBundleEntry>[
    ELinuxBundleEntry(source: backend.executable, target: backend.executable),
    const ELinuxBundleEntry(
        source: 'libflutter_engine.so', target: 'lib/libflutter_engine.so'),
    const ELinuxBundleEntry(source: 'icudtl.dat', target: 'data/icudtl.dat'),
    const ELinuxBundleEntry(
        source: 'flutter_assets', target: 'data/flutter_assets'),
  ];

  if (mode == ELinuxMode.debug) {
    // Debug runs from kernel through the interpreter.
    entries.add(const ELinuxBundleEntry(
      source: 'kernel_blob.bin',
      target: 'data/flutter_assets/kernel_blob.bin',
    ));
  } else {
    // Profile and release are AOT. Shipping kernel alongside would be dead
    // weight, and would imply the app is debuggable when it is not.
    entries.add(const ELinuxBundleEntry(
      source: 'libapp.so',
      target: 'lib/libapp.so',
    ));
  }

  return ELinuxBundleLayout(backend: backend, mode: mode, entries: entries);
}

/// Arguments for `gen_snapshot` producing an eLinux AOT library.
///
/// `app-aot-elf` is the only kind the engine will load here. An assembly or
/// blob snapshot produces files that look plausible and fail at startup on the
/// device, which is a long way from the machine that built them.
///
/// There is deliberately no target-architecture argument: `gen_snapshot` is
/// downloaded per architecture from `linux-{arch}/artifacts.zip`, so the binary
/// already *is* the target. A parameter that reads as though it selects the
/// architecture, and does not, is worse than no parameter — it invites a caller
/// to pass arm64 to an x64 binary and expect a cross-compile.
List<String> genSnapshotArguments({
  required String kernel,
  required String output,
}) {
  return <String>[
    '--deterministic',
    '--snapshot_kind=app-aot-elf',
    '--elf=$output',
    // These ship to devices, often with little storage.
    '--strip',
    kernel,
  ];
}


/// One copy performed while assembling a bundle.
class ELinuxCopy {
  /// Absolute source path.
  final String from;

  /// Destination inside the bundle, relative to its root.
  final String to;

  const ELinuxCopy({required this.from, required this.to});
}

/// How to assemble an eLinux release bundle from a desktop release build.
///
/// This is the route that works today, and it is worth saying why it exists
/// rather than the obvious one. A desktop release build already produces every
/// piece an eLinux release bundle needs — `data/flutter_assets`,
/// `data/icudtl.dat`, and an AOT `lib/libapp.so` for the same architecture —
/// and differs only in which executable and which engine library sit beside
/// them. So a release bundle needs neither an engine build nor
/// `flutter-elinux`, which is pinned to Flutter 3.29.3 and fifteen minor
/// versions behind.
///
/// [desktopBundle] is `build/linux/<arch>/release/bundle`; [artifacts] is the
/// directory holding Sony's embedder executables and `libflutter_engine.so`.
List<ELinuxCopy> elinuxAssemblyPlan({
  required String desktopBundle,
  required String artifacts,
  required ELinuxBackend backend,
  required ELinuxMode mode,
}) {
  if (mode != ELinuxMode.release) {
    // A debug desktop bundle carries kernel_blob.bin and no libapp.so, and the
    // only engine obtainable without building one is the release build, which
    // has no interpreter to run kernel with. Assembling that pair produces a
    // bundle that looks complete and cannot start.
    throw UnsupportedError(
      'Only release bundles can be assembled this way. Debug and profile need '
      'an engine built for those modes, which Google does not publish as a '
      'standalone embedder artifact.',
    );
  }

  return <ELinuxCopy>[
    // The app and its assets, from the desktop build.
    ELinuxCopy(from: '$desktopBundle/lib/libapp.so', to: 'lib/libapp.so'),
    ELinuxCopy(
        from: '$desktopBundle/data/flutter_assets',
        to: 'data/flutter_assets'),
    ELinuxCopy(
        from: '$desktopBundle/data/icudtl.dat', to: 'data/icudtl.dat'),

    // The embedder and engine, from the eLinux artifacts. Deliberately not
    // from the desktop bundle: its libflutter_linux_gtk.so is the desktop
    // embedder with the engine linked into it, and carrying that would ship
    // the GUI stack this target exists to avoid.
    ELinuxCopy(
        from: '$artifacts/${backend.executable}', to: backend.executable),
    ELinuxCopy(
        from: '$artifacts/libflutter_engine.so',
        to: 'lib/libflutter_engine.so'),
  ];
}


/// The architecture an assembled bundle can actually be built for.
///
/// The app, assets and AOT library come from a desktop build, and that build is
/// host-native: `flutter build linux` does not cross-compile. So a [requested]
/// architecture that differs from [host] cannot be satisfied this way, and
/// saying so beats assembling from a directory that does not exist — which
/// surfaces as a missing `libapp.so` and reads like a build failure.
String elinuxAssemblyArch({required String requested, required String host}) {
  if (requested != host) {
    throw UnsupportedError(
      'Cannot assemble a $requested eLinux bundle on a $host host. The app and '
      'its AOT library come from a host-native desktop build. Build on a '
      '$requested machine, or use an engine and gen_snapshot for $requested '
      'with a cross-compiling toolchain.',
    );
  }
  return host;
}
