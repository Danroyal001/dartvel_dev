/// Meta (Facebook) Pixel for Dartvel applications.
///
/// Mounted in `pubspec.yaml` and reached as `DV.Modules.metaPixel`:
///
/// ```yaml
/// dartvel:
///   modules:
///     metaPixel:
///       package: dartvel_meta_pixel
///       backendPolicy: public
///       config:
///         pixelId: "1234567890"
/// ```
///
/// Page views are reported by themselves, on the first page and on every
/// route change. Events are one call each:
///
/// ```dart
/// DV.Modules.metaPixel.lead(contentName: 'Callback form');
/// DV.Modules.metaPixel.outboundClick(Uri.parse('https://wa.me/2348030000000'));
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
export 'src/conversions_api.dart';
export 'src/events.dart';

/// Starts the module: `dartvel.module.start`, called by the generated
/// client and the generated server once the module is registered.
///
/// Reads the settings the application gave at the mount, then begins
/// listening -- in a client for page views and consent, on the backend for
/// purchases another module confirms. Settings that cannot be read are
/// reported and leave the module unconfigured, which is to say doing
/// nothing: a mistake in a pubspec must not stop an application starting.
void startMetaPixel(DVModule module) {
  final MetaPixelRuntime runtime = MetaPixelRuntime.instance;
  runtime.moduleId = module.id;
  final Object? settings = module.config['config'];
  if (settings is Map) {
    try {
      runtime.config = MetaPixelConfig.fromModuleConfig(<String, Object?>{
        for (final MapEntry<Object?, Object?> e in settings.entries)
          '${e.key}': e.value,
      });
    } on ArgumentError catch (error) {
      const DVLog().error('${error.message}', tag: 'metaPixel');
    }
  }
  // Where Flutter serves a mounted package's assets from.
  runtime.scriptUrl = 'assets/${module.asset('assets/meta_pixel.js')}';
  if (!runtime.scriptUrl.contains('packages/')) {
    runtime.scriptUrl = MetaPixelRuntime.defaultScriptUrl;
  }

  dvModuleRegistry.subscribe(
      MetaPixelRuntime.purchaseTopic, runtime.purchaseConfirmed);
  if (runtime.environment == DVModuleEnvironment.backend) return;

  dvModuleRegistry.subscribe(
      MetaPixelRuntime.contextTopic, runtime.contributeContext);
  DVPageViews.addListener((DVPageView view) => runtime.pageShown(view));
  dvMetaPixelOnConsent(() => runtime.consentChanged());
}

/// `DV.Modules.metaPixel`.
///
/// Every method is safe to call anywhere and at any time: with no pixel id
/// configured, before consent, with the pixel's script blocked or the
/// network down, it does nothing and does not throw.
final class MetaPixel {
  const MetaPixel();

  MetaPixelRuntime get _runtime => MetaPixelRuntime.instance;

  /// Whether a pixel id is configured. When it is not, nothing is sent.
  bool get isConfigured => _runtime.config.isConfigured;

  /// Sets the module up in code instead of, or on top of, the mount's
  /// `config:`. The same settings either way.
  void configure(MetaPixelConfig config) => _runtime.config = config;

  /// Reports a page view for the page on screen.
  ///
  /// Not something an application calls: the module reports the first page
  /// and every route change itself. Here for a view that is not a route,
  /// such as a step inside a single page.
  Future<void> pageView() => _runtime.track(MetaPixelEvent.pageView());

  /// Reports [event], a standard or custom one.
  ///
  /// [eventId] is what Meta de-duplicates on; leave it out and each call
  /// gets a new one, shared by the browser's event and the server's. On the
  /// backend there is no page, so say who with [user] and where with
  /// [sourceUrl].
  Future<void> track(
    MetaPixelEvent event, {
    String? eventId,
    MetaUserData? user,
    Uri? sourceUrl,
  }) =>
      _runtime.track(event, eventId: eventId, user: user, sourceUrl: sourceUrl);

  /// Reports a custom event: a name of up to 50 characters and its own
  /// parameters.
  Future<void> trackCustom(
    String name, {
    Map<String, Object?> data = const <String, Object?>{},
    String? eventId,
  }) =>
      _runtime.track(MetaPixelEvent.custom(name, data: data), eventId: eventId);

  /// `ViewContent`: a visit to a page that matters.
  Future<void> viewContent({
    String? contentName,
    String? contentCategory,
    List<String>? contentIds,
    String? contentType,
    num? value,
    String? currency,
  }) =>
      _runtime.track(MetaPixelEvent.viewContent(
        contentName: contentName,
        contentCategory: contentCategory,
        contentIds: contentIds,
        contentType: contentType,
        value: value,
        currency: currency,
      ));

  /// `Lead`: somebody left their details.
  Future<void> lead({
    String? contentName,
    String? contentCategory,
    num? value,
    String? currency,
  }) =>
      _runtime.track(MetaPixelEvent.lead(
        contentName: contentName,
        contentCategory: contentCategory,
        value: value,
        currency: currency,
      ));

  /// `Contact`: somebody got in touch.
  Future<void> contact() => _runtime.track(MetaPixelEvent.contact());

  /// `InitiateCheckout`: a checkout was started.
  Future<void> initiateCheckout({
    num? value,
    String? currency,
    int? numItems,
    List<String>? contentIds,
    List<MetaPixelContent>? contents,
  }) =>
      _runtime.track(MetaPixelEvent.initiateCheckout(
        value: value,
        currency: currency,
        numItems: numItems,
        contentIds: contentIds,
        contents: contents,
      ));

  /// `Purchase`, with the value and currency Meta requires.
  ///
  /// With a store module mounted this is not something to call: the store
  /// reports a purchase when the payment is confirmed, and this module
  /// hears it. Give [eventId] the order's own id when calling it by hand,
  /// so the same purchase reported twice is counted once.
  Future<void> purchase({
    required num value,
    required String currency,
    String? eventId,
    List<String>? contentIds,
    List<MetaPixelContent>? contents,
    String? contentType,
    int? numItems,
    MetaUserData? user,
    Uri? sourceUrl,
  }) =>
      _runtime.track(
        MetaPixelEvent.purchase(
          value: value,
          currency: currency,
          contentIds: contentIds,
          contents: contents,
          contentType: contentType,
          numItems: numItems,
        ),
        eventId: eventId,
        user: user,
        sourceUrl: sourceUrl,
      );

  /// A tap on a link that leaves the application. A WhatsApp link, a phone
  /// number or an email address is a `Contact`; pass [event] to report it as
  /// something else; any other link is a custom `OutboundClick`.
  ///
  /// Call it from the tap, before or beside opening the link:
  ///
  /// ```dart
  /// .onTap(() {
  ///   DV.Modules.metaPixel.outboundClick(whatsApp);
  ///   openLink(whatsApp);   // however the application opens a link
  /// })
  /// ```
  Future<void> outboundClick(Uri destination, {MetaPixelEvent? event}) =>
      _runtime.outboundClick(destination, event: event);
}
