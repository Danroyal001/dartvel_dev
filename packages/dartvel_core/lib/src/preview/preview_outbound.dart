/// A preview does not send anything to anybody.
///
/// Notifications and schedules are the part of a preview that can reach the
/// outside world. Once [DVPreviewOutbound.activate] has run -- which a
/// preview's server does when its environment says it is one -- mail goes to
/// a capture inbox, notification providers are not called, and a scheduled
/// task runs only when the project declared it for previews.
///
/// The checks sit in `DV.Notifications` and [DVScheduler] themselves rather
/// than in a provider the preview registers, so an application that
/// registers its real provider afterwards still sends nothing.
library;

import '../../dartvel.dart'
    show
        DVMailMessage,
        DVNotificationMessage,
        DVNotificationProviderKind,
        DVSentNotification;
import '../observability/observability.dart';
import 'preview_access.dart';
import 'preview_secrets.dart';

/// The capture state of the running preview.
abstract final class DVPreviewOutbound {
  static DVPreviewRuntime? _runtime;
  static void Function(DVPreviewFinding finding) _onFinding = _log;
  static final List<DVMailMessage> _mail = <DVMailMessage>[];
  static final List<DVSentNotification> _notifications = <DVSentNotification>[];

  /// Starts capturing for [runtime]. Replaces any earlier activation and
  /// empties the inboxes.
  static void activate(
    DVPreviewRuntime runtime, {
    void Function(DVPreviewFinding finding)? onFinding,
  }) {
    _runtime = runtime;
    _onFinding = onFinding ?? _log;
    _mail.clear();
    _notifications.clear();
  }

  /// Stops capturing. For tests; a preview process never leaves preview.
  static void deactivate() {
    _runtime = null;
    _onFinding = _log;
    _mail.clear();
    _notifications.clear();
  }

  static bool get isActive => _runtime != null;

  /// Mail captured in this process, oldest first.
  static List<DVMailMessage> get mail => List<DVMailMessage>.unmodifiable(_mail);

  /// Notifications captured in this process, oldest first.
  static List<DVSentNotification> get notifications =>
      List<DVSentNotification>.unmodifiable(_notifications);

  /// Captures [message] instead of sending it.
  static Future<void> captureMail(DVMailMessage message) async {
    _mail.add(message);
    // Neither the recipients nor the body: a seeded address list is still a
    // list of addresses, and this goes to logs somebody else can read.
    _onFinding(DVPreviewFinding(
      'DV-PREVIEW-006',
      'mail "${message.subject}" to ${message.to.length} recipient'
      '${message.to.length == 1 ? '' : 's'} was captured, not sent, because '
      'this is preview ${_runtime?.name}.',
    ));
  }

  /// Captures a notification a provider would have delivered.
  static Future<void> captureNotification(
    String recipient,
    DVNotificationMessage message,
    DVNotificationProviderKind provider,
  ) async {
    _notifications.add(DVSentNotification(recipient: recipient, message: message));
    _onFinding(DVPreviewFinding(
      'DV-PREVIEW-006',
      '${provider.name} notification "${message.title}" was captured, not '
      'sent, because this is preview ${_runtime?.name}.',
    ));
  }

  /// Whether the scheduled task [name] may run. Outside a preview, always;
  /// in one, only when declared under `dartvel.preview.schedules`, and a
  /// refusal is reported.
  static bool allowsSchedule(String name) {
    final DVPreviewRuntime? runtime = _runtime;
    if (runtime == null || runtime.schedules.contains(name)) return true;
    _onFinding(DVPreviewFinding(
      'DV-PREVIEW-008',
      'scheduled task $name did not run: schedules are off in preview '
      '${runtime.name} unless declared under dartvel.preview.schedules.',
    ));
    return false;
  }

  static void _log(DVPreviewFinding finding) {
    DVObservability.log(
      '${finding.code}: ${finding.message}',
      level: switch (finding.level) {
        'error' => DVLogLevel.error,
        'warning' => DVLogLevel.warn,
        'debug' => DVLogLevel.debug,
        _ => DVLogLevel.info,
      },
      code: finding.code,
    );
  }
}
