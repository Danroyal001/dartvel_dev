import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dartvel_core/dartvel.dart';

import 'browser.dart';
import 'config.dart';
import 'consent.dart';
import 'events.dart';
import 'measurement_protocol.dart';

/// How a device's event reaches the application's backend.
typedef GoogleAnalyticsRelay = Future<void> Function(
    Map<String, Object?> event);

/// The module's behaviour, in whichever environment it was compiled for.
///
/// One instance per process, behind `DV.Modules.googleAnalytics`.
/// Everything it depends on that differs by environment or cannot run in a
/// test -- the browser, the route to the backend, consent, the clock -- is
/// handed in, so the rules are the same code everywhere and are tested as
/// such.
///
/// Nothing here throws to its caller: a page or a button must not fail
/// because a measuring script or endpoint did.
final class GoogleAnalyticsRuntime {
  GoogleAnalyticsRuntime({
    this.config = const GoogleAnalyticsConfig(),
    GoogleAnalyticsBrowser? browser,
    GoogleAnalyticsRelay? relay,
    bool Function(String category)? consentGranted,
    DVModuleEnvironment? environment,
    DateTime Function()? clock,
    String Function()? newClientId,
    this.scriptUrl = defaultScriptUrl,
    this.moduleId = 'googleAnalytics',
  })  : browser = browser ?? createGoogleAnalyticsBrowser(),
        // ignore: prefer_initializing_formals
        _relay = relay,
        _consentGranted = consentGranted ?? dvGoogleAnalyticsConsentGranted,
        environment = environment ?? DVModuleEnvironment.current,
        _clock = clock ?? DateTime.now,
        // ignore: prefer_initializing_formals
        _newClientId = newClientId;

  /// The runtime behind `DV.Modules.googleAnalytics`.
  static GoogleAnalyticsRuntime instance = GoogleAnalyticsRuntime();

  /// Where the script that defines `gtag` is served from when the module is
  /// mounted the usual way.
  static const String defaultScriptUrl =
      'assets/packages/dartvel_google_analytics/assets/google_analytics.js';

  /// The topic a store module publishes a confirmed purchase to.
  static const String purchaseTopic = 'commerce.purchase';

  /// The topic a checkout publishes to collect what each analytics module
  /// knows about the visitor.
  static const String contextTopic = 'analytics.context';

  GoogleAnalyticsConfig config;
  final GoogleAnalyticsBrowser browser;
  final DVModuleEnvironment environment;
  String scriptUrl;
  String moduleId;

  final GoogleAnalyticsRelay? _relay;
  final bool Function(String category) _consentGranted;
  final DateTime Function() _clock;
  final String Function()? _newClientId;

  bool _loaded = false;
  bool _denied = false;
  DVPageView? _page;
  bool _pageSent = false;

  /// Who a device's events are reported for. See [identify].
  String? _clientId;
  String? _userId;
  String? _sessionId;

  bool get _isBackend => environment == DVModuleEnvironment.backend;

  bool get _allowed =>
      config.isConfigured && _consentGranted(config.consentCategory);

  /// Names the visitor.
  ///
  /// [clientId] is for a device, which has no tag to give it one: an id the
  /// application keeps for the install, so the same person is one visitor
  /// across launches. Without it each launch is a new visitor. [userId] is
  /// the signed-in person, which Google Analytics uses to join their
  /// devices; it is sent with a device's events and with the server's.
  void identify({String? clientId, String? userId}) {
    if (clientId != null) _clientId = clientId;
    _userId = userId;
  }

  String get _deviceClientId => _clientId ??= (_newClientId ?? _randomClientId)();

  String get _deviceSessionId =>
      _sessionId ??= '${_clock().toUtc().millisecondsSinceEpoch ~/ 1000}';

  /// Two positive numbers joined by a period, the form Google recommends: a
  /// random one and the time it was made.
  String _randomClientId() =>
      '${Random.secure().nextInt(0x7fffffff) + 1}.'
      '${_clock().toUtc().millisecondsSinceEpoch ~/ 1000}';

  /// A page was shown. Sent as a `page_view` if consent and the configured
  /// page view mode allow, and remembered if consent does not yet.
  Future<void> pageShown(DVPageView view) async {
    if (_isBackend || config.excludes(view.location.path)) return;
    if (_page?.location == view.location) return;
    _page = view;
    _pageSent = false;
    await _sendPage();
  }

  Future<void> _sendPage() async {
    final DVPageView? page = _page;
    if (page == null || _pageSent || !_allowed) return;
    _pageSent = true;
    switch (config.pageViews) {
      case GoogleAnalyticsPageViews.off:
        return;
      case GoogleAnalyticsPageViews.automatic:
        // Google's tag sends its own. On a device there is no tag.
        if (browser.available) {
          _guard(_ensureLoaded);
          return;
        }
      case GoogleAnalyticsPageViews.manual:
        break;
    }
    final String? location = browser.available
        ? _guardedValue(() => browser.pageUrl)
        : _deviceLocation(page.location);
    await track(GoogleAnalyticsEvent.pageView(
      location: location,
      title: page.title ?? _guardedValue(() => browser.pageTitle),
    ));
  }

  /// A device's page as a full URL, which `page_location` has to be.
  String _deviceLocation(Uri location) {
    final String origin =
        (config.origin ?? 'app://app').replaceFirst(RegExp(r'/+$'), '');
    final String path =
        location.path.startsWith('/') ? location.path : '/${location.path}';
    return '$origin$path${location.hasQuery ? '?${location.query}' : ''}';
  }

  /// The visitor's consent changed, or was read for the first time.
  Future<void> consentChanged() async {
    if (_isBackend || !config.isConfigured) return;
    final bool granted = _consentGranted(config.consentCategory);
    if (!granted) {
      if (_loaded && !_denied) {
        _denied = true;
        _guard(() => browser.consent(granted: false));
      }
      return;
    }
    if (_denied) {
      _denied = false;
      _guard(() => browser.consent(granted: true));
    }
    await _sendPage();
  }

  /// Reports [event].
  ///
  /// In a browser: through Google's tag, and only through it. On a device:
  /// through the application's backend to the Measurement Protocol. On the
  /// backend: to the Measurement Protocol directly, for the visitor
  /// [clientId] names -- without one there is nobody to report it for and
  /// it is dropped.
  ///
  /// Dropped, silently, when the module has no measurement id or the
  /// visitor has not granted the configured consent category.
  Future<void> track(
    GoogleAnalyticsEvent event, {
    String? clientId,
    String? userId,
    String? sessionId,
  }) async {
    if (!config.isConfigured) return;
    if (_isBackend) {
      if (clientId == null || clientId.trim().isEmpty) {
        const DVLog().warn(
          'Google Analytics: ${event.name} was not sent from the backend: '
          'it needs the client id of the visitor it is about.',
          tag: 'googleAnalytics',
        );
        return;
      }
      await _send(
        clientId: clientId,
        userId: userId,
        sessionId: sessionId,
        events: <GoogleAnalyticsEvent>[event],
      );
      return;
    }
    if (!_allowed) return;

    if (browser.available) {
      _guard(() {
        _ensureLoaded();
        browser.event(event.name, event.params);
      });
      return;
    }
    await _relayEvent(<String, Object?>{
      'name': event.name,
      if (event.params.isNotEmpty) 'params': event.params,
      'client_id': clientId ?? _deviceClientId,
      'session_id': sessionId ?? _deviceSessionId,
      'user_id': ?(userId ?? _userId),
    });
  }

  /// Adds what Google's tag knows about this visitor to [context], for a
  /// checkout to keep with the order: the purchase is reported later, from
  /// the server, when the payment is confirmed.
  ///
  /// Nothing is added unless consent allows, and that absence is what tells
  /// the server not to report the purchase to Google.
  void contributeContext(Object? context) {
    if (_isBackend || context is! Map || !_allowed) return;
    final String? clientId = browser.available
        ? _guardedValue(() => browser.clientId)
        : _deviceClientId;
    if (clientId == null) return;
    context[moduleId] = <String, Object?>{
      'client_id': clientId,
      'session_id': ?(browser.available
          ? _guardedValue(() => browser.sessionId)
          : _deviceSessionId),
      'user_id': ?_userId,
    };
  }

  /// A purchase a store module confirmed: the payload of [purchaseTopic].
  ///
  /// Sent from the backend, as the buyer's, with the client and session ids
  /// their checkout carried. Only from the backend: Google Analytics has no
  /// way to count a purchase reported twice as one, so the buyer's browser
  /// does not report it as well. Only for a buyer whose checkout carried
  /// this module's context, which is to say one who had consented.
  Future<void> purchaseConfirmed(Object? payload) async {
    if (!_isBackend || !config.isConfigured || payload is! Map) return;
    final Object? transaction = payload['transaction_id'];
    final Object? currency = payload['currency'];
    final Object? value = payload['value'] ?? payload['total'];
    if (transaction == null || currency is! String || value is! num) return;
    final Object? context = payload['context'];
    final Object? mine = context is Map ? context[moduleId] : null;
    if (mine is! Map || mine['client_id'] is! String) return;

    final GoogleAnalyticsEvent event;
    try {
      event = GoogleAnalyticsEvent('purchase', params: <String, Object?>{
        'transaction_id': '$transaction',
        'value': value,
        'currency': currency,
        if (payload['tax'] is num) 'tax': payload['tax'],
        if (payload['shipping'] is num) 'shipping': payload['shipping'],
        if (payload['coupon'] is String) 'coupon': payload['coupon'],
        'items': <Object?>[
          if (payload['items'] is List)
            for (final Object? item in payload['items'] as List<Object?>)
              if (item is Map)
                <String, Object?>{
                  if (item['item_id'] != null) 'item_id': '${item['item_id']}',
                  if (item['item_name'] != null)
                    'item_name': '${item['item_name']}',
                  if (item['price'] is num) 'price': item['price'],
                  if (item['quantity'] is int) 'quantity': item['quantity'],
                },
        ],
      });
    } on ArgumentError {
      return;
    }
    await _send(
      clientId: mine['client_id'] as String,
      userId: mine['user_id'] is String ? mine['user_id'] as String : null,
      sessionId:
          mine['session_id'] is String ? mine['session_id'] as String : null,
      occurredAt: DateTime.tryParse('${payload['paid_at']}'),
      events: <GoogleAnalyticsEvent>[event],
    );
  }

  /// The backend's half of a device's event: checks that [arguments] is an
  /// event Google Analytics would accept and nothing else, and sends it to
  /// the Measurement Protocol.
  ///
  /// The route is public, like the tag itself, so what it accepts is
  /// narrow. It answers `{sent: bool}` and, when not sent, a `reason` that
  /// never includes the API secret.
  Future<Map<String, Object?>> collect(Map<String, Object?> arguments) async {
    Map<String, Object?> refused(String reason) =>
        <String, Object?>{'sent': false, 'reason': reason};

    if (!config.isConfigured) return refused('no measurement id is configured');
    if (dvPrivacyOptOut) return refused('the visitor opted out');

    final Object? name = arguments['name'];
    final Object params = arguments['params'] ?? const <String, Object?>{};
    if (name is! String) return refused('not an event name');
    if (params is! Map) return refused('not event parameters');
    final Map<String, Object?> plain;
    try {
      final String encoded = jsonEncode(params);
      if (encoded.length > maxParamsLength) {
        return refused('too many event parameters');
      }
      plain = jsonDecode(encoded) as Map<String, Object?>;
    } on Object {
      return refused('not event parameters');
    }
    final String? problem = GoogleAnalyticsEvent.problemWith(name, plain);
    if (problem != null) return refused(problem);

    final Object? clientId = arguments['client_id'];
    if (clientId is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(clientId)) {
      return refused('not a client id');
    }
    final Object? sessionId = arguments['session_id'];
    if (sessionId != null &&
        (sessionId is! String || !RegExp(r'^\d{1,20}$').hasMatch(sessionId))) {
      return refused('not a session id');
    }
    final Object? userId = arguments['user_id'];
    if (userId != null && (userId is! String || userId.length > 256)) {
      return refused('not a user id');
    }

    final Request? request = DVModuleRpc.request;
    final GoogleAnalyticsResult result =
        await GoogleAnalyticsMeasurementProtocol(config, clock: _clock).send(
      clientId: clientId,
      userId: userId as String?,
      sessionId: sessionId as String?,
      ipOverride: request == null
          ? null
          : DVClientAddress.current.resolve(request)?.toString(),
      events: <GoogleAnalyticsEvent>[GoogleAnalyticsEvent(name, params: plain)],
    );
    return result.sent
        ? <String, Object?>{'sent': true}
        : refused(result.reason ?? 'not sent');
  }

  /// The most JSON a device's event parameters may come to, in characters.
  static const int maxParamsLength = 8192;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    browser.load(
      config.resolvedMeasurementId!,
      scriptUrl: scriptUrl,
      sendPageView: config.pageViews == GoogleAnalyticsPageViews.automatic,
    );
  }

  Future<void> _relayEvent(Map<String, Object?> event) async {
    final GoogleAnalyticsRelay relay = _relay ??
        (Map<String, Object?> e) =>
            DVModuleRpc.call(moduleId, 'collect', e).then((Object? _) {});
    try {
      await relay(event);
    } on Object {
      // The backend could not be reached. The event is lost rather than
      // kept: a queue of events on a device is a store of personal data.
    }
  }

  Future<void> _send({
    required String clientId,
    required List<GoogleAnalyticsEvent> events,
    String? userId,
    String? sessionId,
    DateTime? occurredAt,
  }) async {
    final GoogleAnalyticsResult result =
        await GoogleAnalyticsMeasurementProtocol(config, clock: _clock).send(
      clientId: clientId,
      userId: userId,
      sessionId: sessionId,
      occurredAt: occurredAt,
      events: events,
    );
    if (!result.sent) {
      const DVLog().warn(
        'Google Analytics: ${events.map((GoogleAnalyticsEvent e) => e.name).join(', ')} '
        'not sent: ${result.reason}',
        tag: 'googleAnalytics',
      );
    }
  }

  static void _guard(void Function() call) {
    try {
      call();
    } on Object {
      // The tag is somebody else's script; a page does not fail on it.
    }
  }

  static T? _guardedValue<T>(T? Function() read) {
    try {
      return read();
    } on Object {
      return null;
    }
  }
}
