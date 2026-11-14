import 'package:dartvel_core/dartvel.dart';

/// Whether the visitor's consent allows [category] to be measured now.
///
/// The application decides whether consent is required at all, by declaring
/// a policy under `dartvel.analytics.consent` in its pubspec:
///
/// - **A policy is declared.** Nothing is sent until [category] is granted:
///   not before the stored choice has been read, and not when the policy
///   does not declare [category] at all, which is reported once rather than
///   read as permission.
/// - **No policy is declared.** The application has not asked for consent to
///   be required, and the module sends from the first page.
bool dvMetaPixelConsentGranted(String category) {
  if (!DVAnalyticsRuntime.isConfigured) return true;
  final DVConsent? consent = DVAnalyticsRuntime.current.loadedConsent;
  if (consent == null) return false;
  final DVConsentCategory wanted = DVConsentCategory(category);
  if (consent.policy.declaration(wanted) == null) {
    if (_reported.add(category)) {
      const DVLog().warn(
        'The Meta Pixel module waits for the consent category "$category", '
        'which dartvel.analytics.consent.categories does not declare, so it '
        'sends nothing. Declare it, or set '
        'dartvel.modules.<id>.config.consent to a category that is declared.',
        tag: 'metaPixel',
      );
    }
    return false;
  }
  return consent.isGranted(wanted);
}

final Set<String> _reported = <String>{};

/// Calls [changed] when the stored consent has been read, and again each
/// time the visitor changes it. Does nothing when the application declares
/// no consent policy.
void dvMetaPixelOnConsent(void Function() changed) {
  if (!DVAnalyticsRuntime.isConfigured) return;
  final DVAnalyticsRuntime analytics = DVAnalyticsRuntime.current;
  analytics.whenReady(() {
    analytics.loadedConsent?.addListener((DVConsentChange _) => changed());
    changed();
  });
}
