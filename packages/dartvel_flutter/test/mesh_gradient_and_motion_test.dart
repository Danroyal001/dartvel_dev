// Failing tests for new DVModifier primitives.
// These fail until the framework adds mesh-gradient background, pointer-following
// hover glow, and staggered revealOnScroll.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 1. Mesh / animated gradient background modifier.
  group('meshGradient', () {
    test('modifier exists and carries gradient colors', () {
      final DVModifier m = DVModifier()
          .meshGradient(<Color>[const Color(0xFF2F6BFF), const Color(0xFFFF6B6B)]);
      expect(m, isNotNull);
    });
  });

  // 2. Hover glow that follows pointer.
  group('hoverGlow', () {
    test('modifier exists and has glow parameters', () {
      final DVModifier m = DVModifier()
          .hoverGlow(color: const Color(0xFF7BA2FF), sigma: 18);
      expect(m, isNotNull);
    });
  });

  // 3. Stagger revealOnScroll.
  group('staggerReveal', () {
    test('revealOnScroll with stagger exists', () {
      final DVModifier m = DVModifier()
          .revealOnScroll(delay: const Duration(milliseconds: 120))
          .stagger(delay: const Duration(milliseconds: 200));
      expect(m, isNotNull);
    });
  });
}
