// The docs: a page per topic, a sidebar that reaches every page, and the
// parts every docs page is built from.
//
// Laravel's docs are the model. One topic per URL, so a search result or a
// shared link lands on the answer. A sidebar grouped by what you are building,
// so the next topic is one click away. And each page opens with what is on it
// and ends with where to go next.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'docs_cli_command.dart';
import 'docs_page_info.dart';
import 'docs_samples.dart';
import 'site.dart';

/// Every docs page, in reading order. The sidebar, the pager and the index
/// all read this one list, so a page cannot be in one and missing from
/// another. test/docs_structure_test.dart checks it against the router.
const List<DocsPageInfo> kDocsPages = <DocsPageInfo>[
  DocsPageInfo(DVRoutes.docs, 'Getting started',
      'Install the CLI, create an app and run it', 'Getting started'),
  DocsPageInfo(DVRoutes.docsadopting, 'Existing Flutter apps',
      'Add Dartvel to an app you already have', 'Getting started'),
  DocsPageInfo(DVRoutes.docsdevclient, 'Run on your phone',
      'Pair a development build with dartvel dev', 'Getting started'),
  DocsPageInfo(DVRoutes.docsui, 'UI and styling',
      'DVBox, DVText, modifiers and layouts', 'App'),
  DocsPageInfo(DVRoutes.docsrouting, 'Routing',
      'File pages, parameters, layouts and links', 'App'),
  DocsPageInfo(DVRoutes.docsstate, 'State',
      'Signals, derived signals and globals', 'App'),
  DocsPageInfo(DVRoutes.docsaccessibility, 'Accessibility',
      'Build-time audit, switch control and remote keys', 'App'),
  DocsPageInfo(DVRoutes.docslocalization, 'Localization',
      'Typed translation keys, plurals and ARB files', 'App'),
  DocsPageInfo(DVRoutes.docsdevices, 'Devices and desktop',
      'Native features, home widgets, kiosks, windows and trays', 'App'),
  DocsPageInfo(DVRoutes.docsmedia3d, 'Media, 3D and XR',
      'Players, recorders, 3D scenes and spatial windows', 'App'),
  DocsPageInfo(DVRoutes.docsmodels, 'Models',
      'One class gives you storage, forms, tables and pages', 'Data'),
  DocsPageInfo(DVRoutes.docsforms, 'Forms',
      'A create or edit form for every model', 'Data'),
  DocsPageInfo(DVRoutes.docssearch, 'Search',
      'Full text, hosted engines and semantic search', 'Data'),
  DocsPageInfo(DVRoutes.docssync, 'Sync and offline',
      'Model changes, presence and offline writes', 'Data'),
  DocsPageInfo(DVRoutes.docsimportexport, 'Import and export',
      'CSV, NDJSON and Excel in and out of a model', 'Data'),
  DocsPageInfo(DVRoutes.docschangecapture, 'Change capture',
      'An ordered log of writes, copied to a warehouse', 'Data'),
  DocsPageInfo(DVRoutes.docsdatabase, 'Database',
      'SQLite, Postgres, MySQL and migrations', 'Data'),
  DocsPageInfo(DVRoutes.docscache, 'Cache',
      'Remember values and drop them by tag', 'Data'),
  DocsPageInfo(DVRoutes.docsstorage, 'File storage',
      'Put and get files on S3, GCS or Azure', 'Data'),
  DocsPageInfo(DVRoutes.docsmedia, 'Images',
      'Resized image variants for web builds', 'Data'),
  DocsPageInfo(DVRoutes.docsprivacy, 'Privacy and erasure',
      'Export and erase a person\'s data', 'Data'),
  DocsPageInfo(DVRoutes.docsbackendfunctions, 'Backend functions',
      'A function in lib/backend is an endpoint', 'Backend'),
  DocsPageInfo(DVRoutes.docsauth, 'Auth and sessions',
      'Sign-in, second factor, sessions and account pages', 'Backend'),
  DocsPageInfo(DVRoutes.docsauthorization, 'Authorization',
      'Policies under DV.Auth.authorization', 'Backend'),
  DocsPageInfo(DVRoutes.docsqueues, 'Queues and jobs',
      'Work that runs after the response', 'Backend'),
  DocsPageInfo(DVRoutes.docsworkers, 'Workers and memory',
      'Heavy work on other cores, and memory reserved up front', 'Backend'),
  DocsPageInfo(DVRoutes.docsnotifications, 'Notifications and mail',
      'Email, in-app and push through one service', 'Backend'),
  DocsPageInfo(DVRoutes.docshttp, 'Outbound HTTP',
      'Call APIs you have declared, with retries', 'Backend'),
  DocsPageInfo(DVRoutes.docsai, 'AI',
      'Chat, structured output, embeddings and tools', 'Backend'),
  DocsPageInfo(DVRoutes.docswebhooks, 'Webhooks',
      'Signed events your customers subscribe to', 'Backend'),
  DocsPageInfo(DVRoutes.docsgraphql, 'GraphQL and OpenAPI',
      'The API your models and functions already have', 'Backend'),
  DocsPageInfo(DVRoutes.docsplatformapi, 'Platform API',
      'API keys, scopes and OAuth clients', 'Backend'),
  DocsPageInfo(DVRoutes.docstenancy, 'Multi-tenancy',
      'One deployment, many customers', 'Backend'),
  DocsPageInfo(DVRoutes.docsorganizations, 'Organizations',
      'Members, roles, invitations and seats', 'Backend'),
  DocsPageInfo(DVRoutes.docsbilling, 'Billing and commerce',
      'Subscriptions, store purchases, tax and usage limits', 'Backend'),
  DocsPageInfo(DVRoutes.docsmodules, 'Modules',
      'Mount one app inside another, signed and pinned', 'Backend'),
  DocsPageInfo(DVRoutes.docsedgesecurity, 'Edge security',
      'Sign-in limits, WAF rules and query budgets', 'Operations'),
  DocsPageInfo(DVRoutes.docssecrets, 'Secrets and environments',
      'Keys that stay on the server, checked at build and deploy', 'Operations'),
  DocsPageInfo(DVRoutes.docsmonitoring, 'Monitoring',
      'Metrics, traces, crash reports, alerts and analytics', 'Operations'),
  DocsPageInfo(DVRoutes.docsreleases, 'Releases',
      'Flags, branch previews, rollouts and old clients', 'Operations'),
  DocsPageInfo(DVRoutes.docsbuilding, 'Build targets',
      'dartvel build for every platform, with its status', 'Shipping'),
  DocsPageInfo(DVRoutes.docswebhosting, 'Static web hosting',
      'dartvel build web on Apache or LiteSpeed', 'Shipping'),
  DocsPageInfo(DVRoutes.docsdeploying, 'Servers and deploying',
      'Run the backend, deploy and provision hosts', 'Shipping'),
  DocsPageInfo(DVRoutes.docstesting, 'Testing',
      'DV.Test fakes, model factories and test modes', 'Reference'),
  DocsPageInfo(DVRoutes.docscli, 'CLI reference',
      'Every dartvel command and flag', 'Reference'),
];

/// Every docs group, in sidebar order.
const List<String> kDocsGroupOrder = <String>[
  'Getting started',
  'App',
  'Data',
  'Backend',
  'Operations',
  'Shipping',
  'Studio',
  'Reference',
];

/// The groups that have pages, in sidebar order.
List<String> get docsGroups => <String>[
      for (final String group in kDocsGroupOrder)
        if (kDocsPages.any((DocsPageInfo p) => p.group == group)) group,
    ];

/// The page at [path], or null when [path] is not a docs page.
DocsPageInfo? docsPageAt(String path) {
  final String normal =
      path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  for (final DocsPageInfo page in kDocsPages) {
    if (page.path == normal) return page;
  }
  return null;
}

/// The status docs/spec-status.json records for each section a page labels.
///
/// Copied here because a web page cannot read the repository, and checked
/// against the file by test/docs_status_test.dart, so a section that ships
/// cannot stay labelled partial and the reverse.
const Map<String, String> kDocsSpecStatus = <String, String>{
  '3D Scenes': 'Partial',
  'Accessibility': 'Shipped',
  'Admin, Devtools, and Scaffolding': 'Shipped',
  'Adoption': 'Partial',
  'AI Operations': 'Partial',
  'AI': 'Shipped',
  'Alerting, SLOs and Status Pages': 'Partial',
  'APIs': 'Shipped',
  'App Store Deployment and Privacy Manifests': 'Partial',
  'Authentication': 'Shipped',
  'Authorization': 'Shipped',
  'Backend Function Request Lifecycle': 'Partial',
  'Backend Release Management': 'Partial',
  'Backend': 'Shipped',
  'Background and Durable Work': 'Shipped',
  'Billing': 'Partial',
  'Cache': 'Shipped',
  'Change Data Capture and Warehouse Sync': 'Partial',
  'CLI': 'Partial',
  'Commerce: Tax, Promotions, Disputes and Payouts': 'Partial',
  'Compute: Workers and Native Offload': 'Partial',
  'Content Workflow': 'Partial',
  'Crash Reporting and Release Health': 'Partial',
  'CSRF Protection': 'Shipped',
  'Dartvel Cloud': 'Partial',
  'Dartvel Studio': 'Shipped',
  'Data Compliance and Lifecycle': 'Partial',
  'Data Import, Export, and Reporting': 'Partial',
  'Database': 'Shipped',
  'Deployment': 'Shipped',
  'Desktop, Embedded, and Qt-Critical Capabilities': 'Partial',
  'Dev Client': 'Partial',
  'Distributed Tracing': 'Partial',
  'Documentation Generation': 'Partial',
  'Edge Security': 'Partial',
  'Embedded, Television, and Extension Build Targets': 'Partial',
  'Error, Empty, and Loading States': 'Partial',
  'Feature Flags and Staged Rollout': 'Partial',
  'File Storage': 'Partial',
  'Forms': 'Shipped',
  'Generated Code Determinism': 'Partial',
  'Generated Model Pages': 'Partial',
  'Home Widgets': 'Partial',
  'Internationalization and Localization': 'Shipped',
  'Kiosk Mode': 'Partial',
  'Lifecycle Signals': 'Partial',
  'Mail and Notifications': 'Partial',
  'Media Pipeline': 'Partial',
  'Media Playback and Capture': 'Partial',
  'Middleware': 'Partial',
  'Model Sync and Presence': 'Partial',
  'Models': 'Shipped',
  'Module Distribution and Trust': 'Partial',
  'Modules': 'Partial',
  'Monitoring and Observability': 'Partial',
  'Multi-tenancy': 'Partial',
  'Multi-Window': 'Partial',
  'Offline-First Models': 'Partial',
  'Organizations, Membership and Invitations': 'Partial',
  'OTA Updates': 'Partial',
  'Outbound HTTP': 'Partial',
  'Outbound Webhooks': 'Partial',
  'Package Structure': 'Partial',
  'Pages': 'Shipped',
  'Platform API: Keys, Scopes and OAuth Provider': 'Partial',
  'Platform Memory': 'Partial',
  'Platform': 'Partial',
  'Preview Environments': 'Partial',
  'Product Analytics and Consent': 'Partial',
  'Project Structure': 'Partial',
  'Protocol Versioning and Client Compatibility': 'Partial',
  'Purchases and Entitlements': 'Partial',
  'PWA': 'Shipped',
  'Queues, Jobs, and Signals': 'Partial',
  'Record History and Optimistic Concurrency': 'Partial',
  'Reversible Transactions': 'Shipped',
  'Routing': 'Shipped',
  'Scheduling': 'Partial',
  'Schema Evolution': 'Partial',
  'Search': 'Shipped',
  'Secrets and Environments': 'Partial',
  'Semantic Search and Embeddings': 'Partial',
  'Sensitive Model Fields': 'Partial',
  'SEO': 'Shipped',
  'Server Provisioning': 'Partial',
  'Sessions and Account Management': 'Partial',
  'State': 'Shipped',
  'Static Web Generation': 'Shipped',
  'Streaming Functions': 'Shipped',
  'Styling': 'Shipped',
  'Tab Workspaces': 'Partial',
  'Terminal Rendering': 'Partial',
  'Testing': 'Shipped',
  'The Golden Path': 'Partial',
  'Theme': 'Partial',
  'UI': 'Shipped',
  'Unified Development, Transparency, and Contracts': 'Partial',
  'Usage Metering and Quotas': 'Partial',
  'Web Server Rendering': 'Partial',
  'XR: Spatial Presentation': 'Partial',
};

/// The keys of one docs page's sections, so its contents can scroll to them.
///
/// Held in a State, one set per page. A link preview builds a second live
/// copy of a page while the first is still up, and keys shared across the
/// program would leave one copy without its sections.
class DocsAnchors extends StatefulWidget {
  const DocsAnchors({super.key, required this.ids, required this.builder});

  final List<String> ids;
  final Widget Function(BuildContext context, Map<String, GlobalKey> keys)
      builder;

  /// The keys of the page [context] is in, or null outside one.
  static Map<String, GlobalKey>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DocsAnchorKeys>()?.keys;

  @override
  State<DocsAnchors> createState() => _DocsAnchorsState();
}

class _DocsAnchorsState extends State<DocsAnchors> {
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  @override
  Widget build(BuildContext context) {
    for (final String id in widget.ids) {
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'docs:$id'));
    }
    return _DocsAnchorKeys(
      keys: _keys,
      child: Builder(
        builder: (BuildContext inner) => widget.builder(inner, _keys),
      ),
    );
  }
}

class _DocsAnchorKeys extends InheritedWidget {
  const _DocsAnchorKeys({required this.keys, required super.child});

  final Map<String, GlobalKey> keys;

  @override
  bool updateShouldNotify(_DocsAnchorKeys oldWidget) => keys != oldWidget.keys;
}

/// Scrolls the page [context] is in to its section [id].
///
/// Flutter has no fragment navigation, so this is what an anchor does: find
/// the section by key and scroll to it. Quiet when the key has no element yet.
void dvDocsGoTo(BuildContext context, String id) {
  final BuildContext? target =
      DocsAnchors.maybeOf(context)?[id]?.currentContext;
  if (target == null) return;
  Scrollable.ensureVisible(
    target,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeInOut,
  );
}

/// Scrolls to the section the address names after `#`, once the page is up.
///
/// A link such as dartvel.dev/cloud#plans is printed by the CLI, and Flutter
/// does not scroll to a fragment by itself: the page would open at the top
/// and the reader would never see the section the link was for. The section
/// is found by its key in the enclosing [DocsAnchors]. Frames are retried a
/// few times, because a page that loads deferred code builds its sections a
/// frame or two after this is first built.
class ScrollToFragment extends StatefulWidget {
  const ScrollToFragment({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollToFragment> createState() => _ScrollToFragmentState();
}

class _ScrollToFragmentState extends State<ScrollToFragment> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final String fragment =
        GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.fragment ?? '';
    if (fragment.isNotEmpty) _scroll(fragment, 10);
  }

  void _scroll(String id, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? target = DocsAnchors.maybeOf(context)?[id]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target);
      } else if (tries > 0) {
        _scroll(id, tries - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A docs page: its title, what it covers, its sections, and the way on.
@DVFunctionalWidget()
Widget _docsArticle(
  BuildContext context, {
  required DVRouteTarget page,
  required List<String> lead,
  required List<DocsSection> sections,
}) {
  final Palette palette = Palette.of(context);
  final DocsPageInfo? info = docsPageAt(page.path);
  final List<DocsSection> parts = sections;
  final double gutter =
      context.screen.value<double>(mobile: 22, tablet: 40, desktop: 56);

  return DocsAnchors(
    ids: <String>[for (final DocsSection s in parts) s.id],
    builder: (BuildContext inner, Map<String, GlobalKey> keys) =>
        ScrollToFragment(
      child: SingleChildScrollView(
      child: DVBox.list(<Widget>[
        DVBox(
          DVBox.list(<Widget>[
            DVBox.list(<Widget>[
              Eyebrow((info?.group ?? 'Docs').toUpperCase()),
              DVText(info?.title ?? '').modifier(const DVModifier()
                  .fontSize(context.screen.value<double>(mobile: 30, desktop: 40))
                  .fontWeight(FontWeight.w800)
                  .color(palette.ink)
                  .lineHeight(1.15)
                  .semanticHeading(1)),
              Bullets(lead),
            ], spacing: 14),
            DocsOnThisPage(sections: parts),
            for (final DocsSection section in parts)
              KeyedSubtree(key: keys[section.id], child: section),
            DocsPager(path: page.path),
          ], spacing: 44),
          const DVModifier()
              .maxWidth(780)
              .paddingSymmetric(horizontal: gutter, vertical: 40),
        ),
        const SiteFooter(),
      ], spacing: 0),
    ),
    ),
  );
}

/// The list a page opens with: every section on it, each a jump.
@DVFunctionalWidget()
Widget _docsOnThisPage(BuildContext context,
    {required List<DocsSection> sections}) {
  final Palette palette = Palette.of(context);
  final List<DocsSection> parts = sections;
  return DVBox(
    DVBox.list(<Widget>[
      const Eyebrow('ON THIS PAGE'),
      for (final DocsSection section in parts)
        DVText(section.title).modifier(const DVModifier()
            .fontSize(15)
            .fontWeight(FontWeight.w600)
            .color(palette.accent)
            .paddingSymmetric(vertical: 5)
            .semanticButton()
            .onTap(() => dvDocsGoTo(context, section.id))),
    ], spacing: 2, crossAlign: DVCrossAlign.start),
    const DVModifier()
        .width(double.infinity)
        .padding(20)
        .backgroundColor(palette.surface)
        .rounded(12),
  );
}

/// One section of a docs page, under a heading the contents links to.
@DVFunctionalWidget()
Widget _docsSection(
  BuildContext context, {
  required String id,
  required String title,
  required List<Widget> children,
}) {
  final Palette palette = Palette.of(context);
  return DVBox.list(<Widget>[
    DVText(title).modifier(const DVModifier()
        .fontSize(context.screen.value<double>(mobile: 22, desktop: 26))
        .fontWeight(FontWeight.w800)
        .color(palette.ink)
        .lineHeight(1.25)
        .semanticHeading(2)),
    ...children,
  ], spacing: 16, crossAlign: DVCrossAlign.start);
}

/// A smaller heading inside a section.
@DVFunctionalWidget()
Widget _docsSubheading(BuildContext context, String text) =>
    DVText(text).modifier(const DVModifier()
        .fontSize(18)
        .fontWeight(FontWeight.w700)
        .color(Palette.of(context).ink)
        .semanticHeading(3));

/// A short paragraph.
@DVFunctionalWidget()
Widget _docsText(BuildContext context, String text) =>
    DVText(text).modifier(const DVModifier()
        .fontSize(16)
        .color(Palette.of(context).muted)
        .lineHeight(1.6)
        .maxWidth(680));

/// A compiled sample from examples/docs_samples, by name.
@DVFunctionalWidget()
Widget _docsCode(BuildContext context, String name) =>
    CodeBlock(kDocsSamples[name] ?? <String>['// missing sample: $name']);

/// A block of the dartvel: section of pubspec.yaml, from the samples
/// project, where generation reads and checks it.
@DVFunctionalWidget()
Widget _docsYaml(BuildContext context, String name) => CodeBlock(<String>[
      '# pubspec.yaml',
      'dartvel:',
      for (final String line
          in kDocsSamples[name] ?? <String>['# missing sample: $name'])
        line.isEmpty ? '' : '  $line',
    ]);

/// Commands, a pubspec block or other text that is not Dart.
@DVFunctionalWidget()
Widget _docsShell(BuildContext context, List<String> lines) => CodeBlock(lines);

/// A callout for a fact you should not miss.
@DVFunctionalWidget()
Widget _docsNote(BuildContext context, String title, String text) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVBox.list(<Widget>[
      DVText(title).modifier(const DVModifier()
          .fontSize(15)
          .fontWeight(FontWeight.w700)
          .color(palette.ink)),
      DVText(text).modifier(const DVModifier()
          .fontSize(15)
          .color(palette.muted)
          .lineHeight(1.55)),
    ], spacing: 6),
    const DVModifier()
        .width(double.infinity)
        .maxWidth(680)
        .padding(16)
        .border(Border(left: BorderSide(color: palette.accent, width: 3)))
        .backgroundColor(palette.surface)
        .rounded(6),
  );
}

/// How much of [section] is built, from docs/spec-status.json, and what is
/// missing when it is partial.
@DVFunctionalWidget()
Widget _docsStatus(
  BuildContext context,
  String section, {
  List<String> missing = const <String>[],
}) {
  final Palette palette = Palette.of(context);
  final String status = kDocsSpecStatus[section] ?? 'Unknown';
  final bool partial = status != 'Shipped';
  final List<String> gaps = missing;
  return DVBox(
    DVBox.list(<Widget>[
      DVBox.wrapLine(<Widget>[
        DVText(partial ? 'Partial' : 'Built').modifier(const DVModifier()
            .fontSize(12)
            .fontWeight(FontWeight.w700)
            .color(partial ? palette.ink : palette.accent)
            .paddingSymmetric(horizontal: 9, vertical: 3)
            .backgroundColor(partial
                ? const Color(0xFFFFC857).withValues(alpha: 0.45)
                : palette.accent.withValues(alpha: 0.12))
            .rounded(999)),
        DVText('Spec section: $section').modifier(const DVModifier()
            .fontSize(14)
            .fontWeight(FontWeight.w600)
            .color(palette.muted)),
      ], spacing: 10, crossAlign: DVCrossAlign.center),
      if (gaps.isNotEmpty) Bullets(gaps),
    ], spacing: 12),
    const DVModifier()
        .width(double.infinity)
        .maxWidth(680)
        .padding(16)
        .border(Border.all(color: palette.rule))
        .rounded(10),
  );
}

/// A table that reads on a phone: each row is a small card, its first cell
/// the title and the others labelled by their column.
@DVFunctionalWidget()
Widget _docsTable(
  BuildContext context, {
  required List<String> columns,
  required List<List<String>> rows,
}) {
  final Palette palette = Palette.of(context);
  final List<String> heads = columns;
  return DVBox.list(<Widget>[
    for (final List<String> row in rows)
      DVBox(
        DVBox.list(<Widget>[
          DVText(row.first).modifier(const DVModifier()
              .fontSize(15)
              .fontWeight(FontWeight.w700)
              .fontFamily('RobotoMono')
              .color(palette.ink)),
          for (int i = 1; i < row.length && i < heads.length; i++)
            DVText('${heads[i]}: ${row[i]}').modifier(const DVModifier()
                .fontSize(14)
                .color(palette.muted)
                .lineHeight(1.5)),
        ], spacing: 4),
        const DVModifier()
            .width(double.infinity)
            .maxWidth(680)
            .paddingSymmetric(horizontal: 14, vertical: 10)
            .border(Border(bottom: BorderSide(color: palette.rule))),
      ),
  ], spacing: 0);
}

/// The previous and next pages, in reading order.
@DVFunctionalWidget()
Widget _docsPager(BuildContext context, {required String path}) {
  final int at = kDocsPages.indexWhere((DocsPageInfo p) => p.path == path);
  final DocsPageInfo? previous = at > 0 ? kDocsPages[at - 1] : null;
  final DocsPageInfo? next =
      at >= 0 && at < kDocsPages.length - 1 ? kDocsPages[at + 1] : null;
  return DVBox.wrapLine(<Widget>[
    if (previous != null) DocsPagerLink(page: previous, label: 'Previous'),
    if (next != null) DocsPagerLink(page: next, label: 'Next'),
  ], spacing: 16);
}

/// One pager card.
@DVFunctionalWidget()
Widget _docsPagerLink(
  BuildContext context, {
  required DocsPageInfo page,
  required String label,
}) {
  final Palette palette = Palette.of(context);
  return DVNavLink(
    to: page.target,
    padding: EdgeInsets.zero,
    child: DVBox(
      DVBox.list(<Widget>[
        DVText(label.toUpperCase()).modifier(const DVModifier()
            .fontSize(12)
            .fontWeight(FontWeight.w700)
            .letterSpacing(1.2)
            .color(palette.faint)),
        DVText(page.title).modifier(const DVModifier()
            .fontSize(17)
            .fontWeight(FontWeight.w700)
            .color(palette.accent)),
        DVText(page.summary).modifier(
            const DVModifier().fontSize(14).color(palette.muted).lineHeight(1.4)),
      ], spacing: 4),
      const DVModifier()
          .width(context.screen.value<double>(mobile: 300, tablet: 320))
          .padding(16)
          .border(Border.all(color: palette.rule))
          .rounded(10)
          .animate(const Duration(milliseconds: 160))
          .hover(const DVModifier()
              .border(Border.all(color: palette.accent.withValues(alpha: 0.5)))),
    ),
  );
}

/// Every docs page, grouped. The sidebar on a wide screen and the menu on a
/// narrow one.
///
/// In the sidebar every group is open. In the phone menu the groups fold, so
/// a reader sees the whole outline on one screen: the group holding
/// [current] starts open, and a tap on a heading opens that group instead.
@DVFunctionalWidget()
Widget _docsNav(
  BuildContext context, {
  required String current,
  bool folding = false,
}) {
  final Palette palette = Palette.of(context);
  final List<String> groups = docsGroups;
  final DVSignal<String?> openGroup =
      context.signal<String?>(docsPageAt(current)?.group ?? groups.first);
  final bool fold = folding;
  return DVBox.list(<Widget>[
    for (final String group in groups)
      DVBox.list(<Widget>[
        if (fold)
          MergeSemantics(
            child: Semantics(
              button: true,
              expanded: openGroup.value == group,
              child: DVBox(
                DVBox.row(<Widget>[
                  Flexible(
                    child: DVText(group.toUpperCase()).modifier(const DVModifier()
                        .fontSize(13)
                        .fontWeight(FontWeight.w700)
                        .letterSpacing(1.2)
                        .color(openGroup.value == group
                            ? palette.ink
                            : palette.muted)),
                  ),
                  ExcludeSemantics(
                    child: DVText(openGroup.value == group ? '−' : '+')
                        .modifier(const DVModifier()
                            .fontSize(18)
                            .fontWeight(FontWeight.w600)
                            .color(palette.faint)),
                  ),
                ],
                    spacing: 12,
                    align: DVAlign.spaceBetween,
                    crossAlign: DVCrossAlign.center),
                const DVModifier()
                    .width(double.infinity)
                    .paddingSymmetric(vertical: 10)
                    .onTap(() => openGroup.value =
                        openGroup.value == group ? null : group),
              ),
            ),
          )
        else
          DVText(group.toUpperCase()).modifier(const DVModifier()
              .fontSize(12)
              .fontWeight(FontWeight.w700)
              .letterSpacing(1.2)
              .color(palette.faint)
              .semanticHeading(2)),
        if (!fold || openGroup.value == group)
          for (final DocsPageInfo page in kDocsPages)
            if (page.group == group)
              DocsNavLink(page: page, active: page.path == current),
      ], spacing: 2, crossAlign: DVCrossAlign.start),
  ], spacing: fold ? 4 : 22, crossAlign: DVCrossAlign.start);
}

/// One link in the docs navigation.
@DVFunctionalWidget()
Widget _docsNavLink(
  BuildContext context, {
  required DocsPageInfo page,
  required bool active,
}) {
  final Palette palette = Palette.of(context);
  return DVNavLink(
    to: page.target,
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: DVText(page.title).modifier(const DVModifier()
        .fontSize(15)
        .fontWeight(active ? FontWeight.w700 : FontWeight.w500)
        .color(active ? palette.accent : palette.muted)),
  );
}

/// The docs frame: a sidebar beside the page on a wide screen, and a menu
/// above it on a narrow one.
@DVFunctionalWidget()
Widget _docsFrame(
  BuildContext context, {
  required String current,
  required Widget child,
}) {
  final Palette palette = Palette.of(context);
  final DVSignal<bool> open = context.signal(false);
  final Widget page = child;

  if (context.screen.width >= 960) {
    return DVBox.row(<Widget>[
      DVBox(
        SingleChildScrollView(
          // The sidebar, not the page: the page's controller is the article's.
          primary: false,
          padding: const EdgeInsets.fromLTRB(32, 32, 20, 48),
          child: DocsNav(current: current),
        ),
        const DVModifier()
            .width(270)
            .border(Border(right: BorderSide(color: palette.rule))),
      ),
      Expanded(child: page),
    ], spacing: 0, crossAlign: DVCrossAlign.stretch);
  }

  final DocsPageInfo? here = docsPageAt(current);
  return DVBox.list(<Widget>[
    DVBox(
      DVBox.row(<Widget>[
        DVText(open.value ? 'Close menu' : 'Docs menu').modifier(const DVModifier()
            .fontSize(15)
            .fontWeight(FontWeight.w700)
            .color(palette.accent)),
        Flexible(
          child: DVText(here?.title ?? '').modifier(const DVModifier()
              .fontSize(14)
              .color(palette.muted)
              .maxLines(1)),
        ),
      ], spacing: 12, crossAlign: DVCrossAlign.center),
      const DVModifier()
          .width(double.infinity)
          .paddingSymmetric(horizontal: 22, vertical: 12)
          .backgroundColor(palette.surface)
          .border(Border(bottom: BorderSide(color: palette.rule)))
          .semanticButton()
          .semanticLabel(open.value ? 'Close the docs menu' : 'Open the docs menu')
          .onTap(() => open.value = !open.value),
    ),
    Expanded(
      child: open.value
          ? DVBox(
              SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
                child: DocsNav(current: current, folding: true),
              ),
              const DVModifier().width(double.infinity).backgroundColor(palette.page),
            )
          : page,
    ),
  ], spacing: 0);
}

/// One command of the CLI reference: what it does, its aliases, its flags,
/// and its subcommands under it.
@DVFunctionalWidget()
Widget _docsCliEntry(BuildContext context, {required DocsCliCommand command}) {
  final Palette palette = Palette.of(context);
  final DocsCliCommand entry = command;
  return DVBox.list(<Widget>[
    DocsText(entry.description),
    if (entry.aliases.isNotEmpty)
      DVText('Also: ${entry.aliases.map((String a) => 'dartvel $a').join(', ')}')
          .modifier(const DVModifier().fontSize(14).color(palette.muted)),
    if (entry.options.isNotEmpty) CodeBlock(entry.options),
    for (final DocsCliCommand sub in entry.subcommands)
      DVBox(
        DVBox.list(<Widget>[
          DocsSubheading('dartvel ${entry.name} ${sub.name}'),
          DocsText(sub.description),
          if (sub.options.isNotEmpty) CodeBlock(sub.options),
        ], spacing: 10, crossAlign: DVCrossAlign.start),
        const DVModifier()
            .paddingOnly(left: 14)
            .border(Border(left: BorderSide(color: palette.rule, width: 2))),
      ),
  ], spacing: 12, crossAlign: DVCrossAlign.start);
}
