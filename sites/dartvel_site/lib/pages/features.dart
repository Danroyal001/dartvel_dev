import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

/// Every section the repository records as Shipped, and nothing else.
///
/// The list is taken from docs/spec-status.json, which is checked by a tool
/// that fails when a section claims to be built and the evidence it names does
/// not exist. A marketing page that listed more than that would be the first
/// place the project stopped being honest.
/// Public because the page body is lowered into the generated router,
/// which reaches a page's public symbols through its import and cannot see
/// a private one at all.
const List<(String, String, String)> shipped = <(String, String, String)>[
  (
    'UI',
    'DVBox and DVText',
    'One layout primitive with a fluent modifier chain. DVBox.list, .row, '
    '.grid and .wrapLine for collections; DVBox(child) for a single one.',
  ),
  (
    'Styling',
    'Fluent modifiers',
    'padding, rounded, colour, typography, shadows, tap targets and semantics '
    'on one chain, built on Mix.',
  ),
  (
    'Routing',
    'File-based pages',
    'A file under lib/pages is a route. Navigation is typed against generated '
    'targets, so a moved page is a compile error rather than a 404.',
  ),
  (
    'State',
    'Signals',
    'context.signal, signal(context, value), reactive models and DV.global. '
    'Operating on signals returns a signal, so a + b and stock > 0 track '
    'their sources without a separate computed type.',
  ),
  (
    'Models',
    '@DVModel',
    'One annotated class generates the typed client, serialization, the form, '
    'the table, the admin surface and the sync.',
  ),
  (
    'Forms',
    'DVForm<T>',
    'Inputs, validation and error surfaces derived from the model, so a field '
    'added to the model appears in the form.',
  ),
  (
    'Backend',
    '@DVBackendFunction',
    'A Dart function becomes an endpoint, served by an Axum and Tokio runtime '
    'in Rust reached over FFI, with the client generated alongside it.',
  ),
  (
    'Streaming Functions',
    'Server-sent events',
    'A backend function that returns a stream is served as SSE, with a typed '
    'client that consumes it.',
  ),
  (
    'Authorization',
    'DV.Auth.authorization',
    'Policies over models and functions, enforced before a handler runs '
    'rather than inside it.',
  ),
  (
    'Middleware',
    'Request pipeline',
    'Composable middleware around backend functions, with the request '
    'lifecycle observable as a signal.',
  ),
  (
    'Theme',
    'Light and dark',
    'A themed surface that follows the system by default. This site runs on '
    'it — switch your appearance and it follows.',
  ),
  (
    'Model Sync and Presence',
    'Built on models and signals',
    'Generated sync, subscriptions, presence and fanout. There is no '
    'DV.Realtime namespace, deliberately: it is models, signals and queues.',
  ),
  (
    'Multi-tenancy',
    'Tenant scoping',
    'Tenant resolution and scoping through the model and request layers.',
  ),
  (
    'SEO',
    'Head tags and prerendering',
    'dartvel build web writes the title, description, canonical, Open Graph '
    'and Twitter tags from configuration, and prerendered routes carry '
    'semantic content for crawlers.',
  ),
  (
    'AI',
    'DV.AI',
    'A local adapter, structured outputs and embeddings, with provider '
    'extension points.',
  ),
  (
    'CSRF Protection',
    'On by default',
    'Token issue and verification wired through the request pipeline rather '
    'than left to the application.',
  ),
  (
    'Lifecycle Signals',
    'Read-only enums',
    'DV.lifecycle.app and .build, context.lifecycle.page, .request and '
    '.transaction. Application code observes them; it does not assign them.',
  ),
  (
    'Modules',
    'DV.Modules.<id>',
    'A module is a whole Dartvel application boundary, mounted by a parent. '
    'Module code never hard-codes its mount point.',
  ),
  (
    'Generated Model Pages',
    'Model.Page(...)',
    'Public pages from a model, with .async, .signal and .fromId. Static '
    'paths come from the model rather than a route written out as a string.',
  ),
  (
    'Reversible Transactions',
    'DV.transaction',
    'context.afterCommit and context.compensate, so a failure unwinds what '
    'ran rather than leaving it half-applied.',
  ),
  (
    'Background and Durable Work',
    '@DVJob and DV.Queues',
    'Durable jobs and queues. background: true and durable: true on a backend '
    'function are sugar that compiles onto the same layer.',
  ),
  (
    'Sensitive Model Fields',
    '@DVModel.sensitiveField()',
    'Excluded from logs, AI context, traces, analytics, public serialization, '
    'search, generated pages, tables and admin by default. Reaching a client '
    'takes an explicit policy.',
  ),
  (
    'Passkeys, SAML, LDAP and Web3',
    'Four ways in',
    'WebAuthn assertions, SAML 2.0 built against signature wrapping rather '
    'than around it, LDAP over BER, and Sign-In with Ethereum bound to a '
    'nonce, a domain and a clock.',
  ),
  (
    'Distributed Cache',
    'Rendezvous hashing',
    'Keys spread across several servers. Adding or removing a node moves only '
    'that node’s share — with a modulo it moves almost everything, and the '
    'cache empties without reporting anything.',
  ),
  (
    'Object Storage',
    'S3, Azure Blob, GCS',
    'Verified against Azurite and fake-gcs-server in CI, not against fakes. '
    'Azure signs the encoded path, which only a real server will tell you.',
  ),
  (
    'Hosted Search',
    'Meilisearch, OpenSearch, Algolia',
    'With highlights and facet counts, which an engine returns only when the '
    'query asks. Run against real Meilisearch and OpenSearch in CI.',
  ),
  (
    'Binary Transport',
    'Flat-buffer envelope',
    'Form-data whose fields are binary buffers, so an int stays an int. Over '
    'text multipart the type is gone by the time a parameter is decoded.',
  ),
  (
    'Project Graph',
    'dartvel inspect, dartvel mcp',
    'One versioned graph of routes, models, functions and jobs, with the '
    'source each was derived from. --json is a serialization of it, and '
    'dartvel mcp serves it to a coding agent.',
  ),
  (
    'Block Bodies',
    'Every annotation',
    '@DVPage, @DVFunctionalWidget, @DVBackendFunction and @DVJob.handler all '
    'take a block body. No more one-line wrappers around a public helper.',
  ),
];

@DVPage(title: 'Features — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _featuresPage(BuildContext context) => SingleChildScrollView(
      child: DVBox.list(<Widget>[
        const Section(
          children: <Widget>[
            Eyebrow('WHAT WORKS TODAY'),
            Heading('Thirty-three shipped sections.', level: 1),
            Body(
              'This list is the repository’s own record of what is built, not '
              'a description of what is planned. A tool checks it and fails '
              'when a section claims to be built and the evidence it names '
              'does not exist, so this page cannot quietly get ahead of the '
              'code.',
              width: 660,
            ),
            Body(
              'Twenty-two more sections are partial. They are listed as '
              'partial, with what is absent written next to what is present.',
              width: 660,
            ),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            // A grid where there is room. Twenty-two full-width rows
            // separated by hairlines is a list to scroll past rather than a
            // set of things to compare, and every one of them looked the
            // same as the last.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = constraints.maxWidth >= 900
                    ? 2
                    : 1;
                if (columns == 1) {
                  return DVBox.list(<Widget>[
                    for (final (String area, String surface, String body) f
                        in shipped)
                      FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
                  ], spacing: 14);
                }
                const double gap = 18;
                final double width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    for (final (String area, String surface, String body) f
                        in shipped)
                      SizedBox(
                        width: width,
                        child: FeatureRow(
                            area: f.$1, surface: f.$2, body: f.$3),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        const SiteFooter(),
      ], spacing: 0),
    );

/// One shipped capability: the area, the surface you actually type, and what
/// it does.
@DVFunctionalWidget()
Widget _featureRow(
  BuildContext context, {
  required String area,
  required String surface,
  required String body,
}) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVBox.list(<Widget>[
      // A wrapping line rather than a row. The chip carries an API name and
      // some of them are long: in a fixed row the pair overflowed its card by
      // a few pixels at one width and by forty at another, and an overflow
      // clips in release with nothing to say it did.
      DVBox.wrapLine(<Widget>[
        DVText(area).modifier(
          DVModifier()
              .fontSize(17)
              .fontWeight(FontWeight.w700)
              .color(palette.ink)
              // Under the page's h1. Without a level these were twenty-two
              // paragraphs, so the page had a title and no structure under it
              // -- for a screen reader moving by heading and for the
              // crawler-visible HTML alike.
              .semanticHeading(3),
        ),
        SiteChip(surface),
      ], spacing: 10),
      DVText(body).modifier(
        DVModifier().fontSize(15).color(palette.muted).height(1.6),
      ),
    ], spacing: 6),
    DVModifier()
        // No height: a wrap gives its children unbounded height, so
        // double.infinity here collapsed every card and the section rendered
        // empty. Cards size to their content instead.
        .paddingOnly(left: 18, top: 16, right: 18, bottom: 18)
        // page, not surface: the section this sits on is tinted with surface,
        // so a card in the same colour is an invisible card.
        .backgroundColor(palette.page)
        .rounded(12)
        .border(Border.all(color: palette.rule)),
  );
}
