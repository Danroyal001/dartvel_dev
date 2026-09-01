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

/// The result of checking a capture run.
class DVCaptureVerdict {
  const DVCaptureVerdict({required this.ok, this.message});

  final bool ok;

  /// Null when there is nothing to say.
  final String? message;
}

/// Whether [captured] of [expected] routes is good enough to ship.
DVCaptureVerdict dvVerifyCapture({
  required int captured,
  required int expected,
}) {
  // A project with no pages has nothing to prerender.
  if (expected <= 0) return const DVCaptureVerdict(ok: true);

  // Defensive: a miscount must not fail a build that captured everything.
  if (captured >= expected) return const DVCaptureVerdict(ok: true);

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
