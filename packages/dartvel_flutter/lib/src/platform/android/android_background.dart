/// Long JNI calls off the app's main thread.
///
/// Flutter runs Dart on Android's main thread (the UI and platform threads
/// are merged), so a JNI call made from Dart blocks that thread for as long
/// as it takes. Listing every installed app with its label asks
/// PackageManager to load each app's resources: well under a second on a
/// fast phone, several seconds on a slow 32-bit one, where a launcher that
/// did it on each return to the home screen froze and got Android's "app
/// isn't responding". Such calls go through [dvAndroidOffMainThread].
library dartvel_flutter.platform.android.background;

import 'dart:async';
import 'dart:isolate';

/// Runs [work] on a background isolate and answers its result.
///
/// [work] must look up what it needs (the Context, through the generated
/// provider) inside itself: a JNI reference does not cross isolates. A
/// result is copied back, so it is plain data: strings, numbers, lists, maps
/// and byte lists. When [work] cannot run in the background isolate it runs
/// here, as it used to, rather than not at all; an error here is the
/// caller's.
Future<T> dvAndroidOffMainThread<T>(FutureOr<T> Function() work) async {
  try {
    return await Isolate.run<T>(work);
  } on Object {
    return await work();
  }
}
