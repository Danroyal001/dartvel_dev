// The first test that runs the application rather than a widget in isolation.
//
// Every other test in this repository is a unit or widget test on Linux. That
// leaves a whole class of failure uncovered: a build that produces an artifact
// which does not start, a generated file that compiles but wires nothing, a
// native asset that is bundled but never loads. Windows proved the point —
// four bugs corrupting generated output on every platform passed 1,101 tests
// for months, because nothing ever launched the result.
//
// Run with: dartvel test e2e   (or: flutter test integration_test -d linux)
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('the application starts', () {
    testWidgets('boots, renders a frame, and settles', (tester) async {
      // The assertion that matters is not a particular widget — it is that the
      // real entrypoint runs to a settled frame without throwing. A generated
      // router that references a type it never imported fails here and nowhere
      // else.
      // The real entrypoint, configuration and all — not a hand-built
      // widget tree that skips whatever main() actually does.
      await tester.pumpWidget(createDartvelExampleApp());
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(tester.takeException(), isNull,
          reason: 'the app threw while starting');
      expect(find.byType(MaterialApp), findsOneWidget,
          reason: 'no application shell was built');
    });

    testWidgets('renders visible text, not an empty frame', (tester) async {
      // A frame that settles but paints nothing is the failure mode a smoke
      // test misses. Something readable has to be on screen.
      // The real entrypoint, configuration and all — not a hand-built
      // widget tree that skips whatever main() actually does.
      await tester.pumpWidget(createDartvelExampleApp());
      await tester.pumpAndSettle(const Duration(seconds: 10));

      final texts = find.byType(Text);
      expect(texts, findsWidgets, reason: 'the first frame painted no text');
    });

    testWidgets('the generated client is wired, not merely compiled',
        (tester) async {
      // Generated symbols existing is a compile-time fact. That the running
      // app can reach them is not, and it is what broke on Windows.
      final router = createDartvelRouter();
      expect(router.configuration.routes, isNotEmpty,
          reason: 'no routes were generated into the running app');
    });
  });
}
