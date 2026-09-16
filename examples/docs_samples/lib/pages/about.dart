// docs:start routing-file-page
// lib/pages/about.dart is served at /about.
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'About us')
Widget _aboutPage(BuildContext context) => const DVBox.list(<Widget>[
      DVText('About us'),
      DVText('We make tools for Flutter teams.'),
    ]);
// docs:end
