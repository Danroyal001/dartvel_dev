// A price on a page exports as a price.
//
// The export writes each text node as a single-quoted Dart literal and escaped
// only backslashes and quotes. A dollar sign starts an interpolation, so a
// card reading "$18.50" exported as `const DVText('$18.50')`, which does not
// compile; and a text with a line break in it ran the literal over two lines,
// which does not compile either. The export exists so the result is code
// somebody can keep, and a menu page is exactly where prices appear.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

String exportOf(String text) {
  final DVPageDocument document = DVPageDocument(route: '/menu', title: 'Menu');
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document.toDartSource();
}

void main() {
  test('a dollar sign is escaped', () {
    final String source = exportOf(r'$18.50');
    expect(source, contains(r"DVText('\$18.50')"));
    expect(source, isNot(contains(r"DVText('$18.50')")));
  });

  test('a line break stays inside the literal', () {
    final String source = exportOf('Open daily\nfrom 7am');
    expect(source, contains(r"DVText('Open daily\nfrom 7am')"));
  });

  test('a font family with a dollar sign is escaped as well', () {
    final DVPageDocument document = DVPageDocument(route: '/menu', title: 'Menu');
    DVPageDocumentEditor(document).insert(
        DVPageNode.text('x').withProperty('fontFamily', r'Brand$Sans'),
        parent: document.root.id);
    expect(document.toDartSource(), contains(r".fontFamily('Brand\$Sans')"));
  });
}
