import 'dart:math' as math;

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
  final String? policy;
  final DVPageShellMode shell;
  final bool scaffold;
  final bool showAppBar;

  /// Whether the page's text can be selected. True by default -- a page whose
  /// text cannot be copied is a defect rather than a style.
  final bool selectable;
  final bool safeArea;
  final bool centerTitle;
  final bool extendBody;
  final bool resizeToAvoidBottomInset;
  final int? backgroundColor;
  final int? appBarBackgroundColor;

  const DVPage({
    this.path,
    this.title,
    this.policy,
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
/// `@DVModel(generatePublicPages: true)` supplies these automatically from a
/// model's published records, which covers the common case without a resolver
/// at all. See [DVModel.publicPathsResolver].
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

  const DVModel({
    this.searchable = false,
    this.billable = false,
    this.nativePrice,
    this.pageDataMode = DVModelPageDataMode.auto,
    this.generatePublicPages = false,
    this.publicPathsResolver,
    this.schemaType,
  })  : encrypted = false,
        showInForms = false,
        showInAdmin = false,
        pageRole = null,
        pageOrderIndex = null;

  /// Marks a model field as sensitive: `@DVModel.sensitiveField()`.
  ///
  /// By default a sensitive field is excluded from public serialization
  /// (`toPublicJson`), generated model pages/tables/cards, search indexing,
  /// analytics, traces, and logs, and requires explicit policy authorization
  /// before it can be sent to clients. Set [encrypted] to request at-rest
  /// encryption, and use [showInForms]/[showInAdmin] to opt specific generated
  /// UI surfaces back in.
  const DVModel.sensitiveField({
    this.encrypted = false,
    this.showInForms = false,
    this.showInAdmin = false,
  })  : searchable = false,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = false,
        publicPathsResolver = null,
        pageRole = null,
        pageOrderIndex = null,
        schemaType = null;

  /// Marks a model field for generated search indexing:
  /// `@DVModel.searchableField()`.
  const DVModel.searchableField()
      : searchable = true,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = false,
        publicPathsResolver = null,
        encrypted = false,
        showInForms = false,
        showInAdmin = false,
        pageRole = null,
        pageOrderIndex = null,
        schemaType = null;

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

  const DVModel._page(this.pageRole, [this.pageOrderIndex])
      : searchable = false,
        billable = false,
        nativePrice = null,
        pageDataMode = DVModelPageDataMode.auto,
        generatePublicPages = false,
        publicPathsResolver = null,
        encrypted = false,
        showInForms = false,
        showInAdmin = false,
        schemaType = null;
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

  const DVBackendFunction({this.policy});
}

/// Annotation for a Backend Cron Job
class DVBackendCron {
  final String cron;
  const DVBackendCron(this.cron);
}

/// Annotation for a Client Cron Job
class DVClientCron {
  final String cron;
  const DVClientCron(this.cron);
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
class DVHomeWidget {
  const DVHomeWidget();
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
