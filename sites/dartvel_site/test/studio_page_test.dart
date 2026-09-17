// Studio has its own page, and Studio Pro on it is what dartvel_studio_pro
// ships.
//
// The owner's complaint was that the visual workflow builder, the part of
// Studio Pro a buyer would pay for, was one small card on /cloud under a Figma
// heading. So /studio exists, the header reaches it, the workflow builder has
// its own section inside Studio Pro, and the Pro cards' Built and Planned
// badges are held to the enterprise package when a checkout of it is present.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with line comments dropped, so a comment cannot satisfy a check.
String code(String path) => File(path)
    .readAsLinesSync()
    .where((String l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// The text of [source] from [start] to the next top-level section marker.
String sectionFrom(String source, String start) {
  final int at = source.indexOf(start);
  if (at < 0) return '';
  final int next = source.indexOf(RegExp(r"Eyebrow\('"), at + start.length);
  return source.substring(at, next < 0 ? source.length : next);
}

/// Every `SiteCard('title', ..., built: x)` in [source], title to flag.
Map<String, bool?> cardFlags(String source) => <String, bool?>{
      for (final Match m in RegExp(
        r"SiteCard\(\s*'((?:[^'\\]|\\.)*)'((?:[^()]|\([^()]*\))*)\)",
      ).allMatches(source))
        m[1]!.replaceAll(r"\'", "'"): RegExp(r'built:\s*(true|false)')
                    .firstMatch(m[2]!) ==
                null
            ? null
            : RegExp(r'built:\s*(true|false)').firstMatch(m[2]!)![1] == 'true',
    };

/// Where a checkout of the private enterprise repository might be.
Directory? enterpriseStudioPro() {
  for (final String root in <String>[
    if (Platform.environment['DARTVEL_ENTERPRISE'] != null)
      Platform.environment['DARTVEL_ENTERPRISE']!,
    '../../../dartvel_enterprise',
    '/workspaces/dartvel_enterprise',
  ]) {
    final Directory dir = Directory('$root/packages/dartvel_studio_pro');
    if (dir.existsSync()) return dir;
  }
  return null;
}

/// What Studio Pro ships, as the page must badge it.
const Map<String, bool> kProCards = <String, bool>{
  'Workflow builder': true,
  'Figma import': true,
  'Reusable components': true,
  'Revision history': true,
  'Multi-user editing and approval': true,
  'Enterprise SSO': false,
};

void main() {
  const String page = 'lib/pages/studio.dart';

  test('/studio is a page, and the header links to it', () {
    expect(File(page).existsSync(), isTrue, reason: 'no lib/pages/studio.dart');
    final String header = code('lib/components/site.dart');
    expect(
      RegExp(r"NavLink\('Studio', '/studio'\)").allMatches(header).length,
      2,
      reason: 'the phone and desktop headers both need the Studio link',
    );
  });

  test('the free Studio and Studio Pro are separate sections', () {
    final String source = code(page);
    expect(source, contains("Eyebrow('FREE STUDIO'"));
    expect(source, contains("Eyebrow('STUDIO PRO'"));
    final String free = sectionFrom(source, "Eyebrow('FREE STUDIO'");
    expect(free, contains('dartvel admin grant'));
    expect(free, contains('web-server'));
    // Nothing Pro is sold as free.
    for (final String title in kProCards.keys) {
      expect(free, isNot(contains(title)), reason: '$title is Pro');
    }
  });

  test('the workflow builder has its own section under Studio Pro', () {
    final String source = code(page);
    final int pro = source.indexOf("Eyebrow('STUDIO PRO'");
    final int workflows = source.indexOf("Eyebrow('WORKFLOW BUILDER'");
    expect(workflows, greaterThan(pro),
        reason: 'the workflow builder section must come under Studio Pro');
    final String section = sectionFrom(source, "Eyebrow('WORKFLOW BUILDER'");
    // A workflow, its steps, and what Export writes.
    for (final String step in <String>['CALL', 'SET', 'CONDITION', 'RETURN']) {
      expect(section, contains(step), reason: 'the example has no $step step');
    }
    expect(section, contains('@DVBackendFunction()'));
    expect(section.toLowerCase(), contains('saving'));
    expect(section, contains('publish'));
    expect(section.toLowerCase(), contains('drop the builder'));
  });

  test('the Pro cards are badged as dartvel_studio_pro ships them', () {
    final Map<String, bool?> cards = cardFlags(code(page));
    for (final MapEntry<String, bool> card in kProCards.entries) {
      expect(cards[card.key], card.value,
          reason: '${card.key} should be built: ${card.value}');
    }
  });

  test('those badges match the enterprise package, when it is checked out', () {
    final Directory pro = enterpriseStudioPro()!;
    final String barrel =
        File('${pro.path}/lib/dartvel_studio_pro.dart').readAsStringSync();
    final String lib = <String>[
      for (final FileSystemEntity e in Directory('${pro.path}/lib')
          .listSync(recursive: true))
        if (e is File && e.path.endsWith('.dart')) e.readAsStringSync(),
    ].join('\n');
    final Map<String, List<String>> evidence = <String, List<String>>{
      'Workflow builder': <String>['dvWorkflowStudioSection', 'toDartSource', 'class DVWorkflows'],
      'Figma import': <String>['dvFigmaImportStudioSection'],
      'Reusable components': <String>['dvComponentsStudioSection'],
      'Revision history': <String>['dvHistoryStudioSection'],
      'Multi-user editing and approval': <String>[
        'class DVStudioCollaboration',
        'dvApprovalsStudioSection',
      ],
    };
    for (final MapEntry<String, List<String>> e in evidence.entries) {
      for (final String name in e.value) {
        expect('$barrel\n$lib', contains(name),
            reason: '${e.key} is badged Built and $name is not in the package');
      }
    }
    // SSO for a team is Pro in the business model and is not built there.
    expect(lib, isNot(matches(RegExp(r'\bSAML\b|\bSCIM\b'))),
        reason: 'Enterprise SSO is badged Planned but the package has it');
  }, skip: enterpriseStudioPro() == null
      ? 'no dartvel_enterprise checkout; set DARTVEL_ENTERPRISE to check'
      : false);

  test('every screenshot the page shows is a bundled asset', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final List<String> shots = <String>[
      for (final String path in <String>[page, 'lib/pages/index.dart'])
        for (final Match m
            in RegExp(r"StudioShot\(\s*'([^']+)'").allMatches(code(path)))
          m[1]!,
    ];
    expect(shots, isNotEmpty, reason: 'Studio is shown with no screenshot');
    for (final String shot in shots) {
      expect(File(shot).existsSync(), isTrue, reason: '$shot is missing');
      expect(pubspec, contains(shot.substring(0, shot.lastIndexOf('/') + 1)),
          reason: '$shot is not declared under flutter: assets:');
    }
  });
}
