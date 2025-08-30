import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class Layout extends DartvelLayout {
  const Layout({super.key, required super.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ColoredBox(
              color: Color(0xFF222222),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.flutter_dash, color: Colors.white70),
                    SizedBox(width: 10),
                    Text('Dartvel Demo',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
