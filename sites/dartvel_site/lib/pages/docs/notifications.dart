import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel notifications: email, in-app and push', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsNotificationsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsnotifications,
      lead: <String>[
        'Send email, in-app and push notifications through DV.Notifications.',
        'Mail is part of it, at DV.Notifications.mail.',
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
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Mail and Notifications', missing: <String>[
              'No attachments, bounce webhooks or List-Unsubscribe header.',
              'Mail is sent directly, and not through the job queue.',
              'Desktop and TV push kinds have no implementation.',
            ]),
          ],
        ),
      ],
    );
