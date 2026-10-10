/// Platform logs where there is dart:io, bound through FFI.
///
/// - Android: `__android_log_write` from `liblog.so`, the NDK C entry
///   `android.util.Log` itself writes through, so records appear in logcat
///   under their own priority and tag without a JVM call per line.
/// - iOS and macOS: `syslog(3)`, which Apple routes into the unified log
///   (`log stream`, Console.app, Xcode's console). It is the path Flutter's
///   own engine logs through on iOS. `os_log` itself is a macro over
///   `_os_log_impl`, which requires its format string to sit in the calling
///   binary's own text segment -- something a string built in Dart cannot
///   satisfy -- so syslog is the reachable entry into the same log.
/// - Linux: stderr; under systemd (`JOURNAL_STREAM` set) every line carries
///   the `<N>` prefix so journald records the priority.
/// - Windows: stderr, and `OutputDebugStringW` so a debugger sees it too.
///
/// Every native lookup is lazy. A missing library or symbol falls back to
/// stderr, and nothing here ever throws into the code that logged.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:ffi/ffi.dart';

import 'native_log_format.dart';

/// Writes one entry to the platform log: priority, tag, text.
typedef DVNativeLogWriter = void Function(int priority, String tag, String text);

DVLogSink? dvPlatformLogSink({required String appId}) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
  return DVIoNativeLogSink(appId: appId);
}

/// The platform log on Android, Apple platforms, Linux and Windows.
class DVIoNativeLogSink implements DVLogSink {
  DVIoNativeLogSink({
    required this.appId,
    String? os,
    Map<String, String>? environment,
    void Function(String text)? writeStderr,
    DVNativeLogWriter? writeNative,
  })  : os = os ?? Platform.operatingSystem,
        _journal = (environment ?? Platform.environment)
            .containsKey('JOURNAL_STREAM'),
        _writeStderr = writeStderr ?? stderr.writeln,
        _writeNative = writeNative ??
            _bindNative(os ?? Platform.operatingSystem);

  final String appId;
  final String os;
  final bool _journal;
  final void Function(String text) _writeStderr;
  DVNativeLogWriter? _writeNative;

  @override
  void write(DVLogRecord record) {
    try {
      final String text = dvNativeLogText(record);
      final DVNativeLogWriter? native = _writeNative;
      if (native != null) {
        try {
          switch (os) {
            case 'android':
              final String tag = dvAndroidLogTag(appId, record.tag);
              final int priority = dvAndroidLogPriority(record.level);
              for (final String chunk in dvLogcatChunks(text)) {
                native(priority, tag, chunk);
              }
              return;
            case 'ios' || 'macos':
              native(dvSyslogPriority(record.level), appId, text);
              return;
            case 'windows':
              native(0, appId, '$text\n');
          }
        } on Object {
          // The native log is unavailable here: stderr from now on.
          _writeNative = null;
          if (os != 'windows') {
            _writeStderr(text);
            return;
          }
        }
      }
      if (_journal) {
        final String prefix = dvJournalPrefix(record.level);
        _writeStderr(text.split('\n').map((String line) => '$prefix$line').join('\n'));
      } else {
        _writeStderr(text);
      }
    } on Object {
      // A closed stderr: nowhere left to write, and no reason to fail.
    }
  }

  static DVNativeLogWriter? _bindNative(String os) {
    switch (os) {
      case 'android':
        return _AndroidLog.write;
      case 'ios' || 'macos':
        return _AppleLog.write;
      case 'windows':
        return _WindowsLog.write;
      default:
        return null;
    }
  }
}

typedef _AndroidLogWriteNative = Int32 Function(
    Int32 priority, Pointer<Utf8> tag, Pointer<Utf8> text);
typedef _AndroidLogWriteDart = int Function(
    int priority, Pointer<Utf8> tag, Pointer<Utf8> text);

abstract final class _AndroidLog {
  static final _AndroidLogWriteDart _write = DynamicLibrary.open('liblog.so')
      .lookupFunction<_AndroidLogWriteNative, _AndroidLogWriteDart>(
          '__android_log_write');

  static void write(int priority, String tag, String text) {
    final Pointer<Utf8> nativeTag = tag.toNativeUtf8();
    final Pointer<Utf8> nativeText = text.toNativeUtf8();
    try {
      _write(priority, nativeTag, nativeText);
    } finally {
      malloc.free(nativeTag);
      malloc.free(nativeText);
    }
  }
}

typedef _SyslogNative = Void Function(
    Int32 priority, Pointer<Utf8> format, VarArgs<(Pointer<Utf8>,)>);
typedef _SyslogDart = void Function(
    int priority, Pointer<Utf8> format, Pointer<Utf8> text);

abstract final class _AppleLog {
  static final _SyslogDart _syslog = DynamicLibrary.process()
      .lookupFunction<_SyslogNative, _SyslogDart>('syslog');

  // The text is always an argument, never the format: a `%` in a message
  // must not be read as a conversion.
  static final Pointer<Utf8> _format = '%s'.toNativeUtf8();

  static void write(int priority, String tag, String text) {
    final Pointer<Utf8> nativeText = text.toNativeUtf8();
    try {
      _syslog(priority, _format, nativeText);
    } finally {
      malloc.free(nativeText);
    }
  }
}

typedef _OutputDebugStringNative = Void Function(Pointer<Utf16> text);
typedef _OutputDebugStringDart = void Function(Pointer<Utf16> text);

abstract final class _WindowsLog {
  static final _OutputDebugStringDart _output = DynamicLibrary.open(
          'kernel32.dll')
      .lookupFunction<_OutputDebugStringNative, _OutputDebugStringDart>(
          'OutputDebugStringW');

  static void write(int priority, String tag, String text) {
    final Pointer<Utf16> nativeText = text.toNativeUtf16();
    try {
      _output(nativeText);
    } finally {
      malloc.free(nativeText);
    }
  }
}
