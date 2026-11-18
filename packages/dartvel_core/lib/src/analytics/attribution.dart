/// Where a visitor came from: the campaign, click ids, referrer and landing
/// page of their first visit and of their latest campaign visit, kept on
/// their own device.
///
/// An ad click lands on a page with `utm_*` and `fbclid` in its address, and
/// the first route change takes them out. By the time the visitor sends a
/// contact form or places an order nothing on the page says which ad brought
/// them, and a lead with no source looks exactly like a direct one. So the
/// landing is read once, as the application starts, and kept:
///
/// - **first touch**, the first visit this device made, never overwritten
///   while it is younger than [DVAttribution.firstTouchFor] (90 days);
/// - **last touch**, overwritten by any later visit that brings a campaign
///   parameter, a click id or a referrer from another site.
///
/// Kept as functional, first-party storage (`localStorage` in a browser, the
/// process's memory elsewhere). Nothing here sends it anywhere: the
/// application attaches `DV.Analytics.attribution` to what it sends its own
/// backend, and an analytics module adds the campaign to a page view only
/// once the visitor has consented to that module.
library dartvel_core.analytics.attribution;

import 'dart:convert';

import 'attribution_none.dart'
    if (dart.library.js_interop) 'attribution_web.dart' as platform;

/// Somewhere to keep one string by name. `localStorage` in a browser.
abstract interface class DVAttributionStorage {
  String? read(String key);
  void write(String key, String value);
}

/// One visit's source.
final class DVTouch {
  const DVTouch({
    required this.at,
    this.source,
    this.medium,
    this.campaign,
    this.content,
    this.term,
    this.id,
    this.fbclid,
    this.gclid,
    this.fbc,
    this.referrer,
    this.landingPath,
  });

  /// `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`
  /// and `utm_id`.
  final String? source, medium, campaign, content, term, id;

  /// Meta's and Google's click ids.
  final String? fbclid, gclid;

  /// [fbclid] in the format Meta documents for the `_fbc` cookie and the
  /// Conversions API: `fb.1.<creation time in milliseconds>.<fbclid>`.
  final String? fbc;

  /// The page that linked here, when it was another site's.
  final String? referrer;

  /// The path the visit landed on, without its query.
  final String? landingPath;

  /// When the visit landed.
  final DateTime at;

  /// Whether the visit carried a campaign parameter or a click id.
  bool get isTagged =>
      source != null ||
      medium != null ||
      campaign != null ||
      content != null ||
      term != null ||
      id != null ||
      fbclid != null ||
      gclid != null;

  /// The touch as plain data, with the parameters' own names. A parameter
  /// the visit did not carry is left out.
  Map<String, Object?> toJson() => <String, Object?>{
        'utm_source': ?source,
        'utm_medium': ?medium,
        'utm_campaign': ?campaign,
        'utm_content': ?content,
        'utm_term': ?term,
        'utm_id': ?id,
        'fbclid': ?fbclid,
        'gclid': ?gclid,
        'fbc': ?fbc,
        'referrer': ?referrer,
        'landing_path': ?landingPath,
        'at': at.toIso8601String(),
      };

  static DVTouch? fromJson(Object? json) {
    if (json is! Map) return null;
    final DateTime? at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    String? text(String key) {
      final Object? value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return DVTouch(
      at: at,
      source: text('utm_source'),
      medium: text('utm_medium'),
      campaign: text('utm_campaign'),
      content: text('utm_content'),
      term: text('utm_term'),
      id: text('utm_id'),
      fbclid: text('fbclid'),
      gclid: text('gclid'),
      fbc: text('fbc'),
      referrer: text('referrer'),
      landingPath: text('landing_path'),
    );
  }
}

/// This device's first and last touch. See the library documentation.
final class DVAttribution {
  DVAttribution({
    required DVAttributionStorage storage,
    DateTime Function()? clock,
    this.firstTouchFor = const Duration(days: 90),
  })  : _storage = storage,
        _clock = clock ?? DateTime.now;

  /// The name the touches are kept under.
  static const String storageKey = 'dartvel.attribution';

  static DVAttribution? _current;

  /// This process's attribution, over the platform's storage. In a browser
  /// the page's landing address is captured the first time this is read.
  static DVAttribution get current {
    final DVAttribution? existing = _current;
    if (existing != null) return existing;
    final DVAttribution made =
        _current = DVAttribution(storage: platform.dvAttributionStorage());
    captureLanding();
    return made;
  }

  /// Captures the address the browser landed on and the page that linked to
  /// it. Does nothing outside a browser, and nothing after the first call:
  /// the generated client calls it as it starts, before a route change can
  /// take the campaign out of the address.
  static void captureLanding() {
    final Uri? landing = platform.dvLandingAddress();
    if (landing == null) return;
    current.capture(landing, referrer: platform.dvLandingReferrer());
  }

  /// Forgets [current], for tests.
  static void resetForTest() => _current = null;

  final DVAttributionStorage _storage;
  final DateTime Function() _clock;

  /// How long a first touch stands before a later visit may replace it.
  final Duration firstTouchFor;

  bool _captured = false;
  DVTouch? _first;
  DVTouch? _last;
  DVTouch? _visit;
  bool _read = false;

  /// The first visit this device made within [firstTouchFor].
  DVTouch? get firstTouch {
    _load();
    return _first;
  }

  /// The latest visit that brought a campaign, a click id or another site's
  /// referrer; the first visit until there is one.
  DVTouch? get lastTouch {
    _load();
    return _last;
  }

  /// This page load's own touch, when it brought a campaign, a click id or
  /// another site's referrer. What a page view reports as its campaign.
  DVTouch? get visit => _visit;

  /// `{firstTouch: {...}, lastTouch: {...}}`, plain data for a backend call.
  Map<String, Object?> toJson() => <String, Object?>{
        'firstTouch': firstTouch?.toJson(),
        'lastTouch': lastTouch?.toJson(),
      };

  /// Reads [page] as the landing of a visit, linked from [referrer]. Only the
  /// first call does anything: the landing is the one address that carries
  /// the campaign.
  void capture(Uri page, {String? referrer}) {
    if (_captured) return;
    _captured = true;
    _load();
    final DateTime now = _clock().toUtc();
    final Map<String, String> query = page.queryParameters;
    String? param(String name) {
      final String? value = query[name]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final String? fbclid = param('fbclid');
    final String? from = _external(referrer, page);
    final DVTouch touch = DVTouch(
      at: now,
      source: param('utm_source'),
      medium: param('utm_medium'),
      campaign: param('utm_campaign'),
      content: param('utm_content'),
      term: param('utm_term'),
      id: param('utm_id'),
      fbclid: fbclid,
      gclid: param('gclid'),
      fbc: fbclid == null ? null : 'fb.1.${now.millisecondsSinceEpoch}.$fbclid',
      referrer: from,
      landingPath: page.path.isEmpty ? '/' : page.path,
    );
    final bool newSource = touch.isTagged || from != null;
    if (newSource) _visit = touch;

    final DVTouch? first = _first;
    final bool firstExpired =
        first == null || now.difference(first.at) > firstTouchFor;
    if (firstExpired) _first = touch;
    final DVTouch? last = _last;
    if (newSource ||
        last == null ||
        now.difference(last.at) > firstTouchFor) {
      _last = touch;
    }
    _save();
  }

  /// [referrer] when it is another site's page; null for this site's own
  /// pages and for none.
  static String? _external(String? referrer, Uri page) {
    if (referrer == null || referrer.trim().isEmpty) return null;
    final Uri? from = Uri.tryParse(referrer.trim());
    if (from == null || !from.hasAuthority) return null;
    if (from.host.toLowerCase() == page.host.toLowerCase()) return null;
    return referrer.trim();
  }

  void _load() {
    if (_read) return;
    _read = true;
    try {
      final String? kept = _storage.read(storageKey);
      if (kept == null) return;
      final Object? json = jsonDecode(kept);
      if (json is! Map) return;
      _first = DVTouch.fromJson(json['firstTouch']);
      _last = DVTouch.fromJson(json['lastTouch']);
    } on Object {
      // Storage that cannot be read, or holds something else: nothing kept.
    }
  }

  void _save() {
    try {
      _storage.write(storageKey, jsonEncode(toJson()));
    } on Object {
      // Storage turned off or full. This page load still knows its touch.
    }
  }
}
