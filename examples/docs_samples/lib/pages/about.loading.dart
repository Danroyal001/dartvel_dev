// docs:start routing-loading
// lib/pages/about.loading.dart
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

class AboutPageLoading extends StatelessWidget {
  const AboutPageLoading({super.key});

  @override
  Widget build(BuildContext context) => const DVText('Loading');
}
// docs:end
