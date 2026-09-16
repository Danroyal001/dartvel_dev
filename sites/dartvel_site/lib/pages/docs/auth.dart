import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel auth: sign-in, second factor and sessions', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsAuthPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsauth,
      lead: <String>[
        'Sign people in with email and password, add a second factor and let '
            'them manage their devices.',
        'Account pages are generated for you, so you write none of the forms.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'provider',
          title: 'Choose an auth provider',
          children: <Widget>[
            DocsCode('start-configure'),
            DocsText('DVLocalAuthProvider stores accounts in your app for '
                'development. DV.Auth.configure takes any DVAuthProvider.'),
          ],
        ),
        DocsSection(
          id: 'sign-in',
          title: 'Sign in with email and password',
          children: <Widget>[
            DocsCode('auth-sign-in'),
            Bullets(<String>[
              'DV.Auth.currentUser holds the signed-in DVAuthUser, or null.',
              'An account with a second factor throws DVMfaRequired until '
                  'completeSecondFactor succeeds.',
              'signInWithProvider, signInWithPasskey and signInWithBiometrics '
                  'sit beside it.',
            ]),
            DocsCode('auth-sign-up-out'),
          ],
        ),
        DocsSection(
          id: 'second-factor',
          title: 'Add a second factor',
          children: <Widget>[
            DocsCode('auth-totp'),
            Bullets(<String>[
              'enrollTotp returns a secret and an otpauth:// URI for the QR '
                  'code.',
              'Nothing is active until confirmTotp accepts a code.',
              'completeSecondFactor(recoveryCode: ...) signs in with a recovery '
                  'code.',
            ]),
          ],
        ),
        DocsSection(
          id: 'sessions',
          title: 'List and revoke sessions',
          children: <Widget>[
            DocsCode('auth-sessions'),
            DocsText('Each DVSession has its device, when it was created and '
                'last seen, and whether it is the current one.'),
          ],
        ),
        DocsSection(
          id: 'account-pages',
          title: 'Use the generated account pages',
          children: <Widget>[
            DocsTable(columns: <String>[
              'Route',
              'Page',
            ], rows: <List<String>>[
              <String>['/login', 'Sign in'],
              <String>['/sign-up', 'Sign up'],
              <String>['/account/profile', 'Profile'],
              <String>['/account/security', 'Password and second factor'],
              <String>['/account/sessions', 'Signed-in devices'],
              <String>['/account/delete', 'Delete the account'],
            ]),
            DocsYaml('yaml-auth-pages'),
            Bullets(<String>[
              'false leaves a page out. A path serves it somewhere else.',
              'deletionGraceDays, 0 to 29, is how many days a deleted account '
                  'waits before it is erased.',
            ]),
            DocsText('Every page except sign-up needs a session. Place one '
                'inside your own page with the DV.Auth widgets.'),
            DocsCode('auth-pages'),
          ],
        ),
        DocsSection(
          id: 'cross-origin',
          title: 'Send credentials to an API on another origin',
          children: <Widget>[
            DocsText('The session cookie is __Host-dv_session with SameSite=Lax. '
                'When the web app and the API are on different origins, allow '
                'both sides.'),
            DocsCode('auth-credentialed-origin'),
            DocsYaml('yaml-cors'),
            Bullets(<String>[
              'With allowCredentials, a wildcard origin, method or header is '
                  'refused.',
              'The content-type and CSRF headers are allowed for you.',
              'Native apps send a bearer token and need none of this.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Authentication'),
            DocsStatus('Sessions and Account Management', missing: <String>[
              'No avatar, and passkeys are not a second factor yet.',
              'No per-tenant MFA policy or Redis session store.',
              'session.location is never filled in.',
            ]),
          ],
        ),
      ],
    );
