/// Where `DV.Platform.network` gets its answer.
///
/// Not in the barrel an application imports. Reporting connectivity is the
/// platform binding's job -- the browser's `online` and `offline` events, a
/// desktop or mobile binding registered through `DVNativeBridge` -- and an
/// application reads the signal rather than feeding it. Its own tests drive
/// it through here, which is the other reason it exists.
library dartvel_flutter.platform.network_source;

import 'dart:async';

import 'network.dart';

/// Holds what the platform last said.
///
/// Static because connectivity belongs to the process, not to a widget: the
/// binding reports it whenever the platform decides, which is not at first
/// frame and not tied to anything on screen.
class DVNetworkSource {
  DVNetworkSource._();

  static DVNetworkStatus _status = DVNetworkStatus.unknown;
  static DateTime? _since;
  static final StreamController<DVNetworkStatus> _changes =
      StreamController<DVNetworkStatus>.broadcast();

  static DVNetworkStatus get status => _status;
  static DateTime? get since => _since;
  static Stream<DVNetworkStatus> get changes => _changes.stream;

  /// What the platform now reports.
  ///
  /// A report of the status it already holds changes nothing and is not a
  /// change on the stream: a binding that polls every few seconds would
  /// otherwise rebuild every watching widget each time, and move `since` so
  /// that "offline since" always read as a moment ago.
  static void report(DVNetworkStatus status, {DateTime? at}) {
    if (status == _status) return;
    _status = status;
    _since = at ?? DateTime.now();
    _changes.add(status);
  }

  /// Back to having heard nothing. For tests.
  ///
  /// Silent on purpose: this runs in setUp and tearDown, and a change
  /// delivered into a test that has already finished is reported as that
  /// test failing rather than as this. A widget built after a reset reads
  /// [status] directly and sees `unknown`.
  static void reset() {
    _status = DVNetworkStatus.unknown;
    _since = null;
  }
}
