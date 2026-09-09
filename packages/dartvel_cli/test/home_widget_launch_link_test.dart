// The URL each native half opens, held against the rule that reads it back.
//
// A home widget's tap is a link, and a link only works if the end that writes
// it and the end that resolves it agree. They are in three languages and two
// packages -- generated Java, generated Swift, and the Dart runtime that
// turns the URL into a route -- so nothing compiles them together and nothing
// on a device reports a mismatch. What a mismatch looks like is a widget
// somebody placed on their home screen opening the not-found page, or worse,
// opening the application's home screen, which reads as a widget that works.
//
// So these tests take the URL out of the generated source and ask the
// runtime's resolver what route it names. A literal would only prove the
// generator agrees with this file.
import 'package:dartvel_cli/src/build/android_home_widget.dart';
import 'package:dartvel_cli/src/build/apple_home_widget.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVHomeWidgetSpec _orderStatus = DVHomeWidgetSpec(
  id: 'order-status',
  name: 'OrderStatusWidget',
  route: '/widgets/order-status',
  title: 'Order status',
);

/// The first string literal after [opener] in [source].
String? _urlAfter(String source, String opener) {
  final int at = source.indexOf(opener);
  if (at < 0) return null;
  final RegExpMatch? match =
      RegExp('"([^"]*)"').firstMatch(source.substring(at));
  return match?.group(1);
}

void main() {
  test('the link an Android provider fires names the widget route', () {
    final String java =
        dvAndroidHomeWidgetProviderSource('com.example.app', _orderStatus);
    final String? url = _urlAfter(java, 'Uri.parse(');

    expect(url, isNotNull,
        reason: 'the provider has no URL to tap through to at all');
    expect(dvHomeWidgetRouteForLink(url!), _orderStatus.route);
  });

  test('the link a WidgetKit view hands back names the widget route', () {
    final String swift = dvAppleHomeWidgetSource(<DVHomeWidgetSpec>[
      _orderStatus,
    ], 'dartvel');
    final String? url = _urlAfter(swift, 'widgetURL(URL(string:');

    expect(url, isNotNull,
        reason: 'the widget view has no URL to tap through to at all');
    expect(dvHomeWidgetRouteForLink(url!), _orderStatus.route);
  });

  test('both platforms open the same link for the same widget', () {
    // Not a tidiness point. The application resolves one URL shape, so a
    // widget that works on Android and opens nothing on iOS would be found
    // by whoever happened to own both kinds of device.
    final String java =
        dvAndroidHomeWidgetProviderSource('com.example.app', _orderStatus);
    final String swift = dvAppleHomeWidgetSource(<DVHomeWidgetSpec>[
      _orderStatus,
    ], 'dartvel');

    expect(_urlAfter(java, 'Uri.parse('),
        _urlAfter(swift, 'widgetURL(URL(string:'));
  });
}
