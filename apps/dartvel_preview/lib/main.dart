import 'package:flutter/material.dart';

import 'components/preview_launch.dart';
import 'dartvel_client/dartvel_client.dart';

void main(List<String> arguments) async {
  await negotiateDartvelLaunch(arguments);
  // A link Preview was started with: a desktop launch argument, or ?open=
  // on the address a browser loaded it from.
  previewLaunchLink = previewLinkFromArguments(arguments) ??
      Uri.base.queryParameters['open'];
  runApp(createDartvelApp());
}

Widget createDartvelApp() {
  return MaterialApp.router(
    title: 'Dartvel Preview',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6BFF),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    routerConfig: createDartvelRouter(),
  );
}
