// A layer that takes the room its siblings leave, in a page document.
//
// DVModifier.fill() exists in code, so a page built in Studio must be able to
// say it too and export it, or the same design differs between the two.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the fill flag applies fill() and exports it', () {
    final DVStudioProperty fill =
        dvStudioProperties.firstWhere((DVStudioProperty p) => p.name == 'fill');
    expect(fill.kind, DVStudioPropertyKind.flag);
    expect(fill.apply(const DVModifier(), true, const <String, Object?>{})?.fillValue, isTrue);
    expect(fill.apply(const DVModifier(), false, const <String, Object?>{}), isNull);
    expect(fill.source(true, const <String, Object?>{}), '.fill()');
    expect(fill.source(false, const <String, Object?>{}), isNull);
  });
}
