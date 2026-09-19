// docs:start routing-error
// lib/pages/about.error.dart
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVFunctionalWidget()
Widget _aboutPageError(BuildContext context) =>
    const DVText('That did not load');
// docs:end
