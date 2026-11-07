/// `dartvel.web` keys for features Dartvel has removed.
///
/// A project that still names one keeps building: the key is ignored, and the
/// build says so in one line, so the developer can delete it.
library;

/// One line per removed `dartvel.web` key that [dartvel] (the `dartvel:`
/// section of pubspec.yaml) still sets.
///
/// `firstFrame` asked the build to capture a picture of each page in Chrome
/// and show it before the app loaded. The picture could not be used -- it was
/// a picture -- and visitors took the site for broken, so it was removed: a
/// page shows the splash, its loading line and its loading bar until the real
/// app has drawn its first frame.
List<String> dvRemovedWebOptionWarnings(Map<Object?, Object?> dartvel) {
  final Object? web = dartvel['web'];
  if (web is! Map) return const <String>[];
  return <String>[
    if (web.containsKey('firstFrame'))
      'dartvel.web.firstFrame is ignored: the first-frame picture was removed '
          '(pages show the splash until the app loads); delete the key from '
          'pubspec.yaml.',
  ];
}
