/// The accessibility gate: what fails a release.
///
/// `DV.Accessibility.contrast()` and `.tapTarget()` are checks a developer
/// calls by hand in a widget test, so they run when someone remembers. Nothing
/// failed a build on an accessibility regression, and a page could lose its
/// headings or ship a nameless button with no signal anywhere.
///
/// This audits the semantics tree `dartvel build web` captures from a real
/// browser -- what a screen reader will actually be handed, rather than what
/// the source suggests it might be.
library dartvel_cli.build.accessibility_audit;

import 'semantic_html.dart';

/// One accessibility problem on one route.
class DVA11yFinding {
  const DVA11yFinding({
    required this.route,
    required this.rule,
    required this.message,
  });

  final String route;

  /// A stable identifier, so a build log can be diffed between runs.
  final String rule;

  /// What is wrong and what to do about it.
  final String message;

  @override
  String toString() => '$route  [$rule]  $message';
}

/// Audits one route's captured semantics tree.
///
/// An empty capture returns nothing. A route that captured nothing is already
/// fatal at the capture step, and reporting "no heading" on top of that would
/// point at the wrong problem.
List<DVA11yFinding> dvAuditSemantics({
  required String route,
  required List<DVSemanticNode> nodes,
}) {
  if (nodes.isEmpty) return const <DVA11yFinding>[];

  final List<DVA11yFinding> findings = <DVA11yFinding>[];
  final List<int> headingLevels = <int>[];

  void add(String rule, String message) =>
      findings.add(DVA11yFinding(route: route, rule: rule, message: message));

  void walk(DVSemanticNode node) {
    final String label = (node.label ?? '').trim();
    final int? level = node.headingLevel;

    if (level != null) {
      headingLevels.add(level);
      if (label.isEmpty) {
        add('heading-name',
            'A level $level heading has no text, so a reader navigating by '
                'heading gets an empty entry.');
      }
    } else if (label.isEmpty) {
      // Only things a user operates. Plenty of semantics nodes are structural,
      // and reporting those would bury what matters under noise nobody can act
      // on.
      switch (node.role) {
        case 'link':
          add('link-name',
              'A link to ${node.href ?? 'somewhere'} has no text, so a screen '
                  'reader can only announce "link".');
        case 'button':
        case 'checkbox':
        case 'radio':
        case 'textbox':
        case 'switch':
          add('control-name',
              'A ${node.role} has no accessible name, so it is announced by '
                  'its role alone.');
      }
    }

    for (final DVSemanticNode child in node.children) {
      walk(child);
    }
  }

  for (final DVSemanticNode node in nodes) {
    walk(node);
  }

  if (headingLevels.isEmpty) {
    add('page-heading',
        'The page has no headings, so a screen reader user has no way to tell '
            'what it is or to skim it.');
    return findings;
  }

  if (!headingLevels.contains(1)) {
    add('page-heading',
        'The page has headings but no level 1, so nothing names the page '
            'itself.');
  }

  // Only a skip going down. h1, h2, h3, h2 is an ordinary document; h1 then h3
  // tells a user navigating by heading that they missed one.
  for (var i = 1; i < headingLevels.length; i++) {
    final int from = headingLevels[i - 1];
    final int to = headingLevels[i];
    if (to > from + 1) {
      add('heading-order',
          'A level $to heading follows a level $from one, so a reader '
              'navigating by heading skips a level.');
      break;
    }
  }

  return findings;
}
