import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'browser.dart';

GoogleAnalyticsBrowser createBrowser() => _WebBrowser();

/// Google's tag in a real page.
///
/// Two scripts. The first is this package's own `assets/google_analytics.js`,
/// served from the application's origin: the lines of Google's snippet that
/// define `dataLayer` and `gtag`. The second is Google's, from
/// www.googletagmanager.com. Until the first has run there is no `gtag` to
/// call, so calls made before then wait here. If Google's script never
/// arrives -- a blocker, a network that drops it, a policy that refuses it
/// -- the calls sit in `dataLayer` and nothing reads them: a page must not
/// depend on a measuring script arriving.
final class _WebBrowser implements GoogleAnalyticsBrowser {
  bool _requested = false;
  bool _ready = false;
  bool _failed = false;
  final List<void Function()> _waiting = <void Function()>[];
  String? _clientId;
  String? _sessionId;

  JSObject get _window => globalContext;

  JSObject? get _document => _window['document'] as JSObject?;

  @override
  bool get available => _document != null;

  @override
  void load(String measurementId,
      {required String scriptUrl, required bool sendPageView}) {
    if (_requested) return;
    _requested = true;
    final JSObject? document = _document;
    if (document == null) {
      _failed = true;
      return;
    }
    final JSObject stub =
        document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
    stub['src'] = scriptUrl.toJS;
    stub['onload'] = (() {
      _ready = true;
      _safely(() {
        _gtag(<JSAny?>[
          'config'.toJS,
          measurementId.toJS,
          <String, Object?>{'send_page_view': sendPageView}.jsify(),
        ]);
        // What a checkout later hands the server, so a purchase confirmed
        // there joins this visitor's session.
        _gtag(<JSAny?>[
          'get'.toJS,
          measurementId.toJS,
          'client_id'.toJS,
          ((JSAny? value) {
            _clientId = _text(value);
          }).toJS,
        ]);
        _gtag(<JSAny?>[
          'get'.toJS,
          measurementId.toJS,
          'session_id'.toJS,
          ((JSAny? value) {
            _sessionId = _text(value);
          }).toJS,
        ]);
        final JSObject tag =
            document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
        tag['async'] = true.toJS;
        tag['src'] = 'https://www.googletagmanager.com/gtag/js?id='
                '${Uri.encodeQueryComponent(measurementId)}'
            .toJS;
        _append(document, tag);
      });
      for (final void Function() call in _waiting) {
        _safely(call);
      }
      _waiting.clear();
    }).toJS;
    stub['onerror'] = (() {
      _failed = true;
      _waiting.clear();
    }).toJS;
    _append(document, stub);
  }

  static void _append(JSObject document, JSObject script) {
    final JSObject? head = document['head'] as JSObject?;
    (head ?? document).callMethod<JSAny?>('appendChild'.toJS, script);
  }

  static String? _text(JSAny? value) {
    if (value == null) return null;
    final Object? dart = value.dartify();
    if (dart is String) return dart.isEmpty ? null : dart;
    if (dart is num) return dart.toInt().toString();
    return null;
  }

  @override
  void event(String name, Map<String, Object?> params) {
    _run(() => _gtag(<JSAny?>['event'.toJS, name.toJS, params.jsify()]));
  }

  @override
  void consent({required bool granted}) {
    _run(() => _gtag(<JSAny?>[
          'consent'.toJS,
          'update'.toJS,
          <String, Object?>{
            'analytics_storage': granted ? 'granted' : 'denied',
          }.jsify(),
        ]));
  }

  void _run(void Function() call) {
    if (_failed) return;
    if (_ready) {
      _safely(call);
    } else {
      _waiting.add(call);
    }
  }

  void _gtag(List<JSAny?> arguments) {
    final JSAny? gtag = _window['gtag'];
    if (gtag == null) return;
    (gtag as JSFunction).callMethodVarArgs<JSAny?>(
        'apply'.toJS, <JSAny?>[_window, arguments.toJS]);
  }

  /// The tag is somebody else's script. Whatever it throws stays here.
  static void _safely(void Function() call) {
    try {
      call();
    } on Object {
      // Deliberately dropped.
    }
  }

  @override
  String? get clientId => _clientId ?? dvGoogleAnalyticsClientIdFromCookie(_cookie('_ga'));

  @override
  String? get sessionId => _sessionId;

  String? _cookie(String name) {
    try {
      final String all = ((_document?['cookie']) as JSString?)?.toDart ?? '';
      for (final String part in all.split(';')) {
        final int equals = part.indexOf('=');
        if (equals < 0) continue;
        if (part.substring(0, equals).trim() == name) {
          return part.substring(equals + 1).trim();
        }
      }
    } on Object {
      // No cookies to read.
    }
    return null;
  }

  @override
  String? get pageUrl {
    try {
      final JSObject? location = _window['location'] as JSObject?;
      return (location?['href'] as JSString?)?.toDart;
    } on Object {
      return null;
    }
  }

  @override
  String? get pageTitle {
    try {
      return (_document?['title'] as JSString?)?.toDart;
    } on Object {
      return null;
    }
  }
}
