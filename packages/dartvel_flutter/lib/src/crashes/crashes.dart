/// `DV.Crashes`: the crash reporter, installed where Flutter reports errors.
///
/// The runtime in dartvel_core records a report synchronously and sends it at
/// the next launch. This is what puts it in the path of an error: it chains
/// `FlutterError.onError` and `PlatformDispatcher.instance.onError`, listens
/// to the isolate (and, on the web, to the window), and sends what the last
/// run left.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/foundation.dart';

import 'crash_hook.dart';
import 'crash_platform_none.dart'
    if (dart.library.io) 'crash_platform_io.dart'
    if (dart.library.js_interop) 'crash_platform_web.dart' as platform;

export 'crash_directory.dart' show dvCrashDirectoryFor, dvInstallIdFrom;
export 'crash_hook.dart';

/// An error that reached a hook only as text.
///
/// An isolate's error listener and a browser's error event carry the
/// description and the stack, not the object, so the type that threw is not
/// recoverable from them; this names that honestly rather than as `String`.
final class DVUncaughtError implements Exception {
  const DVUncaughtError(this.description);

  final String description;

  @override
  String toString() => description;
}

class _Arrival {
  _Arrival(this.error, this.text, this.stack, DVCrashHook hook)
      : hooks = <DVCrashHook>{hook};

  final Object error;
  final String text;
  final String stack;
  final Set<DVCrashHook> hooks;
}

/// One installation of the crash reporter into this process.
final class DVCrashInstallation {
  DVCrashInstallation._(this.reporter);

  final DVCrashReporting reporter;

  /// How many reports from earlier runs were sent at install.
  late final Future<int> recovered;

  /// The last thing that went wrong inside the handler itself, if anything.
  ///
  /// Kept rather than thrown: a crash handler that throws replaces the error
  /// being reported with its own, and one that reports through Flutter
  /// recurses. Nothing here is logged either, for the same reason.
  Object? get lastHandlerFailure => _lastFailure;
  Object? _lastFailure;

  bool _installed = false;
  bool _handling = false;

  /// Recent arrivals, so one error reaching two hooks is recorded once.
  final ListQueue<_Arrival> _recent = ListQueue<_Arrival>();
  static const int _remembered = 32;

  /// The declared identity, when the application declared one.
  DVCrashIdentity? _identity;

  FlutterExceptionHandler? _previousFlutter;
  FlutterExceptionHandler? _ownFlutter;
  ErrorCallback? _previousDispatcher;
  ErrorCallback? _ownDispatcher;
  void Function()? _removePlatformHooks;

  void _install({required bool platformHooks, String? sessionId}) {
    _installed = true;
    reporter.install();
    reporter.startSession(sessionId ?? dvCrashReportId(DateTime.now()));

    _previousFlutter = FlutterError.onError;
    _ownFlutter = (FlutterErrorDetails details) {
      // Recorded first, so an application handler that ends the process
      // still leaves the report behind. A silent error is one the framework
      // itself does not print in release, and is recorded as non-fatal.
      receive(
        details.exception,
        details.stack,
        DVCrashHook.flutterError,
        fatal: !details.silent,
      );
      _previousFlutter?.call(details);
    };
    FlutterError.onError = _ownFlutter;

    _previousDispatcher = PlatformDispatcher.instance.onError;
    _ownDispatcher = (Object error, StackTrace stack) {
      receive(error, stack, DVCrashHook.platformDispatcher);
      // False with no earlier handler: true would swallow what the engine
      // prints for an unhandled error.
      return _previousDispatcher?.call(error, stack) ?? false;
    };
    PlatformDispatcher.instance.onError = _ownDispatcher;

    if (platformHooks) {
      try {
        _removePlatformHooks = platform.dvInstallPlatformCrashHooks(receiveText);
      } on Object catch (error) {
        _lastFailure = error;
      }
    }

    recovered = _recover();
  }

  Future<int> _recover() async {
    try {
      return await reporter.recoverAndSend();
    } on Object catch (error) {
      _lastFailure = error;
      return 0;
    }
  }

  /// Records [error] as it arrived at [hook], unless it already arrived at a
  /// different hook. Returns the report written, or null.
  ///
  /// Never throws, and never re-enters itself: an error raised while a
  /// report is being written is not recorded.
  DVCrashReport? receive(
    Object error,
    StackTrace? stack,
    DVCrashHook hook, {
    bool fatal = true,
  }) =>
      _guarded(() {
        final String stackText = '${stack ?? StackTrace.empty}';
        final String text = '$error';
        for (final _Arrival seen in _recent) {
          final bool same = identical(seen.error, error) ||
              (seen.error is DVUncaughtError &&
                  seen.text == text &&
                  seen.stack == stackText);
          if (same && seen.hooks.add(hook)) return null;
        }
        _remember(_Arrival(error, text, stackText, hook));
        return reporter.record(
          error,
          stack ?? StackTrace.empty,
          fatal: fatal,
        );
      });

  /// Records an error that arrived as text — from the isolate's error
  /// listener or a browser event — unless it already arrived elsewhere.
  DVCrashReport? receiveText(String error, String stack, DVCrashHook hook) =>
      _guarded(() {
        for (final _Arrival seen in _recent) {
          if (seen.text == error &&
              seen.stack == stack &&
              seen.hooks.add(hook)) {
            return null;
          }
        }
        final DVUncaughtError uncaught = DVUncaughtError(error);
        _remember(_Arrival(uncaught, error, stack, hook));
        return reporter.record(
          uncaught,
          StackTrace.fromString(stack),
          fatal: true,
        );
      });

  void _remember(_Arrival arrival) {
    if (_recent.length >= _remembered) _recent.removeFirst();
    _recent.add(arrival);
  }

  DVCrashReport? _guarded(DVCrashReport? Function() body) {
    if (!_installed || _handling) return null;
    _handling = true;
    try {
      return body();
    } on Object catch (error) {
      _lastFailure = error;
      return null;
    } finally {
      _handling = false;
    }
  }

  /// Takes the hooks out, restoring what was there before.
  ///
  /// A handler the application set after installation is left alone: it
  /// already replaced this one, and restoring the earlier handler over it
  /// would undo the application's decision.
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    if (identical(FlutterError.onError, _ownFlutter)) {
      FlutterError.onError = _previousFlutter;
    }
    if (identical(PlatformDispatcher.instance.onError, _ownDispatcher)) {
      PlatformDispatcher.instance.onError = _previousDispatcher;
    }
    _removePlatformHooks?.call();
    _removePlatformHooks = null;
    if (identical(DVCrashes._installation, this)) {
      DVCrashes._installation = null;
    }
  }
}

/// `DV.Crashes`.
final class DVCrashes {
  const DVCrashes();

  static DVCrashInstallation? _installation;

  /// The installation in this process, or null before one.
  DVCrashInstallation? get installation => _installation;

  /// Installs [reporter] into Flutter's error hooks and sends what earlier
  /// runs left.
  ///
  /// Refuses a second installation: chaining every hook twice records every
  /// error twice. [platformHooks] adds the isolate's error listener, or on
  /// the web the window's `error` and `unhandledrejection` listeners.
  DVCrashInstallation install(
    DVCrashReporting reporter, {
    bool platformHooks = true,
    String? sessionId,
  }) {
    if (_installation != null) {
      throw StateError(
        'DV.Crashes is already installed. Uninstall the current installation '
        'first: installing again would chain every error hook twice and '
        'record each error twice.',
      );
    }
    final DVCrashInstallation installation = DVCrashInstallation._(reporter);
    _installation = installation;
    installation._install(platformHooks: platformHooks, sessionId: sessionId);
    return installation;
  }

  /// Records a caught [error] as non-fatal: the only kind that is sampled.
  ///
  /// Null before installation, when sampled out, or past the release's
  /// limit. Never throws.
  DVCrashReport? record(Object error, [StackTrace? stack]) =>
      _installation?.receive(
        error,
        stack ?? StackTrace.current,
        DVCrashHook.application,
        fatal: false,
      );

  /// Runs [body] with its uncaught errors recorded as crashes.
  R? runGuarded<R>(R Function() body) => runZonedGuarded<R>(
        body,
        (Object error, StackTrace stack) {
          final DVCrashInstallation? installation = _installation;
          if (installation == null) {
            Zone.root.handleUncaughtError(error, stack);
            return;
          }
          installation.receive(error, stack, DVCrashHook.guardedZone);
        },
      );

  /// Installs crash reporting for the application [appId] at [release]: what
  /// the generated runtime calls at startup.
  ///
  /// Records go to [store], else the platform's default, and the install id
  /// is read from beside them or generated once. Returns the existing
  /// installation when there is one, since the runtime can be configured more
  /// than once in a process, and null under `flutter test` unless
  /// [evenUnderTest].
  DVCrashInstallation? installApplication({
    required String appId,
    required String release,
    DVCrashStore? store,
    DVCrashSink? sink,
    String? installId,
    DVConsentCategory? identityConsent,
    DVCrashConfig config = const DVCrashConfig(),
    void Function(String code, String message)? onDiagnostic,
    Uri Function(String path)? api,
    bool evenUnderTest = false,
  }) {
    if (hostedByTestRunner && !evenUnderTest) return null;
    final DVCrashInstallation? existing = _installation;
    if (existing != null) return existing;
    final DVCrashBuildMode mode = kReleaseMode
        ? DVCrashBuildMode.release
        : kProfileMode
            ? DVCrashBuildMode.profile
            : DVCrashBuildMode.debug;
    if (!config.enabledIn(mode)) {
      // Said, and nothing else done: no hook, no store, no install id
      // written. Off is a declaration, not an accident.
      (onDiagnostic ?? dvLogCrashDiagnostic)(
        'DV-CRASH-009',
        'crash reporting is disabled for ${mode.name} builds, as '
            'dartvel.crashes declares',
      );
      return null;
    }
    identityConsent ??= config.identityConsent;
    DVCrashSink? resolvedSink = sink;
    if (resolvedSink == null && config.sink == DVCrashSinkChoice.dartvel) {
      final Uri Function(String path)? reach = api;
      if (reach == null) {
        throw ArgumentError.value(
          null,
          'api',
          'dartvel.crashes.sink is dartvel and there is no API to send reports '
              'to; the generated runtime passes DartvelRuntime.api',
        );
      }
      // Resolved when a report is sent, so the base URL in force then is
      // the one used.
      resolvedSink =
          DVCrashSink.dartvel(endpoint: () => reach(DVCrashIngest.path));
    }
    DVCrashStore? resolved = store ?? defaultStore(appId);
    if (resolved == null) {
      debugPrint('[dartvel] DV.Crashes has nowhere on this platform that '
          'survives a restart; reports are kept in memory and a crash that '
          'ends the process is lost.');
      resolved = DVMemoryCrashStore();
    }
    final String install = installId ?? platform.dvInstallId(appId);
    final String os =
        kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
    final DVCrashIdentity? identity = identityConsent == null
        ? null
        : DVCrashIdentity(category: identityConsent);

    final (String?, DVConsent)? pending = _pendingIdentity;
    _pendingIdentity = null;
    if (pending != null) {
      if (identity == null) {
        debugPrint('[dartvel] DV.Crashes.identify was called before '
            'installation, and this application declares no '
            'dartvel.crashes.identity.consent; no report carries a user id.');
      } else {
        identity.identify(pending.$1, consent: pending.$2);
      }
    }

    final DVCrashInstallation installation = this.install(
      DVCrashReporting(
        store: resolved,
        sink: resolvedSink,
        // Read when each report is written, so a withdrawal or a changed
        // flag is on the next crash rather than the next launch.
        context: () => DVCrashContext(
          release: release,
          installId: install,
          platform: os,
          locale: PlatformDispatcher.instance.locale.toLanguageTag(),
          userId: identity?.userId,
        ),
        flags: dvCrashFlagsSnapshot,
        breadcrumbs: config.breadcrumbs,
        nonFatalSampleRate: config.nonFatalSampleRate,
        fullReportsPerRelease: config.fullReportsPerRelease,
        onDiagnostic: onDiagnostic,
      ),
    );
    installation._identity = identity;
    return installation;
  }

  static (String?, DVConsent)? _pendingIdentity;

  /// Ties this install's reports to [userId], for as long as the consent
  /// category the application declared under `dartvel.crashes.identity` is
  /// granted in [consent]. Null signs out.
  ///
  /// Refused when the application declared no category: a user id with no
  /// consent behind it is exactly what a crash report must not carry, and
  /// quietly ignoring the call would look like it worked. Before installation
  /// the identity is held and applied when crash reporting is installed.
  void identify(String? userId, {required DVConsent consent}) {
    final DVCrashInstallation? installation = _installation;
    if (installation == null) {
      _pendingIdentity = (userId, consent);
      return;
    }
    final DVCrashIdentity? identity = installation._identity;
    if (identity == null) {
      throw StateError(
        'DV.Crashes.identify needs a consent category to bind the user id '
        'to. Declare dartvel.crashes.identity.consent in pubspec.yaml with the '
        'category a crash report may carry a user id under; without one no '
        'report is tied to an account.',
      );
    }
    identity.identify(userId, consent: consent);
  }

  /// The store records for [appId] are kept in on this platform: files in the
  /// per-user data directory, or `localStorage` on the web. Null when the
  /// platform gives nowhere that survives a restart.
  static DVCrashStore? defaultStore(String appId) =>
      platform.dvDefaultCrashStore(appId);

  /// Whether this process is a `flutter test` run, where the test framework
  /// owns the error hooks and nothing should be written to the person's data
  /// directory.
  static bool get hostedByTestRunner => platform.dvHostedByTestRunner();
}
