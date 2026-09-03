// The live window list a running application publishes, for
// `dartvel inspect windows` to read.
//
// An inspector run from a shell cannot ask a running app; the app writes
// what it has open to a file beside its single-instance lock every time
// that changes, with the time it wrote it, and the inspector reads the file
// when it is fresh. What the tests hold to: every open and close is
// written; the file names the app, the time and each window's route and
// kind; stopping stops the writes; and a stale file is what an inspector
// would call not live.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvLiveWindowsPathFor;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() {
    DVWindowManager.reset();
    dir = Directory.systemTemp.createTempSync('dv_live_');
    DVWindowManager.capabilityOverride = const DVWindowingCapability(multiWindow: true, sameEngine: true, tearOut: true);
    int n = 0;
    DVNativeBridge.register('window.open', (Object? a) => 'win-${++n}');
    DVNativeBridge.register('window.close', (Object? a) => true);
  });
  tearDown(() {
    DVWindowManager.reset();
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
    dir.deleteSync(recursive: true);
  });

  Map<String, Object?> read(String path) => (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

  test('the path is beside the lock, per app', () {
    expect(dvLiveWindowsPathFor('shop'), endsWith('dartvel-shop.windows.json'));
  });

  test('every open and close is written, with the app, the time and each window', () async {
    final String path = '${dir.path}/shop.windows.json';
    final void Function() stop = DV.Platform.Window.publishLiveWindows(path, app: 'shop');
    addTearDown(stop);

    final DVWindow orders = await DV.Platform.Window.open(const DVRouteTarget('/orders'));
    final Map<String, Object?> state = read(path);
    expect(state['app'], 'shop');
    expect(DateTime.parse(state['at']! as String).difference(DateTime.now()).abs(), lessThan(const Duration(seconds: 5)));
    final List<Object?> windows = state['windows']! as List<Object?>;
    expect(windows.map((Object? w) => (w! as Map)['route']), contains('/orders'));
    expect((windows.first! as Map)['kind'], isNotEmpty);

    await DV.Platform.Window.open(const DVRouteTarget('/stock'));
    expect((read(path)['windows']! as List<Object?>).length, greaterThanOrEqualTo(2));

    await orders.close();
    expect((read(path)['windows']! as List<Object?>).map((Object? w) => (w! as Map)['route']), isNot(contains('/orders')));
  });

  test('stopped, nothing more is written', () async {
    final String path = '${dir.path}/shop.windows.json';
    final void Function() stop = DV.Platform.Window.publishLiveWindows(path, app: 'shop');
    await DV.Platform.Window.open(const DVRouteTarget('/orders'));
    final String before = File(path).readAsStringSync();
    stop();
    await DV.Platform.Window.open(const DVRouteTarget('/stock'));
    expect(File(path).readAsStringSync(), before);
  });
}
