// What the site says about pairing is what the repository records.
//
// The home page told readers iOS "cannot pair yet" after the Dev client
// workflow had paired, hot restarted and hot reloaded a development build on
// an iOS simulator and a Linux desktop. A claim that falls behind the work is
// as wrong as one ahead of it, so the pages are read against the Dev Client
// entry in docs/spec-status.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String devClient = () {
    for (final Object? entry
        in (jsonDecode(File('../../docs/spec-status.json').readAsStringSync())
                as Map<String, Object?>)['sections']!
            as List<Object?>) {
      if (entry is Map && entry['section'] == 'Dev Client') {
        return '${entry['absent']}';
      }
    }
    throw StateError('no Dev Client entry');
  }();
  final Map<String, String> pages = <String, String>{
    for (final String page in <String>['index', 'features'])
      page: File('lib/pages/$page.dart').readAsStringSync(),
  };

  test('the repository records iOS simulator and Linux pairing', () {
    expect(devClient, contains('on an iOS simulator'));
    expect(devClient, contains('on a Linux desktop'));
  });

  test('no page says iOS cannot pair', () {
    for (final MapEntry<String, String> page in pages.entries) {
      expect(page.value, isNot(contains('cannot pair')), reason: page.key);
      expect(page.value, isNot(contains('pairing on iOS.')), reason: page.key);
    }
  });

  test('the iPhone answer names what pairs and how a phone pairs', () {
    final String home = pages['index']!;
    expect(home, contains('iOS simulator'));
    expect(home, contains('Linux'));
    expect(home, contains('Xcode'));
  });
}
