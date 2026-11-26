import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel notifications: email, in-app, push and timers',
  description: 'Send email, in-app and push notifications through '
      'DV.Notifications, with mail as part of it at '
      'DV.Notifications.mail, and ring timers with DV.Timers.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsNotificationsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsnotifications,
      lead: <String>[
        'Send email, in-app and push notifications through DV.Notifications.',
        'Mail is part of it, at DV.Notifications.mail.',
        'Timers that ring, several at once, are DV.Timers.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'mail-provider',
          title: 'Pick a mail provider',
          children: <Widget>[
            DocsCode('mail-provider'),
            DocsTable(columns: <String>[
              'Provider',
              'Sends through',
            ], rows: <List<String>>[
              <String>['SmtpMailProvider', 'Any SMTP server, port 587 by '
                  'default'],
              <String>['ResendMailProvider', 'Resend'],
              <String>['SendGridMailProvider', 'SendGrid'],
              <String>['PostmarkMailProvider', 'Postmark'],
              <String>['SesMailProvider', 'Amazon SES'],
              <String>['MailgunMailProvider', 'Mailgun'],
              <String>['DVMemoryMailProvider', 'Nowhere. It keeps messages '
                  'in .sent for tests'],
            ]),
            DocsText('Providers are set in code. Read passwords and API keys '
                'with DV.Secrets.get.'),
          ],
        ),
        DocsSection(
          id: 'mail-send',
          title: 'Send an email',
          children: <Widget>[
            DocsCode('mail-send'),
            Bullets(<String>[
              'Add html: for an HTML body next to the text one.',
              'send throws when no mail provider is set.',
            ]),
          ],
        ),
        DocsSection(
          id: 'notify',
          title: 'Notify a person on several channels',
          children: <Widget>[
            DocsCode('notifications-send'),
            Bullets(<String>[
              'Channels are inApp, email, push, sms and webPush.',
              'Register one provider per kind, such as FirebasePushProvider, '
                  'ApnsPushProvider, WebPushProvider or TwilioSmsProvider.',
              'useRoutes tells the service each person\'s address and device '
                  'tokens.',
              'push tries the native providers first and falls back to Web '
                  'Push when none is registered or the one that is fails.',
              'usePreferences reads each person\'s muted channels and quiet '
                  'hours. Push, web push and SMS are not sent during quiet '
                  'hours, and email is.',
              'send returns a DVNotificationDelivery with the outcome of every '
                  'channel, so a muted or unrouted channel is told apart from '
                  'one that failed.',
            ]),
          ],
        ),
        DocsSection(
          id: 'push-setup',
          title: 'Push to Android and the browser',
          children: <Widget>[
            DocsText('Name the targets under dartvel.push in pubspec.yaml: '
                'web takes the public half of your VAPID key (`dartvel push '
                'vapid-keys` makes a pair), and android.fcm takes the four '
                'values the Firebase console shows for the app. The build '
                'writes everything else, so nothing in android/ or in a '
                'service worker is edited by hand.'),
            Bullets(<String>[
              'The credentials that send are Secrets, never pubspec.yaml: '
                  'FCM_SERVICE_ACCOUNT_JSON for FCM, VAPID_PRIVATE_KEY and '
                  'VAPID_SUBJECT for Web Push. The config parser refuses a '
                  'private key written in pubspec.yaml.',
              'FirebasePushProvider.fromSecrets signs the service-account '
                  'token request itself, keeps the access token until just '
                  'before it expires and retries once after a 401. The key '
                  'is redacted from logs and is in no error message.',
            ]),
            DocsCode('push-send'),
          ],
        ),
        DocsSection(
          id: 'push-receive',
          title: 'Receive push in the app',
          children: <Widget>[
            DocsCode('push-receive'),
            Bullets(<String>[
              'getToken is an FCM registration token on Android and the '
                  'browser subscription on the web. Send it to your server, '
                  'where DVNotificationRoutes takes it as pushTokens or '
                  'webPushSubscriptions.',
              'Starting push asks for no permission. requestPermission is for '
                  'a tap: a browser stops showing the prompt after a few '
                  'dismissals, so asking at load spends the only chance.',
              'On Android the build writes the Firebase service, the JNI '
                  'bridge, the manifest entry, the Gradle dependency and the '
                  'string resources Firebase reads, so there is no '
                  'google-services.json. A message that arrives while the app '
                  'is not running is kept until Dart asks.',
              'On the web the one generated service worker, shared by web and '
                  'web-server, shows a notification when no window is visible, '
                  'hands the message to the page when one is, and opens only '
                  'pages of your own origin when it is clicked.',
              'Fire OS and Horizon OS have no Google Play services, so their '
                  'builds leave FCM out.',
            ]),
          ],
        ),
        DocsSection(
          id: 'push-server',
          title: 'Topics and data messages',
          children: <Widget>[
            DocsCode('push-topic'),
            Bullets(<String>[
              'A topic reaches every device subscribed to it. Web Push has no '
                  'topics, and subscribeToTopic there says so.',
              'A data message shows nothing; the app receives it and decides.',
              'FCM answers a token it no longer knows with UNREGISTERED. That '
                  'is isUnregisteredToken on the exception: drop the token. '
                  'isRetryable is true for quota, unavailable and internal '
                  'errors.',
            ]),
          ],
        ),
        DocsSection(
          id: 'timers',
          title: 'Timers that ring',
          children: <Widget>[
            DocsText('DV.Timers is a countdown that rings with a sound and a '
                'notification: a cooking timer, a break, a parking meter. '
                'Several run at once, each with its own name, and they are '
                'kept across a reload or a restart. Turn it on with '
                'dartvel.timers: true in pubspec.yaml.'),
            DocsCode('timers-start'),
            DocsCode('timers-list'),
            Bullets(<String>[
              'snooze adds time: to a ringing timer from now, to a running '
                  'or paused one on top of what is left. dismiss stops it for '
                  'good. pause and resume keep what was left.',
              'A timer that fell due while the app was closed is ringing '
                  'when it opens again, and overdueAt says how long ago.',
              'The notification has +1 min and +5 min buttons; swiping it '
                  'away dismisses the timer, and a click on it opens the page '
                  'the timer was started from.',
              'DV.Timers.reach says whether a timer here rings with the app '
                  'closed. Say it to the person: nobody should trust a timer '
                  'to wake them that cannot.',
            ]),
            DocsTable(columns: <String>[
              'Where',
              'When it rings',
            ], rows: <List<String>>[
              <String>['Android', 'With the app closed and the screen off: a '
                  'system alarm, a notification on an alarm-sound channel that '
                  'repeats until answered, snooze and dismiss buttons. Exact '
                  'from Android 12 only with the alarms permission; without it '
                  'a few minutes late while the phone dozes.'],
              <String>['Web and installed web app', 'While a tab or window of '
                  'the app is open, in the background included: a chime, a '
                  'vibration and a notification with snooze buttons from the '
                  'service worker. Not once the browser is closed: no browser '
                  'runs a timer then.'],
              <String>['iOS, macOS, Windows, Linux', 'While the app runs: the '
                  'platform\'s plain notification, with no buttons.'],
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Mail and Notifications', missing: <String>[
              'Timers on Android have been built and compiled, not rung on a '
                  'phone. iOS and the desktop do not schedule a timer with the '
                  'system, so they ring only while the app runs.',
              'Web Push has been run against Chrome\'s real push service. FCM '
                  'has not: no Firebase project or Android device was '
                  'available, so no token has come from a phone and no '
                  'message has been delivered to one.',
              'A click on a notification is tested in the worker and has not '
                  'been tried in a browser. Nor have Firefox and Safari.',
              'A tap on a notification while the Android app is already '
                  'running in the background is not reported as opened.',
              'No attachments, bounce webhooks or List-Unsubscribe header.',
              'Mail is sent directly, and not through the job queue.',
              'Desktop and TV push kinds have no implementation, and iOS has '
                  'no device registration yet.',
            ]),
          ],
        ),
      ],
    );
