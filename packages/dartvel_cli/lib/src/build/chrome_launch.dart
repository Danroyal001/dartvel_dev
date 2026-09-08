/// The arguments every headless Chrome this CLI starts is launched with.
///
/// One list because it had already drifted: three launch sites, each with its
/// own hand-written pair of flags, so a fix applied to one reached none of the
/// others.
library;

import 'dart:io';

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
