import 'package:basic_app/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage()
@DVFunctionalWidget()
Widget indexPage(BuildContext context) {
  final data = DvDataScope.of(context).data as Map<String, String>?;

  return DVBox.list([
    const DVText('Welcome to Dartvel'),
    const Icon(Icons.rocket_launch, size: 64, color: Colors.blue),
    const DVText('Your Dartvel app is ready!').modifier(_titleStyle),
    DVText('Loaded at: ${data?['timestamp'] ?? 'N/A'}'),
    DVBox.wrap([
      Button('Docs', () {}),
      Button('GitHub', () {}),
    ], spacing: 12),
  ]).modifier(
    const DVModifier().padding(24).align(Alignment.center),
  );
}

final _titleStyle = const DVModifier()
    .color(const Color(0xFF111827))
    .padding(8)
    .backgroundColor(const Color(0xFFEFF6FF))
    .rounded(8);
