import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

part 'about.page.dartvel.g.dart';

@DVPage(
  title: 'About',
  showAppBar: true,
)
class _AboutPage extends DVClassWidget {
  const _AboutPage({super.key});

  @override
  Future<Object?> loadData(
      Map<String, String> params, Map<String, String> query) async {
    return 'About Page Data';
  }

  @override
  Widget build(BuildContext context) {
    return DVBox(
      const DVText('About'),
      const DVModifier().align(Alignment.center),
    );
  }
}
