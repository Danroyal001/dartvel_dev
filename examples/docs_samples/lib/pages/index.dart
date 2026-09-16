import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start start-index-page
@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => DVBox.list(<Widget>[
      const DVText('Hello from Dartvel'),
      DVNavLink(to: DVRoutes.about, child: const DVText('About us')),
    ]);
// docs:end
