import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

void main() {
  runApp(createDartvelApp());
}

Widget createDartvelApp() {
  return MaterialApp.router(
    title: 'Dartvel App',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    ),
    routerConfig: createDartvelRouter(),
  );
}
