import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';

void main() {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  // Use path-based URLs on web (no hash)
  usePathUrlStrategy();
  runApp(createDartvelExampleApp());
}

void configureDartvelExample() {
  DV.Auth.configure(DVLocalAuthProvider());
  DV.AI.configure(const LocalDVAIAdapter());
  DV.Database.configure(MemoryDVDatabaseAdapter());
  DV.Notifications.register(DVMemoryNotificationProvider());
  DV.Notifications.mail.useProvider(DVMemoryMailProvider());
  DV.global<String>('showcase-ready');
  Analytics.register(LocalAnalyticsProvider());
}

Widget createDartvelExampleApp() {
  configureDartvelExample();
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
