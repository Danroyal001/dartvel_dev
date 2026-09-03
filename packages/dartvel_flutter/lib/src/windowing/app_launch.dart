// Launch: the arguments an application was started with, and the launches
// that come after it.
//
// An OS-level request to open something -- a file association, a
// dartvel:// link, a second launch of a single-instance application --
// arrives as command-line arguments to a new process. The first process
// takes the lock and opens what it was given; every later one hands its
// arguments to the first and leaves. This is what makes "second launch
// focuses the running app" true, and what a file association lands on.
import 'dart:async';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVInstanceLock, DVSingleInstance;

import '../../dartvel_flutter.dart' show DVDeepLinks;

/// What [DVAppLaunch.start] decided.
class DVAppLaunchResult {
  /// True for the process that owns the application; false for one that
  /// handed its arguments over and should exit.
  final bool isPrimary;

  /// The routes a secondary handed to the primary.
  final List<String> forwarded;

  final DVInstanceLock? _lock;
  Timer? _timer;

  DVAppLaunchResult._({required this.isPrimary, required this.forwarded, DVInstanceLock? lock})
      : _lock = lock;

  /// Stops watching for later launches and releases the lock.
  void stop() {
    _timer?.cancel();
    _timer = null;
    final DVInstanceLock? lock = _lock;
    if (lock != null) {
      DVAppLaunch._primaries.remove(lock.path);
      lock.release();
    }
  }
}

/// How a lock is taken; the real one, or a test's.
typedef DVAppLaunchAcquire = DVInstanceLock Function(String path);

class DVAppLaunch {
  DVAppLaunch._();

  /// The first link -- an argument with a scheme, `dartvel://orders/7` or an
  /// https app link -- this process was launched with, or null. What
  /// `deepLinks.initial` answers on desktop; every link argument is also
  /// delivered on `DV.Platform.DeepLinking.getLinkStream()`.
  static String? get initialLink => _initialLink;
  static String? _initialLink;

  /// Forgets the initial link. For tests.
  static void resetForTest() => _initialLink = null;

  /// Whether [argument] is a link rather than a route, a file or a flag.
  static bool isLink(String argument) {
    final Uri? uri = Uri.tryParse(argument.trim());
    return uri != null && uri.hasScheme && uri.scheme != 'file' && !argument.trim().startsWith('/');
  }

  /// Where the lock lives for [appId]: the session's runtime directory
  /// where there is one, else the temp directory.
  static String lockPathFor(String appId) {
    final String base = Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path;
    return '$base/dartvel-$appId.lock';
  }

  /// The route [argument] asks for, or null when it asks for nothing.
  ///
  /// A route is itself; an app link keeps its path and query and loses its
  /// scheme and host; a file goes to [filesRoute] with its path as a query
  /// parameter, encoded, so a path on disk is never mistaken for a route.
  /// Flags and anything else are nothing.
  static String? routeFor(String argument, {String filesRoute = '/open'}) {
    final String text = argument.trim();
    if (text.isEmpty || text.startsWith('-')) return null;
    if (text.startsWith('/')) {
      if (text.startsWith('//')) return null;
      final bool looksLikeFile = _looksLikeFile(text);
      if (!looksLikeFile) return text;
      return '$filesRoute?path=${Uri.encodeComponent(text)}';
    }
    final Uri? uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme == 'file') {
      return '$filesRoute?path=${Uri.encodeComponent(uri.toFilePath())}';
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _pathAndQuery(uri.path.isEmpty ? '/' : uri.path, uri.query);
    }
    if (uri.scheme == 'javascript' || uri.scheme == 'data') return null;
    // dartvel://orders/42 -- the host is the first segment.
    final String path = '/${<String>[if (uri.host.isNotEmpty) uri.host, ...uri.pathSegments].join('/')}';
    return _pathAndQuery(path, uri.query);
  }

  static String _pathAndQuery(String path, String query) =>
      query.isEmpty ? path : '$path?$query';

  /// A path on disk rather than a route: it exists, or its last segment
  /// carries a file extension. Dartvel routes are page paths and do not end
  /// in `.pdf`; a document handed over by a file association always does,
  /// whether or not this process can see it yet.
  static bool _looksLikeFile(String path) {
    final String bare = path.split('?').first;
    if (FileSystemEntity.typeSync(bare) != FileSystemEntityType.notFound) return true;
    final String last = bare.substring(bare.lastIndexOf('/') + 1);
    final int dot = last.lastIndexOf('.');
    return dot > 0 && dot < last.length - 1;
  }

  /// The primary result per lock path in this process. A second start in
  /// the same process -- a test building the router twice, an app that
  /// rebuilds it -- is the same application, not a second launch, and gets
  /// the same result back with its arguments queued.
  static final Map<String, DVAppLaunchResult> _primaries = <String, DVAppLaunchResult>{};

  /// Takes the lock for [appId], or hands [arguments] to the process that
  /// has it. The primary opens its own arguments' routes and, every [poll],
  /// whatever later launches forwarded, through [open].
  static Future<DVAppLaunchResult> start({
    required String appId,
    required List<String> arguments,
    required Future<void> Function(String route) open,
    String? lockPath,
    String filesRoute = '/open',
    Duration poll = const Duration(milliseconds: 500),
    DVAppLaunchAcquire acquire = DVSingleInstance.acquire,
  }) async {
    final List<String> routes = <String>[
      for (final String a in arguments)
        if (routeFor(a, filesRoute: filesRoute) case final String r) r,
    ];
    for (final String a in arguments) {
      if (!isLink(a) || routeFor(a, filesRoute: filesRoute) == null) continue;
      _initialLink ??= a.trim();
      const DVDeepLinks().dispatch(a.trim());
    }
    final String path = lockPath ?? lockPathFor(appId);
    final DVAppLaunchResult? already = _primaries[path];
    if (already != null) {
      for (final String r in routes) {
        already._lock!.send(r);
      }
      return already;
    }
    final DVInstanceLock lock = acquire(path);
    if (!lock.isPrimary) {
      for (final String r in routes) {
        lock.send(r);
      }
      lock.release();
      return DVAppLaunchResult._(isPrimary: false, forwarded: routes);
    }
    // Own arguments go through the same queue as everyone else's, so there
    // is one path, one trust rule and one order.
    for (final String r in routes) {
      lock.send(r);
    }
    final DVAppLaunchResult result = DVAppLaunchResult._(isPrimary: true, forwarded: const <String>[], lock: lock);
    _primaries[path] = result;
    bool draining = false;
    Future<void> drain() async {
      if (draining) return;
      draining = true;
      try {
        for (final String route in lock.takePending()) {
          // Written by another process, so not trusted as a route outright.
          final String path = route.trim();
          if (!path.startsWith('/') || path.startsWith('//')) continue;
          await open(path);
        }
      } finally {
        draining = false;
      }
    }

    result._timer = Timer.periodic(poll, (_) => unawaited(drain()));
    unawaited(drain());
    return result;
  }
}
