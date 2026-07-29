import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(
  title: 'About',
  showAppBar: true,
)
@pragma('vm:entry-point')
Widget _aboutPage(BuildContext context) => DVBox(
      const DVText('About'),
      const DVModifier().align(Alignment.center),
    );
