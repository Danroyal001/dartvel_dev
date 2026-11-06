import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      reason: 'the loading shell must not remove the first-frame picture',
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
}
