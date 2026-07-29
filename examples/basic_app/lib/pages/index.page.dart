import 'package:basic_app/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(title: 'Dartvel', showAppBar: true, centerTitle: true)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => DVBox.list([
      const DVText('Welcome to Dartvel'),
      const Icon(Icons.rocket_launch, size: 64, color: Colors.blue),
      const DVText('Your Dartvel app is ready!').modifier(titleStyle),
      DVText(
        'Loaded at: ${(DvDataScope.of(context).data as Map<String, String>?)?['timestamp'] ?? 'N/A'}',
      ),
      DVBox.wrapLine([Button('Docs', () {}), Button('GitHub', () {})],
          spacing: 12),
    ]).modifier(const DVModifier().padding(24).align(Alignment.center));

final titleStyle = const DVModifier()
    .color(const Color(0xFF111827))
    .padding(8)
    .backgroundColor(const Color(0xFFEFF6FF))
    .rounded(8);
