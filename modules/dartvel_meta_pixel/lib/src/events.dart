import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One thing a visitor did, as Meta names it.
///
/// A standard event is one of the names in [standardNames]; anything else is
/// a custom event. The difference matters to the browser pixel, which sends
/// one with `fbq('track', ...)` and the other with `fbq('trackCustom', ...)`.
final class MetaPixelEvent {
  /// A standard event. [name] must be one of [standardNames].
  MetaPixelEvent(this.name, {Map<String, Object?> data = const <String, Object?>{}})
      : data = Map<String, Object?>.unmodifiable(data),
        custom = false {
    if (!standardNames.contains(name)) {
      throw ArgumentError.value(name, 'name',
          'is not a Meta standard event; use MetaPixelEvent.custom for it');
    }
  }

  /// A custom event. Meta allows a name of up to 50 characters.
  MetaPixelEvent.custom(this.name,
      {Map<String, Object?> data = const <String, Object?>{}})
      : data = Map<String, Object?>.unmodifiable(data),
        custom = true {
    if (name.isEmpty || name.length > 50) {
      throw ArgumentError.value(
          name, 'name', 'a custom event name is 1 to 50 characters');
    }
  }

  /// A page shown to a visitor.
  factory MetaPixelEvent.pageView() => MetaPixelEvent('PageView');

  /// A visit to a page that matters: a product, a plan, a landing page.
  factory MetaPixelEvent.viewContent({
    String? contentName,
    String? contentCategory,
    List<String>? contentIds,
    String? contentType,
    num? value,
    String? currency,
  }) =>
      MetaPixelEvent('ViewContent', data: <String, Object?>{
        'content_name': ?contentName,
        'content_category': ?contentCategory,
        'content_ids': ?contentIds,
        'content_type': ?contentType,
        'value': ?value,
        'currency': ?currency,
      });

  /// Somebody left their details: a form, a sign-up for a call back.
  factory MetaPixelEvent.lead({
    String? contentName,
    String? contentCategory,
    num? value,
    String? currency,
  }) =>
      MetaPixelEvent('Lead', data: <String, Object?>{
        'content_name': ?contentName,
        'content_category': ?contentCategory,
        'value': ?value,
        'currency': ?currency,
      });

  /// Somebody got in touch: a phone call, an email, a chat, a WhatsApp tap.
  factory MetaPixelEvent.contact() => MetaPixelEvent('Contact');

  /// The start of a checkout.
  factory MetaPixelEvent.initiateCheckout({
    num? value,
    String? currency,
    int? numItems,
    List<String>? contentIds,
    List<MetaPixelContent>? contents,
  }) =>
      MetaPixelEvent('InitiateCheckout', data: <String, Object?>{
        'value': ?value,
        'currency': ?currency,
        'num_items': ?numItems,
        'content_ids': ?contentIds,
        'contents': ?contents?.map((MetaPixelContent c) => c.toJson()).toList(),
      });

  /// A completed purchase. Meta requires [value] and [currency].
  factory MetaPixelEvent.purchase({
    required num value,
    required String currency,
    List<String>? contentIds,
    List<MetaPixelContent>? contents,
    String? contentType,
    int? numItems,
  }) =>
      MetaPixelEvent('Purchase', data: <String, Object?>{
        'value': value,
        'currency': currency,
        'content_ids': ?contentIds,
        'contents': ?contents?.map((MetaPixelContent c) => c.toJson()).toList(),
        'content_type': ?contentType,
        'num_items': ?numItems,
      });

  /// Meta's standard event names, and `PageView`, as its Pixel reference
  /// spells them.
  static const Set<String> standardNames = <String>{
    'PageView',
    'AddPaymentInfo',
    'AddToCart',
    'AddToWishlist',
    'CompleteRegistration',
    'Contact',
    'CustomizeProduct',
    'Donate',
    'FindLocation',
    'InitiateCheckout',
    'Lead',
    'Purchase',
    'Schedule',
    'Search',
    'StartTrial',
    'SubmitApplication',
    'Subscribe',
    'ViewContent',
  };

  final String name;
  final bool custom;

  /// The event's parameters: `value`, `currency`, `content_ids` and the
  /// rest of Meta's object properties, or an application's own for a custom
  /// event.
  final Map<String, Object?> data;
}

/// One product in an event's `contents`.
final class MetaPixelContent {
  const MetaPixelContent({required this.id, required this.quantity, this.itemPrice});

  final String id;
  final int quantity;
  final num? itemPrice;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'quantity': quantity,
        'item_price': ?itemPrice,
      };
}

/// What is known about the person an event is about, for the Conversions
/// API to match them with.
///
/// Give the values as the person typed them. [toJson] normalises and hashes
/// what Meta requires hashed (SHA-256), and leaves alone what it requires
/// unhashed: the address, the user agent and the `fbp` and `fbc` cookies.
final class MetaUserData {
  const MetaUserData({
    this.email,
    this.phone,
    this.firstName,
    this.lastName,
    this.city,
    this.country,
    this.postcode,
    this.externalId,
    this.clientIpAddress,
    this.clientUserAgent,
    this.fbp,
    this.fbc,
  });

  final String? email;

  /// With its country code: `+234 803 000 0000`.
  final String? phone;
  final String? firstName;
  final String? lastName;
  final String? city;

  /// The two-letter ISO 3166-1 code.
  final String? country;
  final String? postcode;

  /// The application's own id for the person.
  final String? externalId;
  final String? clientIpAddress;
  final String? clientUserAgent;

  /// The `_fbp` cookie.
  final String? fbp;

  /// The `_fbc` cookie.
  final String? fbc;

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String? _hashed(String? value, String Function(String) normalise) {
    if (value == null) return null;
    final String normal = normalise(value);
    return normal.isEmpty ? null : _hash(normal);
  }

  static String _lowerTrimmed(String v) => v.trim().toLowerCase();

  /// Lowercase letters only: no punctuation, digits or spaces.
  static String _lettersOnly(String v) => v
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\d!-/:-@\[-`{-~]'), '');

  /// The `user_data` object, with the keys Meta's customer information
  /// parameters name.
  Map<String, Object?> toJson() => <String, Object?>{
        'em': ?_hashed(email, _lowerTrimmed),
        // Digits only, without leading zeros, with the country code.
        'ph': ?_hashed(
            phone,
            (String v) => v
                .replaceAll(RegExp(r'\D'), '')
                .replaceFirst(RegExp(r'^0+'), '')),
        'fn': ?_hashed(firstName, _lettersOnly),
        'ln': ?_hashed(lastName, _lettersOnly),
        'ct': ?_hashed(city, _lettersOnly),
        'country': ?_hashed(country, _lowerTrimmed),
        'zp': ?_hashed(
            postcode,
            (String v) =>
                v.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '')),
        'external_id': ?_hashed(externalId, (String v) => v.trim()),
        'client_ip_address': ?_nonEmpty(clientIpAddress),
        'client_user_agent': ?_nonEmpty(clientUserAgent),
        'fbp': ?_nonEmpty(fbp),
        'fbc': ?_nonEmpty(fbc),
      };

  static String? _nonEmpty(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// One event as the Conversions API takes it.
final class MetaServerEvent {
  const MetaServerEvent({
    required this.name,
    required this.time,
    required this.user,
    this.eventId,
    this.actionSource = 'website',
    this.sourceUrl,
    this.customData = const <String, Object?>{},
  });

  /// `event_name`. Matches the browser event's name for de-duplication.
  final String name;

  /// When it happened. Meta refuses a whole request holding an event more
  /// than seven days old.
  final DateTime time;

  /// `event_id`. Matches the browser event's `eventID` for de-duplication.
  final String? eventId;

  /// `action_source`: `website`, `app`, `email`, `phone_call`, `chat`,
  /// `physical_store`, `system_generated`, `business_messaging` or `other`.
  final String actionSource;

  /// `event_source_url`, which Meta requires for a website event.
  final String? sourceUrl;

  final MetaUserData user;
  final Map<String, Object?> customData;

  Map<String, Object?> toJson() => <String, Object?>{
        'event_name': name,
        'event_time': time.toUtc().millisecondsSinceEpoch ~/ 1000,
        'event_id': ?eventId,
        'action_source': actionSource,
        'event_source_url': ?sourceUrl,
        'user_data': user.toJson(),
        if (customData.isNotEmpty) 'custom_data': customData,
      };
}
