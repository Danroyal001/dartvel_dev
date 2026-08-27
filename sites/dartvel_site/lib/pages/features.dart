import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

/// Every section the repository records as Shipped, and nothing else.
///
/// The list is taken from docs/spec-status.json, which is checked by a tool
/// that fails when a section claims to be built and the evidence it names does
/// not exist. A marketing page that listed more than that would be the first
/// place the project stopped being honest.
const List<(String, String, String)> _shipped = <(String, String, String)>[
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
];

@DVPage(title: 'Features — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _featuresPage(BuildContext context) => buildFeaturesPage(context);

Widget buildFeaturesPage(BuildContext context) => SitePage(
      current: '/features',
      children: <Widget>[
        Section(
          children: <Widget>[
            const Eyebrow('WHAT WORKS TODAY'),
            const Heading('Twenty-two shipped sections.'),
            const Body(
              'This list is the repository’s own record of what is built, not '
              'a description of what is planned. A tool checks it and fails '
              'when a section claims to be built and the evidence it names '
              'does not exist, so this page cannot quietly get ahead of the '
              'code.',
              width: 660,
            ),
            const Body(
              'Thirty-three more sections are partial. They are listed as '
              'partial, with what is absent written next to what is present.',
              width: 660,
            ),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            DVBox.list(<Widget>[
              for (final (String area, String surface, String body) f
                  in _shipped)
                FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
            ], spacing: 16),
          ],
        ),
      ],
    );

/// One shipped capability: the area, the surface you actually type, and what
/// it does.
class FeatureRow extends StatelessWidget {
  const FeatureRow({
    super.key,
    required this.area,
    required this.surface,
    required this.body,
  });

  final String area;
  final String surface;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.rule)),
      ),
      child: DVBox.list(<Widget>[
        // Baseline-aligned: a chip centred against a 17pt heading rides high
        // and reads as a separate row.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            DVText(area).modifier(
              DVModifier()
                  .fontSize(17)
                  .fontWeight(FontWeight.w700)
                  .color(palette.ink),
            ),
            const SizedBox(width: 12),
            Flexible(child: Chip_(surface)),
          ],
        ),
        DVText(body).modifier(
          DVModifier().fontSize(15).color(palette.muted).height(1.6).width(760),
        ),
      ], spacing: 6),
    );
  }
}
