/// What the device can reach, as a signal.
///
/// Application code does not branch on connectivity -- a write is made the
/// same way in a tunnel as on Wi-Fi -- but it does *show* it: the offline
/// banner, the queued-writes count, the "last synced" line. That reading is
/// a signal like any other, so a banner is a widget that rebuilds and not a
/// listener somebody has to remember to dispose.
///
/// The specification has named `DV.Platform.network.status` and `.since`
/// since Offline-First Models was written and nothing existed, so there was
/// nothing for a banner to read and nothing for the offline store to learn
/// that it could replay.
library dartvel_flutter.platform.network;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'network_source.dart';

/// What the device can reach.
///
/// [metered] is separate from [offline] because they call for different
/// behaviour: a sync may proceed on a metered connection and a video
/// prefetch should not. [unknown] is separate from [online] because assuming
/// online is how the first write on a train is attempted, fails, and is
/// reported as an error rather than queued.
enum DVNetworkStatus { unknown, online, metered, offline }

/// `DV.Platform.network`.
class DVNetwork {
  const DVNetwork();

  /// What the platform last reported, or [DVNetworkStatus.unknown] on a
  /// target whose binding is not registered.
  DVNetworkStatus get status => DVNetworkSource.status;

  /// When [status] last changed, or null if nothing has reported yet.
  ///
  /// What changed it, not what reported it: a platform that re-reports the
  /// same status every few seconds would otherwise make "offline since" read
  /// as a few seconds ago, for ever.
  DateTime? get since => DVNetworkSource.since;

  /// Each change. An unchanged report is not one.
  Stream<DVNetworkStatus> get changes => DVNetworkSource.changes;

  /// Whether a request is worth making.
  ///
  /// True for [DVNetworkStatus.metered], which is a connection. True for
  /// [DVNetworkStatus.unknown] as well: refusing to try because nothing has
  /// reported would strand every target that has no binding, and a write's
  /// own failure is what says the network is gone.
  bool get canReachTheServer => status != DVNetworkStatus.offline;

  /// The status, rebuilding the widget [context] belongs to when it changes.
  ///
  /// One subscription per element, however often it rebuilds. Nothing tells
  /// a signal an element went away, so the first change after it did is when
  /// the subscription goes.
  DVNetworkStatus watch(BuildContext context) {
    final Element element = context as Element;
    if (_watchers[element] == null) {
      late final StreamSubscription<DVNetworkStatus> subscription;
      subscription = changes.listen((DVNetworkStatus _) {
        if (element.mounted) {
          element.markNeedsBuild();
          return;
        }
        _watchers[element] = null;
        unawaited(subscription.cancel());
      });
      _watchers[element] = subscription;
    }
    return status;
  }

  static final Expando<StreamSubscription<DVNetworkStatus>> _watchers =
      Expando<StreamSubscription<DVNetworkStatus>>('DV.Platform.network');
}
