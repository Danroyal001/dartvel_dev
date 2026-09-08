/// Whether the semantics capture covered every route.
///
/// `dartvel build web` reads the semantics tree of each route in a headless
/// browser and writes the crawler-visible HTML from it. Under resource
/// pressure that can come back short: one real build reported "Captured 1 of
/// 4" and then "web build successful", shipping three pages whose only
/// crawler-visible content was whatever the string-literal fallback could
/// scrape.
///
/// A build that quietly ships 75% of its SEO is worse than one that fails,
/// because the failure is invisible until someone checks a search result weeks
/// later.
library dartvel_cli.build.capture_completeness;

/// What a capture run managed, and whether there was a browser for it.
///
/// The count alone could not tell a machine under load from a machine with no
/// Chrome on it, and those want opposite answers: one is worth failing a
/// build for and the other is the ordinary state of a slim CI image.
class DVCaptureRun {
  const DVCaptureRun({required this.captured, required this.browserAvailable});

  /// Routes whose semantics tree was read.
  final int captured;

  /// Whether a browser was launched at all.
  final bool browserAvailable;
}

/// The result of checking a capture run.
class DVCaptureVerdict {
  const DVCaptureVerdict({required this.ok, this.message});

  final bool ok;

  /// Null when there is nothing to say.
  final String? message;
}

/// Whether [captured] of [expected] routes is good enough to ship.
///
/// [browserAvailable] separates the two ways a capture comes back empty, which
/// used to be indistinguishable here and are not the same problem.
///
/// A browser that ran and came back short is resource pressure: the machine
/// can do this, it did not manage it this time, and rerunning fixes it. That
/// is worth failing a build for.
///
/// No browser at all is a fact about the machine. A slim CI image, a Docker
/// build stage and a locked-down laptop have no Chrome and never will, so
/// there is nothing to rerun and no memory to free -- and failing there makes
/// `dartvel build web` a command that only runs where somebody has already
/// installed a browser. The build still writes every page; what it loses is
/// the richer crawler-visible HTML, and the way to get that is `dartvel
/// prerender` on a machine that has a browser.
DVCaptureVerdict dvVerifyCapture({
  required int captured,
  required int expected,
  bool browserAvailable = true,
}) {
  // A project with no pages has nothing to prerender.
  if (expected <= 0) return const DVCaptureVerdict(ok: true);

  // Defensive: a miscount must not fail a build that captured everything.
  if (captured >= expected) return const DVCaptureVerdict(ok: true);

  if (!browserAvailable) {
    return const DVCaptureVerdict(
      ok: true,
      message: 'No browser, so every page carries the page-text form of its '
          'crawler-visible HTML rather than the semantics tree: the words are '
          'there, the headings, links and landmarks are not. Run `dartvel '
          'prerender` on a machine with Chrome to fill them in, or set '
          'DARTVEL_CHROME to one this machine can reach.',
    );
  }

  final int missing = expected - captured;
  return DVCaptureVerdict(
    ok: false,
    message: 'Captured $captured of $expected routes. $missing page(s) would '
        'ship with no crawler-visible content: a crawler, a link preview and a '
        'reader with scripting off would all see an empty body. This is '
        'usually resource pressure during the headless capture -- rerun the '
        'build, or free memory and disk on the machine running it.',
  );
}
