// The accessibility gate: what fails a release.
//
// DV.Accessibility.contrast() and .tapTarget() existed as checks a developer
// calls by hand in a widget test, which means they run when someone remembers.
// Nothing failed a build on an accessibility regression, so a page could lose
// its headings or ship a nameless button and no signal existed anywhere.
//
// The data is already there: `dartvel build web` drives a real browser over
// every route and captures the semantics tree. This audits that tree, which is
// what a screen reader will actually be handed rather than what the source
// suggests.
import 'package:dartvel_cli/src/build/accessibility_audit.dart';
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

DVSemanticNode node({
  String? role,
  int? level,
  String? label,
  String? href,
  List<DVSemanticNode> children = const <DVSemanticNode>[],
}) =>
    DVSemanticNode(
      role: role,
      headingLevel: level,
      label: label,
      href: href,
      children: children,
    );

List<DVA11yFinding> audit(List<DVSemanticNode> nodes) =>
    dvAuditSemantics(route: '/page', nodes: nodes);

/// The same, on a page that already has a heading.
///
/// Used where the test is about a control's name: without a heading the page
/// also fails page-heading, which is true but is not what is being isolated.
List<DVA11yFinding> onNamedPage(List<DVSemanticNode> nodes) => audit(
      <DVSemanticNode>[node(level: 1, label: 'Page'), ...nodes],
    );

void main() {
  group('a page with nothing wrong', () {
    test('reports nothing', () {
      expect(
        audit(<DVSemanticNode>[
          node(level: 1, label: 'Orders'),
          node(role: 'link', label: 'Back to home', href: '/'),
          node(role: 'button', label: 'Save'),
        ]),
        isEmpty,
      );
    });
  });

  group('things a screen reader cannot announce', () {
    test('a link with no text', () {
      // "link" is all a screen reader has to offer the user.
      final List<DVA11yFinding> found =
          onNamedPage(<DVSemanticNode>[node(role: 'link', href: '/orders')]);

      expect(found, hasLength(1));
      expect(found.single.rule, 'link-name');
      expect(found.single.route, '/page');
    });

    test('a button with no name', () {
      final List<DVA11yFinding> found =
          onNamedPage(<DVSemanticNode>[node(role: 'button')]);

      expect(found.single.rule, 'control-name');
    });

    test('whitespace is not a name', () {
      expect(onNamedPage(<DVSemanticNode>[node(role: 'button', label: '   ')]),
          hasLength(1));
    });

    test('a nameless node with no role is not a finding', () {
      // Plenty of semantics nodes are structural. Reporting those would bury
      // the ones that matter under noise nobody can act on.
      expect(onNamedPage(<DVSemanticNode>[node()]), isEmpty);
    });

    test('it looks inside children, not just the top level', () {
      final List<DVA11yFinding> found = onNamedPage(<DVSemanticNode>[
        node(children: <DVSemanticNode>[
          node(children: <DVSemanticNode>[node(role: 'button')]),
        ]),
      ]);

      expect(found, hasLength(1));
    });
  });

  group('heading structure', () {
    test('a page with no h1 is reported', () {
      // The heading is how a screen reader user knows what the page is.
      final List<DVA11yFinding> found =
          audit(<DVSemanticNode>[node(level: 2, label: 'Section')]);

      expect(found.map((DVA11yFinding f) => f.rule), contains('page-heading'));
    });

    test('a skipped level is reported', () {
      // h1 then h3 tells a user navigating by heading that they missed one.
      final List<DVA11yFinding> found = audit(<DVSemanticNode>[
        node(level: 1, label: 'Orders'),
        node(level: 3, label: 'Details'),
      ]);

      expect(found.map((DVA11yFinding f) => f.rule), contains('heading-order'));
    });

    test('going back up a level is fine', () {
      // h1, h2, h3, h2 is an ordinary document, not a skip.
      expect(
        audit(<DVSemanticNode>[
          node(level: 1, label: 'A'),
          node(level: 2, label: 'B'),
          node(level: 3, label: 'C'),
          node(level: 2, label: 'D'),
        ]).map((DVA11yFinding f) => f.rule),
        isNot(contains('heading-order')),
      );
    });

    test('an empty heading is reported', () {
      expect(
        audit(<DVSemanticNode>[node(level: 1)])
            .map((DVA11yFinding f) => f.rule),
        contains('heading-name'),
      );
    });

    test('a second h1 is not an error', () {
      // Sectioned documents legitimately have more than one, and flagging it
      // would train people to ignore the channel.
      expect(
        audit(<DVSemanticNode>[
          node(level: 1, label: 'A'),
          node(level: 1, label: 'B'),
        ]),
        isEmpty,
      );
    });

    test('a page with no headings at all is reported once, not twice', () {
      final List<DVA11yFinding> found = audit(<DVSemanticNode>[
        node(role: 'button', label: 'Save'),
      ]);

      expect(found, hasLength(1));
      expect(found.single.rule, 'page-heading');
    });
  });

  group('an empty capture', () {
    test('is not audited, because there is nothing to judge', () {
      // A route that captured nothing is already fatal at the capture step,
      // and reporting "no h1" on top of it would point at the wrong problem.
      expect(audit(const <DVSemanticNode>[]), isEmpty);
    });
  });

  group('the gate', () {
    test('findings across routes are collected together', () {
      final List<DVA11yFinding> all = <DVA11yFinding>[
        ...dvAuditSemantics(route: '/a', nodes: <DVSemanticNode>[
          node(level: 1, label: 'A'),
          node(role: 'button'),
        ]),
        ...dvAuditSemantics(route: '/b', nodes: <DVSemanticNode>[
          node(level: 1, label: 'B'),
          node(role: 'link'),
        ]),
      ];

      expect(all.map((DVA11yFinding f) => f.route), <String>['/a', '/b']);
    });

    test('a finding says what to do, not just what is wrong', () {
      final DVA11yFinding f =
          onNamedPage(<DVSemanticNode>[node(role: 'button')]).single;

      expect(f.message, isNotEmpty);
      expect(f.toString(), contains('/page'));
      expect(f.toString(), contains('control-name'));
    });
  });
}
