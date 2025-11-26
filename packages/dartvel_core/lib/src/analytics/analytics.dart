// Analytics integration - Firebase/Mixpanel/etc
abstract class AnalyticsProvider {
  Future<void> logEvent(String name, [Map<String, Object>? parameters]);
  Future<void> setUserId(String? userId);
  Future<void> setUserProperty(String name, String value);
  Future<void> logScreenView(String screenName, {String? screenClass});
}

/// Analytics manager supporting multiple providers
class Analytics {
  static final List<AnalyticsProvider> _providers = [];

  static void register(AnalyticsProvider provider) {
    _providers.add(provider);
  }

  static Future<void> logEvent(String name,
      [Map<String, Object>? parameters]) async {
    for (final provider in _providers) {
      await provider.logEvent(name, parameters);
    }
  }

  static Future<void> setUserId(String? userId) async {
    for (final provider in _providers) {
      await provider.setUserId(userId);
    }
  }

  static Future<void> setUserProperty(String name, String value) async {
    for (final provider in _providers) {
      await provider.setUserProperty(name, value);
    }
  }

  static Future<void> logScreenView(String screenName,
      {String? screenClass}) async {
    for (final provider in _providers) {
      await provider.logScreenView(screenName, screenClass: screenClass);
    }
  }

  // Common events
  static Future<void> logLogin(String method) =>
      logEvent('login', {'method': method});

  static Future<void> logSignUp(String method) =>
      logEvent('sign_up', {'method': method});

  static Future<void> logPurchase({
    required double value,
    required String currency,
    String? transactionId,
  }) =>
      logEvent('purchase', {
        'value': value,
        'currency': currency,
        if (transactionId != null) 'transaction_id': transactionId,
      });

  static Future<void> logShare({required String itemId, String? method}) =>
      logEvent('share', {
        'item_id': itemId,
        if (method != null) 'method': method,
      });
}

/// Mock analytics provider for development
class DebugAnalyticsProvider implements AnalyticsProvider {
  @override
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    print('Analytics:logEvent: $name ${parameters ?? {}}');
  }

  @override
  Future<void> setUserId(String? userId) async {
    print('Analytics:setUserId: $userId');
  }

  @override
  Future<void> setUserProperty(String name, String value) async {
    print('Analytics:setUserProperty: $name = $value');
  }

  @override
  Future<void> logScreenView(String screenName, {String? screenClass}) async {
    print('Analytics:logScreenView: $screenName');
  }
}
