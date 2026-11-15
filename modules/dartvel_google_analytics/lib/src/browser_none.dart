import 'browser.dart';

/// Where there is no page: a device, or the backend.
GoogleAnalyticsBrowser createBrowser() => const _NoBrowser();

final class _NoBrowser implements GoogleAnalyticsBrowser {
  const _NoBrowser();

  @override
  bool get available => false;

  @override
  void load(String measurementId,
      {required String scriptUrl, required bool sendPageView}) {}

  @override
  void event(String name, Map<String, Object?> params) {}

  @override
  void consent({required bool granted}) {}

  @override
  String? get clientId => null;

  @override
  String? get sessionId => null;

  @override
  String? get pageUrl => null;

  @override
  String? get pageTitle => null;
}
