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

// ---------------------------------------------------------------------------
// Waivers

/// The rules the audit can report, so a waiver can be checked against them.
const Set<String> dvA11yRules = <String>{
  'link-name',
  'control-name',
  'heading-name',
  'page-heading',
  'heading-order',
};

/// One documented exception: this rule, on this route, for this reason.
class DVA11yWaiver {
  const DVA11yWaiver({required this.route, required this.rule, required this.reason});
  final String route;

  /// A rule name, or `*` for every rule on the route.
  final String rule;
  final String reason;

  bool matches(DVA11yFinding finding) =>
      finding.route == route && (rule == '*' || finding.rule == rule);
}

/// What the gate decides once waivers are applied.
class DVA11yVerdict {
  const DVA11yVerdict({required this.failing, required this.waived, required this.unused});

  /// Findings nothing waived. These fail the build.
  final List<DVA11yFinding> failing;

  /// Findings a waiver set aside. Printed, not failed.
  final List<DVA11yFinding> waived;

  /// Waivers that matched nothing: a typo, or a finding since fixed. Printed,
  /// so they do not sit in the file forever.
  final List<DVA11yWaiver> unused;

  bool get ok => failing.isEmpty;
}

/// The waivers a project declares under `dartvel.accessibility.waivers`.
///
/// A waiver needs a route, a rule the audit actually has, and a reason. No
/// reason, no waiver: "waived" with nothing after it is exactly the silent
/// exception the gate exists to prevent.
class DVA11yWaivers {
  const DVA11yWaivers({required this.entries, required this.problems});

  final List<DVA11yWaiver> entries;

  /// Declarations that could not be accepted, in the developer's terms.
  final List<String> problems;

  static DVA11yWaivers parse(Object? dartvelSection) {
    final Object? section =
        dartvelSection is Map ? dartvelSection['accessibility'] : null;
    final Object? raw = section is Map ? section['waivers'] : null;
    final List<DVA11yWaiver> entries = <DVA11yWaiver>[];
    final List<String> problems = <String>[];
    if (raw == null) return DVA11yWaivers(entries: entries, problems: problems);
    if (raw is! List) {
      problems.add('dartvel.accessibility.waivers must be a list.');
      return DVA11yWaivers(entries: entries, problems: problems);
    }
    for (var i = 0; i < raw.length; i++) {
      final Object? item = raw[i];
      if (item is! Map) {
        problems.add('dartvel.accessibility.waivers[$i] must be a map with '
            'route, rule and reason.');
        continue;
      }
      final String route = '${item['route'] ?? ''}'.trim();
      final String rule = '${item['rule'] ?? ''}'.trim();
      final String reason = '${item['reason'] ?? ''}'.trim();
      if (route.isEmpty) {
        problems.add('dartvel.accessibility.waivers[$i] names no route.');
        continue;
      }
      if (rule != '*' && !dvA11yRules.contains(rule)) {
        problems.add('dartvel.accessibility.waivers[$i] names rule "$rule", '
            'which the audit does not have; it is one of '
            '${dvA11yRules.join(', ')} or *.');
        continue;
      }
      if (reason.isEmpty) {
        problems.add('dartvel.accessibility.waivers[$i] ($route, $rule) has '
            'no reason; a waiver has to say why the finding is accepted.');
        continue;
      }
      entries.add(DVA11yWaiver(route: route, rule: rule, reason: reason));
    }
    return DVA11yWaivers(entries: entries, problems: problems);
  }

  /// Splits [findings] into what fails, what is waived, and which waivers
  /// did nothing.
  DVA11yVerdict apply(List<DVA11yFinding> findings) {
    final List<DVA11yFinding> failing = <DVA11yFinding>[];
    final List<DVA11yFinding> waived = <DVA11yFinding>[];
    final Set<DVA11yWaiver> used = <DVA11yWaiver>{};
    for (final DVA11yFinding f in findings) {
      DVA11yWaiver? by;
      for (final DVA11yWaiver w in entries) {
        if (w.matches(f)) {
          by = w;
          break;
        }
      }
      if (by == null) {
        failing.add(f);
      } else {
        waived.add(f);
        used.add(by);
      }
    }
    return DVA11yVerdict(
      failing: failing,
      waived: waived,
      unused: <DVA11yWaiver>[for (final DVA11yWaiver w in entries) if (!used.contains(w)) w],
    );
  }
}
