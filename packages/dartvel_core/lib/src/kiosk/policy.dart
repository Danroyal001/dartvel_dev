/// The kiosk policy: what a declaration means, and what it refuses to mean.
///
/// A kiosk runs one application for whoever walks up to it, and this is the
/// set of guarantees that makes "cannot be left by the user" true. Nothing
/// parsed it, so every key in the specification was documentation.
///
/// Pure Dart, in the package with no Flutter dependency, because both the
/// runtime and `dartvel doctor` have to agree about what a policy says.
library dartvel.kiosk.policy;

import 'runtime.dart' show DVKioskState;
import 'updates.dart';

/// Whether the whole device is the kiosk, or one display of it.
enum DVKioskScope {
  /// One application, no windows. `open()` presents in place.
  device,

  /// One window owns one display; ordinary windows continue on the others.
  display,
}

/// What happens when the session goes idle.
enum DVKioskIdleAction { reset, home, none }

/// How staff leave kiosk mode.
enum DVKioskExitMethod { none, pin, gesturePin, adminAuth, remote, hardwareCombo }

/// What a session reset clears.
enum DVKioskClearable { signals, forms, sharedStore, auth, clientCache }

/// One kiosk's declared policy.
///
/// Never throws on bad input: a policy that cannot be read has to report what
/// is wrong with it, because the alternative is a device that will not boot
/// with no way to see why.
class DVKioskPolicy {
  const DVKioskPolicy({
    required this.enabled,
    required this.scope,
    required this.home,
    required this.allow,
    required this.blockSystemGestures,
    required this.blockHardwareKeys,
    required this.blockShortcuts,
    required this.idleTimeout,
    required this.idleWarning,
    required this.onIdle,
    required this.clearOnReset,
    required this.fullscreen,
    required this.exitMethod,
    required this.exitPinSecret,
    required this.maxAttempts,
    required this.lockoutFor,
    required this.audit,
    required this.updatesApply,
    required this.updatesWindow,
    required this.problems,
  });

  final bool enabled;
  final DVKioskScope scope;

  /// The attract route, returned to on idle and after a reset.
  final String home;

  /// Route patterns the kiosk permits. Empty means every application route,
  /// which is the documented default -- read as "allow nothing" it would make
  /// a kiosk show its home route and refuse every link on it.
  final List<String> allow;

  final bool blockSystemGestures;
  final bool blockHardwareKeys;
  final bool blockShortcuts;

  final Duration idleTimeout;
  final Duration idleWarning;
  final DVKioskIdleAction onIdle;
  final Set<DVKioskClearable> clearOnReset;

  final bool fullscreen;

  final DVKioskExitMethod exitMethod;

  /// The name of the secret holding the exit PIN, never the PIN.
  final String? exitPinSecret;

  final int maxAttempts;
  final Duration lockoutFor;
  final bool audit;

  /// When this kiosk may apply an update it has found.
  final DVKioskUpdateApply updatesApply;

  /// The span of the day [DVKioskUpdateApply.maintenanceWindow] waits for.
  final DVMaintenanceWindow? updatesWindow;

  /// What this kiosk should do with [update], under its declared policy.
  ///
  /// [state] decides a staff-mode policy and [now] a windowed one; a required
  /// update overrides both, resetting whatever session is on screen rather
  /// than landing on top of it.
  DVKioskUpdateDecision decideUpdate({
    required DVUpdateOffer update,
    required DVKioskState state,
    required DateTime now,
  }) =>
      dvDecideKioskUpdate(
        apply: updatesApply,
        window: updatesWindow,
        update: update,
        state: state,
        now: now,
      );

  /// Declarations that cannot be honoured, in the specification's terms.
  final List<String> problems;

  /// Whether [route] is inside the allowlist.
  ///
  /// Segment-aware: `/welcome` does not match `/welcomes`, and `/order/**`
  /// matches `/order` as well as everything below it -- allowing the children
  /// of a page the user cannot reach would be a strange thing to mean.
  bool allowsRoute(String route) {
    if (allow.isEmpty) return true;
    final List<String> parts = _segments(route);
    for (final String pattern in allow) {
      if (_matches(_segments(pattern), parts)) return true;
    }
    return false;
  }

  static List<String> _segments(String path) =>
      path.split('/').where((String s) => s.isNotEmpty).toList();

  static bool _matches(List<String> pattern, List<String> path) {
    for (var i = 0; i < pattern.length; i++) {
      if (pattern[i] == '**') return true;
      if (i >= path.length) return false;
      if (pattern[i] != '*' && pattern[i] != path[i]) return false;
    }
    return pattern.length == path.length;
  }

  /// Reads `dartvel.kiosk`.
  static DVKioskPolicy parse(Object? dartvelSection) {
    final List<String> problems = <String>[];
    final Object? raw =
        dartvelSection is Map ? dartvelSection['kiosk'] : null;
    if (raw != null && raw is! Map) {
      problems.add('dartvel.kiosk must be a map, but is a ${raw.runtimeType}.');
    }
    final Map<Object?, Object?> k =
        raw is Map ? raw : const <Object?, Object?>{};

    final bool enabled = k['enabled'] == true;

    final DVKioskScope scope = _enum<DVKioskScope>(
      k['scope'],
      const <String, DVKioskScope>{
        'device': DVKioskScope.device,
        'display': DVKioskScope.display,
      },
      DVKioskScope.device,
      'dartvel.kiosk.scope',
      problems,
    );

    final Map<Object?, Object?> routes = _map(k['routes']);
    final List<String> allow = <String>[
      for (final Object? entry in _list(routes['allow']))
        if (entry is String) entry,
    ];

    final Map<Object?, Object?> input = _map(k['input']);
    final Map<Object?, Object?> session = _map(k['session']);
    final Map<Object?, Object?> display = _map(k['display']);
    final Map<Object?, Object?> exit = _map(k['exit']);
    final Map<Object?, Object?> updates = _map(k['updates']);

    final DVKioskUpdateApply updatesApply = _enum<DVKioskUpdateApply>(
      updates['apply'],
      const <String, DVKioskUpdateApply>{
        'immediate': DVKioskUpdateApply.immediate,
        'maintenanceWindow': DVKioskUpdateApply.maintenanceWindow,
        'staffMode': DVKioskUpdateApply.staffMode,
      },
      DVKioskUpdateApply.immediate,
      'dartvel.kiosk.updates.apply',
      problems,
    );
    final DVMaintenanceWindow? updatesWindow =
        DVMaintenanceWindow.parse(updates['window']);
    if (updates['window'] != null && updatesWindow == null) {
      problems.add('dartvel.kiosk.updates.window is "${updates['window']}", '
          'which is not a span such as "02:00-04:00".');
    }
    if (updatesApply == DVKioskUpdateApply.maintenanceWindow &&
        updatesWindow == null) {
      // A window policy with no window defers for ever, and a kiosk that
      // never installs anything looks exactly like a kiosk with nothing to
      // install.
      problems.add('dartvel.kiosk.updates.apply is "maintenanceWindow" but '
          'no updates.window is declared, so no update would ever be '
          'applied.');
    }

    final Duration idleTimeout = _duration(
        session['idleTimeout'], const Duration(seconds: 90),
        'dartvel.kiosk.session.idleTimeout', problems);
    final Duration idleWarning = _duration(
        session['idleWarning'], const Duration(seconds: 15),
        'dartvel.kiosk.session.idleWarning', problems);
    if (idleWarning > idleTimeout) {
      // The countdown would start before the clock did, so the user would see
      // it immediately and never get the time the timeout promises.
      problems.add('dartvel.kiosk.session.idleWarning ($idleWarning) is longer '
          'than idleTimeout ($idleTimeout).');
    }

    final Set<DVKioskClearable> clear = <DVKioskClearable>{};
    for (final Object? entry in _list(session['clearOnReset'])) {
      const Map<String, DVKioskClearable> names = <String, DVKioskClearable>{
        'signals': DVKioskClearable.signals,
        'forms': DVKioskClearable.forms,
        'sharedStore': DVKioskClearable.sharedStore,
        'auth': DVKioskClearable.auth,
        'clientCache': DVKioskClearable.clientCache,
      };
      final DVKioskClearable? value = names['$entry'];
      if (value == null) {
        problems.add('dartvel.kiosk.session.clearOnReset has "$entry", which '
            'is not one of ${names.keys.join(', ')}.');
        continue;
      }
      // Refused rather than merely reported: a customer display timing out
      // must not sign the cashier out. The session is the staff window's.
      if (value == DVKioskClearable.auth && scope == DVKioskScope.display) {
        problems.add('dartvel.kiosk.session.clearOnReset may not contain '
            '"auth" in display scope: the session belongs to the staff '
            'window, and clearing it would sign the operator out when the '
            'customer display timed out.');
        continue;
      }
      clear.add(value);
    }

    final DVKioskExitMethod method = _enum<DVKioskExitMethod>(
      exit['method'],
      const <String, DVKioskExitMethod>{
        'none': DVKioskExitMethod.none,
        'pin': DVKioskExitMethod.pin,
        'gesture+pin': DVKioskExitMethod.gesturePin,
        'adminAuth': DVKioskExitMethod.adminAuth,
        'remote': DVKioskExitMethod.remote,
        'hardwareCombo': DVKioskExitMethod.hardwareCombo,
      },
      DVKioskExitMethod.none,
      'dartvel.kiosk.exit.method',
      problems,
    );

    String? pinSecret;
    final Object? pin = exit['pin'];
    final bool needsPin = method == DVKioskExitMethod.pin ||
        method == DVKioskExitMethod.gesturePin;
    if (pin != null) {
      if (pin is String && pin.startsWith('secret:')) {
        pinSecret = pin.substring('secret:'.length);
      } else {
        // A literal would sit in the built artifact, readable by anyone with
        // the image -- the one thing the exit method exists to prevent.
        problems.add('dartvel.kiosk.exit.pin must be a secret reference such '
            'as "secret:KIOSK_EXIT_PIN", never the PIN itself.');
      }
    } else if (needsPin) {
      problems.add('dartvel.kiosk.exit.method is "${exit['method']}" but no '
          'exit.pin secret is declared.');
    }

    return DVKioskPolicy(
      enabled: enabled,
      scope: scope,
      home: k['home'] is String ? k['home']! as String : '/',
      allow: allow,
      blockSystemGestures: _blocks(input['systemGestures'], true),
      // display scope defaults to passthrough; device scope blocks.
      blockHardwareKeys:
          _blocks(input['hardwareKeys'], scope == DVKioskScope.device),
      blockShortcuts: _blocks(input['shortcuts'], true),
      idleTimeout: idleTimeout,
      idleWarning: idleWarning,
      onIdle: _enum<DVKioskIdleAction>(
        session['onIdle'],
        const <String, DVKioskIdleAction>{
          'reset': DVKioskIdleAction.reset,
          'home': DVKioskIdleAction.home,
          'none': DVKioskIdleAction.none,
        },
        DVKioskIdleAction.reset,
        'dartvel.kiosk.session.onIdle',
        problems,
      ),
      clearOnReset: clear,
      fullscreen: display['fullscreen'] != false,
      exitMethod: method,
      exitPinSecret: pinSecret,
      maxAttempts: exit['maxAttempts'] is int ? exit['maxAttempts']! as int : 5,
      lockoutFor: _duration(exit['lockoutFor'], const Duration(minutes: 10),
          'dartvel.kiosk.exit.lockoutFor', problems),
      audit: exit['audit'] != false,
      updatesApply: updatesApply,
      updatesWindow: updatesWindow,
      problems: problems,
    );
  }

  static bool _blocks(Object? value, bool fallback) =>
      value == null ? fallback : value == 'block' || value == 'disabled';

  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? value : const <Object?, Object?>{};

  static List<Object?> _list(Object? value) =>
      value is List ? value : const <Object?>[];

  static T _enum<T>(
    Object? value,
    Map<String, T> names,
    T fallback,
    String key,
    List<String> problems,
  ) {
    if (value == null) return fallback;
    final T? found = names['$value'];
    if (found != null) return found;
    problems.add('$key is "$value", which is not one of '
        '${names.keys.join(', ')}.');
    return fallback;
  }

  /// Reads `90s`, `10m`, `2h`.
  ///
  /// An unreadable value keeps the default rather than becoming zero: a zero
  /// idle timeout resets the kiosk continuously, which looks like a crash loop.
  static Duration _duration(
    Object? value,
    Duration fallback,
    String key,
    List<String> problems,
  ) {
    if (value == null) return fallback;
    final RegExpMatch? m =
        RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch('$value'.trim());
    if (m == null) {
      problems.add('$key is "$value", which is not a duration such as "90s", '
          '"10m" or "2h".');
      return fallback;
    }
    final int n = int.parse(m.group(1)!);
    return switch (m.group(2)) {
      'ms' => Duration(milliseconds: n),
      's' => Duration(seconds: n),
      'm' => Duration(minutes: n),
      _ => Duration(hours: n),
    };
  }
}
