// Every field in Studio can be typed into on the web.
//
// Studio's own text input is an EditableText, and on the web, with
// semantics on -- which a site that serves crawler text always has -- the
// engine draws each text field as an <input> and disables it unless the
// field says it is enabled. Material's TextField says so; Studio's input did
// not, so on dartvel.dev's Studio a click on "New page", a data model's name
// or any other Studio field focused nothing, and every key was lost.
import 'dart:ui' show Tristate;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("Studio's text input tells the platform it is enabled",
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioTextInput(
          value: '',
          placeholder: '/new-page',
          onChanged: (_) {},
        ),
      ),
    ));

    final SemanticsData field =
        tester.getSemantics(find.byType(EditableText)).getSemanticsData();
    expect(field.flagsCollection.isTextField, isTrue);
    expect(field.flagsCollection.isEnabled, Tristate.isTrue,
        reason: 'the web engine disables a text field that does not say it '
            'is enabled');
    semantics.dispose();
  });
}
