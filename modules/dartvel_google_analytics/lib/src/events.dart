/// One event, as Google Analytics 4 names it.
///
/// The recommended events have constructors here with the parameters
/// Google's reference gives them; anything else is [GoogleAnalyticsEvent.new]
/// with a name of the application's own.
final class GoogleAnalyticsEvent {
  /// An event called [name] with [params].
  ///
  /// Refuses what Google Analytics would silently drop: a name that is not
  /// letters, digits and underscores starting with a letter, one longer
  /// than 40 characters, a reserved name or prefix, or more than 25
  /// parameters.
  GoogleAnalyticsEvent(this.name,
      {Map<String, Object?> params = const <String, Object?>{}})
      : params = Map<String, Object?>.unmodifiable(params) {
    final String? problem = problemWith(name, params);
    if (problem != null) throw ArgumentError(problem);
  }

  /// Why Google Analytics would not accept an event called [name] with
  /// [params], or null when it would.
  static String? problemWith(String name, Map<String, Object?> params) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$').hasMatch(name)) {
      return '"$name" is not an event name: up to 40 letters, digits and '
          'underscores, starting with a letter';
    }
    if (reservedNames.contains(name)) {
      return '"$name" is a name Google Analytics reserves';
    }
    if (reservedPrefixes.any(name.startsWith)) {
      return '"$name" begins with a prefix Google Analytics reserves';
    }
    if (params.length > maxParams) {
      return '$name has ${params.length} parameters; Google Analytics takes '
          '$maxParams';
    }
    for (final String key in params.keys) {
      if (key.length > 40 || reservedPrefixes.any(key.startsWith)) {
        return '"$key" is not a parameter name Google Analytics accepts';
      }
    }
    return null;
  }

  /// Parameters per event.
  static const int maxParams = 25;

  /// Event names the Measurement Protocol reference lists as reserved,
  /// and the three it allows only on app streams.
  static const Set<String> reservedNames = <String>{
    'ad_activeview',
    'ad_click',
    'ad_exposure',
    'ad_query',
    'ad_reward',
    'adunit_exposure',
    'app_clear_data',
    'app_exception',
    'app_install',
    'app_remove',
    'app_store_refund',
    'app_update',
    'app_upgrade',
    'dynamic_link_app_open',
    'dynamic_link_app_update',
    'dynamic_link_first_open',
    'error',
    'firebase_campaign',
    'firebase_in_app_message_action',
    'firebase_in_app_message_dismiss',
    'firebase_in_app_message_impression',
    'first_open',
    'first_visit',
    'notification_dismiss',
    'notification_foreground',
    'notification_open',
    'notification_receive',
    'notification_send',
    'os_update',
    'session_start',
    'user_engagement',
    'ad_impression',
    'in_app_purchase',
    'screen_view',
  };

  static const List<String> reservedPrefixes = <String>[
    '_',
    'firebase_',
    'ga_',
    'google_',
    'gtag.',
  ];

  /// A page shown to a visitor. [location] is a full URL.
  factory GoogleAnalyticsEvent.pageView({String? location, String? title}) =>
      GoogleAnalyticsEvent('page_view', params: <String, Object?>{
        'page_location': ?location,
        'page_title': ?title,
      });

  /// Somebody left their details, or got in touch.
  factory GoogleAnalyticsEvent.generateLead({
    num? value,
    String? currency,
    String? leadSource,
  }) =>
      GoogleAnalyticsEvent('generate_lead', params: <String, Object?>{
        'value': ?value,
        'currency': ?currency,
        'lead_source': ?leadSource,
      });

  /// The start of a checkout.
  factory GoogleAnalyticsEvent.beginCheckout({
    num? value,
    String? currency,
    String? coupon,
    List<GoogleAnalyticsItem> items = const <GoogleAnalyticsItem>[],
  }) =>
      GoogleAnalyticsEvent('begin_checkout', params: <String, Object?>{
        'value': ?value,
        'currency': ?currency,
        'coupon': ?coupon,
        'items': <Object?>[
          for (final GoogleAnalyticsItem i in items) i.toJson(),
        ],
      });

  /// A completed purchase. [value] is the sum of price times quantity of
  /// the items, without shipping or tax, which have parameters of their own.
  factory GoogleAnalyticsEvent.purchase({
    required String transactionId,
    required num value,
    required String currency,
    num? tax,
    num? shipping,
    String? coupon,
    List<GoogleAnalyticsItem> items = const <GoogleAnalyticsItem>[],
  }) =>
      GoogleAnalyticsEvent('purchase', params: <String, Object?>{
        'transaction_id': transactionId,
        'value': value,
        'currency': currency,
        'tax': ?tax,
        'shipping': ?shipping,
        'coupon': ?coupon,
        'items': <Object?>[
          for (final GoogleAnalyticsItem i in items) i.toJson(),
        ],
      });

  /// A product or plan was looked at.
  factory GoogleAnalyticsEvent.viewItem({
    num? value,
    String? currency,
    List<GoogleAnalyticsItem> items = const <GoogleAnalyticsItem>[],
  }) =>
      GoogleAnalyticsEvent('view_item', params: <String, Object?>{
        'value': ?value,
        'currency': ?currency,
        'items': <Object?>[
          for (final GoogleAnalyticsItem i in items) i.toJson(),
        ],
      });

  /// An account was created, by [method]: `email`, `google`.
  factory GoogleAnalyticsEvent.signUp({String? method}) =>
      GoogleAnalyticsEvent('sign_up',
          params: <String, Object?>{'method': ?method});

  /// Somebody signed in, by [method].
  factory GoogleAnalyticsEvent.login({String? method}) =>
      GoogleAnalyticsEvent('login', params: <String, Object?>{'method': ?method});

  final String name;
  final Map<String, Object?> params;
}

/// One product in an event's `items`.
final class GoogleAnalyticsItem {
  const GoogleAnalyticsItem({
    this.itemId,
    this.itemName,
    this.price,
    this.quantity,
    this.itemCategory,
    this.itemVariant,
  }) : assert(itemId != null || itemName != null,
            'Google Analytics requires an item_id or an item_name');

  final String? itemId;
  final String? itemName;
  final num? price;
  final int? quantity;
  final String? itemCategory;
  final String? itemVariant;

  Map<String, Object?> toJson() => <String, Object?>{
        'item_id': ?itemId,
        'item_name': ?itemName,
        'price': ?price,
        'quantity': ?quantity,
        'item_category': ?itemCategory,
        'item_variant': ?itemVariant,
      };
}
