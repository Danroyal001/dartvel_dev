import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

void main() {
  DV.Auth.configure(DVLocalAuthProvider());
  DV.AI.configure(const LocalDVAIAdapter());
  DV.Database.configure(MemoryDVDatabaseAdapter());
  Analytics.register(LocalAnalyticsProvider());
  GoRouter.optionURLReflectsImperativeAPIs = true;
  // Use path-based URLs on web (no hash)
  usePathUrlStrategy();
  runApp(createDartvelExampleApp());
}

Widget createDartvelExampleApp() {
  return ProviderScope(
    child: MaterialApp.router(
      title: 'Dartvel Example',
      routerConfig: createDartvelRouter(),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6750A4),
      ),
    ),
  );
}
