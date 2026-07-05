import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:dartvel_core/dartvel.dart';

@DVPage()
class AboutPage extends DVClassWidget {
  const AboutPage({super.key});

  @override
  Future<Object?> loadData(
      Map<String, String> params, Map<String, String> query) async {
    return 'About Page Data';
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('About')),
    );
  }
}
