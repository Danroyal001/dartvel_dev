// The link a home widget's tap carries, and the route it names.
//
// The specification says a home widget can launch and navigate to a page in
// the application. Launching was built on both platforms: Android's provider
// fires a PendingIntent at a `dartvel://` URL and WidgetKit hands the same
// shape of URL to the containing app. Navigating was not, and the reason is
// the shape of the URL rather than anything missing at the far end -- the
// route is carried in the path under a host that says what kind of link this
// is, and the general rule for a `dartvel://` link folds the host back into
// the path. `dartvel://widget/widgets/order-status` came out as
// `/widget/widgets/order-status`, which no router has.
//
// So the URL is written in one place and read back in one place, and these
// hold the two against each other. A widget somebody has put on their home
// screen taps once and either lands on its page or lands on the not-found
// page, and nothing anywhere reports which.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('the link a widget is given resolves back to the widget route',
      () {
    // The round trip, through the same two functions the build and the
    // runtime use. Written this way rather than against a literal URL
    // because a literal proves the functions agree with the test, and what
    // matters is that they agree with each other.
    final String route = dvHomeWidgetRoute('order-status');
    final String link = dvHomeWidgetLaunchUrl('dartvel', route);

    expect(dvHomeWidgetRouteForLink(link), route);
  });

  test('an ordinary deep link is not read as a widget launch', () {
    // The host is what separates them. Without this check every
    // `dartvel://` link would lose its first path segment on the way to the
    // router, which is a page opening at the wrong place rather than not
    // opening at all -- the harder of the two to notice.
    expect(dvHomeWidgetRouteForLink('dartvel://orders/42'), isNull);
    expect(dvHomeWidgetRouteForLink('https://example.com/widgets/steps'),
        isNull);
    expect(dvHomeWidgetRouteForLink('/widgets/steps'), isNull);
  });

  test('a widget link with nothing after the host names no route', () {
    // `dartvel://widget` and `dartvel://widget/widgets/` are what a
    // half-written URL looks like. Answering with `/widgets/` would send the
    // application to a route that matches no widget and looks like a widget
    // that was removed.
    expect(dvHomeWidgetRouteForLink('dartvel://widget'), isNull);
    expect(dvHomeWidgetRouteForLink('dartvel://widget/widgets/'), isNull);
    expect(dvHomeWidgetRouteForLink('dartvel://widget/orders/42'), isNull);
  });
}
