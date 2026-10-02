// The server's list of Studio's screens, and the sections Studio actually
// has, held to each other.
//
// `dvStudioScreens` is what a server answers at `/__studio/<id>` with a
// document, so every id in it must be a section somebody can open. The
// reverse holds too, for the sections free Studio puts on the rail: a screen
// on the rail with no id in that list is a screen with no URL, no document
// and nothing to link to.
//
// The one deliberate exception is `flags` and `operations`: they exist only
// when the project declared a flag runtime or an alerting engine, which a
// server cannot know, so the server never prints them in its rail. Their URLs
// still answer, because a project that declared them does have the section.
//
// The two lists are written in different packages, by people who do not see
// each other's file, which is exactly the case a test is for. The ids are
// read off the rail rather than off the source, so a section the source lists
// but the rail does not show is caught here too.
import 'package:dartvel_core/dartvel.dart'
    show DVStudioScreenSpec, dvStudioScreens;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ids Studio has only when the project asked for the runtime behind them.
const Set<String> _declaredAtRuntime = <String>{'flags', 'operations'};

/// The prefix every rail item's key carries, and therefore the rail's own
/// naming of a section.
const String _railKey = 'dv-studio-section-';

/// A transport that answers nothing: this reads the rail, and no section here
/// waits on a server.
DVStudioTransport get _transport =>
    (String method, String path, {Object? body}) async =>
        const DVStudioReply(404, <String, Object?>{});

/// The ids on the rail of the Studio under the tree.
Set<String> railSections() {
  final Set<String> ids = <String>{};
  for (final Element element
      in find
          .byWidgetPredicate(
            (Widget widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(_railKey),
          )
          .evaluate()) {
    ids.add(
      (element.widget.key! as ValueKey<String>).value.substring(
        _railKey.length,
      ),
    );
  }
  return ids;
}

void main() {
  Future<void> openStudio(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: DVStudioScreen(
            sections: dvStudioServerSections(DVStudioClient(_transport)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every screen the server answers is a section Studio has', (
    WidgetTester tester,
  ) async {
    await openStudio(tester);
    for (final DVStudioScreenSpec screen in dvStudioScreens) {
      if (_declaredAtRuntime.contains(screen.id)) continue;
      expect(
        railSections(),
        contains(screen.id),
        reason:
            'the server answers /__studio/${screen.id} with a document, '
            'so a section of that id has to open',
      );
    }
  });

  testWidgets('every section on the rail has a URL of its own', (
    WidgetTester tester,
  ) async {
    await openStudio(tester);
    final Set<String> named = <String>{
      for (final DVStudioScreenSpec screen in dvStudioScreens) screen.id,
    };
    for (final String id in railSections()) {
      expect(
        named,
        contains(id),
        reason: '$id is on the rail, so it needs an address a link can name',
      );
    }
  });

  test('the screens a server cannot know about are not in its own list', () {
    // A server cannot tell whether a project declared a flag runtime or an
    // alerting engine, so printing `/__studio/flags` in the rail would be
    // printing a link to a screen most projects do not have. The client still
    // answers those URLs: DVStudioScreen reads the path itself and opens the
    // section when the runtime is there.
    expect(
      dvStudioScreens.map((DVStudioScreenSpec screen) => screen.id),
      isNot(anyOf(contains('flags'), contains('operations'))),
      reason: 'a screen only some projects have must not be printed as one '
          'every project has',
    );
  });
}
