/// Which page is on screen, said once per page by the page shell.
///
/// A page view is the one event every measuring tool wants and no
/// application should have to send by hand: a call somebody has to remember
/// on every page is a page that is missing from the report. The shell every
/// page is drawn in reports the address when the page is first shown and each
/// time the router moves, and a module that measures page views listens here.
///
/// In this package rather than the Flutter one because the listeners are
/// modules, and a module's surface is compiled into the backend as well as
/// the client: it cannot import Flutter to hear about a route.
library;

/// One page shown to one reader.
final class DVPageView {
  const DVPageView({required this.location, this.title});

  /// The page's address, without its fragment.
  final Uri location;

  /// The page's title, when the shell knows it.
  final String? title;
}

/// The page views of this process.
abstract final class DVPageViews {
  static final List<void Function(DVPageView view)> _listeners =
      <void Function(DVPageView view)>[];
  static DVPageView? _last;

  /// The page on screen now, or null before the first one is shown.
  static DVPageView? get current => _last;

  /// Says [location] is the page on screen.
  ///
  /// The same address twice running is one view: a shell rebuilds, and its
  /// router repeats itself. A fragment names a place within a page, so it is
  /// dropped and following one is not a view either.
  static void report(Uri location, {String? title}) {
    final Uri page = location.removeFragment();
    if (_last?.location == page) return;
    final DVPageView view = DVPageView(location: page, title: title);
    _last = view;
    for (final void Function(DVPageView view) listener
        in List<void Function(DVPageView view)>.of(_listeners)) {
      _tell(listener, view);
    }
  }

  /// Calls [listener] for each page shown from now on, and at once for the
  /// page already on screen: a listener that had to wait for something --
  /// consent, a script -- would otherwise miss the landing page, which is
  /// the only page most visits have.
  static void addListener(void Function(DVPageView view) listener) {
    _listeners.add(listener);
    final DVPageView? shown = _last;
    if (shown != null) _tell(listener, shown);
  }

  static void removeListener(void Function(DVPageView view) listener) =>
      _listeners.remove(listener);

  /// A listener is somebody else's code, and measuring must never be what
  /// stops a page being shown.
  static void _tell(void Function(DVPageView view) listener, DVPageView view) {
    try {
      listener(view);
    } on Object {
      // Deliberately dropped: see above.
    }
  }

  /// Forgets the listeners and the page, for tests.
  static void resetForTesting() {
    _listeners.clear();
    _last = null;
  }
}
