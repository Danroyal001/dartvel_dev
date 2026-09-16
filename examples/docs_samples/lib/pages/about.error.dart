// docs:start routing-error
// lib/pages/about.error.dart
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

class AboutPageError extends StatelessWidget {
  const AboutPageError({super.key});

  @override
  Widget build(BuildContext context) =>
      const DVText('This page could not load. Try again.');
}
// docs:end
