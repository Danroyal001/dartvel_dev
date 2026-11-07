// The hook the build's semantics read drives a running app through.
//
// The read used to load every route afresh, and each load booted the whole
// app -- its code, the renderer, the first frame -- for about ten seconds of a
// route's eleven. It now boots the app once per browser tab and moves between
// routes inside it, through `globalThis.__dartvelCapture`: `go(path)` goes to a
// route the way a link does, after forgetting the images the previous route
// decoded (so the next route asks for its own and the capture sees them), and
// `location()` says where the router ended up, so a route that redirects is
// read with a fresh load instead.
//
// Only a browser under automation (navigator.webdriver) gets the hook.
//
// Run with: flutter test --platform chrome test/capture_hook_browser_test.dart
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_flutter/src/routing/capture_hook_web.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

JSObject? hook() => globalContext.getProperty<JSObject?>('__dartvelCapture'.toJS);

GoRouter router() => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('home', textDirection: .ltr)),
        GoRoute(path: '/docs', builder: (_, _) => const Text('docs', textDirection: .ltr)),
        GoRoute(path: '/old', redirect: (_, _) => '/docs'),
      ],
    );

void main() {
  setUp(() => globalContext.delete('__dartvelCapture'.toJS));

  testWidgets('a browser under automation can move the app between routes',
      (WidgetTester tester) async {
    final GoRouter app = router();
    dvInstallCaptureHook(app, automated: true);
    await tester.pumpWidget(MaterialAppShim(app));
    expect(hook(), isNotNull);

    hook()!.callMethod<JSAny?>('go'.toJS, '/docs'.toJS);
    await tester.pumpAndSettle();
    expect(find.text('docs'), findsOneWidget);
    expect(hook()!.callMethod<JSString>('location'.toJS).toDart, '/docs');
  });

  testWidgets('a redirect shows in the location, so the read can tell',
      (WidgetTester tester) async {
    final GoRouter app = router();
    dvInstallCaptureHook(app, automated: true);
    await tester.pumpWidget(MaterialAppShim(app));

    hook()!.callMethod<JSAny?>('go'.toJS, '/old'.toJS);
    await tester.pumpAndSettle();
    expect(hook()!.callMethod<JSString>('location'.toJS).toDart, '/docs');
  });

  testWidgets('going forgets the decoded images and the recorded slots',
      (WidgetTester tester) async {
    final GoRouter app = router();
    dvInstallCaptureHook(app, automated: true);
    await tester.pumpWidget(MaterialAppShim(app));
    globalContext.setProperty('__dartvelImages'.toJS, JSObject());
    PaintingBinding.instance.imageCache.putIfAbsent('probe',
        () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future));
    expect(PaintingBinding.instance.imageCache.containsKey('probe'), isTrue);

    hook()!.callMethod<JSAny?>('go'.toJS, '/docs'.toJS);
    await tester.pumpAndSettle();
    expect(PaintingBinding.instance.imageCache.containsKey('probe'), isFalse);
    expect(globalContext.has('__dartvelImages'), isFalse);
  });

  testWidgets('a browser a person is using gets no hook', (WidgetTester tester) async {
    dvInstallCaptureHook(router(), automated: false);
    expect(hook(), isNull);
  });
}

/// The smallest app that hosts a router.
class MaterialAppShim extends StatelessWidget {
  const MaterialAppShim(this.router, {super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => WidgetsApp.router(
        routerConfig: router,
        color: const Color(0xFF000000),
      );
}
