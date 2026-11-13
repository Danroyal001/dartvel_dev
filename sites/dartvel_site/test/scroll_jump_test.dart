// The site's long pages -- the docs index, Features, the CLI reference -- have
// the "To the bottom / Back to top" button, from the layout's `pageScroll`
// attribute. The button's own behaviour is the framework's
// (dartvel_flutter/test/page_scroll_test.dart).
import 'package:dartvel_site/pages/_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the layout turns the long-page button on for every page', () {
    expect(const Layout(child: SizedBox()).pageScroll, isTrue);
  });
}
