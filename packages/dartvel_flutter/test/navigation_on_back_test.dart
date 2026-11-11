// DV.Navigation.onBack: Back closes what is on top (a drawer, a sheet) before
// it navigates. The router answers Back first, so an app's own observer
// never heard it (Dev Launcher's drawer on Android 12, 11 Nov 2026).
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('a handler that takes Back stops it; removed, Back reaches the router again', (WidgetTester tester) async {
    final GoRouter router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('Home')),
      GoRoute(path: '/next', builder: (_, __) => const Text('Next')),
    ]);
    DVNavigation.attach(router);
    addTearDown(DVNavigation.detach);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/next');
    await tester.pumpAndSettle();

    int closed = 0;
    final VoidCallback remove = DV.Navigation.onBack(() {
      closed++;
      return true;
    });
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.text('Next'), findsOneWidget, reason: 'the handler took Back, so the page stayed');

    remove();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.text('Home'), findsOneWidget, reason: 'with the handler gone, Back pops the page');
  });

  testWidgets('a handler that declines lets the router have Back', (WidgetTester tester) async {
    final GoRouter router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('Home')),
      GoRoute(path: '/next', builder: (_, __) => const Text('Next')),
    ]);
    DVNavigation.attach(router);
    addTearDown(DVNavigation.detach);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/next');
    await tester.pumpAndSettle();
    final VoidCallback remove = DV.Navigation.onBack(() => false);
    addTearDown(remove);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('while a handler is registered, Android is told the app handles Back', (WidgetTester tester) async {
    // At the root, with no page to pop, Flutter tells Android the app does
    // not handle Back, and Android never sends it: a launcher's drawer stayed
    // open on Android 12. A handler must claim Back until it is removed.
    final List<Object?> said = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') said.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final GoRouter router = GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => const Text('Home'))]);
    DVNavigation.attach(router);
    addTearDown(DVNavigation.detach);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    said.clear();
    final VoidCallback remove = DV.Navigation.onBack(() => true);
    await tester.pump();
    expect(said.last, isTrue, reason: 'Back is claimed while the handler is there');
    remove();
    await tester.pump();
    expect(said.last, isFalse, reason: 'with nothing to pop and no handler, Back goes back to Android');
  });
}
