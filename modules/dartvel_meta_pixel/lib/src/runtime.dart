import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dartvel_core/dartvel.dart';

import 'browser.dart';
import 'config.dart';
import 'consent.dart';
import 'conversions_api.dart';
import 'events.dart';

/// How a client's event reaches the application's backend.
typedef MetaPixelRelay = Future<void> Function(Map<String, Object?> event);

/// The module's behaviour, in whichever environment it was compiled for.
///
/// One instance per process, behind `DV.Modules.metaPixel`. Everything it
/// depends on that differs by environment or cannot run in a test -- the
/// browser, the route to the backend, consent, the clock -- is handed in, so
/// the rules are the same code everywhere and are tested as such.
///
/// Nothing here throws to its caller. A page view or a button tap must not
/// fail because an advertiser's script or endpoint did.
final class MetaPixelRuntime {
  MetaPixelRuntime({
    this.config = const MetaPixelConfig(),
    MetaPixelBrowser? browser,
    MetaPixelRelay? relay,
    bool Function(String category)? consentGranted,
    DVModuleEnvironment? environment,
    DateTime Function()? clock,
    String Function()? newEventId,
    this.scriptUrl = defaultScriptUrl,
    this.moduleId = 'metaPixel',
  })  : browser = browser ?? createMetaPixelBrowser(),
        // ignore: prefer_initializing_formals
        _relay = relay,
        _consentGranted = consentGranted ?? dvMetaPixelConsentGranted,
        environment = environment ?? DVModuleEnvironment.current,
        _clock = clock ?? DateTime.now,
        _newEventId = newEventId ?? _randomEventId;

  /// The runtime behind `DV.Modules.metaPixel`.
  static MetaPixelRuntime instance = MetaPixelRuntime();

  /// Where the pixel's script is served from when the module is mounted the
  /// usual way: Flutter serves a package's assets under `assets/packages/`.
  static const String defaultScriptUrl =
      'assets/packages/dartvel_meta_pixel/assets/meta_pixel.js';

  /// The topic a store module publishes a confirmed purchase to.
  static const String purchaseTopic = 'commerce.purchase';

  /// The topic a checkout publishes to collect what each analytics module
  /// knows about the visitor.
  static const String contextTopic = 'analytics.context';

  MetaPixelConfig config;
  final MetaPixelBrowser browser;
  final DVModuleEnvironment environment;
  String scriptUrl;

  /// The id the application mounted the module under, which the route a
  /// client's events are carried to is named after.
  String moduleId;

  final MetaPixelRelay? _relay;
  final bool Function(String category) _consentGranted;
  final DateTime Function() _clock;
  final String Function() _newEventId;

  bool _loaded = false;
  bool _revoked = false;

  /// The page on screen, and whether it has been sent as a view.
  DVPageView? _page;
  bool _pageSent = false;

  bool get _isBackend => environment == DVModuleEnvironment.backend;

  bool get _allowed =>
      config.isConfigured && _consentGranted(config.consentCategory);

  static String _randomEventId() {
    final Random random = Random.secure();
    final StringBuffer id = StringBuffer();
    for (int i = 0; i < 16; i++) {
      id.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return id.toString();
  }

  /// A page was shown. Sent as a `PageView` if consent allows, and
  /// remembered if it does not yet, so it can be sent when it does.
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
    await track(MetaPixelEvent.pageView());
  }

  /// The visitor's consent changed, or was read for the first time.
  Future<void> consentChanged() async {
    if (_isBackend || !config.isConfigured) return;
    final bool granted = _consentGranted(config.consentCategory);
    if (!granted) {
      if (_loaded && !_revoked) {
        _revoked = true;
        _guard(() => browser.consent(granted: false));
      }
      return;
    }
    if (_revoked) {
      _revoked = false;
      _guard(() => browser.consent(granted: true));
    }
    await _sendPage();
  }

  /// Reports [event].
  ///
  /// In a browser: through the pixel, and through the application's backend
  /// to the Conversions API with the same id, so Meta counts it once. On a
  /// device: through the backend. On the backend: to the Conversions API
  /// directly, where [user] and [sourceUrl] say who and where, since there
  /// is no page to read them from.
  ///
  /// Dropped, silently, when the module has no pixel id or the visitor has
  /// not granted the configured consent category.
  Future<void> track(
    MetaPixelEvent event, {
    String? eventId,
    MetaUserData? user,
    Uri? sourceUrl,
  }) async {
    if (!config.isConfigured) return;
    final String id = eventId ?? _newEventId();
    if (_isBackend) {
      await _send(MetaServerEvent(
        name: event.name,
        time: _clock(),
        eventId: id,
        sourceUrl: sourceUrl?.toString(),
        actionSource: sourceUrl == null ? 'other' : 'website',
        user: user ?? const MetaUserData(),
        customData: event.data,
      ));
      return;
    }
    if (!_allowed) return;

    if (browser.available) {
      _guard(() {
        _ensureLoaded();
        browser.track(event.name, event.data, eventId: id, custom: event.custom);
      });
    }
    if (!config.serverEvents) return;
    final String? url = sourceUrl?.toString() ?? _guardedValue(() => browser.pageUrl);
    await _relayEvent(<String, Object?>{
      'name': event.name,
      'custom': event.custom,
      'id': id,
      'time': _clock().toUtc().millisecondsSinceEpoch ~/ 1000,
      'url': ?url,
      if (event.data.isNotEmpty) 'data': event.data,
      'fbp': ?_guardedValue(() => browser.cookie('_fbp')),
      'fbc': ?_clickId(),
      'agent': ?_guardedValue(() => browser.userAgent),
      'source': browser.available ? 'website' : 'app',
    });
  }

  /// A tap on a link that leaves the application.
  ///
  /// A WhatsApp link, a phone number or an email address is somebody
  /// getting in touch, which Meta calls `Contact`; pass [event] to call it
  /// something else, a `Lead` for instance. Any other destination is a
  /// custom `OutboundClick` naming where it went, without its query: a
  /// link's query is where tokens live.
  Future<void> outboundClick(Uri destination, {MetaPixelEvent? event}) {
    if (event != null) return track(event);
    final String host = destination.host.toLowerCase();
    final bool contact = destination.scheme == 'tel' ||
        destination.scheme == 'mailto' ||
        destination.scheme == 'sms' ||
        destination.scheme == 'whatsapp' ||
        host == 'wa.me' ||
        host.endsWith('whatsapp.com');
    if (contact) return track(MetaPixelEvent.contact());
    return track(MetaPixelEvent.custom('OutboundClick', data: <String, Object?>{
      'destination': Uri(
        scheme: destination.scheme,
        host: destination.host,
        port: destination.hasPort ? destination.port : null,
        path: destination.path,
      ).toString(),
    }));
  }

  /// Adds what the pixel knows about this visitor to [context], for a
  /// checkout to keep with the order: the purchase is reported later, from
  /// the server, when the payment is confirmed and the visitor may be gone.
  ///
  /// Nothing is added unless consent allows, and that absence is what tells
  /// the server not to report the purchase to Meta.
  void contributeContext(Object? context) {
    if (_isBackend || context is! Map || !_allowed) return;
    context[moduleId] = <String, Object?>{
      'fbp': ?_guardedValue(() => browser.cookie('_fbp')),
      'fbc': ?_clickId(),
      'url': ?_guardedValue(() => browser.pageUrl),
      'agent': ?_guardedValue(() => browser.userAgent),
    };
  }

  /// A purchase a store module confirmed: the payload of [purchaseTopic].
  ///
  /// On the backend it is sent to the Conversions API as `Purchase` with
  /// the event id `purchase.<transaction id>`. In the buyer's browser it is
  /// the pixel's `Purchase` with that same id and no second server event,
  /// so the two are one purchase to Meta. Only for a buyer whose checkout
  /// carried this module's context, which is to say one who had consented.
  Future<void> purchaseConfirmed(Object? payload) async {
    if (!config.isConfigured || payload is! Map) return;
    final Object? transaction = payload['transaction_id'];
    final Object? currency = payload['currency'];
    final Object? total = payload['total'] ?? payload['value'];
    if (transaction == null || currency is! String || total is! num) return;
    final Object? context = payload['context'];
    final Object? mine = context is Map ? context[moduleId] : null;
    if (mine is! Map) return;

    final String eventId = 'purchase.$transaction';
    final List<Map<String, Object?>> contents = <Map<String, Object?>>[
      if (payload['items'] is List)
        for (final Object? item in payload['items'] as List<Object?>)
          if (item is Map && item['item_id'] != null)
            <String, Object?>{
              'id': '${item['item_id']}',
              'quantity': item['quantity'] is int ? item['quantity'] : 1,
              if (item['price'] is num) 'item_price': item['price'],
            },
    ];
    final Map<String, Object?> data = <String, Object?>{
      'value': total,
      'currency': currency,
      if (contents.isNotEmpty) 'contents': contents,
      if (contents.isNotEmpty) 'content_type': 'product',
    };

    if (!_isBackend) {
      if (!browser.available || !_allowed) return;
      _guard(() {
        _ensureLoaded();
        browser.track('Purchase', data, eventId: eventId, custom: false);
      });
      return;
    }

    final Object? customer = payload['customer'];
    final Object? request = context is Map ? context['request'] : null;
    String? text(Object? map, String key) =>
        map is Map && map[key] is String ? map[key] as String : null;
    await _send(MetaServerEvent(
      name: 'Purchase',
      time: DateTime.tryParse('${payload['paid_at']}') ?? _clock(),
      eventId: eventId,
      sourceUrl: text(mine, 'url'),
      actionSource: 'website',
      user: MetaUserData(
        email: text(customer, 'email'),
        phone: text(customer, 'phone'),
        firstName: text(customer, 'first_name'),
        lastName: text(customer, 'last_name'),
        city: text(customer, 'city'),
        country: text(customer, 'country'),
        postcode: text(customer, 'postcode'),
        clientIpAddress: text(request, 'ip'),
        clientUserAgent: text(mine, 'agent') ?? text(request, 'agent'),
        fbp: text(mine, 'fbp'),
        fbc: text(mine, 'fbc'),
      ),
      customData: data,
    ));
  }

  /// The backend's half of a client's event: checks that [arguments] is an
  /// event and nothing else, adds the address and user agent of the request
  /// it arrived on, and sends it to the Conversions API.
  ///
  /// The route is public, like the pixel itself, so what it accepts is
  /// narrow: a known or custom event name, a web address, a small map of
  /// parameters and the two cookies. It answers `{sent: bool}` and, when
  /// not sent, a `reason` that never includes the access token.
  Future<Map<String, Object?>> collect(Map<String, Object?> arguments) async {
    Map<String, Object?> refused(String reason) =>
        <String, Object?>{'sent': false, 'reason': reason};

    if (!config.isConfigured) return refused('no pixel id is configured');
    // The visitor's own instruction, sent with the request: honoured here
    // as well as in the client, which may be an older build.
    if (dvPrivacyOptOut) return refused('the visitor opted out');

    final Object? name = arguments['name'];
    final bool custom = arguments['custom'] == true;
    if (name is! String || name.isEmpty || name.length > 50) {
      return refused('not an event name');
    }
    if (!custom && !MetaPixelEvent.standardNames.contains(name)) {
      return refused('not a standard event');
    }
    final Object? url = arguments['url'];
    String? sourceUrl;
    if (url != null) {
      final Uri? parsed = url is String ? Uri.tryParse(url) : null;
      if (parsed == null ||
          url.toString().length > 2048 ||
          (parsed.scheme != 'https' && parsed.scheme != 'http') ||
          parsed.host.isEmpty) {
        return refused('not a web address');
      }
      sourceUrl = parsed.toString();
    }
    final Object? data = arguments['data'];
    if (data != null) {
      if (data is! Map) return refused('not event data');
      final String encoded;
      try {
        encoded = jsonEncode(data);
      } on Object {
        return refused('not event data');
      }
      if (encoded.length > maxDataLength) return refused('too much event data');
    }
    final RegExp cookie = RegExp(r'^fb\.\d+\.\d+\.[A-Za-z0-9_.-]{1,500}$');
    for (final String key in const <String>['fbp', 'fbc']) {
      final Object? value = arguments[key];
      if (value != null && (value is! String || !cookie.hasMatch(value))) {
        return refused('not a Meta cookie');
      }
    }
    final Object? id = arguments['id'];
    if (id != null && (id is! String || id.isEmpty || id.length > 128)) {
      return refused('not an event id');
    }

    final DateTime now = _clock().toUtc();
    final Object? seconds = arguments['time'];
    DateTime time = now;
    if (seconds is int) {
      final DateTime claimed =
          DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      // A client's clock is its own. One far enough out that Meta would
      // refuse the event is replaced by the server's.
      if (claimed.isAfter(now.subtract(const Duration(days: 6))) &&
          claimed.isBefore(now.add(const Duration(minutes: 5)))) {
        time = claimed;
      }
    }

    final Request? request = DVModuleRpc.request;
    final String? agent = request?.headers.get('user-agent') ??
        (arguments['agent'] is String ? arguments['agent'] as String : null);
    final bool website = arguments['source'] != 'app';
    final MetaConversionsResult result = await MetaConversionsApi(
      config,
      clock: _clock,
    ).send(<MetaServerEvent>[
      MetaServerEvent(
        name: name,
        time: time,
        eventId: id as String?,
        actionSource: website ? 'website' : 'app',
        sourceUrl: sourceUrl,
        user: MetaUserData(
          clientIpAddress: request == null
              ? null
              : DVClientAddress.current.resolve(request)?.toString(),
          clientUserAgent: agent,
          fbp: arguments['fbp'] as String?,
          fbc: arguments['fbc'] as String?,
        ),
        customData: data == null
            ? const <String, Object?>{}
            : (jsonDecode(jsonEncode(data)) as Map<String, Object?>),
      ),
    ]);
    return result.sent
        ? <String, Object?>{'sent': true}
        : refused(result.reason ?? 'not sent');
  }

  /// The most JSON a client's event data may come to, in characters.
  static const int maxDataLength = 4096;

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    browser.load(config.resolvedPixelId!, scriptUrl: scriptUrl);
  }

  /// The `_fbc` cookie, or one made from the `fbclid` in the page's address
  /// in the format Meta documents: `fb.1.<creation time>.<fbclid>`.
  String? _clickId() {
    final String? cookie = _guardedValue(() => browser.cookie('_fbc'));
    if (cookie != null && cookie.isNotEmpty) return cookie;
    final String? clickId = _guardedValue(() => browser.queryParameter('fbclid'));
    if (clickId == null || clickId.isEmpty) return null;
    return 'fb.1.${_clock().toUtc().millisecondsSinceEpoch}.$clickId';
  }

  Future<void> _relayEvent(Map<String, Object?> event) async {
    final MetaPixelRelay relay = _relay ??
        (Map<String, Object?> e) =>
            DVModuleRpc.call(moduleId, 'collect', e).then((Object? _) {});
    try {
      await relay(event);
    } on Object {
      // The backend could not be reached. The browser's own event, if there
      // was one, has gone; this one is lost rather than retried, because a
      // queue of conversions on a device is a store of personal data.
    }
  }

  Future<void> _send(MetaServerEvent event) async {
    final MetaConversionsResult result =
        await MetaConversionsApi(config, clock: _clock)
            .send(<MetaServerEvent>[event]);
    if (!result.sent) {
      const DVLog().warn(
        'Meta Conversions API: ${event.name} was not sent: ${result.reason}',
        tag: 'metaPixel',
      );
    }
  }

  static void _guard(void Function() call) {
    try {
      call();
    } on Object {
      // The pixel is somebody else's script; a page does not fail on it.
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
