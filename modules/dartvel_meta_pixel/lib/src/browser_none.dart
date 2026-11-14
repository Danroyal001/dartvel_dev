import 'browser.dart';

/// Where there is no page: a device, or the backend.
MetaPixelBrowser createBrowser() => const _NoBrowser();

final class _NoBrowser implements MetaPixelBrowser {
  const _NoBrowser();

  @override
  bool get available => false;

  @override
  void load(String pixelId, {required String scriptUrl}) {}

  @override
  void track(String name, Map<String, Object?> data,
      {required String eventId, required bool custom}) {}

  @override
  void consent({required bool granted}) {}

  @override
  String? cookie(String name) => null;

  @override
  String? queryParameter(String name) => null;

  @override
  String? get pageUrl => null;

  @override
  String? get userAgent => null;
}
