// DV.Updates on a Shorebird build: updates.check, updates.apply and
// updates.rollback bound to the Shorebird updater's C API over FFI.
//
// The updater is linked into Shorebird's Flutter engine, not into a package,
// so its symbols are looked up in the running process. Nothing here has them;
// the native side is a fake with the updater's own status codes, and what is
// asserted is the translation -- which is where a wrong answer would look
// plausible: an installed patch reported as a failure, a failed download
// reported as nothing to do.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeUpdater implements DVShorebirdNative {
  FakeUpdater({
    this.linked = true,
    this.current = 0,
    this.next = 0,
    this.downloadable = false,
    this.status = DVShorebirdNative.noUpdate,
    this.message,
  });

  @override
  final bool linked;
  int current;
  int next;
  bool downloadable;
  int status;
  String? message;
  final List<String?> channels = <String?>[];
  List<int> rolledBackOnCheck = const <int>[];

  @override
  int currentPatch() => current;

  @override
  int nextPatch() => next;

  @override
  bool checkForUpdate(String? channel) {
    channels.add(channel);
    // A check is when the updater learns of rollbacks, and it acts on them
    // then: a rolled-back next patch is not booted.
    if (rolledBackOnCheck.contains(next)) next = 0;
    return downloadable;
  }

  @override
  (int, String?) update(String? channel) {
    channels.add(channel);
    if (status == DVShorebirdNative.updateInstalled) next = current + 1;
    return (status, message);
  }
}

void clearUpdateBindings() {
  for (final String name in <String>[
    'updates.check',
    'updates.apply',
    'updates.rollback',
  ]) {
    DVNativeBridge.unregister(name);
  }
}

void main() {
  late FakeUpdater updater;

  Future<void> install(FakeUpdater native) async {
    updater = native;
    clearUpdateBindings();
    final bool ok = DVShorebirdUpdates.register(
      native: () => updater,
      run: <R>(R Function() work) async => work(),
    );
    expect(ok, native.linked);
  }

  tearDown(clearUpdateBindings);

  test('a build without the updater registers nothing and says why', () async {
    await install(FakeUpdater(linked: false));
    expect(DVNativeBridge.registered, isNot(contains('updates.check')));
    expect(DVShorebirdUpdates.lastFailure, contains('Shorebird'));
  });

  test('a Shorebird build binds all three names', () async {
    await install(FakeUpdater());
    expect(
      DVNativeBridge.registered,
      containsAll(<String>['updates.check', 'updates.apply', 'updates.rollback']),
    );
  });

  test('check reports a downloadable patch, with the channel as a track',
      () async {
    await install(FakeUpdater(current: 2, next: 2, downloadable: true));
    final DVUpdateInfo info = await const DVUpdates().check();
    expect(info.available, isTrue);
    expect(info.metadata['provider'], 'shorebird');
    expect(info.metadata['currentPatch'], '2');
    // production is Shorebird's stable track.
    expect(updater.channels, <String?>['stable']);

    await const DVUpdates().check(channel: DVUpdateChannel.beta);
    expect(updater.channels.last, 'beta');
  });

  test('nothing to download and nothing waiting is not available', () async {
    await install(FakeUpdater(current: 3, next: 3));
    final DVUpdateInfo info = await const DVUpdates().check();
    expect(info.available, isFalse);
  });

  test('a patch already downloaded but not yet booted is still available, '
      'and needs a restart', () async {
    await install(FakeUpdater(current: 1, next: 2));
    final DVUpdateInfo info = await const DVUpdates().check();
    expect(info.available, isTrue);
    expect(info.patchId, '2');
    expect(info.metadata['restartRequired'], 'true');
  });

  test('apply installs through the updater and succeeds', () async {
    await install(
      FakeUpdater(
        current: 0,
        next: 0,
        downloadable: true,
        status: DVShorebirdNative.updateInstalled,
      ),
    );
    await const DVUpdates().apply();
    expect(updater.next, 1);
  });

  test('an update already running elsewhere is not a failure', () async {
    await install(
      FakeUpdater(downloadable: true, status: DVShorebirdNative.inProgress),
    );
    await const DVUpdates().apply();
  });

  test('a failed download is an error carrying the updater\'s message', () async {
    await install(
      FakeUpdater(
        downloadable: true,
        status: DVShorebirdNative.hadError,
        message: 'connection reset',
      ),
    );
    await expectLater(
      const DVUpdates().apply(),
      throwsA(
        isA<Object>().having(
          (Object e) => '$e',
          'message',
          contains('connection reset'),
        ),
      ),
    );
  });

  test('a patch that fails its hash is an error, not "nothing to do"',
      () async {
    await install(
      FakeUpdater(
        downloadable: true,
        status: DVShorebirdNative.badPatch,
        message: 'hash mismatch',
      ),
    );
    await expectLater(
      const DVUpdates().apply(),
      throwsA(
        isA<Object>().having((Object e) => '$e', 'message', contains('hash')),
      ),
    );
  });

  test('rollback asks the updater, which applies a published rollback, and '
      'reports whether an earlier patch boots next', () async {
    await install(FakeUpdater(current: 2, next: 2)..rolledBackOnCheck = <int>[2]);
    await const DVUpdates().rollback();
    expect(updater.next, 0);
  });

  test('rollback with nothing rolled back is refused, saying where it is '
      'published', () async {
    await install(FakeUpdater(current: 2, next: 2));
    await expectLater(
      const DVUpdates().rollback(),
      throwsA(
        isA<Object>().having(
          (Object e) => '$e',
          'message',
          contains('dartvel updates rollback'),
        ),
      ),
    );
  });
}
