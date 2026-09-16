// docs:start routing-layout
// lib/pages/_layout.dart wraps every page in lib/pages.
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

class Layout extends DartvelLayout {
  const Layout({super.key, required super.child});

  @override
  Widget build(BuildContext context) => DVBox.list(<Widget>[
        DVBox.row(<Widget>[
          DVNavLink(to: DVRoutes.index, child: const DVText('Home')),
          DVNavLink(to: DVRoutes.about, child: const DVText('About')),
        ], spacing: 16),
        Expanded(child: child),
      ]);
}
// docs:end
