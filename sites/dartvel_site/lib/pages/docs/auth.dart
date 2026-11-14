import 'package:flutter/material.dart';

import '../../components/password_manager_demo.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel auth: sign-in, second factor and sessions',
  description: 'Sign people in with email and password, add a second factor, '
      'and let them manage their devices. The account pages are '
      'generated, so you write none of the forms.',
  showAppBar: false,
)
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
          id: 'appearance',
          title: 'Make account pages yours',
          children: <Widget>[
            DocsText('Prebuilt pages use your Material theme. Wide screens '
                'show a brand panel; small screens use a scrolling form. '
                'dartvel.pwa.name and icon supply the identity. '
                'dartvel.auth accepts tagline, heroImage and brandPanelColor '
                '(a six-digit RGB hex color). Include images in flutter.assets.'),
            DocsText('DV.Auth.appearance accepts DVAuthAppearance with a '
                'brandPanelBuilder for your own wide-screen panel, or a '
                'frameBuilder that draws the whole sign-in screen around '
                'the form Dartvel hands it, plus signInTitle and '
                'signUpTitle. dartvel.auth.forgotPassword links the '
                'sign-in form to your reset page. '
                'Sign-in and sign-up links follow configured account routes '
                'and carry the internal from destination. Pending requests '
                'disable submission and errors are announced.'),
            DocsText('There is no public password-reset endpoint yet. '
                'Interactive server HTML forms and visual parity before '
                'Flutter loads are not delivered by the current fallback renderer.'),
          ],
        ),
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
              'DV.Auth also has signInWithProvider, signInWithPasskey and '
                  'signInWithBiometrics. They need a DVAuthProvider that '
                  'implements them: the generated backend\'s provider signs in '
                  'with email and password and throws UnsupportedError for '
                  'the others.',
            ]),
            DocsCode('auth-sign-up-out'),
          ],
        ),
        DocsSection(
          id: 'password-managers',
          title: 'Password managers save and fill the sign-in page',
          children: <Widget>[
            DocsText('The prebuilt sign-in and sign-up pages work with the '
                'browser\'s password manager, and with 1Password, Bitwarden, '
                'iCloud Keychain and Google Password Manager on phones.'),
            Bullets(<String>[
              'The email and password fields are one form, marked as a '
                  'username and a password, so a manager recognises them and '
                  'fills them.',
              'Enter in the password field signs in.',
              'The manager is asked to save the password only after the '
                  'server accepts it. A wrong password is never offered for '
                  'saving, and leaving the page saves nothing.',
            ]),
            DocsText('Try it: if your browser has a saved password for any '
                'site, click the email field below. This demo signs nobody in, '
                'so it never asks to save.'),
            PasswordManagerDemo(),
          ],
        ),
        DocsSection(
          id: 'enterprise',
          title: 'Verify passkeys, SAML, LDAP and Ethereum sign-in',
          children: <Widget>[
            DocsTable(columns: <String>[
              'In dartvel_core',
              'Does',
            ], rows: <List<String>>[
              <String>['DVWebAuthn', 'verifyAssertion checks a passkey '
                  'signature against the stored credential'],
              <String>['DVSaml', 'validateResponse checks a SAML 2.0 response '
                  'and its signature'],
              <String>['DVLdapClient', 'connect, then authenticate a user name '
                  'and password against a directory'],
              <String>['dvVerifySiwe', 'Checks a Sign-In with Ethereum message, '
                  'its signature, domain and nonce'],
            ]),
            Bullets(<String>[
              'These run on the server, where your backend functions call them.',
              'CI runs the LDAP client against a real directory server.',
              'DVLdapClient needs dart:io, so it is not available on the web.',
            ]),
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
            DocsText('To ask for the factor before a page or a function, add '
                'mfa: DVMfa.required, or mfa: DVMfa.recent(Duration(minutes: 5)) '
                'for one entered in the last five minutes, to @DVPage or '
                '@DVBackendFunction. A generated call that is refused shows the '
                'challenge and sends the call again.'),
          ],
        ),
        DocsSection(
          id: 'codes',
          title: 'Send a code and ask for it back',
          children: <Widget>[
            DocsText('DV.Auth.code() mints the digits to send: six by '
                'default, from a secure random, with leading zeros kept.'),
            DocsCode('auth-code'),
            DocsText('DV.Auth.askForCode asks for them back, over whatever '
                'is on screen. It answers with what was typed, or null when '
                'it was dismissed; verify checks the code without closing, '
                'so a wrong one can be typed again.'),
            DocsCode('auth-ask-for-code'),
            DocsText('For a flow with a page of its own:'),
            DocsCode('auth-ask-for-code-page'),
            Bullets(<String>[
              'The field takes digits only, as many as the code has.',
              'It offers the code a phone shows above the keyboard, through '
                  'the one-time-code autofill hint.',
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
          id: 'restore',
          title: 'Know who is signed in when the app starts',
          children: <Widget>[
            DocsText('The app asks the server who is signed in as it starts, '
                'in a browser after a reload as on a device. '
                'DV.Auth.currentUser is that person, and DV.Auth.user is the '
                'same as a signal a widget can watch.'),
            DocsCode('auth-signed-in-user'),
            Bullets(<String>[
              'It is one request to /auth/session. Nobody signed in, or no '
                  'network, leaves the app signed out without an error.',
              'DV.Auth.restoring is true until the answer arrives, so a page '
                  'can show neither state rather than flash "Sign in".',
              'Guarded pages wait for it before sending anyone to sign in.',
              'It runs by itself. You do not call it, and calling '
                  'DV.Auth.restore() from boot code is harmless.',
              'A provider you configured yourself is not asked.',
            ]),
          ],
        ),
        DocsSection(
          id: 'hosts',
          title: 'Stay signed in across your hosts',
          children: <Widget>[
            DocsText('When dartvel.hosts serves several hosts on one '
                'registrable domain, such as example.com and '
                'tools.example.com, signing in on one signs in on all of '
                'them, and signing out on one signs out on all of them.'),
            DocsShell(<String>[
              'hosts:',
              '  example.com: {}',
              '  tools.example.com: { mount: /tools, siteUrl: https://tools.example.com }',
              'auth:',
              '  sessionScope: site            # the default; host gives each host its own',
              '  # sessionDomain: example.com  # optional, checked at build time',
            ]),
            Bullets(<String>[
              'The cookie is __Secure-dv_session for that domain, still '
                  'HttpOnly, Secure and SameSite=Lax. An app with one host '
                  'keeps __Host-dv_session.',
              'The domain comes from the Public Suffix List, so co.uk or '
                  'github.io is never used. A host on another domain, or one '
                  'that only redirects, keeps a cookie of its own.',
              'sessionScope: host gives every host its own session. '
                  'sessionDomain names the domain; the build refuses one that '
                  'is a public suffix or not above every host.',
              'A change sent from a host you do not list is refused, even '
                  'under the same domain.',
              'People already signed in stay signed in: the old cookie moves '
                  'to the new one on their next request.',
              'Every site under the domain receives the cookie. If someone '
                  'else runs a site there, use sessionScope: host.',
            ]),
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
            DocsText('The session cookie is __Host-dv_session with SameSite=Lax, '
                'or __Secure-dv_session when your hosts share it. '
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
