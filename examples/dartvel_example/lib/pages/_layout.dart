import 'package:flutter/material.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

class Layout extends DartvelLayout {
  const Layout({super.key, required super.child});

  @override
  Widget build(BuildContext context) {
    return DVBox.list([
      ColoredBox(
        color: const Color(0xFF222222),
        child: DVBox.row([
          const Icon(Icons.flutter_dash, color: Colors.white70),
          const DVText('Dartvel Demo')
              .modifier(const DVModifier().color(Colors.white70)),
        ], spacing: 10)
            .modifier(
          const DVModifier().padding(10),
        ),
      ),
      Expanded(child: child),
    ]);
  }
}
