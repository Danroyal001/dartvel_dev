/// `dartvel: web: lazyBackfill:` in pubspec.yaml, handed to the app as a
/// define.
///
/// ```yaml
/// dartvel:
///   web:
///     lazyBackfill: true   # off by default
/// ```
///
/// On the web, rows a lazy list holds back are then built while the page is
/// idle, so a screen reader's virtual cursor and the browser's find after an
/// in-app navigation reach them. Off by default since Dartvel 3.47.9: on long
/// lists it kept the main thread busy and the heap high. The app reads it in
/// dartvel_flutter's `DVLazyBackfill`.
library;

/// The `--dart-define` arguments for the [dartvel] section's
/// `web.lazyBackfill`.
List<String> dvLazyBackfillDefines(Object? dartvel) {
  final Object? web = dartvel is Map ? dartvel['web'] : null;
  final Object? value = web is Map ? web['lazyBackfill'] : null;
  if (value == null || value == false) return const [];
  if (value != true) {
    throw FormatException('dartvel.web.lazyBackfill is "$value"; use true or false.');
  }
  return const ['--dart-define=DARTVEL_LAZY_BACKFILL=true'];
}
