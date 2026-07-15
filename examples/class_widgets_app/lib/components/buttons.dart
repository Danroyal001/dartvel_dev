import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

final appButtonStyle = const DVModifier()
    .padding(12)
    .rounded(8)
    .backgroundColor(const Color(0xFF2563EB))
    .color(Colors.white);

@DVFunctionalWidget()
Widget button(String label, VoidCallback onPressed) {
  return DVText(label).modifier(appButtonStyle.onPressed(onPressed));
}
