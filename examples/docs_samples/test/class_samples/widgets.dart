// The class alternative to each function-shaped widget on the docs site: an
// ordinary StatelessWidget, public because nothing is generated from it.
import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

// docs:start ui-functional-widget-class
// lib/components/price_tag.dart
class const PriceTag(final int cents, {super.key, final String currency = 'USD'})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      DVText('$currency ${(cents / 100).toStringAsFixed(2)}').modifier(
        const DVModifier().fontWeight(.w600),
      );
}

// Used anywhere as a widget: PriceTag(2499, currency: 'EUR')
// docs:end

// docs:start routing-loading-class
// lib/pages/about.loading.dart
class const AboutPageLoading({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const DVText('Loading');
}
// docs:end

// docs:start routing-error-class
// lib/pages/about.error.dart
class const AboutPageError({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const DVText('That did not load');
}
// docs:end

// docs:start devices-home-widget-class
// A widget class, with the annotation on it. The class is the widget, so
// NextShiftWidget is what the home screen and the route reach.
@DVHomeWidget(title: 'Next shift')
class const NextShiftWidget({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const DVBox.list(<Widget>[
        DVText('Next shift'),
        DVText('Thursday, 07:00'),
      ]);
}

// What the home screen shows, pushed from anywhere in the app.
Future<void> refreshShift(String when) =>
    DVHomeWidgets.publish('next-shift', when);
// docs:end

// docs:start offline-connectivity-class
// What the device can reach, as a signal: a banner is a widget that
// rebuilds, not a listener to remember to dispose.
class const ConnectionBanner({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final DVNetworkStatus status = DV.Platform.network.watch(context);
    if (status != DVNetworkStatus.offline) return const DVBox.list(<Widget>[]);
    return DVBox.list(<Widget>[
      const DVText('Offline. Your changes are saved here and will be sent.'),
      DVText('Since ${DV.Platform.network.since}'),
    ]);
  }
}
// docs:end
