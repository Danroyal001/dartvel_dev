import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

final showcaseCardStyle = const DVModifier()
    .card()
    .margin(10)
    .padding(20)
    .rounded(24)
    .backgroundColor(const Color(0xFFFFFFFF))
    .shadow([const BoxShadow(color: Color(0x18000000), blurRadius: 18)]);

final showcaseButtonStyle = const DVModifier()
    .padding(13)
    .rounded(999)
    .backgroundColor(const Color(0xFF4F378B))
    .color(Colors.white)
    .fontWeight(FontWeight.w700);

final showcaseTitleStyle = const DVModifier()
    .padding(10)
    .rounded(12)
    .backgroundColor(const Color(0xFFFFD8E4))
    .color(const Color(0xFF31111D))
    .fontSize(18)
    .fontWeight(FontWeight.w800);

final showcaseMetricStyle = const DVModifier()
    .padding(14)
    .rounded(18)
    .backgroundColor(const Color(0xFFF7F2FA))
    .shadow([const BoxShadow(color: Color(0x0F000000), blurRadius: 10)]);

final showcaseMetricLabelStyle = const DVModifier()
    .color(const Color(0xFF625B71))
    .fontSize(12)
    .fontWeight(FontWeight.w700);

final showcaseMetricValueStyle = const DVModifier()
    .color(const Color(0xFF1D1B20))
    .fontSize(16)
    .fontWeight(FontWeight.w800);

final showcaseBodyStyle = const DVModifier()
    .color(const Color(0xFF49454F))
    .fontSize(14)
    .fontWeight(FontWeight.w500);

@DVFunctionalWidget()
Widget showcaseSection(String title, List<Widget> children) {
  return DVBox.list([
    DVText(title).modifier(showcaseTitleStyle),
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
    DVText(label).modifier(showcaseMetricLabelStyle),
    DVText(value).modifier(showcaseMetricValueStyle),
  ]).modifier(showcaseMetricStyle);
}

@DVFunctionalWidget()
Widget featureCard(String title, String body) {
  return DVBox.list([
    DVText(title).modifier(
      const DVModifier()
          .color(const Color(0xFF1D1B20))
          .fontSize(15)
          .fontWeight(FontWeight.w800),
    ),
    DVText(body).modifier(showcaseBodyStyle),
  ]).modifier(
    const DVModifier()
        .card()
        .rounded(20)
        .backgroundColor(const Color(0xFFFFFFFF))
        .shadow([const BoxShadow(color: Color(0x12000000), blurRadius: 14)]),
  );
}

@DVFunctionalWidget()
Widget showcaseHero(String platform, String deviceType, String backend) {
  return DVBox.list([
    const DVText('Dartvel Platform Showcase').modifier(
      const DVModifier()
          .color(const Color(0xFFFFFFFF))
          .fontSize(30)
          .fontWeight(FontWeight.w900)
          .padding(4),
    ),
    const DVText(
      'A generated full-stack Flutter app exercising routing, API clients, native bindings, services, AI, and observability.',
    ).modifier(
      const DVModifier()
          .color(const Color(0xFFF6EDFF))
          .fontSize(15)
          .fontWeight(FontWeight.w600)
          .padding(4),
    ),
    DVBox.wrapLine([
      showcaseMetric('Platform', platform),
      showcaseMetric('Device', deviceType),
      showcaseMetric('Backend', backend),
    ]),
  ]).modifier(
    const DVModifier()
        .padding(26)
        .rounded(30)
        .backgroundColor(const Color(0xFF4F378B))
        .shadow([const BoxShadow(color: Color(0x334F378B), blurRadius: 28)]),
  );
}
