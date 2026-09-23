import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Links')
Widget _linksPage(BuildContext context) => DVBox.list(<Widget>[
      // docs:start routing-navlink
      DVNavLink(
        to: DVRoutes.about,
        child: const DVText('About us'),
      ),
      // docs:end
      // docs:start routing-navlink-options
      DVNavLink(
        to: DVRoutes.blog(id: '42'),
        preload: DVLinkPreload.hover, // none, hover, visible, immediate
        preview: DVLinkPreview.none, // none, auto
        child: const DVText('Read post 42'),
      ),
      DVNavLink.external(
        'https://pub.dev/packages/dartvel_dev',
        child: const DVText('Dartvel on pub.dev'),
      ),
      // docs:end
      // docs:start routing-navigate
      DVText('Open post 7').modifier(
        DVModifier().onTap(() => context.navigateToPage(DVRoutes.blog(id: '7'))),
      ),
      DVText('Back to home').modifier(
        DVModifier().onTap(DV.Navigation.to(DVRoutes.index)),
      ),
      // A query is still a typed route. Both halves are generated targets,
      // so a page that moves is a compile error here.
      DVText('Sign in and come back').modifier(
        DVModifier().onTap(DV.Navigation.to(
          DVRoutes.accountsecurity.withQuery(<String, String>{
            'from': DVRoutes.accountsettings.path,
          }),
        )),
      ),
      // docs:end
    ]);
