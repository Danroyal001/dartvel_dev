import 'dart:async';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVInstanceLock, DVSingleInstance;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/opened_files.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(DVOpenedFiles.resetForTest);
  tearDown(() {
    for (final String name in const <String>['associations.opened', 'media.pick', 'dialogs.openFile']) {
      DVNativeBridge.unregister(name);
    }
  });

  group('one shape from every platform', () {
    test('Android: take() answers JSON with a cache path, a type, a size and the content URI', () {
      final List<DVOpenedFile> files = dvOpenedFilesFrom(
          '[{"path":"/data/user/0/shop/cache/dartvel-opened/1-march.order","name":"march.order",'
          '"mimeType":"application/x-shop-order","bytes":42,"uri":"content://downloads/7"}]');
      final DVOpenedFile file = files.single;
      expect(file.name, 'march.order');
      expect(file.path, endsWith('1-march.order'));
      expect(file.mimeType, 'application/x-shop-order');
      expect(file.size, 42, reason: 'Android reports the copied size as bytes');
      expect(file.uri, 'content://downloads/7');
      expect(file.extension, 'order');
    });

    test('iOS: the delegate\'s list has a path and a name', () {
      final DVOpenedFile file = dvOpenedFilesFrom('[{"path":"/tmp/dartvel-opened/9-a.order","name":"a.order"}]').single;
      expect(file.path, '/tmp/dartvel-opened/9-a.order');
      expect(file.name, 'a.order');
      expect(file.mimeType, isNull);
    });

    test('web and pickers: the bytes come with the file', () async {
      final DVOpenedFile file = dvOpenedFilesFrom(<Object?>[
        <String, Object?>{'name': 'a.order', 'mimeType': 'application/x-shop-order', 'bytes': <int>[1, 2, 3]},
      ]).single;
      expect(file.path, isNull);
      expect(file.size, 3);
      expect(await file.read(), <int>[1, 2, 3]);
    });

    test('nothing, or nonsense, is no files rather than an error', () {
      expect(dvOpenedFilesFrom(null), isEmpty);
      expect(dvOpenedFilesFrom(''), isEmpty);
      expect(dvOpenedFilesFrom('not json'), isEmpty);
      expect(dvOpenedFilesFrom('[{"name":"no path and no bytes"}]'), isEmpty);
    });

    test('a file with a path is read from disk', () async {
      final Directory directory = Directory.systemTemp.createTempSync('dv_opened_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final File on = File('${directory.path}/b.order')..writeAsBytesSync(<int>[7, 8]);
      final DVOpenedFile file = DVOpenedFile.atPath(on.path);
      expect(file.name, 'b.order');
      expect(await file.read(), <int>[7, 8]);
    });
  });

  group('delivery', () {
    test('a file that arrives before anything listens goes to the first listener', () async {
      DVOpenedFiles.deliver(<DVOpenedFile>[DVOpenedFile.atPath('/home/ada/launch.order')]);
      final List<String> seen = <String>[];
      final StreamSubscription<DVOpenedFile> listening =
          const DVFileAssociations().opened.listen((DVOpenedFile file) => seen.add(file.name));
      addTearDown(listening.cancel);
      await pumpEventQueue();
      expect(seen, <String>['launch.order']);
      DVOpenedFiles.deliver(<DVOpenedFile>[DVOpenedFile.atPath('/home/ada/later.order')]);
      await pumpEventQueue();
      expect(seen, <String>['launch.order', 'later.order']);
    });

    test('initial() is what the application was started with, taken from the platform once', () async {
      int takes = 0;
      DVNativeBridge.register('associations.opened', (Object? _) {
        takes++;
        return takes == 1 ? '[{"path":"/cache/1-a.order","name":"a.order"}]' : '[]';
      });
      final List<DVOpenedFile> first = await const DVFileAssociations().initial();
      expect(first.map((DVOpenedFile file) => file.name), <String>['a.order']);
      DVOpenedFiles.deliver(<DVOpenedFile>[DVOpenedFile.atPath('/cache/2-b.order')]);
      final List<DVOpenedFile> again = await const DVFileAssociations().initial();
      expect(again.map((DVOpenedFile file) => file.name), <String>['a.order'], reason: 'a file opened later is not part of the launch');
      expect(takes, 1);
    });

    test('a phone hands over a file opened while running when the app resumes', () async {
      final List<String> queue = <String>[];
      DVNativeBridge.register('associations.opened', (Object? _) {
        final String answer = '[${queue.join(',')}]';
        queue.clear();
        return answer;
      });
      final List<String> seen = <String>[];
      final StreamSubscription<DVOpenedFile> listening =
          const DVFileAssociations().opened.listen((DVOpenedFile file) => seen.add(file.name));
      addTearDown(listening.cancel);
      await pumpEventQueue();
      expect(seen, isEmpty);
      queue.add('{"path":"/cache/3-c.order","name":"c.order"}');
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(seen, <String>['c.order']);
    });

    test('a desktop launch with a file delivers it as well as opening the files route', () async {
      final Directory directory = Directory.systemTemp.createTempSync('dv_opened_launch_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final List<String> routes = <String>[];
      final DVAppLaunchResult launch = await DVAppLaunch.start(
        appId: 'shop',
        arguments: <String>['/home/ada/report.order'],
        lockPath: '${directory.path}/shop.lock',
        open: (String route) async => routes.add(route),
        poll: const Duration(milliseconds: 20),
        acquire: (String path) => DVSingleInstance.acquire(path) as DVInstanceLock,
      );
      addTearDown(launch.stop);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(routes, <String>['/open?path=%2Fhome%2Fada%2Freport.order']);
      final List<DVOpenedFile> started = await const DVFileAssociations().initial();
      expect(started.single.path, '/home/ada/report.order');
    });
  });

  group('the picker fallback', () {
    test('a desktop picker is narrowed to the types and feeds the same stream', () async {
      Object? asked;
      DVNativeBridge.register('dialogs.openFile', (Object? arguments) {
        asked = arguments;
        return <String, Object?>{'paths': <String>['/home/ada/picked.order']};
      });
      final List<String> seen = <String>[];
      final StreamSubscription<DVOpenedFile> listening =
          const DVFileAssociations().opened.listen((DVOpenedFile file) => seen.add(file.name));
      addTearDown(listening.cancel);
      final List<DVOpenedFile> picked = await const DVFileAssociations().pick(
        types: const <DVFileType>[DVFileType(mimeType: 'application/x-shop-order', extensions: <String>['.order'], description: 'Order')],
      );
      await pumpEventQueue();
      expect(picked.single.path, '/home/ada/picked.order');
      expect(seen, <String>['picked.order']);
      expect((asked! as Map<Object?, Object?>)['filters'], <Object?>[
        <String, Object?>{'label': 'Order', 'extensions': <String>['order']},
      ]);
    });

    test('elsewhere it is media.pick for any file, accepting the types', () async {
      Object? asked;
      DVNativeBridge.register('media.pick', (Object? arguments) {
        asked = arguments;
        return <Object?>[
          <String, Object?>{'name': 'a.order', 'bytes': <int>[1]},
        ];
      });
      final List<DVOpenedFile> picked = await const DVFileAssociations().pick(
        types: const <DVFileType>[DVFileType(mimeType: 'application/x-shop-order', extensions: <String>['order'])],
        multiple: true,
      );
      expect(picked.single.name, 'a.order');
      expect(asked, <String, Object?>{
        'type': 'file',
        'multiple': true,
        'accept': <String>['application/x-shop-order', '.order'],
      });
    });

    test('canPick says whether there is a picker', () {
      expect(const DVFileAssociations().canPick, isFalse);
      DVNativeBridge.register('media.pick', (Object? _) => const <Object?>[]);
      expect(const DVFileAssociations().canPick, isTrue);
    });
  });
}
