/// DV.Timers on Android: the timer is handed to the broadcast receiver
/// `dartvel build` writes for `dartvel.timers`, which rings it from the
/// operating system with the app closed and the screen off.
///
/// The receiver's half is in `dartvel_cli`'s `android_timers.dart`; the action
/// names and the events file below are the contract between the two and are
/// spelt the same there.
library dartvel_flutter.platform.android.android_timers_jni;

import 'dart:async';
import 'dart:io';

import 'package:jni/jni.dart';

import '../../timers/timer.dart';
import '../../timers/timer_basic_delivery.dart';
import '../../timers/timer_delivery.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/content/Intent.dart';

const String _schedule = 'dev.dartvel.timer.SCHEDULE';
const String _cancel = 'dev.dartvel.timer.CANCEL';
const String _silence = 'dev.dartvel.timer.SILENCE';

/// Under the app's files directory: what the receiver did while the app was
/// away, `<id>\t<action>\t<epoch ms>` a line.
const String dvAndroidTimerEventsFile = 'dartvel-timers/events.txt';

/// The receiver's delivery. [filesDirectory] is the app's files directory,
/// where the receiver writes the actions taken in its notifications.
final class DVAndroidTimerDelivery implements DVTimerDelivery {
  DVAndroidTimerDelivery(this._context, String filesDirectory)
      : _events = File('$filesDirectory/$dvAndroidTimerEventsFile') {
    // A snooze pressed in the notification while the app is open comes back
    // within two seconds; one pressed while it was closed, on the next start.
    scheduleMicrotask(readEvents);
    _poll = Timer.periodic(const Duration(seconds: 2), (Timer _) => readEvents());
  }

  final Context _context;
  final File _events;
  late final Timer _poll;
  final DVBasicTimerDelivery _plain = DVBasicTimerDelivery();
  final StreamController<DVTimerAction> _actions = StreamController<DVTimerAction>.broadcast();

  @override
  DVTimerReach get reach => .appClosed;

  @override
  Stream<DVTimerAction> get actions => _actions.stream;

  @override
  Future<DVTimerPermission> permission() => _plain.permission();

  @override
  Future<DVTimerPermission> requestPermission() => _plain.requestPermission();

  @override
  void prime() {}

  @override
  Future<void> schedule(DVTimer timer) async {
    _send(_schedule, timer.id, (Intent intent) {
      intent.putExtra$8('title'.toJString(), timer.label.toJString());
      intent.putExtra$8('body'.toJString(), dvTimerDoneBody(timer).toJString());
      intent.putExtra$8('route'.toJString(), (timer.route ?? '').toJString());
      intent.putExtra$5('at'.toJString(), timer.endsAt!.millisecondsSinceEpoch);
    });
  }

  @override
  Future<void> cancel(String id) async => _send(_cancel, id);

  /// Nothing: the receiver's alarm rings it, the notification and its sound
  /// included, whether or not the app is open.
  @override
  Future<void> ring(DVTimer timer) async {}

  @override
  Future<void> silence(String id) async => _send(_silence, id);

  void _send(String action, String id, [void Function(Intent intent)? extras]) {
    final String? package = _context.packageName?.toDartString(releaseOriginal: true);
    if (package == null) return;
    final Intent intent = Intent();
    intent.setClassName$1(package.toJString(), '$package.DartvelTimerReceiver'.toJString());
    intent.setAction(action.toJString());
    intent.putExtra$8('id'.toJString(), id.toJString());
    extras?.call(intent);
    _context.sendBroadcast(intent);
  }

  /// Reads what the receiver recorded and forgets it.
  void readEvents() {
    final List<String> lines;
    try {
      if (!_events.existsSync()) return;
      lines = _events.readAsLinesSync();
      _events.deleteSync();
    } on FileSystemException {
      return;
    }
    for (final DVTimerAction action in dvAndroidTimerEvents(lines)) {
      _actions.add(action);
    }
  }

  void dispose() => _poll.cancel();
}

/// The receiver's lines as actions; a line that is not one is skipped.
List<DVTimerAction> dvAndroidTimerEvents(List<String> lines) => <DVTimerAction>[
      for (final String line in lines)
        if (line.split('\t') case [final String id, final String action, ...])
          if (dvTimerActionFrom(id, action) case final DVTimerAction parsed) parsed,
    ];
