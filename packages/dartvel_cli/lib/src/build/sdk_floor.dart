/// The Dart an embedder bundles, against the one Dartvel needs.
///
/// A vendor embedder carries its own Flutter SDK and therefore its own Dart.
/// When that Dart is older than Dartvel's floor, nothing about the build can
/// work: `pub get` inside the generated scaffold fails version solving before
/// a single file is compiled, and what the developer sees is
///
///     Because dartvel_example requires SDK version >=3.12.0 <4.0.0,
///     version solving failed.
///
/// followed by a scaffold Dartvel deletes and a failed build. That is a true
/// message about the wrong thing: the project is fine, the embedder is old,
/// and there is nothing to fix in the application.
///
/// The build toolchain rule says a target whose toolchain cannot serve must
/// skip cleanly with a clear message. This is how that decision is made for
/// the wall that is not the toolchain being absent -- it is present, and it
/// is too old.
library;

/// The Dart every Dartvel package declares.
///
/// One number rather than a floor per package. It used to be several that
/// disagreed, which is how webOS was recorded as merely unproven when its
/// bundled Dart could not resolve dependencies at all.
const String dvDartFloor = '3.12.0';

/// The Dart version named in a `flutter --version` line, or null.
///
/// Every vendor CLI wraps Flutter's own, so they all print the same shape:
///
///     Flutter 3.24.0 • channel stable • https://github.com/...
///     Tools • Dart 3.5.0 • DevTools 2.37.2
///
/// Read rather than assumed, because the interesting case is a fork whose
/// Flutter version says nothing about how old its Dart is.
String? dvEmbedderDartVersion(String versionOutput) {
  final RegExpMatch? match = RegExp(
    r'\bDart\s+(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)',
  ).firstMatch(versionOutput);
  return match?.group(1);
}

/// Whether [version] is at least [floor].
///
/// Compares the three numbers rather than the strings: `3.9.0` sorts after
/// `3.12.0` as text, and reasoning from that is how a target that cannot
/// resolve at all gets recorded as unproven.
///
/// A prerelease of the floor itself is below it -- `3.12.0-1.0.dev` is not
/// 3.12.0 -- which is what pub does too.
bool dvMeetsDartFloor(String version, {String floor = dvDartFloor}) {
  final List<int>? have = _numbers(version);
  final List<int>? need = _numbers(floor);
  if (have == null || need == null) return true;

  for (int i = 0; i < 3; i++) {
    if (have[i] != need[i]) return have[i] > need[i];
  }
  // Equal numbers: a prerelease or build suffix on the version means it comes
  // before the release it is a prerelease of.
  return !version.contains('-');
}

List<int>? _numbers(String version) {
  final RegExpMatch? match =
      RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
  if (match == null) return null;
  return <int>[
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

/// What to say when an embedder's Dart is too old, or null when it is not.
///
/// Names both numbers and which wall was hit. "Skipping webos" on its own
/// sends somebody to look for a missing toolchain that is installed.
String? dvEmbedderTooOld({
  required String target,
  required String executable,
  required String versionOutput,
  String floor = dvDartFloor,
}) {
  final String? dart = dvEmbedderDartVersion(versionOutput);
  // Unreadable is not too old. A vendor CLI that prints something else is a
  // reason to try the build and let it say what is wrong, not a reason to
  // refuse it here.
  if (dart == null) return null;
  if (dvMeetsDartFloor(dart, floor: floor)) return null;
  return 'Skipping $target: $executable bundles Dart $dart and Dartvel needs '
      '$floor or newer. The embedder is installed and it is the version that '
      'is the problem, so there is nothing to fix in this project -- the '
      'vendor has to ship a newer Flutter.';
}

/// What to say when a build failed because pub refused the SDK, or null.
///
/// The second half of the same wall. Four of the embedders are Flutter CLI
/// wrappers and answer `--version` with the Dart they carry, so they are
/// caught before anything is generated. Fuchsia's is a Bazel workspace with
/// no CLI to ask, and the first thing that says so is pub, mid-build:
///
///     The current Dart SDK version is 2.19.0-415.0.dev.
///     Because dartvel_example requires SDK version >=3.12.0 <4.0.0,
///     version solving failed.
///
/// That is evidence rather than inference -- the toolchain itself refusing
/// for a stated reason -- so it is read rather than guessed at, and the
/// version in it is quoted back.
String? dvSdkFloorRefusal({
  required String target,
  required String output,
  String floor = dvDartFloor,
}) {
  if (!output.contains('version solving failed')) return null;
  if (!output.contains('requires SDK version')) return null;

  final RegExpMatch? current = RegExp(
    r'current Dart SDK version is (\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?)',
  ).firstMatch(output);
  final String said = current == null ? 'a Dart older than' : current.group(1)!;

  return 'Skipping $target: the embedder resolved with '
      '${current == null ? said : 'Dart $said'} and Dartvel needs $floor or '
      'newer. Its own pub refused to solve, which is the toolchain saying it '
      'cannot build this project -- there is nothing to fix here.';
}
