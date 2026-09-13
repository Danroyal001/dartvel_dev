import 'dart:async';

import 'package:dartvel_core/dartvel.dart'
    show DVFeatureFlag, DVFlags;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart' show DVReadableSignal;

/// Reading a flag as a signal.
extension DVFlagContextX on BuildContext {
  /// [flag] as a read-only signal bound to this element.
  ///
  /// Reading `.value` in a build method subscribes the element, so a widget
  /// guarded on a flag rebuilds when the synced rules change under it — a kill
  /// switch reaches the screens that are already open. And it is a
  /// [DVReadableSignal], so it composes with the rest of the state layer:
  /// `context.flag(Flags.newCheckout) & user.isStaff` is a signal too.
  DVReadableSignal<T> flag<T>(DVFeatureFlag<T> flag) =>
      _DVFlagSignal<T>(flag, this as Element);
}

/// One subscription per element per flag, however many times the flag is
/// read during a build. Held by the element, so it goes when the element does.
final Expando<Map<String, StreamSubscription<void>>> _subscriptions =
    Expando<Map<String, StreamSubscription<void>>>('dartvel flag signals');

class _DVFlagSignal<T> implements DVReadableSignal<T> {
  _DVFlagSignal(this._flag, this._element);

  final DVFeatureFlag<T> _flag;
  final Element _element;

  @override
  T read() => DVFlags.resolve(_flag).value;

  @override
  T get value {
    final Map<String, StreamSubscription<void>> subscriptions =
        _subscriptions[_element] ??= <String, StreamSubscription<void>>{};
    subscriptions.putIfAbsent(_flag.key, () {
      late final StreamSubscription<void> subscription;
      subscription = DVFlags.changes.listen((void _) {
        if (_element.mounted) {
          _element.markNeedsBuild();
          return;
        }
        // The widget is gone. Nothing unsubscribes an element when it is
        // unmounted, so the first change after that does it.
        subscriptions.remove(_flag.key);
        unawaited(subscription.cancel());
      });
      return subscription;
    });
    return read();
  }
}
