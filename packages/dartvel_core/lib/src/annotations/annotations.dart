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

/// Annotation metadata for a Dartvel data model.
///
/// The generator adds serialization and model behavior to the annotated class;
/// this annotation intentionally does not provide a fake runtime model.
class DVModel {
  final bool searchable;
  final bool billable;
  final int? nativePrice;

  const DVModel({
    this.searchable = false,
    this.billable = false,
    this.nativePrice,
  });
}

/// Marks a model property for generated search indexing.
class DVSearchable {
  const DVSearchable();
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

  const DVJob({
    this.queue,
    this.priority = 0,
    this.maxAttempts = 3,
    this.backoffSeconds = 30,
  });
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

void registerFormControlsFactory<T>(DVFormControlsFactory factory) {
  formControlsFactories[T] = factory;
}
