/// A rendering backend linked into a build.
///
/// Which of these a binary contains is decided at build time and never at
/// startup: resolving it on launch would mean every application shipped every
/// backend, and paid for modes most of them never use.
enum DVRenderBackend { gui, terminal }

/// The value `dartvel build` hands `dartvel routes` in `--render`.
///
/// It exists because the two run in separate processes. The build resolves the
/// linked backends from the `-cli`/`-tui` suffix and the `dartvel.terminal`
/// key, and the generator has to emit a main for that exact set — it cannot
/// re-derive it, because the suffix is an argument to a command it never sees.
String renderBackendsFlag(Set<DVRenderBackend> backends) =>
    (backends.map((DVRenderBackend b) => b.name).toList()..sort()).join(',');

/// Reads a `--render` value back, or null when nothing was said.
///
/// Null rather than a default set, because "not stated" and "the GUI" are
/// different answers. `dartvel routes` run by hand knows nothing about the
/// suffix somebody might have typed, and answering GUI on its behalf would
/// take the terminal away from a project whose pubspec asked for it. Left
/// null, the project's own declaration stands.
///
/// Anything unrecognised is refused: rounding a typo down to the GUI would let
/// a terminal build quietly generate a windowed main again, which is the
/// defect this argument exists to close.
Set<DVRenderBackend>? parseRenderBackends(String? value) {
  if (value == null) return null;
  // Checked here rather than after the loop, where it could never be reached:
  // an empty string splits into one empty name and fails as an unknown
  // backend, under a message about spelling.
  if (value.trim().isEmpty) {
    throw const FormatException(
      'A build must link at least one rendering backend; --render was empty.',
    );
  }
  final Set<DVRenderBackend> backends = <DVRenderBackend>{};
  for (final String name in value.split(',')) {
    final DVRenderBackend? backend = DVRenderBackend.values
        .where((DVRenderBackend b) => b.name == name.trim())
        .firstOrNull;
    if (backend == null) {
      throw FormatException(
        '"$name" is not a rendering backend. Expected one or more of '
        '${DVRenderBackend.values.map((DVRenderBackend b) => b.name).join(', ')}.',
      );
    }
    backends.add(backend);
  }
  return backends;
}
