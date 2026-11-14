/// Google Analytics 4 for Dartvel applications.
///
/// Mounted in `pubspec.yaml` and reached as `DV.Modules.googleAnalytics`:
///
/// ```yaml
/// dartvel:
///   modules:
///     googleAnalytics:
///       package: dartvel_google_analytics
///       backendPolicy: public
///       config:
///         measurementId: G-XXXXXXXXXX
/// ```
///
/// Page views are reported by themselves, on the first page and on every
/// route change. Events are one call each:
///
/// ```dart
/// DV.Modules.googleAnalytics.generateLead(leadSource: 'contact form');
/// ```
///
/// See the package's README for every setting and what is sent where.
library;

import 'package:dartvel_core/dartvel.dart';

import 'src/config.dart';
import 'src/consent.dart';
import 'src/events.dart';
import 'src/runtime.dart';

export 'src/config.dart';
export 'src/events.dart';
export 'src/measurement_protocol.dart';

/// Starts the module: `dartvel.module.start`, called by the generated
/// client and the generated server once the module is registered.
///
/// Settings that cannot be read are reported and leave the module
/// unconfigured, which is to say doing nothing: a mistake in a pubspec must
/// not stop an application starting.
void startGoogleAnalytics(DVModule module) {
  final GoogleAnalyticsRuntime runtime = GoogleAnalyticsRuntime.instance;
  runtime.moduleId = module.id;
  final Object? settings = module.config['config'];
  if (settings is Map) {
    try {
      runtime.config = GoogleAnalyticsConfig.fromModuleConfig(<String, Object?>{
        for (final MapEntry<Object?, Object?> e in settings.entries)
          '${e.key}': e.value,
      });
    } on ArgumentError catch (error) {
      const DVLog().error('${error.message}', tag: 'googleAnalytics');
    }
  }
  // Where Flutter serves a mounted package's assets from.
  final String asset = module.asset('assets/google_analytics.js');
  runtime.scriptUrl = asset.contains('packages/')
      ? 'assets/$asset'
      : GoogleAnalyticsRuntime.defaultScriptUrl;

  dvModuleRegistry.subscribe(
      GoogleAnalyticsRuntime.purchaseTopic, runtime.purchaseConfirmed);
  if (runtime.environment == DVModuleEnvironment.backend) return;

  dvModuleRegistry.subscribe(
      GoogleAnalyticsRuntime.contextTopic, runtime.contributeContext);
  DVPageViews.addListener((DVPageView view) => runtime.pageShown(view));
  dvGoogleAnalyticsOnConsent(() => runtime.consentChanged());
}

/// `DV.Modules.googleAnalytics`.
///
/// Every method is safe to call anywhere and at any time: with no
/// measurement id configured, before consent, with Google's tag blocked or
/// the network down, it does nothing and does not throw.
final class GoogleAnalytics {
  const GoogleAnalytics();

  GoogleAnalyticsRuntime get _runtime => GoogleAnalyticsRuntime.instance;

  /// Whether a measurement id is configured. When it is not, nothing is
  /// sent.
  bool get isConfigured => _runtime.config.isConfigured;

  /// Sets the module up in code instead of, or on top of, the mount's
  /// `config:`. The same settings either way.
  void configure(GoogleAnalyticsConfig config) => _runtime.config = config;

  /// Names the visitor: [userId] for the signed-in person, [clientId] for a
  /// device's install, which has no tag to give it one.
  void identify({String? clientId, String? userId}) =>
      _runtime.identify(clientId: clientId, userId: userId);

  /// Reports a page view by hand.
  ///
  /// Not something an application calls for a route: the module reports the
  /// first page and every route change itself. Here for a view that is not
  /// a route, such as a step inside a single page.
  Future<void> pageView({String? location, String? title}) => _runtime
      .track(GoogleAnalyticsEvent.pageView(location: location, title: title));

  /// Reports [event]. On the backend, [clientId] says which visitor it is
  /// about and is required.
  Future<void> track(
    GoogleAnalyticsEvent event, {
    String? clientId,
    String? userId,
    String? sessionId,
  }) =>
      _runtime.track(event,
          clientId: clientId, userId: userId, sessionId: sessionId);

  /// `generate_lead`: somebody left their details, or got in touch.
  Future<void> generateLead({
    num? value,
    String? currency,
    String? leadSource,
    String? clientId,
  }) =>
      _runtime.track(
        GoogleAnalyticsEvent.generateLead(
            value: value, currency: currency, leadSource: leadSource),
        clientId: clientId,
      );

  /// `begin_checkout`: a checkout was started.
  Future<void> beginCheckout({
    num? value,
    String? currency,
    String? coupon,
    List<GoogleAnalyticsItem> items = const <GoogleAnalyticsItem>[],
    String? clientId,
  }) =>
      _runtime.track(
        GoogleAnalyticsEvent.beginCheckout(
            value: value, currency: currency, coupon: coupon, items: items),
        clientId: clientId,
      );

  /// `purchase`.
  ///
  /// With a store module mounted this is not something to call: the store
  /// reports a purchase when the payment is confirmed, and this module
  /// hears it on the backend. Calling it as well counts the purchase twice.
  Future<void> purchase({
    required String transactionId,
    required num value,
    required String currency,
    num? tax,
    num? shipping,
    String? coupon,
    List<GoogleAnalyticsItem> items = const <GoogleAnalyticsItem>[],
    String? clientId,
  }) =>
      _runtime.track(
        GoogleAnalyticsEvent.purchase(
          transactionId: transactionId,
          value: value,
          currency: currency,
          tax: tax,
          shipping: shipping,
          coupon: coupon,
          items: items,
        ),
        clientId: clientId,
      );

  /// `view_item`: a product or plan was looked at.
  Future<void> viewItem({
    num? value,
    String? currency,
    List<GoogleAnalyticsItem> items = const <GoogleAnalyticsItem>[],
    String? clientId,
  }) =>
      _runtime.track(
        GoogleAnalyticsEvent.viewItem(
            value: value, currency: currency, items: items),
        clientId: clientId,
      );

  /// `sign_up`.
  Future<void> signUp({String? method, String? clientId}) => _runtime
      .track(GoogleAnalyticsEvent.signUp(method: method), clientId: clientId);

  /// `login`.
  Future<void> login({String? method, String? clientId}) => _runtime
      .track(GoogleAnalyticsEvent.login(method: method), clientId: clientId);
}
