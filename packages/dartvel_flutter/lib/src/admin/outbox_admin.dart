import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The mail and notification outbox.
///
/// "Did it send?" is the first question after a notification does not arrive,
/// and nothing else can answer it: a provider that accepted a message and a
/// provider that was never called look identical from the calling code.
///
/// Reads the in-memory providers, which is what local and test runs use. A
/// remote provider sends from someone else's infrastructure and has no
/// outbox here to read.
class DVOutboxAdmin extends StatefulWidget {
  /// The mail provider to read. Only the in-memory provider keeps a record.
  final DVMemoryMailProvider? mail;

  /// The notification provider to read.
  final DVMemoryNotificationProvider? notifications;

  const DVOutboxAdmin({super.key, this.mail, this.notifications});

  @override
  State<DVOutboxAdmin> createState() => _DVOutboxAdminState();
}

class _DVOutboxAdminState extends State<DVOutboxAdmin> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final mail = widget.mail;
    final notifications = widget.notifications;
    return DVBox.scrollableList(<Widget>[
      const DVText('Outbox')
          .modifier(const DVModifier().fontSize(24).fontWeight(FontWeight.bold)),
      GestureDetector(
        key: const ValueKey<String>('dv-outbox-refresh'),
        onTap: _refresh,
        child: const DVText('Refresh'),
      ),
      if (mail == null && notifications == null)
        const DVText(
          'No in-memory provider configured. A remote provider sends from its '
          'own infrastructure and keeps no outbox here.',
        ),
      if (mail != null) _mailSection(mail),
      if (notifications != null) _notificationSection(notifications),
    ]);
  }

  Widget _mailSection(DVMemoryMailProvider mail) {
    return DVBox.list(<Widget>[
      DVText('Mail (${mail.sent.length})')
          .modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      if (mail.sent.isEmpty) const DVText('No mail sent.'),
      for (final message in mail.sent)
        DVBox.list(<Widget>[
          DVText(message.subject),
          DVText('to ${message.to.map((DVMailAddress a) => a.email).join(', ')}'),
        ]),
    ]).modifier(const DVModifier().card().padding(16));
  }

  Widget _notificationSection(DVMemoryNotificationProvider provider) {
    return DVBox.list(<Widget>[
      DVText('Notifications (${provider.sent.length})')
          .modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      if (provider.sent.isEmpty) const DVText('No notifications sent.'),
      for (final notification in provider.sent)
        DVBox.list(<Widget>[
          DVText(notification.message.title),
          DVText('to ${notification.recipient}'),
        ]),
    ]).modifier(const DVModifier().card().padding(16));
  }
}
