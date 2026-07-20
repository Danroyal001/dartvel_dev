import 'package:class_widgets_app/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(
  title: 'Dartvel',
  showAppBar: true,
  centerTitle: true,
)
class IndexPage extends DVClassWidget {
  const IndexPage({super.key});

  @override
  Future<Object?> loadData(
      Map<String, String> params, Map<String, String> query) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return <String, String>{'timestamp': DateTime.now().toIso8601String()};
  }

  @override
  Widget build(BuildContext context) {
    final data = DvDataScope.of(context).data as Map<String, String>?;

    return DVBox.list([
      const DVText('Welcome to Dartvel (Class Widgets)'),
      const Icon(Icons.rocket_launch, size: 64, color: Colors.blue),
      const DVText('Your Class-Based Dartvel app is ready!')
          .modifier(_titleStyle),
      DVText('Loaded at: ${data?['timestamp'] ?? 'N/A'}'),
      DVBox.wrapLine([
        Button('Docs', () {}),
        Button('GitHub', () {}),
      ], spacing: 12),
    ]).modifier(
      const DVModifier().padding(24).align(Alignment.center),
    );
  }
}

final _titleStyle = const DVModifier()
    .color(const Color(0xFF111827))
    .padding(8)
    .backgroundColor(const Color(0xFFEFF6FF))
    .rounded(8);
