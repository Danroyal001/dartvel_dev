// Where each built part of Dartvel is written up on the site.
//
// docs/spec-status.json records every section of NEW_SPEC.md as Shipped,
// Partial or Designed. Each Shipped or Partial section is either mapped here
// to the page and heading that covers it, or listed in kSpecKnownGaps.
// test/spec_coverage_test.dart holds both to the site and to the index, and
// the docs index page lists them all from these two lists.
import '../dartvel_client/dartvel_client.dart';

/// One built spec section and the place on the site that covers it.
class SpecCoverage {
  const SpecCoverage(
    this.section,
    this.group,
    this.target,
    this.heading, {
    this.anchor,
  });

  /// The section title exactly as docs/spec-status.json has it.
  final String section;

  /// The docs group it is listed under, one of kDocsGroupOrder.
  final String group;

  /// The page that covers it.
  final DVRouteTarget target;

  /// A heading written in that page's source: a DocsSection title, a
  /// Heading or a card title.
  final String heading;

  /// The DocsSection id of [heading], so a link can land on it.
  final String? anchor;

  /// Where a link to this section goes.
  String get href => anchor == null ? target.path : '${target.path}#$anchor';
}

/// Built sections and where each is covered. A section is named as
/// docs/spec-status.json names it, with a colon in place of an em dash, which
/// site copy does not use.
const List<SpecCoverage> kSpecCoverage = <SpecCoverage>[
  // Getting started
  SpecCoverage('Project Structure', 'Getting started', DVRoutes.docs,
      'Project structure', anchor: 'structure'),
  SpecCoverage('Adoption', 'Getting started', DVRoutes.docsadopting,
      'Run dartvel init', anchor: 'init'),
  SpecCoverage('Package Structure', 'Getting started', DVRoutes.docs,
      'One package with every import'),
  SpecCoverage('Dev Client', 'Getting started', DVRoutes.docsdevclient,
      'Pair it with dartvel dev', anchor: 'pair'),

  // App
  SpecCoverage('UI', 'App', DVRoutes.docsui, 'Wrap one child with DVBox',
      anchor: 'box'),
  SpecCoverage('Styling', 'App', DVRoutes.docsui,
      'Style anything with DVModifier', anchor: 'modifiers'),
  SpecCoverage('Theme', 'App', DVRoutes.docsui, 'Switch light and dark mode',
      anchor: 'theme'),
  SpecCoverage('Pages', 'App', DVRoutes.docsrouting, 'Add a page with a file',
      anchor: 'file-pages'),
  SpecCoverage('Routing', 'App', DVRoutes.docsrouting,
      'Navigate with typed DVRoutes targets', anchor: 'typed-navigation'),
  SpecCoverage('Error, Empty, and Loading States', 'App', DVRoutes.docsrouting,
      'Show loading and error states', anchor: 'loading-error'),
  SpecCoverage('SEO', 'App', DVRoutes.docsrouting,
      'Set the title and sitemap entry', anchor: 'seo'),
  SpecCoverage('State', 'App', DVRoutes.docsstate,
      'Create a signal with context.signal', anchor: 'signals'),
  SpecCoverage('Lifecycle Signals', 'App', DVRoutes.docsstate,
      'Observe the app lifecycle', anchor: 'lifecycle'),
  SpecCoverage('Platform Memory', 'App', DVRoutes.docsworkers,
      'Reserve memory up front', anchor: 'arena'),
  SpecCoverage('Accessibility', 'App', DVRoutes.docsaccessibility,
      'Fail the build on an accessibility regression', anchor: 'audit'),
  SpecCoverage('Internationalization and Localization', 'App',
      DVRoutes.docslocalization, 'Declare keys and load catalogues',
      anchor: 'keys'),

  // Data
  SpecCoverage('Models', 'Data', DVRoutes.docsmodels, 'Declare a model',
      anchor: 'declare'),
  SpecCoverage('Forms', 'Data', DVRoutes.docsforms,
      'Generate a form from a model', anchor: 'automatic'),
  SpecCoverage('Generated Model Pages', 'Data', DVRoutes.docsmodels,
      'Serve a public page per record', anchor: 'model-pages'),
  SpecCoverage('Record History and Optimistic Concurrency', 'Data',
      DVRoutes.docsmodels, 'Keep and revert record history',
      anchor: 'history'),
  SpecCoverage('Search', 'Data', DVRoutes.docssearch,
      'Choose a search provider', anchor: 'providers'),
  SpecCoverage('Semantic Search and Embeddings', 'Data', DVRoutes.docssearch,
      'Search by meaning with embeddings', anchor: 'semantic'),
  SpecCoverage('Model Sync and Presence', 'Data', DVRoutes.docssync,
      'Watch model changes', anchor: 'changes'),
  SpecCoverage('Offline-First Models', 'Data', DVRoutes.docssync,
      'Keep writing while offline', anchor: 'offline'),
  SpecCoverage('Data Import, Export, and Reporting', 'Data',
      DVRoutes.docsimportexport, 'Import a CSV file', anchor: 'import'),
  SpecCoverage('Change Data Capture and Warehouse Sync', 'Data',
      DVRoutes.docschangecapture, 'Record every write in order',
      anchor: 'log'),
  SpecCoverage('Media Pipeline', 'Data', DVRoutes.docsmedia,
      'Serve each image at the width it needs', anchor: 'variants'),
  SpecCoverage('Sensitive Model Fields', 'Data', DVRoutes.docsmodels,
      'Protect sensitive fields', anchor: 'sensitive'),
  SpecCoverage('Database', 'Data', DVRoutes.docsdatabase, 'Use SQLite locally',
      anchor: 'sqlite'),
  SpecCoverage('Schema Evolution', 'Data', DVRoutes.docsdatabase,
      'Migrate production safely', anchor: 'production'),
  SpecCoverage('Cache', 'Data', DVRoutes.docscache,
      'Remember a value and revalidate it by tag', anchor: 'remember'),
  SpecCoverage('File Storage', 'Data', DVRoutes.docsstorage,
      'Configure a storage adapter', anchor: 'configure'),
  SpecCoverage('Data Compliance and Lifecycle', 'Data', DVRoutes.docsprivacy,
      'Export and erase a person\'s data', anchor: 'erase'),

  // Backend
  SpecCoverage('Backend', 'Backend', DVRoutes.docsbackendfunctions,
      'Write a backend function', anchor: 'write'),
  SpecCoverage('Streaming Functions', 'Backend', DVRoutes.docsbackendfunctions,
      'Stream results with server-sent events', anchor: 'streams'),
  SpecCoverage('Reversible Transactions', 'Backend',
      DVRoutes.docsbackendfunctions, 'Undo partial work with a transaction',
      anchor: 'transactions'),
  SpecCoverage('Background and Durable Work', 'Backend',
      DVRoutes.docsbackendfunctions, 'Move slow work to a job',
      anchor: 'background'),
  SpecCoverage('Middleware', 'Backend', DVRoutes.docsbackendfunctions,
      'Add middleware', anchor: 'middleware'),
  SpecCoverage('Authentication', 'Backend', DVRoutes.docsauth,
      'Sign in with email and password', anchor: 'sign-in'),
  SpecCoverage('Sessions and Account Management', 'Backend', DVRoutes.docsauth,
      'List and revoke sessions', anchor: 'sessions'),
  SpecCoverage('Authorization', 'Backend', DVRoutes.docsauthorization,
      'Write a policy class', anchor: 'policy'),
  SpecCoverage('Queues, Jobs, and Signals', 'Backend', DVRoutes.docsqueues,
      'Declare a job and its handler', anchor: 'declare'),
  SpecCoverage('Scheduling', 'Backend', DVRoutes.docsqueues,
      'Schedule work with cron', anchor: 'schedules'),
  SpecCoverage('Mail and Notifications', 'Backend', DVRoutes.docsnotifications,
      'Send an email', anchor: 'mail-send'),
  SpecCoverage('Outbound HTTP', 'Backend', DVRoutes.docshttp, 'Declare a host',
      anchor: 'declare'),
  SpecCoverage('Outbound Webhooks', 'Backend', DVRoutes.docswebhooks,
      'Declare, subscribe and emit', anchor: 'emit'),
  SpecCoverage('APIs', 'Backend', DVRoutes.docsgraphql, 'The endpoints',
      anchor: 'endpoints'),
  SpecCoverage('Platform API: Keys, Scopes and OAuth Provider', 'Backend',
      DVRoutes.docsplatformapi, 'Issue an API key', anchor: 'keys'),
  SpecCoverage('Multi-tenancy', 'Backend', DVRoutes.docstenancy,
      'Resolve the tenant from the request', anchor: 'resolve'),
  SpecCoverage('Organizations, Membership and Invitations', 'Backend',
      DVRoutes.docsorganizations, 'Invite people by email', anchor: 'invite'),
  SpecCoverage('AI', 'Backend', DVRoutes.docsai, 'Pick a provider',
      anchor: 'configure'),
  SpecCoverage('AI Operations', 'Backend', DVRoutes.docsai,
      'Run a prompt with a budget and a fallback', anchor: 'operations'),
  SpecCoverage('Backend Function Request Lifecycle', 'Backend',
      DVRoutes.docsbackendfunctions, 'Watch a request move through its stages',
      anchor: 'lifecycle'),
  SpecCoverage('CSRF Protection', 'Backend', DVRoutes.docsbackendfunctions,
      'CSRF protection is on for every function', anchor: 'csrf'),
  SpecCoverage('Compute: Workers and Native Offload', 'Backend',
      DVRoutes.docsworkers, 'Run a task on a worker', anchor: 'run'),

  SpecCoverage('Billing', 'Backend', DVRoutes.docsbilling,
      'Sell a plan through Stripe or Paddle', anchor: 'subscriptions'),

  SpecCoverage('Purchases and Entitlements', 'Backend', DVRoutes.docsbilling,
      'Check app store purchases on your server', anchor: 'purchases'),

  SpecCoverage('Commerce: Tax, Promotions, Disputes and Payouts', 'Backend', DVRoutes.docsbilling,
      'Charge with tax and promotions, and refund cleanly', anchor: 'commerce'),

  SpecCoverage('Usage Metering and Quotas', 'Backend', DVRoutes.docsbilling,
      'Meter usage and cap it per tenant', anchor: 'usage'),

  // Operations
  SpecCoverage('Server Provisioning', 'Operations', DVRoutes.docsdeploying,
      'Provision servers with dartvel infra', anchor: 'infra'),
  SpecCoverage('Edge Security', 'Operations', DVRoutes.docsedgesecurity,
      'Sign-in is rate limited by default', anchor: 'sign-in'),
  SpecCoverage('Secrets and Environments', 'Operations', DVRoutes.docssecrets,
      'Declare your secrets', anchor: 'declare'),

  SpecCoverage('Monitoring and Observability', 'Operations', DVRoutes.docsmonitoring,
      'Read metrics and health from any backend', anchor: 'metrics'),

  SpecCoverage('Distributed Tracing', 'Operations', DVRoutes.docsmonitoring,
      'Follow one request across services', anchor: 'tracing'),

  SpecCoverage('Crash Reporting and Release Health', 'Operations', DVRoutes.docsmonitoring,
      'Crash reports are on from the first build', anchor: 'crashes'),

  SpecCoverage('Alerting, SLOs and Status Pages', 'Operations', DVRoutes.docsmonitoring,
      'Alert on error budgets and open incidents', anchor: 'alerts'),

  SpecCoverage('Product Analytics and Consent', 'Operations', DVRoutes.docsmonitoring,
      'Product analytics that respect consent', anchor: 'analytics'),

  SpecCoverage('Feature Flags and Staged Rollout', 'Operations', DVRoutes.docsreleases,
      'Roll a feature out with typed flags', anchor: 'flags'),

  SpecCoverage('Preview Environments', 'Operations', DVRoutes.docsreleases,
      'Give every branch its own preview', anchor: 'previews'),

  SpecCoverage('Backend Release Management', 'Operations', DVRoutes.docsreleases,
      'Release a backend behind health gates', anchor: 'backend-releases'),

  SpecCoverage('Protocol Versioning and Client Compatibility', 'Operations', DVRoutes.docsreleases,
      'Keep old app versions working', anchor: 'old-clients'),

  // Shipping
  SpecCoverage('Deployment', 'Shipping', DVRoutes.docsdeploying,
      'Deploy with dartvel deploy', anchor: 'deploy'),
  SpecCoverage('Static Web Generation', 'Shipping', DVRoutes.docswebhosting,
      'What the build writes', anchor: 'output'),
  SpecCoverage('Embedded, Television, and Extension Build Targets', 'Shipping',
      DVRoutes.docsbuilding, 'TVs and embedded devices use vendor embedders',
      anchor: 'embedded'),
  SpecCoverage('Terminal Rendering', 'Shipping', DVRoutes.docsbuilding,
      'Build for the terminal', anchor: 'terminal'),
  SpecCoverage('App Store Deployment and Privacy Manifests', 'Shipping',
      DVRoutes.cloud,
      'Build and upload to Google Play or the App Store in one step.'),
  SpecCoverage('OTA Updates', 'Shipping', DVRoutes.cloud,
      'Push a fix to phones without waiting for store review.'),
  SpecCoverage('Dartvel Cloud', 'Shipping', DVRoutes.cloud,
      'Build for Android, iOS, Apple TV, Samsung TVs, Linux devices and browser extensions from any computer.'),

  // Studio
  SpecCoverage('Admin, Devtools, and Scaffolding', 'Studio',
      DVRoutes.docsmodels, 'Add an admin screen', anchor: 'admin'),
  SpecCoverage('Dartvel Studio', 'Studio', DVRoutes.studio,
      'Drag a page together, then keep it as an ordinary @DVPage.'),
  SpecCoverage('Content Workflow', 'Data', DVRoutes.studio, 'Content review'),
  SpecCoverage('Documentation Generation', 'Reference', DVRoutes.studio,
      'Project docs'),

  // Reference
  SpecCoverage('CLI', 'Reference', DVRoutes.docscli, 'Status',
      anchor: 'status'),
  SpecCoverage('Testing', 'Reference', DVRoutes.docstesting,
      'A test with fakes', anchor: 'example'),
];

/// Built sections the site does not cover yet, with the group each belongs
/// in. This list only shrinks: when a page covers one, move it to
/// kSpecCoverage.
const Map<String, String> kSpecKnownGaps = <String, String>{
  // Getting started
  'The Golden Path': 'Getting started',
  'Unified Development, Transparency, and Contracts': 'Getting started',
  'Generated Code Determinism': 'Getting started',

  // App
  'PWA': 'App',
  'Platform': 'App',
  'Multi-Window': 'App',
  'Tab Workspaces': 'App',
  'Home Widgets': 'App',
  'Kiosk Mode': 'App',
  'Media Playback and Capture': 'App',
  '3D Scenes': 'App',
  'XR: Spatial Presentation': 'App',
  'Desktop, Embedded, and Qt-Critical Capabilities': 'App',

  // Backend
  'Web Server Rendering': 'Backend',
  'Modules': 'Backend',
  'Module Distribution and Trust': 'Backend',

  // Operations
};
