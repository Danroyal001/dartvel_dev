// Credit for the projects Dartvel is built on.
//
// Every embedded, television, extension and terminal target rides somebody
// else's Flutter embedder, and Dartvel keeps a fork of each so it can pin and
// patch it. The site names those targets on a dozen pages. Wherever it does,
// it names the people who wrote the embedder too, with a link to their
// repository and the licence it is published under.
//
// One list, so a credit is written once. The licences were read from each
// fork's LICENSE file and checked against the upstream repository on GitHub;
// the fork notes are what each fork's README banner and history record.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// Where the upstream table sits, for the footer and every "Thanks to" line.
const String kAcknowledgementsHref = '/docs/building#upstream';

/// One project Dartvel builds on, and what Dartvel's fork of it adds.
///
/// A value class rather than a widget: it answers questions, it does not
/// draw. [fork] is null for a project Dartvel uses as it is published.
class const Upstream({
  /// The key a page names it by.
  required final String id,

  /// The project, as its repository names it.
  required final String project,

  /// Who wrote it, as its copyright line or its GitHub owner names them.
  required final String vendor,

  /// Its repository.
  required final String url,

  /// Its licence, as an SPDX identifier where it has one.
  required final String license,

  /// The dartvel build target it drives, or what it is when it is not one.
  final String? target,

  /// Dartvel's fork of it.
  final String? fork,

  /// What the fork changes, from its README banner and its history.
  final String? forkAdds,
}) {
  /// The licence in a sentence: "(BSD-3-Clause)", or what stands in for one.
  String get licenseNote =>
      license.isEmpty ? '(upstream declares no licence)' : '($license)';
}

/// The embedders and the one package Dartvel forks, in the order the build
/// targets page lists the targets.
const List<Upstream> kUpstreams = <Upstream>[
  Upstream(
    id: 'tizen',
    project: 'flutter-tizen',
    vendor: 'Samsung',
    url: 'https://github.com/flutter-tizen/flutter-tizen',
    license: 'BSD-3-Clause',
    target: '`dartvel build tizen` (alias tpk)',
    fork: 'https://github.com/Danroyal001/dartvel_tizen',
    forkAdds: 'Tracks upstream\'s pin of Flutter 3.44.4, the minor Dartvel '
        'ships. One patch: it stages the Flutter engine and assets into a '
        'native TPK, which Tizen SDK CLI 10.x left out.',
  ),
  Upstream(
    id: 'elinux',
    project: 'flutter-elinux',
    vendor: 'Sony',
    url: 'https://github.com/sony/flutter-elinux',
    license: 'BSD-3-Clause',
    target: '`dartvel build sony-elinux`',
    fork: 'https://github.com/Danroyal001/dartvel_elinux',
    forkAdds: 'Records the pin at Flutter 3.29.3, the newest engine Sony '
        'publishes. `dartvel build sony-elinux` assembles its bundle from '
        'Sony\'s embedder artifacts.',
  ),
  Upstream(
    id: 'webos',
    project: 'flutter-webos',
    vendor: 'LG',
    url: 'https://github.com/lg-flutter-webos/flutter-webos',
    license: 'BSD-3-Clause',
    target: '`dartvel build webos`',
    fork: 'https://github.com/Danroyal001/dartvel_webos',
    forkAdds: 'Records the pin at Flutter 3.38.10. Its Dart 3.10.9 is below '
        'Dartvel\'s floor, so `dartvel build webos` skips; CI assembles a '
        'package from LG\'s engine instead.',
  ),
  Upstream(
    id: 'fuchsia',
    project: 'flutter-embedder',
    vendor: 'the Fuchsia authors',
    url: 'https://fuchsia.googlesource.com/flutter-embedder/',
    license: 'BSD-2-Clause',
    target: '`dartvel build fuchsia`',
    fork: 'https://github.com/Danroyal001/dartvel_fuchsia',
    forkAdds: 'Adds a Bazel rule and a script that package any Flutter app, '
        'and a build-only bootstrap. Blocked today: the Flutter it bundles '
        'is too old to resolve a Dartvel project.',
  ),
  Upstream(
    id: 'vscode',
    project: 'flutter_vscode',
    vendor: 'SlowGen',
    url: 'https://github.com/SlowGen/flutter_vscode',
    license: '',
    target: '`dartvel build vscode`',
    fork: 'https://github.com/Danroyal001/dartvel_vscode',
    forkAdds: 'Points the generated extension at the file tsc writes. '
        '`dartvel build vscode` runs upstream\'s own scaffold and build steps.',
  ),
  Upstream(
    id: 'tvos',
    project: 'flutter-tvos',
    vendor: 'the FlutterTV authors',
    url: 'https://github.com/fluttertv/flutter-tvos',
    license: 'BSD-3-Clause',
    target: '`dartvel build tvos`',
    fork: 'https://github.com/Danroyal001/dartvel_tvos',
    forkAdds: 'No source changes. Upstream pins Flutter 3.44.8, three patch '
        'releases ahead of the 3.44.5 Dartvel ships.',
  ),
  Upstream(
    id: 'flt',
    project: 'flt',
    vendor: 'Jia Hao (jiahaog)',
    url: 'https://github.com/jiahaog/flt',
    license: 'BSD-3-Clause',
    target: '`dartvel build linux-cli` (alias linux-tui)',
    fork: 'https://github.com/Danroyal001/dartvel_cli_flt',
    forkAdds: 'Re-pins to Flutter 3.44.5 and adds dartvel-cli-flt, which '
        'bundles an app so it can leave the machine. Upstream is a research '
        'project that runs apps in development.',
  ),
  Upstream(
    id: 'mix',
    project: 'mix',
    vendor: 'Leo Farias and Bitwild',
    url: 'https://github.com/btwld/mix',
    license: 'BSD-3-Clause',
    target: 'A package, for projects that already use mix',
    fork: 'https://github.com/Danroyal001/dartvel_mix',
    forkAdds: 'Targets Dart 3.12 and Flutter 3.44 and keeps the package name, '
        'so a project swaps the dependency and its imports resolve unchanged. '
        'Upstream\'s 2,918 tests run unchanged in CI. DVBox and DVText do not '
        'use mix.',
  ),
];

/// Projects Dartvel uses as they are published, credited where a page
/// names them.
const List<Upstream> kLibraries = <Upstream>[
  Upstream(
    id: 'flutter',
    project: 'Flutter',
    vendor: 'the Flutter authors',
    url: 'https://github.com/flutter/flutter',
    license: 'BSD-3-Clause',
  ),
  Upstream(
    id: 'go_router',
    project: 'go_router',
    vendor: 'the Flutter authors',
    url: 'https://github.com/flutter/packages/tree/main/packages/go_router',
    license: 'BSD-3-Clause',
  ),
  Upstream(
    id: 'shorebird',
    project: 'updater',
    vendor: 'Shorebird',
    url: 'https://github.com/shorebirdtech/updater',
    license: 'MIT or Apache-2.0',
  ),
  Upstream(
    id: 'axum',
    project: 'Axum',
    vendor: 'the Tokio project',
    url: 'https://github.com/tokio-rs/axum',
    license: 'MIT',
  ),
  Upstream(
    id: 'tokio',
    project: 'Tokio',
    vendor: 'the Tokio project',
    url: 'https://github.com/tokio-rs/tokio',
    license: 'MIT',
  ),
];

/// The project a page names by [id], from either list.
Upstream upstreamFor(String id) => <Upstream>[...kUpstreams, ...kLibraries]
    .firstWhere((Upstream u) => u.id == id);

/// One credit on one line: "Built on flutter-tizen by Samsung (BSD-3-Clause)."
///
/// The project name is the link. [lead] is the verb the sentence needs where
/// "Built on" does not fit the thing being credited.
@DVFunctionalWidget()
Widget _upstreamCredit(
  BuildContext context,
  String id, {
  String lead = 'Built on',
  bool onDark = false,
}) {
  final Palette palette = Palette.of(context);
  final Upstream upstream = upstreamFor(id);
  final Color text = onDark ? Palette.deepMuted : palette.muted;
  final DVModifier small = const DVModifier().fontSize(14).color(text);
  return DVBox.wrapLine(<Widget>[
    Prose(lead, small),
    ExternalLink(upstream.project, upstream.url, onDark: onDark),
    DVText('by ${upstream.vendor} ${upstream.licenseNote}.').modifier(small),
  ], spacing: 2, crossAlign: DVCrossAlign.center);
}

/// A short "Thanks to" line for a page that names several targets: each
/// project linked, who wrote it beside it, and the way to the full table.
@DVFunctionalWidget()
Widget _upstreamCredits(
  BuildContext context, {
  required List<String> ids,
  String lead = 'Thanks to the projects these targets are built on:',
  bool onDark = false,
  bool link = true,
}) {
  final Palette palette = Palette.of(context);
  final Color text = onDark ? Palette.deepMuted : palette.muted;
  final DVModifier small = const DVModifier().fontSize(14).color(text);
  final List<String> named = ids;
  // The building page holds the table itself, so there it links nowhere.
  final bool linked = link;
  return DVBox.list(<Widget>[
    Prose(lead, small),
    DVBox.wrapLine(<Widget>[
      for (final String id in named)
        DVBox.row(<Widget>[
          ExternalLink(upstreamFor(id).project, upstreamFor(id).url,
              onDark: onDark),
          DVText('by ${upstreamFor(id).vendor}').modifier(small),
        ], spacing: 0, crossAlign: DVCrossAlign.center),
      if (linked)
        AcknowledgementsLink(label: 'Credits and licences', onDark: onDark),
    ], spacing: 10, crossAlign: DVCrossAlign.center),
  ], spacing: 4, crossAlign: DVCrossAlign.start);
}

/// A link to the upstream table, for the footer and the credit lines.
@DVFunctionalWidget()
Widget _acknowledgementsLink(
  BuildContext context, {
  String label = 'Acknowledgements',
  bool onDark = false,
}) =>
    DVNavLink(
      to: const DVRouteTarget(kAcknowledgementsHref),
      child: Prose(label, const DVModifier()
          .fontSize(14)
          .fontWeight(FontWeight.w600)
          .color(onDark ? Palette.deepAccent : Palette.of(context).accent)),
    );

/// Every upstream, with who wrote it, its licence, and what Dartvel's fork
/// adds. Laid out the way DocsTable is, so it reads on a phone: each project
/// a small card, its name the link.
@DVFunctionalWidget()
Widget _upstreamTable(BuildContext context) {
  final Palette palette = Palette.of(context);
  final DVModifier line =
      const DVModifier().fontSize(14).color(palette.muted).lineHeight(1.5);
  return DVBox.list(<Widget>[
    for (final Upstream upstream in kUpstreams)
      DVBox(
        DVBox.list(<Widget>[
          DVNavLink.external(
            upstream.url,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DVText(upstream.project).modifier(const DVModifier()
                .fontSize(15)
                .fontWeight(FontWeight.w700)
                .fontFamily('JetBrainsMono')
                .color(palette.accent)),
          ),
          Prose('Target: ${upstream.target ?? ''}', line),
          DVText('By: ${upstream.vendor}').modifier(line),
          DVText('Licence: ${upstream.license.isEmpty ? 'none declared; '
                  'the upstream LICENSE file is a placeholder' : upstream.license}')
              .modifier(line),
          Prose('What the fork adds: ${upstream.forkAdds ?? ''}',
              line),
          ExternalLink('Dartvel\'s fork', upstream.fork ?? upstream.url),
        ], spacing: 4, crossAlign: DVCrossAlign.start),
        const DVModifier()
            .width(double.infinity)
            .maxWidth(680)
            .paddingSymmetric(horizontal: 14, vertical: 10)
            .border(Border(bottom: BorderSide(color: palette.rule))),
      ),
  ], spacing: 0);
}
