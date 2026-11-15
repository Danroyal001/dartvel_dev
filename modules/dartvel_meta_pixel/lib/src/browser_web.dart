import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'browser.dart';

MetaPixelBrowser createBrowser() => _WebBrowser();

/// The pixel in a real page.
///
/// The script is Meta's base code, served from the application's own origin
/// (`assets/meta_pixel.js` in this package). It defines `fbq` and loads
/// `fbevents.js` from connect.facebook.net. Until that first script has run
/// there is no `fbq` to call, so calls made before then wait here and are
/// made in order when it has. If it never runs -- a blocker, a network that
/// drops it, a policy that refuses it -- they are dropped: a page must not
/// depend on an advertiser's script arriving.
final class _WebBrowser implements MetaPixelBrowser {
  bool _requested = false;
  bool _ready = false;
  bool _failed = false;
  final List<void Function()> _waiting = <void Function()>[];

  JSObject get _window => globalContext;

  JSObject? get _document => _window['document'] as JSObject?;

  @override
  bool get available => _document != null;

  @override
  void load(String pixelId, {required String scriptUrl}) {
    if (_requested) return;
    _requested = true;
    final JSObject? document = _document;
    if (document == null) {
      _failed = true;
      return;
    }
    final JSObject script =
        document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
    script['async'] = true.toJS;
    script['src'] = scriptUrl.toJS;
    script['onload'] = (() {
      _ready = true;
      for (final void Function() call in _waiting) {
        _safely(call);
      }
      _waiting.clear();
    }).toJS;
    script['onerror'] = (() {
      _failed = true;
      _waiting.clear();
    }).toJS;
    _run(() => _fbq(<JSAny?>['init'.toJS, pixelId.toJS]));
    final JSObject? head = document['head'] as JSObject?;
    (head ?? document).callMethod<JSAny?>('appendChild'.toJS, script);
  }

  @override
  void track(String name, Map<String, Object?> data,
      {required String eventId, required bool custom}) {
    _run(() => _fbq(<JSAny?>[
          (custom ? 'trackCustom' : 'track').toJS,
          name.toJS,
          data.jsify(),
          <String, Object?>{'eventID': eventId}.jsify(),
        ]));
  }

  @override
  void consent({required bool granted}) {
    _run(() =>
        _fbq(<JSAny?>['consent'.toJS, (granted ? 'grant' : 'revoke').toJS]));
  }

  /// Makes [call] now, or once the script has run, or never if it failed.
  void _run(void Function() call) {
    if (_failed) return;
    if (_ready) {
      _safely(call);
    } else {
      _waiting.add(call);
    }
  }

  void _fbq(List<JSAny?> arguments) {
    final JSAny? fbq = _window['fbq'];
    if (fbq == null) return;
    (fbq as JSFunction).callMethodVarArgs<JSAny?>(
        'apply'.toJS, <JSAny?>[_window, arguments.toJS]);
  }

  /// The pixel is somebody else's script. Whatever it throws stays here.
  static void _safely(void Function() call) {
    try {
      call();
    } on Object {
      // Deliberately dropped.
    }
  }

  @override
  String? cookie(String name) {
    try {
      final String all =
          ((_document?['cookie']) as JSString?)?.toDart ?? '';
      for (final String part in all.split(';')) {
        final int equals = part.indexOf('=');
        if (equals < 0) continue;
        if (part.substring(0, equals).trim() == name) {
          return Uri.decodeComponent(part.substring(equals + 1).trim());
        }
      }
    } on Object {
      // No cookies to read: a sandboxed frame, or none allowed.
    }
    return null;
  }

  @override
  String? queryParameter(String name) {
    final String? url = pageUrl;
    if (url == null) return null;
    return Uri.tryParse(url)?.queryParameters[name];
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
  String? get userAgent {
    try {
      final JSObject? navigator = _window['navigator'] as JSObject?;
      return (navigator?['userAgent'] as JSString?)?.toDart;
    } on Object {
      return null;
    }
  }
}
