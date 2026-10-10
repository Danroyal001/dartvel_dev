/// The platform's own log, as a destination for DV.log records: logcat on
/// Android, the unified log on iOS and macOS, journald or stderr on Linux,
/// stderr and the debugger on Windows, the console in a browser.
library;

import 'package:dartvel_core/dartvel.dart' show DVLogSink;

import 'native_log_sink_none.dart'
    if (dart.library.io) 'native_log_sink_io.dart'
    if (dart.library.js_interop) 'native_log_sink_web.dart' as platform;

/// The sink for this platform, or null where there is none -- and under
/// `flutter test`, whose runner owns the output.
DVLogSink? dvNativeLogSink({required String appId}) =>
    platform.dvPlatformLogSink(appId: appId);
