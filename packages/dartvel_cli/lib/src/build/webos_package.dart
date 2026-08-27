/// Assembling a webOS application without `flutter-webos`.
///
/// LG's CLI cannot run here: it bundles Dart 3.10.9, below Dartvel's 3.12
/// floor, so it cannot resolve the example's dependencies at all. That is a
/// version wall rather than a vendor secret, and it does not stop Dartvel
/// assembling the package itself — LG's engine exports `FlutterEngineRun` and
/// their runner template carries Sony's copyright, so a webOS application is
/// an eLinux application with a webOS manifest on it.
///
/// The manifest is where this fails quietly. webOS reports most rejections as
/// a generic install failure on the television, hours after the build that
/// caused them, so the checks here run at build time.
library;

/// Which engine flavour the package is built against.
enum WebosMode { debug, release }

/// One file in the package.
class WebosEntry {
  const WebosEntry({required this.source, required this.target});

  /// Where it comes from in the build output.
  final String source;

  /// Where it goes, relative to the package root.
  final String target;
}

/// The files a webOS package contains, and the directory they sit in.
class WebosPackageLayout {
  const WebosPackageLayout({
    required this.root,
    required this.mode,
    required this.entries,
  });

  /// The directory `ares-package` builds the IPK from.
  ///
  /// Named for the application id, because webOS expects that: a mismatch
  /// installs an application the launcher cannot find.
  final String root;

  final WebosMode mode;
  final List<WebosEntry> entries;
}

/// The architecture a webOS engine has to be.
///
/// Televisions run a 32-bit ARM userland and Google publishes `linux-x64` and
/// `linux-arm64` embedder engines and no 32-bit `linux-arm`. That single fact
/// was the whole of the webOS blocker.
const String webosEngineArchitecture = 'arm';

/// Whether `gen_snapshot` runs on the machine doing the build.
///
/// It does, and it emits ARM. Asking for an ARM `gen_snapshot` would be asking
/// for a binary to run on the television.
const bool webosGenSnapshotRunsOnHost = true;

/// The `appinfo.json` for an application.
Map<String, Object?> webosAppInfo({
  required String id,
  required String title,
  String version = '1.0.0',
  String executable = 'dartvel_app',
  String icon = 'icon.png',
  String vendor = 'Dartvel',
}) =>
    <String, Object?>{
      'id': id,
      'title': title,
      'version': version,
      // The default is "web". A Flutter application packaged as a web app
      // loads nothing and shows a blank screen, which reads as a rendering
      // bug rather than a manifest one.
      'type': 'native',
      'main': executable,
      'icon': icon,
      'vendor': vendor,
    };

/// What webOS would refuse about [info], all of it at once.
List<String> webosPackageProblems(Map<String, Object?> info) {
  final problems = <String>[];

  final id = '${info['id'] ?? ''}';
  if (!id.contains('.')) {
    problems.add('The application id "$id" is not reverse-DNS. webOS installs '
        'it nowhere and the failure names no reason.');
  }
  if (id != id.toLowerCase()) {
    problems.add('The application id "$id" is not lowercase. The packager '
        'accepts it and the television refuses it.');
  }

  final title = '${info['title'] ?? ''}';
  if (title.trim().isEmpty) {
    problems.add('The application has no title, so its tile on the home '
        'screen is blank.');
  }

  final version = '${info['version'] ?? ''}';
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    problems.add('The version "$version" is not three numeric parts. "1.0" '
        'and "1.0.0-beta" both package and then fail to install.');
  }

  if ('${info['type'] ?? ''}' != 'native') {
    problems.add('The application type is not "native", so webOS loads it as '
        'a web app and shows a blank screen.');
  }

  final main = '${info['main'] ?? ''}';
  if (main.isEmpty) {
    problems.add('The application names no entry point.');
  }

  return problems;
}

/// The layout for an application in [mode].
WebosPackageLayout webosPackageLayout({
  required String id,
  required WebosMode mode,
  String executable = 'dartvel_app',
}) {
  final entries = <WebosEntry>[
    const WebosEntry(source: 'appinfo.json', target: 'appinfo.json'),
    WebosEntry(source: executable, target: executable),
    const WebosEntry(
        source: 'libflutter_engine.so', target: 'lib/libflutter_engine.so'),
    const WebosEntry(source: 'icudtl.dat', target: 'data/icudtl.dat'),
    const WebosEntry(source: 'flutter_assets', target: 'data/flutter_assets'),
    const WebosEntry(source: 'icon.png', target: 'icon.png'),
  ];

  if (mode == WebosMode.debug) {
    // Debug runs kernel through the interpreter.
    entries.add(const WebosEntry(
      source: 'kernel_blob.bin',
      target: 'data/flutter_assets/kernel_blob.bin',
    ));
  } else {
    // Release is AOT. Shipping kernel too would be dead weight and would
    // imply the application is debuggable when it is not.
    entries.add(const WebosEntry(source: 'libapp.so', target: 'lib/libapp.so'));
  }

  return WebosPackageLayout(root: id, mode: mode, entries: entries);
}

/// The problems in a package's *contents*, given [info] and the set of
/// [files] it holds as paths relative to the application root.
///
/// [webosPackageProblems] reads the metadata and stops there — it checks that
/// `main` names something, never that the something exists. The example
/// shipped for weeks with an appinfo.json naming a `dartvel_app` that was
/// never built, passing every check, because nothing compared the two.
///
/// A television reports a missing entry point as a generic install failure,
/// hours after the build that caused it and without naming the file.
List<String> webosPackageContentProblems(
  Map<String, Object?> info,
  Set<String> files,
) {
  final problems = <String>[];

  // Read from appinfo rather than assumed: checking for the default name
  // passes whenever the two agree and misses exactly the case where they do
  // not.
  final main = '${info['main'] ?? ''}';
  if (main.isNotEmpty && !files.contains(main)) {
    problems.add('appinfo.json names "$main" as its main, and the package '
        'does not contain it. webOS reports this as an install failure that '
        'names no file.');
  }

  final icon = '${info['icon'] ?? ''}';
  if (icon.isNotEmpty && !files.contains(icon)) {
    problems.add('appinfo.json names "$icon" as its icon, and the package '
        'does not contain it.');
  }

  for (final String required in <String>[
    'lib/libflutter_engine.so',
    'lib/libapp.so',
    'data/icudtl.dat',
  ]) {
    if (!files.contains(required)) {
      problems.add('The package is missing $required.');
    }
  }

  if (!files.any((String p) => p.startsWith('data/flutter_assets/'))) {
    problems.add('The package has no data/flutter_assets, so the application '
        'starts with no assets and draws nothing.');
  }

  return problems;
}
