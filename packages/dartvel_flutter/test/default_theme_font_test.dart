import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The family a [Text] is actually drawn in, after the theme's style is merged in.
String? drawnFamily(WidgetTester tester, String text) =>
    (tester.renderObject<RenderParagraph>(find.text(text)).text as TextSpan).style?.fontFamily;

void main() {
  test('the bundled Manrope is named by its asset path, with no package to pass on', () {
    final TextStyle body = dartvelDefaultTheme(Brightness.light).textTheme.bodyMedium!;
    expect(body.fontFamily, 'packages/dartvel_flutter/Manrope');
    expect(dartvelDefaultTheme(Brightness.dark, fontPackage: null).textTheme.bodyMedium!.fontFamily, 'Manrope');
  });

  testWidgets('a family a widget names is drawn as named, not under the theme font\'s package', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: dartvelDefaultTheme(Brightness.light),
      home: const Scaffold(
        body: Column(children: <Widget>[
          Text('themed'),
          Text('named', style: TextStyle(fontFamily: 'DejaVu Sans Mono')),
        ]),
      ),
    ));
    expect(drawnFamily(tester, 'themed'), 'packages/dartvel_flutter/Manrope');
    expect(drawnFamily(tester, 'named'), 'DejaVu Sans Mono');
  });
}
