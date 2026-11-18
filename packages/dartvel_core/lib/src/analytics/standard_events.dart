/// The events a shop or a lead form tracks, one call each, with the names
/// and parameters of Google Analytics' recommended events.
///
/// ```dart
/// DV.Analytics.track(DVGenerateLead(leadSource: 'contact form'));
/// DV.Analytics.track(DVPurchase(transactionId: order.id, value: 45000, currency: 'NGN'));
/// ```
///
/// Tracking one hands it, as the call is made, to every analytics module the
/// application mounted, on the module topic [DVStandardEvent.topic]: Google
/// Analytics sends it as the recommended event of the same name, Meta's
/// pixel as the standard event it corresponds to (`view_item` is
/// `ViewContent`, `add_to_cart` `AddToCart`, `begin_checkout`
/// `InitiateCheckout`, `sign_up` `CompleteRegistration`, `generate_lead`
/// `Lead`, `purchase` `Purchase`). Each module waits for its own consent
/// category. The event is also kept in the application's own analytics store
/// when its [DVAnalyticsEvent.category] is declared.
library dartvel_core.analytics.standard_events;

import 'consent.dart';
import 'product_analytics.dart';

/// A product, plan or service in an event, with Google Analytics' item
/// fields.
final class DVAnalyticsItem {
  const DVAnalyticsItem({
    this.id,
    this.name,
    this.price,
    this.quantity,
    this.category,
    this.brand,
    this.variant,
  });

  final String? id;
  final String? name;

  /// The price of one, in the event's currency.
  final num? price;
  final int? quantity;
  final String? category;
  final String? brand;
  final String? variant;

  Map<String, Object?> toJson() => <String, Object?>{
        'item_id': ?id,
        'item_name': ?name,
        'price': ?price,
        'quantity': ?quantity,
        'item_category': ?category,
        'item_brand': ?brand,
        'item_variant': ?variant,
      };
}

/// One of the events in this library. See the library documentation.
abstract class DVStandardEvent extends DVAnalyticsEvent {
  DVStandardEvent({DVConsentCategory? category})
      : category = category ?? defaultCategory;

  /// The category an event is kept under in the application's own store
  /// unless it names another: `analytics`.
  static const DVConsentCategory defaultCategory =
      DVConsentCategory('analytics');

  /// The module topic each event is published to as it is tracked, as plain
  /// data: `{name: 'generate_lead', params: {...}}`.
  static const String topic = 'analytics.event';

  @override
  final DVConsentCategory category;

  /// What is published on [topic].
  Map<String, Object?> toPayload() =>
      <String, Object?>{'name': name, 'params': properties};

  static final RegExp _currency = RegExp(r'^[A-Z]{3}$');

  /// The value, currency and items every commerce event shares, checked:
  /// Google Analytics drops a value that has no currency and keeps the
  /// event, so revenue would read zero with nothing saying why.
  static Map<String, Object?> commerce({
    num? value,
    String? currency,
    List<DVAnalyticsItem> items = const <DVAnalyticsItem>[],
  }) {
    for (final DVAnalyticsItem item in items) {
      if ((item.id == null || item.id!.trim().isEmpty) &&
          (item.name == null || item.name!.trim().isEmpty)) {
        throw ArgumentError.value(
            item, 'items', 'each item needs an id or a name');
      }
    }
    num? total = value;
    if (total == null &&
        items.isNotEmpty &&
        items.every((DVAnalyticsItem i) => i.price != null)) {
      total = items.fold<num>(
          0, (num sum, DVAnalyticsItem i) => sum + i.price! * (i.quantity ?? 1));
    }
    if (currency != null && !_currency.hasMatch(currency)) {
      throw ArgumentError.value(currency, 'currency',
          'must be an ISO 4217 code in capitals, such as NGN or USD');
    }
    if (total != null && currency == null) {
      throw ArgumentError.value(value, 'value',
          'needs a currency; Google Analytics ignores a value without one');
    }
    return <String, Object?>{
      'currency': ?currency,
      'value': ?total,
      if (items.isNotEmpty)
        'items': <Object?>[for (final DVAnalyticsItem i in items) i.toJson()],
    };
  }
}

/// `view_item` (Meta: `ViewContent`): a product, plan or service was looked
/// at.
class DVViewItem extends DVStandardEvent {
  DVViewItem({
    num? value,
    String? currency,
    List<DVAnalyticsItem> items = const <DVAnalyticsItem>[],
    super.category,
  }) : properties = DVStandardEvent.commerce(
            value: value, currency: currency, items: items);

  @override
  String get name => 'view_item';

  @override
  final Map<String, Object?> properties;
}

/// `add_to_cart` (Meta: `AddToCart`).
class DVAddToCart extends DVStandardEvent {
  DVAddToCart({
    num? value,
    String? currency,
    List<DVAnalyticsItem> items = const <DVAnalyticsItem>[],
    super.category,
  }) : properties = DVStandardEvent.commerce(
            value: value, currency: currency, items: items);

  @override
  String get name => 'add_to_cart';

  @override
  final Map<String, Object?> properties;
}

/// `begin_checkout` (Meta: `InitiateCheckout`).
class DVBeginCheckout extends DVStandardEvent {
  DVBeginCheckout({
    num? value,
    String? currency,
    String? coupon,
    List<DVAnalyticsItem> items = const <DVAnalyticsItem>[],
    super.category,
  }) : properties = <String, Object?>{
          ...DVStandardEvent.commerce(
              value: value, currency: currency, items: items),
          'coupon': ?coupon,
        };

  @override
  String get name => 'begin_checkout';

  @override
  final Map<String, Object?> properties;
}

/// `purchase` (Meta: `Purchase`). [transactionId] is the order's id: Google
/// Analytics counts two purchases with one id once.
class DVPurchase extends DVStandardEvent {
  DVPurchase({
    required String transactionId,
    required num value,
    required String currency,
    num? tax,
    num? shipping,
    String? coupon,
    List<DVAnalyticsItem> items = const <DVAnalyticsItem>[],
    super.category,
  }) : properties = <String, Object?>{
          'transaction_id': _required(transactionId),
          ...DVStandardEvent.commerce(
              value: value,
              currency: currency.isEmpty ? null : currency,
              items: items),
          'tax': ?tax,
          'shipping': ?shipping,
          'coupon': ?coupon,
        };

  static String _required(String id) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'transactionId', 'must be set');
    }
    return id.trim();
  }

  @override
  String get name => 'purchase';

  @override
  final Map<String, Object?> properties;
}

/// `sign_up` (Meta: `CompleteRegistration`). [method] is how, such as
/// `email` or `google`.
class DVSignUp extends DVStandardEvent {
  DVSignUp({this.method, super.category});

  final String? method;

  @override
  String get name => 'sign_up';

  @override
  Map<String, Object?> get properties =>
      <String, Object?>{'method': ?method};
}

/// `login`. Meta has no standard event for it, so the pixel sends nothing.
class DVLogin extends DVStandardEvent {
  DVLogin({this.method, super.category});

  final String? method;

  @override
  String get name => 'login';

  @override
  Map<String, Object?> get properties =>
      <String, Object?>{'method': ?method};
}

/// `generate_lead` (Meta: `Lead`): somebody sent a contact form, booked a
/// call or left their details.
class DVGenerateLead extends DVStandardEvent {
  DVGenerateLead({
    num? value,
    String? currency,
    String? leadSource,
    super.category,
  }) : properties = <String, Object?>{
          ...DVStandardEvent.commerce(value: value, currency: currency),
          'lead_source': ?leadSource,
        };

  @override
  String get name => 'generate_lead';

  @override
  final Map<String, Object?> properties;
}
