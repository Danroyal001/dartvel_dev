// The page shell's scrolling, in a browser.
//
// page_default_scroll_test.dart proves the shell with no document. These are
// the parts only a browser has: dartvel.dev's long-page button went missing on
// a web-server build while every VM test still found it, and taking over from
// the server-rendered document never put the reader back where they were.
//
// Run with: flutter test --platform chrome test/page_scroll_browser_test.dart
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_core/dartvel.dart' show dvApplyPageHtml;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/widgets/page_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

/// dartvel.dev's layout: a header over the page, the long-page button on.
class _SiteLayout extends DartvelLayout {
  const _SiteLayout({required super.child}) : super(pageScrollToTop: true);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 70, child: Text('Header')),
          Expanded(child: child),
        ],
      );
}

/// A page whose content arrives after the first frames, as a deferred page
/// library and its data do on the web: a loading line, then the page, which
/// scrolls itself.
class _LatePage extends StatefulWidget {
  const _LatePage({required this.scrollsItself});
  final bool scrollsItself;

  @override
  State<_LatePage> createState() => _LatePageState();
}

class _LatePageState extends State<_LatePage> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Text('Loading');
    final Widget rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int row = 0; row < 80; row++) SizedBox(height: 50, child: Text('Row $row')),
      ],
    );
    return widget.scrollsItself ? SingleChildScrollView(child: rows) : rows;
  }
}

/// Prints what a browser test threw, which flutter test otherwise leaves in
/// the browser's console.
Future<void> reporting(Future<void> Function() body) async {
  try {
    await body();
  } catch (error, stack) {
    // ignore: avoid_print
    print('THREW: $error\n$stack'.split('\n').take(12).join('\n'));
    rethrow;
  }
}

Widget app(Widget page) => MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Long'),
        child: page,
      ),
    );

/// Pumps frames with real time passing, so timers and the browser run.
Future<void> settle(WidgetTester tester, {int milliseconds = 1500}) async {
  for (int waited = 0; waited < milliseconds; waited += 100) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String describeScrollables(WidgetTester tester) => <String>[
      for (final ScrollableState state in tester.stateList<ScrollableState>(find.byType(Scrollable)))
        '${identityHashCode(state.widget.controller)}:'
            '${state.position.hasContentDimensions ? state.position.maxScrollExtent : 'none'}',
    ].join(' ');

void main() {
  setUp(DVPageScrollMemory.reset);
  tearDown(DVPageScrollMemory.reset);

  group('the long-page button', () {
    for (final bool scrollsItself in <bool>[true]) {
      testWidgets(
          'shows at the bottom right on a layout with a header, once a late page '
          '${scrollsItself ? 'that scrolls itself' : 'the shell scrolls'} arrives', (WidgetTester tester) async => reporting(() async {
        tester.view.physicalSize = const Size(1366, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(app(_SiteLayout(child: _LatePage(scrollsItself: scrollsItself))));
        await settle(tester);
        final Finder button = find.byKey(const ValueKey<String>('dv-page-scroll'));
        expect(button, findsOneWidget, reason: 'scrollables ${describeScrollables(tester)}');
        final Rect rect = tester.getRect(button);
        expect(rect.right, greaterThan(1366 - 80), reason: '$rect');
        expect(rect.bottom, inInclusiveRange(800 - 80, 800), reason: '$rect');
      }));
    }
  });

  group('taking over from the server-rendered document', () {
    tearDown(() => globalContext.delete('__dvScrollY'.toJS));

    test('the document records how far its reader scrolled, and stops once the app is in', () async {
      // A page as the build writes it, in a frame of its own: no app yet.
      final String html = dvApplyPageHtml(
        '<!DOCTYPE html><html><head></head><body><div style="height:5000px">Long</div></body></html>',
        '<p>Long</p>',
      );
      final web.HTMLIFrameElement frame = web.HTMLIFrameElement()
        ..style.width = '800px'
        ..style.height = '600px'
        ..srcdoc = html.toJS;
      final Completer<void> loaded = Completer<void>();
      frame.onLoad.first.then((_) => loaded.complete());
      web.document.body!.append(frame);
      addTearDown(() => frame.remove());
      await loaded.future;
      final web.Window inner = frame.contentWindow!;
      double? recorded() => ((inner as JSObject).getProperty<JSNumber?>('__dvScrollY'.toJS))?.toDartDouble;

      inner.scrollTo(0.toJS, 700);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(recorded(), 700);

      // The engine puts its view in and fixes the body, which scrolls the
      // document back to the top. That is not the reader.
      inner.document!.body!.append(inner.document!.createElement('flutter-view'));
      inner.scrollTo(0.toJS, 0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(recorded(), 700);
    });

    testWidgets('puts the reader where the document was, once a late page arrives', (WidgetTester tester) async => reporting(() async {
      // What the document's own script records as the reader scrolls it,
      // before the engine fixes the body in place.
      globalContext.setProperty('__dvScrollY'.toJS, 700.toJS);
      tester.view.physicalSize = const Size(1366, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const _SiteLayout(child: _LatePage(scrollsItself: true))));
      await settle(tester, milliseconds: 2500);
      final List<double> moved = <double>[
        for (final ScrollableState state in tester.stateList<ScrollableState>(find.byType(Scrollable)))
          if (state.position.hasContentDimensions && state.position.maxScrollExtent > 0) state.position.pixels,
      ];
      expect(moved, <double>[700], reason: 'scrollables ${describeScrollables(tester)}');
    }));
  });
}
