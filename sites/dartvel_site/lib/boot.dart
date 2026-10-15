import 'package:flutter/material.dart';

import 'dartvel_client/dartvel_client.dart';
import 'theme.dart';

/// The site, in whichever appearance the visitor already prefers.
///
/// `ThemeMode.system` rather than a stored choice: a visitor who has set their
/// machine to dark has already answered the question, and handing them white
/// is the site overriding an answer it was given.
///
/// A root of its own rather than Dartvel's default for one reason: the scroll
/// behaviour draws a scrollbar for touch as well, which a theme cannot say.
@DVAppRoot()
Widget _siteRoot(BuildContext context, DVAppParts parts) => MaterialApp.router(
      title: 'Dartvel: the full-stack platform for Flutter in one Dart project',
      debugShowCheckedModeBanner: false,
      themeMode: .system,
      theme: dartvelSiteTheme(.light),
      darkTheme: dartvelSiteTheme(.dark),
      scrollBehavior: const DartvelSiteScrollBehavior(),
      routerConfig: parts.router,
    );
