// Every built part of Dartvel on one list, grouped as the docs sidebar is,
// with how built each is and a link to the section that covers it.
//
// Drawn from kSpecCoverage and kDocsSpecStatus, the lists
// test/spec_coverage_test.dart holds to the site and to docs/spec-status.json,
// so a row cannot claim a status or a page the site does not have.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'docs.dart';
import 'site.dart';
import 'spec_coverage.dart';

/// The whole platform on one list, on the docs home page.
@DVFunctionalWidget()
Widget _docsPlatformIndex(BuildContext context) {
  final Palette palette = Palette.of(context);
  final Map<String, SpecCoverage> covered = <String, SpecCoverage>{
    for (final SpecCoverage c in kSpecCoverage) c.section: c,
  };
  String groupOf(String section) =>
      covered[section]?.group ?? kSpecKnownGaps[section] ?? 'Reference';
  final List<String> sections = kDocsSpecStatus.keys.toList()..sort();
  return DVBox.list(<Widget>[
    for (final String group in kDocsGroupOrder)
      if (sections.any((String s) => groupOf(s) == group))
        DVBox.list(<Widget>[
          DVText(group.toUpperCase()).modifier(const DVModifier()
              .fontSize(12)
              .fontWeight(FontWeight.w700)
              .letterSpacing(1.2)
              .color(palette.faint)
              .semanticHeading(3)),
          for (final String section in sections)
            if (groupOf(section) == group)
              KeyedSubtree(
                key: ValueKey<String>('spec:$section'),
                child: DocsIndexRow(
                  section: section,
                  shipped: kDocsSpecStatus[section] == 'Shipped',
                  href: covered[section]?.href,
                ),
              ),
        ], spacing: 4, crossAlign: DVCrossAlign.stretch),
  ], spacing: 22, crossAlign: DVCrossAlign.stretch);
}

/// One section: its name, linked when a page covers it, and its status.
@DVFunctionalWidget()
Widget _docsIndexRow(
  BuildContext context, {
  required String section,
  required bool shipped,
  String? href,
}) {
  final Palette palette = Palette.of(context);
  final Widget name = Prose(section, const DVModifier()
      .fontSize(15)
      .fontWeight(FontWeight.w500)
      .color(href == null ? palette.ink : palette.accent));
  return DVBox.row(<Widget>[
    Flexible(
      child: href == null
          ? name
          : DVNavLink(
              to: DVRouteTarget(href),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: name,
            ),
    ),
    DVText(shipped ? 'Shipped' : 'Partly built').modifier(const DVModifier()
        .fontSize(12)
        .fontWeight(FontWeight.w700)
        .color(shipped ? palette.accent : palette.ink)
        .paddingSymmetric(horizontal: 9, vertical: 3)
        .backgroundColor(shipped
            ? palette.accent.withValues(alpha: 0.12)
            : const Color(0xFFFFC857).withValues(alpha: 0.45))
        .rounded(999)),
  ], spacing: 12, align: DVAlign.spaceBetween, crossAlign: DVCrossAlign.center);
}
