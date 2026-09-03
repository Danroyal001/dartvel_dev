// The two facts launch negotiation needs from the machine: whether there is
// a display, and where the terminal runner is.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the terminal runner sits beside the GUI binary, named -cli', () {
    expect(dvTerminalRunnerPathFor('/opt/shop/bin/shop'), '/opt/shop/bin/shop-cli');
    expect(dvTerminalRunnerPathFor(r'C:\Program Files\Shop\shop.exe'), r'C:\Program Files\Shop\shop-cli.exe');
    expect(dvTerminalRunnerPathFor('/Applications/Shop.app/Contents/MacOS/shop'), '/Applications/Shop.app/Contents/MacOS/shop-cli');
  });

  test('a display is available where the environment names one', () {
    expect(dvDisplayAvailableIn(<String, String>{'DISPLAY': ':0'}, os: 'linux'), isTrue);
    expect(dvDisplayAvailableIn(<String, String>{'WAYLAND_DISPLAY': 'wayland-0'}, os: 'linux'), isTrue);
    expect(dvDisplayAvailableIn(<String, String>{}, os: 'linux'), isFalse);
    expect(dvDisplayAvailableIn(<String, String>{}, os: 'windows'), isTrue, reason: 'a desktop always has one');
    expect(dvDisplayAvailableIn(<String, String>{}, os: 'macos'), isTrue);
  });

  test('the process reads its own environment', () {
    expect(dvDisplayAvailable(), dvDisplayAvailableIn(Platform.environment, os: Platform.operatingSystem));
  });
}
