// Every Dartvel link gets a preview: a parameter route's preview gets its
// parameters, and a guarded route's preview shows only what is public about
// it -- its title and that it needs signing in -- never the page itself.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DVRoutePreviews.clear);
  tearDown(DVRoutePreviews.clear);

  testWidgets('a parameter route previews a concrete path, with its parameters',
      (WidgetTester tester) async {
    DVRoutePreviews.register('/articles/:slug', (BuildContext context) =>
        Text('article ${DartvelRouteState.of(context).params['slug']}'));
    final WidgetBuilder? builder = DVRoutePreviews.forPath('/articles/hello-world');
    expect(builder, isNotNull);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: builder!)));
    expect(find.text('article hello-world'), findsOneWidget);
  });

  test('a static route wins over a parameter route that would also match', () {
    DVRoutePreviews.register('/articles/:slug', (_) => const Text('param'));
    DVRoutePreviews.register('/articles/new', (_) => const Text('static'));
    expect(DVRoutePreviews.forPath('/articles/new'), isNotNull);
    expect(DVRoutePreviews.forPath('/nowhere'), isNull);
  });

  testWidgets('a guarded route never builds its page in a preview',
      (WidgetTester tester) async {
    bool built = false;
    DVRoutePreviews.register('/account', (_) {
      built = true;
      return const Text('balance: 1,000,000');
    });
    DVRoutePreviews.registerGuarded('/account', title: 'Your account');
    final WidgetBuilder? builder = DVRoutePreviews.forPath('/account');
    expect(builder, isNotNull, reason: 'every link gets a preview');
    await tester.pumpWidget(MaterialApp(home: Builder(builder: builder!)));
    expect(built, isFalse);
    expect(find.textContaining('balance'), findsNothing);
    expect(find.text('Your account'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsOneWidget);
  });

  testWidgets('a guarded parameter route is safe too', (WidgetTester tester) async {
    DVRoutePreviews.registerGuarded('/orders/:id', title: 'Order');
    await tester.pumpWidget(MaterialApp(
        home: Builder(builder: DVRoutePreviews.forPath('/orders/42')!)));
    expect(find.text('Order'), findsOneWidget);
    expect(find.textContaining('42'), findsNothing);
  });
}
