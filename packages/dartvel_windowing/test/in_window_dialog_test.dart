// showInWindowDialog: a dialog in front of the window that asked for it.
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens in the same view, answers with what it was popped with',
      (WidgetTester tester) async {
    late BuildContext asker;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (BuildContext context) {
        asker = context;
        return const SizedBox();
      }),
    ));
    final Future<String?> answer = showInWindowDialog<String>(
      context: asker,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Leave this project?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop('leave'), child: const Text('Leave')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Leave this project?'), findsOneWidget);
    expect(tester.getSize(find.byType(AlertDialog)).width, greaterThan(250));
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(await answer, 'leave');
  });
}
