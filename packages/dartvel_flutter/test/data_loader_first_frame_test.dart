import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/routing/first_frame_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => dvDebugWebFirstFrame = true);
  tearDown(() => dvDebugWebFirstFrame = null);
  testWidgets('initial routing holds the frame before a loader is mounted', (
    tester,
  ) async {
    final decision = Completer<String?>();
    final ready = Completer<Object?>();
    final router = DVRouter(
      initialLocation: '/page',
      routes: [
        GoRoute(
          path: '/page',
          redirect: (_, _) => decision.future,
          builder: (_, _) => DvDataLoader(
            load: () => ready.future,
            child: const Text('Ready route'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.binding.resetFirstFrameSent();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    expect(tester.binding.sendFramesToEngine, isFalse);
    decision.complete(null);
    await tester.pump();
    await tester.pump();
    expect(tester.binding.sendFramesToEngine, isFalse);
    ready.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Ready route'), findsOneWidget);
    expect(tester.binding.sendFramesToEngine, isTrue);
  });

  testWidgets('the first engine frame waits for the initial page content', (
    tester,
  ) async {
    final ready = Completer<Object?>();
    tester.binding.resetFirstFrameSent();
    await tester.pumpWidget(
      MaterialApp(
        home: DvDataLoader(
          load: () => ready.future,
          child: const Text('Ready page'),
        ),
      ),
    );
    expect(
      tester.binding.sendFramesToEngine,
      isFalse,
      reason: 'the loading shell must not remove the splash',
    );
    ready.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Ready page'), findsOneWidget);
    expect(tester.binding.sendFramesToEngine, isTrue);
  });

  testWidgets('disposing a pending page releases its first-frame hold', (
    tester,
  ) async {
    final ready = Completer<Object?>();
    tester.binding.resetFirstFrameSent();
    await tester.pumpWidget(
      MaterialApp(
        home: DvDataLoader(load: () => ready.future, child: const Text('Page')),
      ),
    );
    expect(tester.binding.sendFramesToEngine, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.sendFramesToEngine, isTrue);
    ready.complete(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('native loading still paints its accessible loading shell', (
    tester,
  ) async {
    dvDebugWebFirstFrame = false;
    final ready = Completer<Object?>();
    tester.binding.resetFirstFrameSent();
    await tester.pumpWidget(
      MaterialApp(
        home: DvDataLoader(load: () => ready.future, child: const Text('Page')),
      ),
    );
    expect(tester.binding.sendFramesToEngine, isTrue);
    ready.complete(null);
    await tester.pump();
  });
}
