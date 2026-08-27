import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

void main() {
  runApp(createDartvelApp());
}

/// The site, in whichever appearance the visitor already prefers.
///
/// `ThemeMode.system` rather than a stored choice: a visitor who has set their
/// machine to dark has already answered the question, and handing them white
/// is the site overriding an answer it was given.
Widget createDartvelApp() => MaterialApp.router(
      title: 'Dartvel — Flutter, full stack',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      routerConfig: createDartvelRouter(),
    );

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0A0D13) : const Color(0xFFFFFFFF),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2F6BFF),
      brightness: brightness,
    ),
  );
}
