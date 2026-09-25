import 'dart:math' as math;

import '../auth/sessions.dart' show DVMfa;
import '../data/record_history.dart' show DVConflict, DVHistory;
import '../privacy/privacy.dart' show DVRetention;

/// Annotation for a route
class Route {
  final String path;
  final String? name;

  const Route(this.path, {this.name});
}

/// Annotation for a GET handler
class Get {
  final String path;
  const Get([this.path = '/']);
}

/// Annotation for a POST handler
class Post {
  final String path;
  const Post([this.path = '/']);
}

/// Annotation for a PUT handler
class Put {
  final String path;
  const Put([this.path = '/']);
}

/// Annotation for a DELETE handler
class Delete {
  final String path;
  const Delete([this.path = '/']);
}

/// Annotation for a PATCH handler
class Patch {
  final String path;
  const Patch([this.path = '/']);
}

/// Platform shell used by [DVPage].
enum DVPageShellMode {
  adaptive,
  material,
  cupertino,
  none,
}

/// Annotation for a Dartvel Page.
class DVPage {
  final String? path;
  final String? title;

  /// What this page is about, in a sentence: its meta description, its
  /// og:description and the description in its structured data.
  ///
  /// A page could say what it was called and not what it was about, so
  /// every page on a site shipped the project-wide description -- fifty pages
  /// competing for one snippet, which is fifty pages a search engine has no
  /// reason to tell apart. Null keeps the project's own, which is the right
  /// answer for a page nobody has written a sentence for yet.
  final String? description;
  final String? policy;
  final DVPageShellMode shell;
  final bool scaffold;
  final bool showAppBar;

  /// Whether the page's text can be selected. True by default -- a page whose
  /// text cannot be copied is a defect rather than a style.
  final bool selectable;

  /// Whether the browser's own find (Ctrl+F, "Find in page") reaches this
  /// page on the web. True by default: the shell keeps a findable copy of
  /// the page's rendered text in the document and scrolls to what the
  /// browser matched, with nothing for the page to add.
  ///
  /// False keeps that copy out of the document at runtime, for a page whose
  /// text should never be anywhere but its canvas. What the build wrote for
  /// crawlers and printers is left, and not searched.
  final bool findable;
  final bool safeArea;
  final bool centerTitle;
  final bool extendBody;
  final bool resizeToAvoidBottomInset;
  final int? backgroundColor;
  final int? appBarBackgroundColor;

  /// How this page appears in `sitemap.xml`, or null for the defaults.
  ///
  /// The specification shows this argument and no Dart file had it, so a
  /// page could not say it changes daily or matters more than its
  /// neighbours -- every route was emitted with a URL and nothing else.
  final DVPageSitemap? sitemap;

  /// The second factor this device's session must have presented before the
  /// page opens, or null for none. An unsatisfied page redirects to the
  /// second-factor challenge and comes back once it is presented. The page is
  /// the interface; the backend functions it calls enforce their own `mfa`.
  final DVMfa? mfa;

  const DVPage({
    this.path,
    this.title,
    this.description,
    this.policy,
    this.mfa,
    this.shell = DVPageShellMode.adaptive,
    this.scaffold = true,
    this.showAppBar = false,
    this.selectable = true,
    this.findable = true,
    this.safeArea = true,
    this.centerTitle = false,
    this.extendBody = false,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
    this.appBarBackgroundColor,
    this.sitemap,
  });
}

/// How often a page changes, in the words sitemaps.org defines.
///
/// A crawler treats these as a hint rather than a promise, which is the
/// reason to be honest with them: a site that says hourly everywhere is
/// telling a crawler nothing, and one that says it about a page that changes
/// yearly spends somebody else's crawl budget.
enum DVSitemapChangeFrequency {
  always,
  hourly,
  daily,
  weekly,
  monthly,
  yearly,
  never;

  /// The token sitemaps.org expects, which is the enum's own name.
  String get token => name;
}

/// A page's entry in `sitemap.xml`.
///
/// [priority] is relative to the rest of this site and nothing else. It does
/// not raise a page in anybody's results; it says which of your own pages to
/// crawl first when a crawler cannot take them all.
class DVPageSitemap {
  const DVPageSitemap({this.priority, this.changeFrequency});

  /// Between 0 and 1. Out of range is refused where it is read rather than
  /// clamped, because a 5 that silently became a 1 reads as working.
  final double? priority;

  final DVSitemapChangeFrequency? changeFrequency;
}

/// Annotation for a functional widget Page
class DVFunctionalWidget {
  const DVFunctionalWidget();
}

/// How a generated `Model.Page(...)` resolves the data it renders.
enum DVModelPageDataMode {
  /// Picks the mode from the input: an existing model renders synchronously,
  /// an id or route parameter triggers an async query, a signal renders
  /// reactively, and a cached record renders immediately then refreshes.
  auto,

  /// Renders an already-loaded model with no fetch.
  sync,

  /// Awaits a future before rendering.
  async,

  /// Rebuilds from a signal as it changes.
  reactive,

  /// Serves the cached record; does not refresh on its own.
  cached,

  /// Serves the cached record immediately, then refreshes in the background.
  staleWhileRevalidate,
}

/// Supplies the concrete parameter values a parameterized route needs during
/// static generation.
///
/// Static routes are always generated. A parameterized route cannot be unless
/// something enumerates the values to generate for it:
///
/// ```dart
/// @DVModel(publicPathsResolver: productPaths)
/// class _Product { ... }
///
/// Future<List<String>> productPaths() async =>
///     Product.public().select((product) => product.slug);
/// ```
///
/// A model generates public pages by default, and they supply these
/// automatically from its published records, which covers the common case
/// without a resolver at all. See [DVModel.publicPathsResolver].
typedef DVPublicPathsResolver = Future<List<String>> Function();

/// The part a field plays in a generated model page, set by the field-scoped
/// `@DVModel.featuredImage()`, `.pageTitle()`, `.mainContent()` and
/// `.hideFromPage()` constructors.
enum DVModelPageRole {
  /// The page's featured image.
  featuredImage,

  /// The page's title.
  pageTitle,

  /// The page's main text content.
  mainContent,

  /// Excluded from the page.
  hidden,
}

/// What an erasure does to a sensitive field:
/// `@DVModel.sensitiveField(onErase: DVErase.anonymize)`.
enum DVErase {
  /// The row goes with the erasure. The default.
  delete,

  /// The field is replaced with a tombstone and the row stays.
  anonymize,
}

/// Annotation metadata for a Dartvel data model.
///
/// The generator adds serialization and model behavior to the annotated class;
/// this annotation intentionally does not provide a fake runtime model.
class DVModel {
  final bool searchable;
  final bool billable;
  final int? nativePrice;

  /// How generated `Model.Page(...)` resolves its data by default.
  final DVModelPageDataMode pageDataMode;

  /// Whether the generator emits public pages, and static paths for them
  /// during static generation, from this model's published records.
  ///
  /// On by default: every model gets a page per record at
  /// `/<plural-kebab-model>/:<key>` unless it says `generatePublicPages:
  /// false`. What a page shows is decided by the model's other
  /// declarations, not by this flag. A `@DVModel.sensitiveField()`, and the
  /// fields that identify a model's privacy `subject:`, are never on a page,
  /// in its head or structured data, in static output or in the sitemap,
  /// except for a viewer the model's `viewSensitive` policy admits. A record
  /// the model's `view` policy refuses has no page: it answers 404, exactly
  /// as a record that does not exist.
  ///
  /// Models that stand for accounts and credentials -- a `User`, a
  /// `Session`, an `ApiToken`, an `AuditLog`, a row that is its own privacy
  /// subject -- and tenant-scoped models get no page unless they ask for one
  /// with `generatePublicPages: true`.
  ///
  /// The field-scoped constructors carry the same default so no annotation
  /// states a second one; a field's value is never read.
  final bool generatePublicPages;

  /// Supplies the path values static generation should render for this
  /// model's parameterized route, when the default enumeration is not what is
  /// wanted.
  ///
  /// Static generation can enumerate `/about` on its own but not
  /// `/products/:slug`: nothing tells it which slugs exist. With
  /// [generatePublicPages] the values come from the model's published
  /// records; this replaces that with an explicit resolver — a subset, an
  /// ordering, or paths drawn from somewhere the model does not know about.
  ///
  /// The route is the model's own, so it is never written out as a string.
  /// A route repeated in an annotation drifts silently the moment the page
  /// file moves, which is the failure file-based routing exists to prevent.
  final DVPublicPathsResolver? publicPathsResolver;

  /// Field-scoped metadata, set only by the named field constructors below.
  final bool encrypted;
  final bool showInForms;
  final bool showInAdmin;

  /// The part this field plays in a generated model page, when one of the
  /// page-composition field constructors set it.
  final DVModelPageRole? pageRole;

  /// Where this field sits among a generated page's remaining fields, set by
  /// `@DVModel.pageOrder(n)`. Lower comes first.
  final int? pageOrderIndex;

  /// The schema.org type this model's public page is, such as `Product`,
  /// `Article` or `Person`.
  ///
  /// Null means `Thing`, which says a page is about something and nothing
  /// more. It is declared rather than guessed from the model's name: a
  /// `Person` labelled a `Product` because it is called `Customer` is worse
  /// than the honest general type, and search engines act on the label.
  final String? schemaType;

  /// The favicon this model's generated pages wear, or null for the
  /// application's.
  ///
  /// A path the application serves. `dartvel build web` treats it as a
  /// source rather than as the file to link: it resizes and re-encodes the
  /// image and names the result after a hash of its bytes, so a page does not
  /// download a press shot to fill a 32-pixel square and the icon can be
  /// cached forever. A value naming something the build cannot read -- a CDN
  /// URL, an SVG -- is used exactly as written.
  ///
  /// Still not a derivative of the featured image, which the specification
  /// also asks for. That image is a URL a row supplied, so deriving from it
  /// means fetching an arbitrary host mid-build or mid-request; both cost
  /// more than the icon is worth.
  final String? favicon;

  /// Whether this model's rows belong to a tenant.
  ///
  /// On the shared-database strategy -- one database, one schema, rows
  /// scoped by a tenant column -- a query with no tenant predicate returns
  /// every tenant's rows. Nothing in the generated model had one, so the
  /// isolation the strategy is named for did not exist.
  ///
  /// Opt in per model rather than on for everything: a single-tenant
  /// application should not carry a column it never reads, and a model that
  /// is deliberately shared across tenants -- a currency table, a country
  /// list -- would be broken by a predicate it never asked for.
  final bool tenantScoped;

  /// Whether this field holds a 3D asset, set by `@DVModel.model3dField()`.
  final bool isModel3dField;

  /// Whether a 3D field asks for a still of its model, for where 3D cannot
  /// render.
  final bool model3dPoster;

  /// A 3D field's upload ceiling, in mebibytes.
  final int? model3dMaxSizeMb;

  /// A 3D field's triangle budget.
  final int? model3dMaxTriangles;

  /// How this model's rows reach the person they belong to, for erasure and
  /// export: `DVSubject.self` when a row is the person, `#field` for the
  /// field holding the person's id, or `DVSubject.through('column', parent:
  /// 'Model')` for a row that belongs to them through another model's row.
  ///
  /// Null for a model holding nobody's data. A model with a sensitive field
  /// and no subject path fails the build (`DV-PRIVACY-001`): an erasure could
  /// not reach it, and would report success anyway.
  final Object? subject;

  /// How long this model's rows are kept: `DVRetention.days(90)`, then
  /// deleted or anonymized, or `DVRetention.indefinite`, deliberately.
  ///
  /// A model with personal data and no retention is kept indefinitely by
  /// nobody's decision, which the build warns about (`DV-PRIVACY-002`).
  final DVRetention? retain;

  /// Set by `@DVModel.retain(years:, because:)` on a field a law requires to
  /// be kept: an erasure keeps the row, anonymizes its personal fields, and
  /// names [retainBecause] as the reason.
  final int? retainYears;
  final String? retainBecause;

  /// What an erasure does to a sensitive field, set by
  /// `@DVModel.sensitiveField(onErase: ...)`.
  final DVErase onErase;

  /// The model's change log: `DVHistory(keep: Duration(days: 365))`, or null
  /// for none.
  ///
  /// Every generated model already writes at the version it read; this adds
  /// the log of who changed what, written with each change and read back
  /// with `model.history()`. Sensitive fields are recorded as changed and
  /// never as values, and an erasure removes the log with the row.
  final DVHistory? history;

  /// Whether every write to this model is recorded as a change.
  ///
  /// On, each insert, update, delete, soft delete and restore lands in the
  /// process's configured [DVCapture] log with the record's version, the
  /// tenant and the transaction it committed in, and a consumer copies them
  /// onward in order. Sensitive fields are named in the change and never
  /// carried in it. Off, nothing is recorded.
  ///
  /// Nothing else changes: a captured model is read and written like any
  /// other, and saving a record is what records the change. A process that
  /// has configured no log writes normally and captures nothing.
  final bool capture;

  /// Whether this model has a semantic index. On, its searchable fields are
  /// embedded when a record is saved and [semanticSearch] answers from the
  /// vectors; the embedder and the vector store are configured once with
  /// the model's own `useSemanticSearch`. Off, nothing is embedded.
  ///
  /// The id, the fields, the loader, the sensitive set and the JSON come
  /// from the model, because an index that restates them drifts from it.
  final bool semantic;

  /// How a write made on a device that could not reach the server is
  /// resolved when it is replayed. Set, the model gets a local store and a
  /// server side built from the table, key and columns it already declares,
  /// so neither is written out a second time.
  ///
  /// `DVConflict.ask` cannot work offline -- there is nobody to ask -- and
  /// stops the build rather than failing on a device.
  final DVConflict? offline;

  /// Whether every write is checked against the version it read: on by
  /// default, because a lost update is silent. `version: false` is for
  /// append-only data whose writes never contend, and says so here.
  final bool version;

  /// Whether deleting marks the row rather than removing it. Queries skip a
  /// marked row, `Model.withDeleted` reads it, and `Model.restore(id)` brings
  /// it back.
  final bool softDelete;

  const DVModel({
    this.searchable = false,
    this.billable = false,
    this.nativePrice,
    this.pageDataMode = DVModelPageDataMode.auto,
    this.generatePublicPages = true,
    this.publicPathsResolver,
    this.schemaType,
    this.favicon,
    this.tenantScoped = false,
    this.subject,
    this.retain,
    this.history,
    this.capture = false,
    this.semantic = false,
    this.offline,
    this.version = true,
    this.softDelete = false,
  })  : encrypted = false,
        retainYears = null,
        retainBecause = null,
        onErase = DVErase.delete,
        showInForms = false,
        showInAdmin = false,
        pageRole = null,
        pageOrderIndex = null,
        isModel3dField = false,
        model3dPoster = false,
        model3dMaxSizeMb = null,
        model3dMaxTriangles = null;

  /// Marks a model field as sensitive: `@DVModel.sensitiveField()`.
  ///
  /// By default a sensitive field is excluded from public serialization
  /// (`toPublicJson`), generated model pages/tables/cards, search indexing,
  /// analytics, traces, and logs, and requires explicit policy authorization
  /// before it can be sent to clients. Use [showInForms]/[showInAdmin] to opt
  /// specific generated UI surfaces back in.
  ///
  /// [encrypted] seals the value with AES-256-GCM before it reaches the
  /// database and opens it on the way back, under the keyring in
  /// `DARTVEL_FIELD_KEYS` — a server-process environment variable, because
  /// generated model code compiles into the application bundle too and a key
  /// held anywhere the generator writes would ship to every visitor. Only
  /// `String` and `String?` can carry it, it cannot go on the field
  /// generated lookups use, and with no keyring configured the field raises
  /// rather than falling back to plaintext — so a model carrying one is
  /// persisted by the server, and saving or reading it against a device's own
  /// database gets that refusal. See [DVFieldCipher].
  const DVModel.sensitiveField({
    this.encrypted = false,
    this.showInForms = false,
    this.showInAdmin = false,
    this.onErase = DVErase.delete,
  })  : searchable = false,
        subject = null,
        history = null,
        capture = false,
        semantic = false,
        offline = null,
        version = true,
        softDelete = false,
        retain = null,
        retainYears = null,
        retainBecause = null,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = true,
        publicPathsResolver = null,
        pageRole = null,
        pageOrderIndex = null,
        schemaType = null,
        favicon = null,
        tenantScoped = false,
        isModel3dField = false,
        model3dPoster = false,
        model3dMaxSizeMb = null,
        model3dMaxTriangles = null;

  /// Marks a model field for generated search indexing:
  /// `@DVModel.searchableField()`.
  const DVModel.searchableField()
      : searchable = true,
        subject = null,
        history = null,
        capture = false,
        semantic = false,
        offline = null,
        version = true,
        softDelete = false,
        retain = null,
        retainYears = null,
        retainBecause = null,
        onErase = DVErase.delete,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = true,
        publicPathsResolver = null,
        encrypted = false,
        showInForms = false,
        showInAdmin = false,
        pageRole = null,
        pageOrderIndex = null,
        schemaType = null,
        favicon = null,
        tenantScoped = false,
        isModel3dField = false,
        model3dPoster = false,
        model3dMaxSizeMb = null,
        model3dMaxTriangles = null;

  /// Marks the field a generated model page uses as its featured image:
  /// `@DVModel.featuredImage()`.
  ///
  /// Without it the page takes the first public image/media field. Only one
  /// field per model may carry it.
  const DVModel.featuredImage() : this._page(DVModelPageRole.featuredImage);

  /// Marks the field a generated model page uses as its title:
  /// `@DVModel.pageTitle()`.
  ///
  /// Without it the page takes the first public `String` field named `title`
  /// or `name`, else the first public `String` field.
  const DVModel.pageTitle() : this._page(DVModelPageRole.pageTitle);

  /// Marks the field a generated model page renders as its main text content:
  /// `@DVModel.mainContent()`.
  ///
  /// Without it the page picks the longest non-empty text field at render
  /// time, ignoring the title and any hidden or sensitive field.
  const DVModel.mainContent() : this._page(DVModelPageRole.mainContent);

  /// Excludes the field from generated model pages:
  /// `@DVModel.hideFromPage()`.
  ///
  /// The field stays part of the model, its serialization, and its forms —
  /// this only removes it from the generated page. Use
  /// `@DVModel.sensitiveField()` for data that must not reach clients at all.
  const DVModel.hideFromPage() : this._page(DVModelPageRole.hidden);

  /// Sets where the field appears among a generated page's remaining fields:
  /// `@DVModel.pageOrder(3)`.
  ///
  /// Lower values come first; unannotated fields keep declaration order after
  /// every ordered one.
  const DVModel.pageOrder(int order) : this._page(null, order);

  /// Marks a field as a 3D asset: `@DVModel.model3dField()`.
  ///
  /// The field holds a `DVSceneAsset`, the verified reference
  /// `DVModel3DFieldPolicy.accept` makes from an upload. The generated model
  /// carries the limits as `Model.model3dFields`, `model.viewer3D()` renders
  /// the field in an orbit viewer, and the generated page renders that
  /// viewer where the field appears. [maxSizeMb] and [maxTriangles] bound an
  /// upload; [poster] asks for a still of the model for where 3D cannot
  /// render.
  const DVModel.model3dField({
    bool poster = true,
    int? maxSizeMb,
    int? maxTriangles,
  })  : isModel3dField = true,
        subject = null,
        history = null,
        capture = false,
        semantic = false,
        offline = null,
        version = true,
        softDelete = false,
        retain = null,
        retainYears = null,
        retainBecause = null,
        onErase = DVErase.delete,
        model3dPoster = poster,
        model3dMaxSizeMb = maxSizeMb,
        model3dMaxTriangles = maxTriangles,
        searchable = false,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = true,
        publicPathsResolver = null,
        encrypted = false,
        showInForms = false,
        showInAdmin = false,
        pageRole = null,
        pageOrderIndex = null,
        schemaType = null,
        favicon = null,
        tenantScoped = false;

  /// Marks the field whose row a law requires to be kept:
  /// `@DVModel.retain(years: 7, because: 'tax law')`.
  ///
  /// An erasure that reaches the row keeps it for [years], replaces its
  /// personal fields, and reports the row with [because] -- which exists so
  /// the answer to "why do you still have my invoice" is in the codebase
  /// rather than in somebody's memory.
  const DVModel.retain({required int years, required String because})
      : retainYears = years,
        retainBecause = because,
        subject = null,
        history = null,
        capture = false,
        semantic = false,
        offline = null,
        version = true,
        softDelete = false,
        retain = null,
        onErase = DVErase.delete,
        searchable = false,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = true,
        publicPathsResolver = null,
        encrypted = false,
        showInForms = false,
        showInAdmin = false,
        pageRole = null,
        pageOrderIndex = null,
        schemaType = null,
        favicon = null,
        tenantScoped = false,
        isModel3dField = false,
        model3dPoster = false,
        model3dMaxSizeMb = null,
        model3dMaxTriangles = null;

  const DVModel._page(this.pageRole, [this.pageOrderIndex])
      : searchable = false,
        subject = null,
        history = null,
        capture = false,
        semantic = false,
        offline = null,
        version = true,
        softDelete = false,
        retain = null,
        retainYears = null,
        retainBecause = null,
        onErase = DVErase.delete,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = true,
        publicPathsResolver = null,
        encrypted = false,
        showInForms = false,
        showInAdmin = false,
        schemaType = null,
        favicon = null,
        tenantScoped = false,
        isModel3dField = false,
        model3dPoster = false,
        model3dMaxSizeMb = null,
        model3dMaxTriangles = null;
}

/// Marks a model property for generated search indexing.
@Deprecated('Use @DVModel.searchableField() instead. '
    'Model-scoped annotations live under the DVModel parent.')
class DVSearchable {
  const DVSearchable();
}

/// Marks a model field as sensitive.
///
/// See [DVModel.sensitiveField] for the canonical form and full behaviour.
@Deprecated('Use @DVModel.sensitiveField() instead. '
    'Model-scoped annotations live under the DVModel parent.')
class DVSensitiveModelField {
  final bool encrypted;
  final bool showInForms;
  final bool showInAdmin;

  const DVSensitiveModelField({
    this.encrypted = false,
    this.showInForms = false,
    this.showInAdmin = false,
  });
}

/// Annotation for a Dartvel Backend Function
class DVBackendFunction {
  final String? policy;

  /// The second factor the caller's session must have presented, or null for
  /// none: `DVMfa.required` for one at some point in the session,
  /// `DVMfa.recent(Duration(minutes: 15))` for one within the window.
  ///
  /// Refused with 401 and RFC 9470's `insufficient_user_authentication`, so
  /// the client asks for a code and retries rather than signing out.
  final DVMfa? mfa;

  /// The exact path the function is served at, outside the API base path,
  /// such as `'/payments/webhook'`. Mutually exclusive with [rawPathSuffix].
  ///
  /// A string literal of plain segments: the build reads it from source and
  /// refuses anything else, path parameters included.
  final String? rawPath;

  /// Appended to the generated path: `'/public'` on
  /// `functions/catalog.get.dart` serves `<apiBasePath>/catalog/public`.
  /// Mutually exclusive with [rawPath].
  final String? rawPathSuffix;

  const DVBackendFunction({
    this.policy,
    this.mfa,
    this.rawPath,
    this.rawPathSuffix,
  }) : assert(rawPath == null || rawPathSuffix == null,
            'rawPath and rawPathSuffix are mutually exclusive');
}

/// Annotation for a Backend Cron Job
class DVBackendCron {
  final String cron;

  /// Whether the occurrences missed while the process was down are run when
  /// it comes back.
  ///
  /// Null is not false: it is this schedule saying nothing, which lets the
  /// application's own blanket setting decide. A schedule that writes false
  /// has decided for itself and wins over that -- a nightly digest sent four
  /// times the morning a server comes back is worse than one digest missed.
  /// True is right for work that writes a row per period, where a missing
  /// period is a hole in the data.
  final bool? catchUp;

  const DVBackendCron(this.cron, {this.catchUp});
}

/// Annotation for a Client Cron Job
class DVClientCron {
  final String cron;

  /// See [DVBackendCron.catchUp]. A phone is closed far more often than a
  /// server is down, so the blanket default matters more here.
  final bool? catchUp;

  const DVClientCron(this.cron, {this.catchUp});
}

/// Annotation for a durable background job.
class DVJob {
  final String? queue;
  final int priority;
  final int maxAttempts;
  final int backoffSeconds;

  /// Whether this annotation marks a handler function rather than a payload
  /// class. Set only by [DVJob.handler].
  final bool isHandler;

  const DVJob({
    this.queue,
    this.priority = 0,
    this.maxAttempts = 3,
    this.backoffSeconds = 30,
  }) : isHandler = false;

  /// Marks the function that runs a job: `@DVJob.handler()`.
  ///
  /// The function takes the generated payload type as its only parameter. Job
  /// metadata is grouped under the job annotation rather than a standalone
  /// name, which also leaves the [DVJobHandler] typedef — the runtime handler
  /// function type — free to keep meaning what it means.
  const DVJob.handler()
      : queue = null,
        priority = 0,
        maxAttempts = 3,
        backoffSeconds = 30,
        isHandler = true;
}

/// Annotation for backend function/page middleware.
class DVMiddleware {
  final List<String> names;

  const DVMiddleware(this.names);
}

class DVMiddlewareKey {
  final String name;

  const DVMiddlewareKey(this.name);

  @override
  String toString() => name;
}

/// Typed annotation for page, layout, model, storage, and backend middleware.
class DVUseMiddleware {
  final List<DVMiddlewareKey> middleware;

  const DVUseMiddleware(this.middleware);
}

class DVMiddlewares {
  static const auth = DVMiddlewareKey('auth');
  static const policy = DVMiddlewareKey('policy');
  static const tenant = DVMiddlewareKey('tenant');
  static const cors = DVMiddlewareKey('cors');
  static const csrf = DVMiddlewareKey('csrf');
  static const rateLimit = DVMiddlewareKey('rateLimit');
  static const rateLimitCheckout = DVMiddlewareKey('rateLimitCheckout');
  static const requestLogging = DVMiddlewareKey('requestLogging');
  static const tracing = DVMiddlewareKey('tracing');
  static const securityHeaders = DVMiddlewareKey('securityHeaders');
  static const csp = DVMiddlewareKey('csp');
  static const bodyLimit = DVMiddlewareKey('bodyLimit');
  static const uploadLimit = DVMiddlewareKey('uploadLimit');
  static const compression = DVMiddlewareKey('compression');
  static const locale = DVMiddlewareKey('locale');
  static const idempotency = DVMiddlewareKey('idempotency');
  static const cacheTags = DVMiddlewareKey('cacheTags');
  static const featureFlags = DVMiddlewareKey('featureFlags');
  static const maintenance = DVMiddlewareKey('maintenance');
}

/// Annotation for model/resource authorization policies.
class DVPolicy {
  final Type resource;

  const DVPolicy(this.resource);
}

class DVPolicyAction {
  static const viewAny = 'viewAny';
  static const view = 'view';

  /// Whether the caller may see a record's `@DVModel.sensitiveField()`s, and
  /// the fields naming its privacy subject, where they would otherwise be
  /// left out -- on the record's generated page. Separate from [view]
  /// because a policy that lets anybody read an article must not, by that
  /// alone, let anybody read its editor's notes. Nothing registered refuses.
  static const viewSensitive = 'viewSensitive';
  static const create = 'create';
  static const update = 'update';
  static const delete = 'delete';
  static const restore = 'restore';
  static const forceDelete = 'forceDelete';
  static const export = 'export';
  static const impersonate = 'impersonate';
}

class DVPolicies {
  static const viewAdmin = 'viewAdmin';
  static const refund = 'refund';
  static const manageBilling = 'manageBilling';
  static const exportData = 'exportData';
  static const impersonate = 'impersonate';
}

/// Annotation for supported home-screen and lock-screen widgets.
///
/// "Home widgets act like `DVPage` and support the same shell properties," so
/// these are [DVPage]'s, with the same names and the same defaults: the page
/// Dartvel generates at `/widgets/<id>` is a page, and a property that means
/// one thing on a page and another here would be worse than not having it.
///
/// [title] is the one that also leaves the application. A launcher's widget
/// picker and WidgetKit's gallery both ask for a name, and without a title
/// they are given the identifier -- `step-counter`, a route segment, sitting
/// among the names of somebody's applications.
class DVHomeWidget {
  final String? title;
  final DVPageShellMode shell;
  final bool scaffold;
  final bool showAppBar;
  final bool selectable;
  final bool safeArea;
  final bool centerTitle;
  final bool extendBody;
  final bool resizeToAvoidBottomInset;
  final int? backgroundColor;
  final int? appBarBackgroundColor;

  const DVHomeWidget({
    this.title,
    this.shell = DVPageShellMode.adaptive,
    this.scaffold = true,
    this.showAppBar = false,
    this.selectable = true,
    this.safeArea = true,
    this.centerTitle = false,
    this.extendBody = false,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
    this.appBarBackgroundColor,
  });
}

/// Annotation for exposing a function as an AI-callable tool.
class DVAITool {
  final String? description;
  const DVAITool({this.description});
}

/// Annotation for excluding a backend function from AI tool auto-exposure.
class DVAIHidden {
  const DVAIHidden();
}

/// CSRF helper surface used by generated backend, form, model, DB, and realtime flows.
class DVCSRF {
  const DVCSRF();

  static const fieldName = '_dv_csrf';
  static const headerName = 'x-dartvel-csrf-token';

  String token() {
    final random = math.Random.secure();
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
      List<int>.generate(
        32,
        (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ),
    );
  }

  bool validate(String? token, {String? bodyToken}) {
    if (token == null || !_isValidToken(token)) return false;
    if (bodyToken != null && bodyToken != token) return false;
    return true;
  }

  bool validateRequest({
    required String method,
    required String? headerToken,
    String? bodyToken,
  }) {
    if (!requiresValidation(method)) return true;
    return validate(headerToken, bodyToken: bodyToken);
  }

  bool requiresValidation(String method) {
    final normalized = method.toUpperCase();
    return normalized != 'GET' &&
        normalized != 'HEAD' &&
        normalized != 'OPTIONS';
  }

  bool _isValidToken(String token) =>
      token.length >= 32 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token);
}

class DVFormControls {
  final Object? model;
  final void Function()? _onSubmit;
  final void Function()? _onReset;

  const DVFormControls(
    this.model, {
    void Function()? onSubmit,
    void Function()? onReset,
  })  : _onSubmit = onSubmit,
        _onReset = onReset;

  void submit() {
    _onSubmit?.call();
  }

  void reset() {
    _onReset?.call();
  }
}

typedef DVFormControlsFactory = DVFormControls Function(
  Object? model, {
  void Function()? onSubmit,
  void Function()? onReset,
});
final Map<Type, DVFormControlsFactory> formControlsFactories = {};

typedef DVModelFactory<T> = T Function();
typedef DVModelSerializer<T> = Map<String, Object?> Function(T model);
typedef DVModelDeserializer<T> = T Function(Map<String, Object?> json);

final Map<Type, Object? Function()> dvModelFactories = {};
final Map<Type, Map<String, Object?> Function(Object?)> dvModelSerializers = {};
final Map<Type, Object? Function(Map<String, Object?>)> dvModelDeserializers =
    {};

void registerFormControlsFactory<T>(DVFormControlsFactory factory) {
  formControlsFactories[T] = factory;
}

void registerDVModelFactory<T>(DVModelFactory<T> factory) {
  dvModelFactories[T] = () => factory();
}

T? createDVModel<T>() {
  final factory = dvModelFactories[T];
  if (factory == null) return null;
  return factory() as T;
}

void registerDVModelSerializer<T>(DVModelSerializer<T> serializer) {
  dvModelSerializers[T] = (Object? model) => serializer(model as T);
}

Map<String, Object?>? serializeDVModel<T>(T model) {
  final serializer = dvModelSerializers[T];
  if (serializer == null) return null;
  return serializer(model);
}

/// Registers how a [T] is rebuilt from a JSON map.
///
/// Serializing alone is one-way: a form can show a model's fields but cannot
/// hand back an edited one without this.
void registerDVModelDeserializer<T>(DVModelDeserializer<T> deserializer) {
  dvModelDeserializers[T] = (Map<String, Object?> json) => deserializer(json);
}

/// Rebuilds a [T] from [json], or null when no deserializer is registered.
T? deserializeDVModel<T>(Map<String, Object?> json) {
  final deserializer = dvModelDeserializers[T];
  if (deserializer == null) return null;
  return deserializer(json) as T;
}

/// How an edited [T] keeps the version its record was read at.
///
/// A generated model remembers the record it was loaded from beside itself,
/// and saves against that version. A form rebuilds the model it returns from
/// JSON, which remembers nothing, so without this every edit made in a form
/// would reach save as a model nobody read -- refused as a write with no read
/// version (`DV-HISTORY-001`).
typedef DVModelReadCarrier<T> = void Function(T read, T edited);

final Map<Type, void Function(Object? read, Object? edited)>
    dvModelReadCarriers = {};

/// Registers how an edit of a [T] inherits the read of the [T] it edits.
void registerDVModelReadCarrier<T>(DVModelReadCarrier<T> carry) {
  dvModelReadCarriers[T] =
      (Object? read, Object? edited) => carry(read as T, edited as T);
}

/// Makes [edited] carry the version [read] was loaded at, when [T] registered
/// a carrier; otherwise does nothing.
void carryDVModelRead<T>(T read, T edited) {
  if (identical(read, edited)) return;
  dvModelReadCarriers[T]?.call(read, edited);
}
