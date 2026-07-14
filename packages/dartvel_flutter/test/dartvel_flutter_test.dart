import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mix/mix.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

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
          body: DVBox(
            const DVText('Save'),
          ).modifier(style),
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
                return Column(
                  children: [
                    Text('Count: ${counter.value}'),
                    ElevatedButton(
                      onPressed: () {
                        counter.value = counter.value + 1;
                      },
                      child: const Text('Increment'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Count: 1'), findsOneWidget);
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
  });

  test('integration APIs provide concrete local behavior', () async {
    await DV.Auth.signIn();
    expect(DV.Auth.currentUser, isA<DVAuthUser>());

    await DV.Auth.signInWithEmailAndPassword(
      email: 'dev@example.com',
      password: 'secret',
    );
    final user = DV.Auth.currentUser as DVAuthUser;
    expect(user.email, 'dev@example.com');

    expect(await DV.Platform.camera.takePhoto(), isEmpty);
    expect(
      await DV.Platform.location.getCoordinates(),
      {'latitude': 0, 'longitude': 0},
    );
    expect(await DV.Platform.media.pick(), isEmpty);

    await DV.Platform.files.writeBytes('local.bin', [7, 8, 9]);
    expect(await DV.Platform.files.readBytes('local.bin'), [7, 8, 9]);
    await DV.Platform.files.delete('local.bin');
    expect(await DV.Platform.files.readBytes('local.bin'), isEmpty);

    expect(await DV.Platform.permissions.request('camera'), isTrue);
    expect(await DV.Platform.permissions.isGranted('camera'), isTrue);

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

    await DV.Storage.upload('avatar', [1, 2, 3]);
    expect(await DV.Storage.download('avatar'), [1, 2, 3]);

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
}
