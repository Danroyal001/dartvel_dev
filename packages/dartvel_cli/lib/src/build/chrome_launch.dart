/// The arguments every headless Chrome this CLI starts is launched with.
///
/// One list because it had already drifted: three launch sites, each with its
/// own hand-written pair of flags, so a fix applied to one reached none of the
/// others.
library;

import 'dart:io';

import 'package:puppeteer/puppeteer.dart' show downloadChrome, puppeteer;

/// Flags for a headless Chrome, in the environments this actually runs in.
///
/// `--no-sandbox` and `--disable-setuid-sandbox` are the usual pair for a
/// container, where the sandbox has no user namespace to work with.
///
/// `--disable-dev-shm-usage` is the one that was missing everywhere, and it
/// is not a tuning flag. A container gives `/dev/shm` 64 megabytes -- Docker's
/// default, so every Codespace, every Actions container job and most CI --
/// and Chrome puts its shared memory there. It runs out during startup and
/// dies before printing the DevTools address it was asked for, so the caller
/// times out waiting and reports that no browser could be found. There is a
/// browser. It cannot allocate.
///
/// The cost of that is a failed build rather than a slow one: `dartvel build
/// web` refuses when the semantics capture comes back empty, because four
/// pages with no crawler-visible content is worse than stopping. The refusal
/// is right and it was firing on machines where the only thing wrong was a
/// flag. Pointing the shared memory at the ordinary temp directory costs
/// nothing on a machine that never needed it.
const List<String> dvChromeLaunchArgs = <String>[
  '--no-sandbox',
  '--disable-setuid-sandbox',
  '--disable-dev-shm-usage',
];

/// A system Chrome, when one is installed, so nothing is downloaded on a
/// machine that already has a browser.
///
/// The semantics capture did not ask for one. It called `puppeteer.launch`
/// with no executable at all, so puppeteer went looking for a copy of its own
/// -- and when it could not get one it failed with "Websocket url not found",
/// which reads as a browser that crashed rather than one that was never
/// there. `dartvel build web` then refused to ship pages with no
/// crawler-visible content, on a machine with a working Chrome at
/// /usr/bin/google-chrome.
///
/// [environment] is injectable so the precedence can be tested without
/// setting a variable on the process running the test.
String? dvSystemChrome({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? named = env['DARTVEL_CHROME'];
  // Empty is not a path. An unset variable and one set to nothing arrive
  // here the same way in a shell, and treating '' as an executable makes
  // puppeteer fail with something that names neither.
  if (named != null && named.isNotEmpty) return named;
  for (final String candidate in <String>[
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
    '/opt/google/chrome/chrome',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// The Chrome to launch: the machine's own when it has one, and otherwise a
/// single copy shared by every Dartvel project on the machine.
///
/// Every launch site already passed [dvSystemChrome], so none ever lacked an
/// executable. On a machine with no system Chrome that is null, and puppeteer
/// then fetches its own copy into `<workspace-root>/.dart_tool/puppeteer` -- a
/// different root for the site, the CLI and each user project, so the same
/// 380 MB browser was downloaded once per package and kept once per package.
/// On the machine this was written on that filled the disk: one run of the
/// CLI's own suite re-fetched a copy deleted an hour earlier, and the next
/// write failed with "No space left on device".
///
/// So the download goes to [puppeteer.userCachePath], and a build already
/// there is reused whichever version it is. Sharing the folder alone was not
/// enough: each puppeteer release pins its own Chrome, the site and the CLI
/// resolved different releases, and each fetched its own build into the
/// shared cache. [downloadChrome] returns at once for a version already
/// present, so naming the cached one costs nothing.
///
/// [findSystem], [cachedVersion] and [download] are injectable so the choice
/// can be tested without a browser or a network.
Future<String> dvChromeExecutable({
  String? Function()? findSystem,
  String? Function(String cachePath)? cachedVersion,
  Future<String> Function(String cachePath, String? version)? download,
}) async {
  final String? system = (findSystem ?? dvSystemChrome)();
  if (system != null) return system;
  final String cachePath = puppeteer.userCachePath;
  // Null when the cache is empty, which leaves puppeteer to fetch the build
  // it pins -- the only case in which anything is downloaded.
  final String? have = (cachedVersion ?? dvNewestCachedChrome)(cachePath);
  final Future<String> Function(String, String?) fetch = download ??
      (String cache, String? version) async =>
          (await downloadChrome(cachePath: cache, version: version))
              .executablePath;
  return fetch(cachePath, have);
}

/// The newest Chrome build in [cachePath], or null when there is none.
///
/// Compared as numbers, because as strings `99.0` sorts above `152.0`. Only
/// folders named as a version count: puppeteer downloads into a
/// `<version>.downloading` folder and renames it when complete, so a
/// half-finished download is never offered as a browser.
String? dvNewestCachedChrome(String cachePath) {
  final Directory dir = Directory(cachePath);
  if (!dir.existsSync()) return null;
  final RegExp version = RegExp(r'^\d+(\.\d+)+$');
  List<int> parts(String v) => v.split('.').map(int.parse).toList();
  int compare(String a, String b) {
    final List<int> x = parts(a);
    final List<int> y = parts(b);
    for (int i = 0; i < x.length || i < y.length; i++) {
      final int xi = i < x.length ? x[i] : 0;
      final int yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi.compareTo(yi);
    }
    return 0;
  }

  String? best;
  for (final FileSystemEntity entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final String name =
        entity.path.substring(entity.path.lastIndexOf(Platform.pathSeparator) + 1);
    if (!version.hasMatch(name)) continue;
    if (best == null || compare(name, best) > 0) best = name;
  }
  return best;
}
