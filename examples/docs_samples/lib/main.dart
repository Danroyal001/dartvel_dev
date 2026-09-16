import 'package:flutter/material.dart';

import 'dartvel_client/dartvel_client.dart';
import 'services/setup.dart';

void main() {
  configureServices();
  runApp(createDocsSamplesApp());
}

Widget createDocsSamplesApp() => MaterialApp.router(
      title: 'Docs samples',
      routerConfig: createDartvelRouter(),
    );
