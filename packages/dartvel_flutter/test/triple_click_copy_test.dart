// Ctrl+C after a triple-click copies the paragraph the triple-click selected
// (Tori and Learnacer, Dartvel 3.47.7: drag and Ctrl+C copied, a triple-click
// and Ctrl+C copied nothing).
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/accessibility/browser_clicks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget page() => MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Terms'),
        child: DVBox.list(const <Widget>[
          DVText('The terms for dartvel.dev and Dartvel.'),
          DVText('Last updated 1 October 2026.'),
        ]),
      ),
    );

Future<void> copy(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> clicks(WidgetTester tester, Offset at, int count) async {
  for (int click = 0; click < count; click++) {
    final TestGesture mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 30));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  late List<String?> written;
  setUp(() {
    written = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        written.add((call.arguments as Map<Object?, Object?>)['text'] as String?);
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  for (final TargetPlatform platform in <TargetPlatform>[TargetPlatform.linux, TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets('a triple-click, then Ctrl+C, copies the paragraph (${platform.name})', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await clicks(tester, tester.getCenter(find.text('Last updated 1 October 2026.')), 3);
      if (platform == TargetPlatform.macOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
      } else {
        await copy(tester);
      }
      debugDefaultTargetPlatformOverride = null;
      expect(written, isNotEmpty, reason: 'nothing was copied');
      expect(written.last, contains('Last updated 1 October 2026.'));
    });
  }

  testWidgets('a double-click, then Ctrl+C, copies the word', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final Offset start = tester.getTopLeft(find.text('Last updated 1 October 2026.'));
    await clicks(tester, start + const Offset(8, 8), 2);
    await copy(tester);
    debugDefaultTargetPlatformOverride = null;
    expect(written, isNotEmpty);
    expect(written.last, 'Last');
  });

  // The browser counts a run of clicks with the system's double-click time
  // (500 ms on Windows by default); Flutter gives up after 300 ms. Clicks 400
  // ms apart are a triple-click to the browser and three single clicks to
  // Flutter, which selected nothing.
  for (final int count in <int>[2, 3]) {
    testWidgets('a run of $count clicks the browser counted and Flutter did not selects and copies', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final Offset at = tester.getTopLeft(find.text('Last updated 1 October 2026.')) + const Offset(8, 8);
      for (int click = 0; click < count; click++) {
        final TestGesture mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpAndSettle();
      DVBrowserClicks.report(count, at);
      await tester.pump();
      await copy(tester);
      debugDefaultTargetPlatformOverride = null;
      expect(written, isNotEmpty, reason: 'nothing was copied');
      expect(written.last, count == 2 ? 'Last' : 'Last updated 1 October 2026.');
    });
  }

  testWidgets('a run Flutter counted itself ends as it did', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final Offset at = tester.getCenter(find.text('Last updated 1 October 2026.'));
    await clicks(tester, at, 3);
    DVBrowserClicks.report(3, at);
    await tester.pump();
    await copy(tester);
    debugDefaultTargetPlatformOverride = null;
    expect(written.last, 'Last updated 1 October 2026.');
  });

  testWidgets('a run of clicks off the page selects nothing', (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    DVBrowserClicks.report(3, const Offset(5000, 5000));
    await tester.pump();
    await copy(tester);
    expect(written, isEmpty);
  });
}
