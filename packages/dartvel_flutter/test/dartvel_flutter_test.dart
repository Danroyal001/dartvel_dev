import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DVBox and DVText render correctly with style modifiers',
      (WidgetTester tester) async {
    final style = const DVStyleModifier()
        .padding(12)
        .backgroundColor(Colors.blue)
        .color(Colors.white);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const DVBox(DVText('Save')).modifier(style),
        ),
      ),
    );

    expect(find.byType(DVBox), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('DVSignal reacts to state updates within ProviderScope',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final counter = context.signal(0);
                return DVBox.list([
                  DVText('Count: ${counter.value}'),
                  const DVText('Increment').modifier(
                    const DVModifier().onPressed(() {
                      counter.value = counter.value + 1;
                    }),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.text('Increment'));
    await tester.pumpAndSettle();

    expect(find.text('Count: 1'), findsOneWidget);
  });

  testWidgets('DVBox supports static and builder collection layouts',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DVBox.wrap([
            DVText('One'),
            DVText('Two'),
            DVText('Three'),
          ]),
        ),
      ),
    );

    expect(find.text('One'), findsOneWidget);
    expect(find.byType(Wrap), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DVBox.builder<int>(
            [1, 2, 3],
            (item) => DVText('Item $item'),
          ).grid(columns: 2),
        ),
      ),
    );

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DVBox.horizontalScrollable([
            DVText('Story 1'),
            DVText('Story 2'),
          ]),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Story 1'), findsOneWidget);
  });

  testWidgets('DVPlatform reports runtime screen and platform data',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    const platform = DVPlatform();

    expect(platform.currentPlatform, isNotEmpty);
    expect(platform.screenWidth, greaterThan(0));
    expect(platform.screenHeight, greaterThan(0));
    expect(platform.safeAreas.keys,
        containsAll(<String>['top', 'bottom', 'left', 'right']));
    expect(platform.breakpoint, isIn(<String>['mobile', 'tablet', 'desktop']));
    expect(platform.deviceType, isNotEmpty);
    expect(platform.type, platform.deviceType);
    expect(platform.deviceOrientation, platform.orientation);
    expect(platform.screen.size.width, platform.screenWidth);
    expect(platform.screen.safeAreaBounds, platform.safeAreas);
    expect(platform.Window.bounds.width, platform.screenWidth);
    expect(platform.display.isFullscreen, isFalse);
    expect(platform.display.isKiosk, isFalse);
    expect(platform.isChromiumExtension, isFalse);
    expect(platform.isFirefoxExtension, isFalse);
    expect(platform.browserExtension.isAvailable, isFalse);
    expect(
      () => platform.browserExtension.getManifest(),
      throwsA(isA<StateError>()),
    );
  });

  test('integration APIs provide concrete local behavior', () async {
    DVNativeBridge.register('camera.takePhoto', (_) => <int>[1, 2, 3]);
    DVNativeBridge.register(
        'location.current',
        (_) => {
              'latitude': 6.5244,
              'longitude': 3.3792,
            });
    DVNativeBridge.register(
        'media.pick',
        (_) => <Map<String, Object?>>[
              {'path': 'image.jpg', 'type': 'image'}
            ]);
    DVNativeBridge.register('permissions.request', (_) => true);
    DVNativeBridge.register('permissions.isGranted', (_) => true);
    DVNativeBridge.register('display.enterFullscreen', (arguments) {
      expect(arguments, isA<Map<String, Object>>());
      return true;
    });
    DVNativeBridge.register('display.exitFullscreen', (_) => true);
    DVNativeBridge.register('display.enableKiosk', (arguments) {
      expect(arguments, isA<Map<String, Object>>());
      return true;
    });
    DVNativeBridge.register('display.disableKiosk', (_) => true);

    await DV.Auth.signIn();
    expect(DV.Auth.currentUser, isA<DVAuthUser>());

    await DV.Auth.signInWithEmailAndPassword(
      email: 'dev@example.com',
      password: 'secret',
    );
    final user = DV.Auth.currentUser as DVAuthUser;
    expect(user.email, 'dev@example.com');

    expect(await DV.Platform.camera.takePhoto(), [1, 2, 3]);
    expect(
      await DV.Platform.location.getCoordinates(),
      {'latitude': 6.5244, 'longitude': 3.3792},
    );
    expect(await DV.Platform.media.pick(), [
      {'path': 'image.jpg', 'type': 'image'}
    ]);

    await DV.Platform.files.writeBytes('local.bin', [7, 8, 9]);
    expect(await DV.Platform.files.readBytes('local.bin'), [7, 8, 9]);
    await DV.Platform.files.delete('local.bin');
    expect(await DV.Platform.files.readBytes('local.bin'), isEmpty);

    expect(await DV.Platform.permissions.request('camera'), isTrue);
    expect(await DV.Platform.permissions.isGranted('camera'), isTrue);

    await DV.Platform.display.enterFullscreen(
      const DVFullscreenOptions(lockOrientation: true),
    );
    expect(DV.Platform.display.isFullscreen, isTrue);
    await DV.Platform.display.enableKiosk(
      const DVKioskOptions(allowedExitKeys: <String>['Escape']),
    );
    expect(DV.Platform.display.currentState.isKiosk, isTrue);
    expect(DV.Platform.display.currentState.isFullscreen, isTrue);
    await DV.Platform.display.disableKiosk();
    expect(DV.Platform.display.isKiosk, isFalse);
    await DV.Platform.display.exitFullscreen();
    expect(DV.Platform.display.isFullscreen, isFalse);

    expect(await DV.AI.chat('hello'), contains('hello'));
    expect(await DV.AI.embed('hello'), hasLength(16));
    expect(await DV.DB.query('select 1'), [
      {'1': 1}
    ]);

    await DV.DB.execute(
      'insert into users (id, name) values (?, ?)',
      [1, 'Ada'],
    );
    expect(await DV.DB.query('select * from users'), [
      {'id': 1, 'name': 'Ada'}
    ]);

    await DV.Storage.put('avatar', [1, 2, 3]);
    expect(await DV.Storage.get('avatar'), [1, 2, 3]);
    await DV.FileStorage.put('file-avatar', [4, 5, 6]);
    expect(await DV.BlobStorage.get('file-avatar'), [4, 5, 6]);

    final events = <dynamic>[];
    await DV.Realtime.subscribe('room', events.add);
    await DV.Realtime.publish('room', {'message': 'hi'});
    await Future<void>.delayed(Duration.zero);
    expect(events, [
      {'message': 'hi'}
    ]);
  });

  test('local cache and theme APIs have concrete behavior', () async {
    await DV.Cache.set('answer', 42);
    expect(await DV.Cache.get<int>('answer'), 42);

    await DV.Cache.delete('answer');
    expect(await DV.Cache.get<int>('answer'), isNull);

    DV.Theme.setMode(ThemeMode.dark);
    expect(DV.Theme.mode, ThemeMode.dark);
  });

  test('observability emits structured logs, metrics, and traces', () async {
    final provider = LocalAnalyticsProvider();
    Analytics.register(provider);

    await DV.log(
      'checkout completed',
      level: 'info',
      context: <String, Object>{'orderId': 'order-1'},
    );
    await DV.ObservabilityAndLogging.metric(
      'checkout_total',
      12.5,
      tags: <String, Object>{'currency': 'USD'},
    );
    final result = await DV.ObservabilityAndLogging.trace<int>(
      'calculate_total',
      () => 42,
      context: <String, Object>{'cartId': 'cart-1'},
    );
    await DV.ObservabilityAndLogging.profile<void>(
      'render_cart',
      () async {},
    );
    await DV.ObservabilityAndLogging.error(
      StateError('failed'),
      context: <String, Object>{'component': 'cart'},
    );
    await DV.ObservabilityAndLogging.diagnostic(
      'runtime',
      <String, Object>{'healthy': true},
    );

    expect(result, 42);
    expect(
      provider.events.map((event) => event.name),
      containsAll(<String>[
        'log',
        'metric',
        'trace',
        'error',
        'diagnostic',
      ]),
    );
    expect(provider.events.where((event) => event.name == 'trace').length, 2);
    expect(
      provider.events.first.parameters,
      containsPair('message', 'checkout completed'),
    );
  });

  test('form controls execute submit and reset callbacks', () {
    var submitted = false;
    var reset = false;

    final controls = DVFormControls(
      'model',
      onSubmit: () => submitted = true,
      onReset: () => reset = true,
    );

    controls.submit();
    controls.reset();

    expect(controls.model, 'model');
    expect(submitted, isTrue);
    expect(reset, isTrue);
  });

  test('DV facade exposes queues, signals, mail, notifications, and policies',
      () async {
    DV.Test.resetQueues();
    DV.Test.resetSignals();
    DV.Test.resetPolicies();

    final processed = <String>[];
    DV.Queues.register<String>(processed.add);
    await DV.Jobs.dispatch<String>('sync-user');
    expect(await DV.Queues.work(), 1);
    expect(processed, ['sync-user']);

    final signalValues = <String>[];
    DV.Signals.listen<String>(signalValues.add);
    await DV.Signals.emit<String>('user.created');
    expect(signalValues, ['user.created']);

    final mailProvider = DVMemoryMailProvider();
    DV.Mail.useProvider(mailProvider);
    await DV.Mail.send(
      const DVMailMessage(
        from: DVMailAddress('system@example.com'),
        to: <DVMailAddress>[DVMailAddress('dev@example.com')],
        subject: 'Queued',
        text: 'Done',
      ),
    );
    expect(mailProvider.sent.single.subject, 'Queued');

    final notificationProvider = DVMemoryNotificationProvider();
    DV.Notifications.register(notificationProvider);
    await DV.Notifications.send(
      'dev@example.com',
      const DVNotificationMessage(title: 'Build', body: 'Passed'),
    );
    expect(notificationProvider.sent.single.message.title, 'Build');

    DVNativeBridge.register('updates.check', (arguments) {
      expect(arguments, {'channel': 'production'});
      return <String, Object?>{
        'available': true,
        'version': '1.0.1',
        'patchId': 'patch-1',
        'required': false,
        'metadata': <String, String>{'provider': 'shorebird'},
      };
    });
    DVNativeBridge.register('updates.apply', (_) => true);
    DVNativeBridge.register('updates.rollback', (_) => true);
    final update = await DV.Updates.check();
    expect(update.available, isTrue);
    expect(update.metadata['provider'], 'shorebird');
    await DV.Updates.apply();
    await DV.Updates.rollback();

    DV.Auth.authorization.register<String, String>(
      'deploy',
      (user, resource) => user == 'admin' && resource == 'production',
    );
    expect(
      await DV.Auth.authorization.can<String, String>(
        'admin',
        'deploy',
        'production',
      ),
      isTrue,
    );

    DV.CacheInvalidation.tag('users:list', <String>['users']);
    expect(DV.CacheInvalidation.revalidateTag('users'), contains('users:list'));
  });

  testWidgets('prebuilt auth pages use Dartvel primitives without scaffolds',
      (WidgetTester tester) async {
    await DV.Auth.signOut();

    await tester.pumpWidget(
      MaterialApp(
        home: DV.Auth.SignInWithEmailAndPasswordPage(),
      ),
    );

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(DVBox), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'dev@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    final user = DV.Auth.currentUser as DVAuthUser;
    expect(user.email, 'dev@example.com');

    await DV.Auth.signOut();
    await tester.pumpWidget(
      MaterialApp(
        home: DV.Auth.SignInWithProviderPage(),
      ),
    );

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Continue with provider'), findsOneWidget);

    await tester.tap(find.text('Continue with provider'));
    await tester.pump();

    expect((DV.Auth.currentUser as DVAuthUser).provider, 'provider');
  });
}
