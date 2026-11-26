// The SSR-first theme (the app's look for a page the build could not
// capture) is worked out from every captured page: one layout per page, 26
// seconds on one core for a site of 225 routes. Worked out a page per
// isolate, it must be byte for byte the shell the one-core pass writes.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/ssr_first_capture.dart';
import 'package:test/test.dart';

Map<String, Object?> _text(String text, List<num> rect, {String colour = '#111111', num size = 16, int weight = 400}) =>
    <String, Object?>{
      'k': 't', 'r': rect, 'z': 1, 's': true, 'text': text,
      'runs': <Map<String, Object?>>[
        <String, Object?>{'t': text, 'f': 'Inter', 'fs': size, 'fw': weight, 'c': colour},
      ],
      'al': 'left', 'lines': 1, 'lh': size * 1.5,
    };

Map<String, Object?> _width(int width, int gutter, String ink) {
  List<Map<String, Object?>> items(String colour) => <Map<String, Object?>>[
        _text('Heading of the page', <num>[gutter, 90, width - 2 * gutter, 48], size: 32, weight: 700, colour: colour),
        _text('A paragraph that says what the page is about.', <num>[gutter, 170, width - 2 * gutter, 48], colour: colour),
        _text('A section', <num>[gutter, 260, 200, 30], size: 22, weight: 600, colour: colour),
        _text('More words in the section.', <num>[gutter, 306, 300, 24], colour: colour),
      ];
  return <String, Object?>{
    'width': width, 'height': 800,
    'light': <String, Object?>{'width': width, 'height': 800, 'items': items(ink)},
    'dark': <String, Object?>{'width': width, 'height': 800, 'items': items('#f0f0f0')},
    'controls': const <Object?>[],
  };
}

const String _doc = '<h1>Heading of the page</h1>\n<p>A paragraph that says what the page is about.</p>\n'
    '<h2>A section</h2>\n<p>More words in the section.</p>\n';

void main() {
  test('the theme worked out a page per isolate is the shell the one-core pass writes', () async {
    final Directory root = Directory.systemTemp.createTempSync('theme_parallel');
    addTearDown(() => root.deleteSync(recursive: true));
    final Map<String, String> pages = <String, String>{};
    for (int index = 0; index < 9; index++) {
      final String route = index == 0 ? '/' : '/page-$index';
      pages[route] = _doc;
      // One page has no capture at all and one a capture with no widths:
      // both are skipped, and the first page with widths sets the styler.
      if (index == 4) continue;
      File(dvLayoutCapturePathFor(root.path, route))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'widths': index == 0
              ? <Object?>[]
              : <Object?>[_width(390, 16 + index, '#1a1410'), _width(1366, 120 + 7 * index, '#1a1410')],
        }));
    }
    const String shell = '<!DOCTYPE html><html><head><title>t</title></head><body></body></html>';
    final String sequential = dvWithSsrFirstTheme(root.path, shell, pages, const {});
    expect(sequential, contains('dv-ssr-theme'), reason: 'the fixture has to produce a theme to compare');
    for (final int workers in <int>[1, 2, 4]) {
      expect(await dvWithSsrFirstThemeInParallel(root.path, shell, pages, const {}, workers: workers), sequential);
    }
  });
}
