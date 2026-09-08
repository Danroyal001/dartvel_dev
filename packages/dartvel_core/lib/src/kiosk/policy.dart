/// The kiosk policy: what a declaration means, and what it refuses to mean.
///
/// A kiosk runs one application for whoever walks up to it, and this is the
/// set of guarantees that makes "cannot be left by the user" true. Nothing
/// parsed it, so every key in the specification was documentation.
///
/// Pure Dart, in the package with no Flutter dependency, because both the
/// runtime and `dartvel doctor` have to agree about what a policy says.
library dartvel.kiosk.policy;

import '../updates/update_info.dart';
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

/// Whether a kiosk shows a pointer.
enum DVKioskCursor {
  /// Hidden when no pointing device is attached, which is what the
  /// specification's "touch-only" means in the only terms a running
  /// application can check.
  auto,

  /// Hidden whatever is attached. An operator who wrote this has a reason --
  /// a projected display, a screen that gets photographed -- and a mouse
  /// plugged in to service the machine should not undo it.
  always,

  /// Left alone.
  never,
}

/// Whether the pointer is hidden, given the mode and the hardware.
///
/// Separate from the widget that applies it so the decision can be tested
/// without one, and so the two cannot disagree.
bool dvKioskHidesCursor(
  DVKioskCursor mode, {
  required bool mouseConnected,
}) =>
    switch (mode) {
      DVKioskCursor.always => true,
      DVKioskCursor.never => false,
      DVKioskCursor.auto => !mouseConnected,
    };

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
    required this.blockClipboard,
    required this.blockTextSelection,
    required this.hideCursor,
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

  /// Whether the clipboard is locked, from `input.clipboard`.
  ///
  /// Not implied by kiosk mode. An order screen showing a reference number
  /// is more useful if the number can be copied, and the specification
  /// makes this an explicit key rather than a consequence.
  ///
  /// What this reaches is the framework's own clipboard API and the
  /// selection that feeds it. A desktop kiosk running beside another
  /// application whose clipboard the OS shares is not covered by a rule
  /// written in Dart, and saying so is better than implying otherwise.
  final bool blockClipboard;

  /// Whether page text can be selected, from `input.textSelection`.
  ///
  /// Overrides what a page declares. `@DVPage(selectable: true)` is the
  /// page's preference and the kiosk policy is the deployment's decision,
  /// and a deployment that has locked selection has not left the question
  /// open to each page.
  final bool blockTextSelection;

  /// Whether the pointer is hidden over the application, from
  /// `display.hideCursor`.
  ///
  /// `auto` is the specification's default and means touch-only, which
  /// cannot be read off the build target: a kiosk on a Linux box with a
  /// touchscreen is a desktop build, and a tablet in a keyboard case has a
  /// trackpad. Whether a pointing device is attached is the question the
  /// mode is actually asking, so that is the question it asks.
  final DVKioskCursor hideCursor;

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
    required DVUpdateInfo update,
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

    // A key this parser does not read is reported rather than dropped.
    //
    // The specification describes more containment than is built --
    // routes.external and display.screenDim, each of which still needs
    // something underneath it -- and every one of the five was read straight
    // past. input.clipboard, input.textSelection and display.hideCursor are
    // built now: the three Dartvel can honour on its own, in Dart, with no
    // platform binding.
    // An unrecognised enum value has always produced a problem here; an
    // unrecognised key produced nothing, and that is the worse of the two.
    // Somebody who writes `input.clipboard: disabled` into a kiosk has
    // decided the clipboard is locked and has been told nothing to the
    // contrary. Silence reads as agreement.
    void unread(String path, Map<Object?, Object?> map, Set<String> known) {
      for (final Object? key in map.keys) {
        if (key is! String || known.contains(key)) continue;
        problems.add('$path.$key is not read by this version of Dartvel: it '
            'is accepted here and changes nothing at runtime.');
      }
    }

    unread('dartvel.kiosk', k, const <String>{
      'enabled',
      'scope',
      'home',
      'routes',
      'input',
      'session',
      'display',
      'exit',
      'updates',
    });
    unread('dartvel.kiosk.routes', routes, const <String>{'allow'});
    unread('dartvel.kiosk.input', input, const <String>{
      'systemGestures',
      'hardwareKeys',
      'shortcuts',
      // Read now, so reporting them would say a key does nothing while it
      // does. routes.external, display.hideCursor and display.screenDim are
      // still unbuilt and still report: naming two of the five as done would
      // be worse than naming none, because the other three would look
      // implemented by association.
      'clipboard',
      'textSelection',
    });
    unread('dartvel.kiosk.session', session, const <String>{
      'onIdle',
      'idleTimeout',
      'idleWarning',
      'clearOnReset',
    });
    unread('dartvel.kiosk.display', display, const <String>{
      'fullscreen',
      // Read now. screenDim is still unbuilt and still reports: it wants
      // a backlight, and an overlay drawn over the application is a
      // different thing wearing the same name.
      'hideCursor',
    });
    unread('dartvel.kiosk.exit', exit, const <String>{
      'method',
      'pin',
      'audit',
      'lockoutFor',
      'maxAttempts',
    });
    unread('dartvel.kiosk.updates', updates, const <String>{
      'apply',
      'window',
    });

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
      // Default false on both: see the field comments. A kiosk is not
      // automatically a device where nothing can be selected.
      blockClipboard: _blocks(input['clipboard'], false),
      blockTextSelection: _blocks(input['textSelection'], false),
      hideCursor: _enum<DVKioskCursor>(
        display['hideCursor'],
        const <String, DVKioskCursor>{
          'auto': DVKioskCursor.auto,
          'always': DVKioskCursor.always,
          'never': DVKioskCursor.never,
        },
        DVKioskCursor.auto,
        'dartvel.kiosk.display.hideCursor',
        problems,
      ),
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
