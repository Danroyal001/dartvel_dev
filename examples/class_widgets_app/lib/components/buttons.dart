import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

@DVFunctionalWidget()
@pragma('vm:entry-point')
Widget _button(String label, VoidCallback onPressed) => DVText(label).modifier(
      const DVModifier()
          .padding(12)
          .rounded(8)
          .backgroundColor(const Color(0xFF2563EB))
          .color(Colors.white)
          .onPressed(onPressed),
    );
