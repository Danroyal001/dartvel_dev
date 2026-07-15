import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

final showcaseCardStyle = const DVModifier()
    .card()
    .margin(8)
    .backgroundColor(const Color(0xFFF7F7FB));

final showcaseButtonStyle = const DVModifier()
    .padding(12)
    .rounded(8)
    .backgroundColor(const Color(0xFF111827))
    .color(Colors.white);

@DVFunctionalWidget()
Widget showcaseSection(String title, List<Widget> children) {
  return DVBox.list([
    DVText(title).modifier(
      const DVModifier().color(const Color(0xFF111827)).padding(4),
    ),
    ...children,
  ]).modifier(showcaseCardStyle);
}

@DVFunctionalWidget()
Widget showcaseButton(String label, FutureOr<void> Function() onPressed) {
  return DVText(label).modifier(
    showcaseButtonStyle.onPressed(() {
      unawaited(Future<void>.sync(onPressed));
    }),
  );
}

@DVFunctionalWidget()
Widget showcaseMetric(String label, String value) {
  return DVBox.list([
    DVText(label).modifier(const DVModifier().color(const Color(0xFF6B7280))),
    DVText(value).modifier(const DVModifier().color(const Color(0xFF111827))),
  ]).modifier(const DVModifier().padding(8).rounded(8));
}

@DVFunctionalWidget()
Widget featureCard(String title, String body) {
  return DVBox.list([
    DVText(title).modifier(const DVModifier().color(const Color(0xFF111827))),
    DVText(body).modifier(const DVModifier().color(const Color(0xFF4B5563))),
  ]).modifier(
    const DVModifier()
        .card()
        .backgroundColor(const Color(0xFFFFFFFF))
        .shadow([const BoxShadow(color: Color(0x14000000), blurRadius: 8)]),
  );
}
