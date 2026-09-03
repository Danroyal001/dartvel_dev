/// Kiosk enforcement on Linux: the escape combos, grabbed.
///
/// A grab is the mechanism X11 has for "this key goes to me and nobody
/// else", which is exactly what blocking the window switcher means. It rides
/// the same pump and registry global shortcuts use, under ids of its own, so
/// releasing the kiosk releases only the kiosk's grabs. A grab the server
/// refuses -- another client holds it -- is reported as unenforced rather
/// than thrown: reduced enforcement is a fact to show the operator.
library;

import 'dart:async';

import '../../../dartvel_flutter.dart' show DVGlobalShortcut, DVShortcuts;
import '../../kiosk/kiosk.dart';

class DVLinuxKiosk {
  const DVLinuxKiosk._();

  static const String _prefix = 'dv.kiosk:';
  static final List<String> _held = <String>[];

  static const Set<String> implemented = <String>{
    'kiosk.enforce',
    'kiosk.release',
  };

  /// Why the last pointer grab was refused, for the operator and the test.
  static String? lastConfineError;

  static bool _confined = false;
  static void Function()? _releasePointer;

  /// Whether the kiosk is holding system notifications back, and how many
  /// it has held: the spec says system notifications are suppressed on the
  /// kiosk surface while the in-app inbox continues, and the freedesktop
  /// notification is what the Linux binding sends.
  static bool notificationsSuppressed = false;
  static int suppressedNotifications = 0;

  /// For the notification binding: true when the notification must not be
  /// sent, counted.
  static bool suppressNotification() {
    if (!notificationsSuppressed) return false;
    suppressedNotifications++;
    return true;
  }

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind, {
    required Future<bool> Function() fullscreen,
    required String? Function() confinePointer,
    required void Function() releasePointer,
  }) {
    _releasePointer = releasePointer;
    bind('kiosk.enforce', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      await _release();
      final List<String> blocked = <String>[];
      final Map<String, String> unenforced = <String, String>{};
      for (final Object? raw in (map['combos'] as List?) ?? const <Object?>[]) {
        final String combo = '$raw';
        try {
          await const DVShortcuts().register(
            DVGlobalShortcut(id: '$_prefix$combo', accelerator: combo),
            onPressed: () => DVKiosk.reportBlocked(combo),
          );
          _held.add(combo);
          blocked.add(combo);
        } catch (error) {
          unenforced[combo] = '$error';
        }
      }
      final bool wentFullscreen =
          map['fullscreen'] == true ? await fullscreen() : false;
      bool confined = false;
      if (map['confinePointer'] == true) {
        lastConfineError = confinePointer();
        confined = lastConfineError == null;
        _confined = confined;
      }
      notificationsSuppressed = map['suppressNotifications'] == true;
      return <String, Object?>{
        'blocked': blocked,
        'unenforced': unenforced,
        'fullscreen': wentFullscreen,
        'confined': confined,
        'notificationsSuppressed': notificationsSuppressed,
      };
    });

    bind('kiosk.release', (Object? _) async {
      await _release();
      return true;
    });
  }

  static Future<void> _release() async {
    for (final String combo in List<String>.of(_held)) {
      await const DVShortcuts().unregister('$_prefix$combo');
    }
    _held.clear();
    notificationsSuppressed = false;
    if (_confined) {
      _releasePointer?.call();
      _confined = false;
    }
  }

  /// Releases the kiosk's grabs. For tests and shutdown.
  static Future<void> unregister() => _release();
}
