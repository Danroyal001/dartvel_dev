import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An icon control is a DVBox around an Icon with .tooltip() and .onTap():
/// it takes its own size and a 48-point tap target, never what it is offered.
/// As a text field's suffix the old icon button grew to the whole field, put
/// the eye in the middle and pushed the label out (Dartvel Authenticator).
Widget eye() => DVBox(
      const Icon(Icons.visibility_outlined),
      DVModifier().tooltip('Show the password').onTap(() {}).minimumTapTarget(width: 48, height: 48),
    );

void main() {
  testWidgets('as a suffix icon it stays small and the label shows', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: TextField(decoration: InputDecoration(labelText: 'Master password', suffixIcon: eye())),
        ),
      ),
    ));
    final Finder control = find.byType(DVBox).first;
    expect(tester.getSize(control).width, lessThanOrEqualTo(48));
    expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
    expect(tester.getTopLeft(control).dx, greaterThan(300));
    expect(tester.getSize(find.text('Master password')).width, greaterThan(0));
  });

  testWidgets('in a row it does not take the free space', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Row(children: <Widget>[eye(), const Text('beside')])),
    ));
    expect(tester.getSize(find.byType(DVBox).first).width, 48);
  });
}
