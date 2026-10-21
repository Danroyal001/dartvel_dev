// The browser's DVWindowHost renders its home in the page's one view.
@TestOn('vm')
library;

import 'package:dartvel_windowing/src/windowing_web.dart' as web;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders its home under runWidget, which needs a View', (WidgetTester tester) async {
    await tester.pumpWidget(
      web.DVWindowHost(
        home: const Directionality(textDirection: TextDirection.ltr, child: Text('the desk')),
        routeBuilder: (BuildContext context, _) => const SizedBox(),
      ),
      wrapWithView: false,
    );
    expect(find.text('the desk'), findsOneWidget);
  });
}
