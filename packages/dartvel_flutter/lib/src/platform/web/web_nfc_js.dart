/// `nfc.readTag` and `nfc.writeTag` through Web NFC.
///
/// `NDEFReader` is Chrome on Android and nothing else — not Chrome on a
/// desktop, where the API is simply not defined. Both names are registered
/// only where the constructor exists, so a desktop browser reports them
/// unregistered rather than sitting on a read that can never complete.
///
/// `nfc.isAvailable` is registered everywhere, because "no" is a true answer
/// to that question and an application deciding whether to show a Tap panel
/// needs it answered rather than thrown.
///
/// The text-versus-URI split is the same one the neard binding makes, for the
/// same reason: a link written into a text record reads back as exactly the
/// characters somebody typed and does nothing at all when a phone touches it.
library dartvel_flutter.platform.web.nfc;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_capabilities.dart';
import 'web_interop.dart';

class DVWebNfc {
  const DVWebNfc._();

  static const Set<String> implemented = <String>{
    'nfc.readTag',
    'nfc.writeTag',
  };

  /// Why the last write did not do what was asked.
  ///
  /// The same escape hatch the Linux binding keeps, and for the same reason:
  /// "no tag was presented" and "the tag is locked" both come back as false,
  /// and they send whoever reads them to different places.
  static String? lastError;

  /// Whether this browser has Web NFC.
  static bool get available => dvJsMethod(globalContext, 'NDEFReader') != null;

  /// Schemes worth writing as a URI record, matching the neard binding's set
  /// so the same string produces the same kind of tag on both.
  static const Set<String> _uriSchemes = <String>{
    'http', 'https', 'ftp', 'ftps', 'sftp', 'file', 'smb', 'nfs',
    'mailto', 'tel', 'sms', 'geo', 'urn',
  };

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('nfc.readTag', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? timeout = map['timeoutMs'];
      return readTag(
        timeout: Duration(milliseconds: timeout is int ? timeout : 20000),
      );
    });

    register('nfc.writeTag', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? timeout = map['timeoutMs'];
      return writeTag(
        '${map['value'] ?? ''}',
        language: map['language'] is String ? map['language']! as String : 'en',
        timeout: Duration(milliseconds: timeout is int ? timeout : 20000),
      );
    });
  }

  /// What is written on the next tag presented to the reader.
  ///
  /// Unlike the desktop binding this cannot look at a tag already sitting on
  /// a reader: Web NFC has no such notion, and a phone reads when a tag
  /// touches it. So this waits, and gives up after [timeout] saying that
  /// nothing was presented — which is a different sentence from "the tag was
  /// blank", and a person holding a phone against a card needs to be able to
  /// tell them apart.
  static Future<String> readTag({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final JSObject reader =
        dvJsMethod(globalContext, 'NDEFReader')!.callAsConstructor<JSObject>();
    final Completer<String> done = Completer<String>();

    void onReading(web.Event event) {
      if (done.isCompleted) return;
      final String? text = _firstRecord(event as JSObject);
      if (text != null) done.complete(text);
    }

    void onError(web.Event _) {
      if (done.isCompleted) return;
      done.completeError(StateError(
        'nfc.readTag failed: a tag was presented and could not be read.',
      ));
    }

    final JSFunction readingHandler = onReading.toJS;
    final JSFunction errorHandler = onError.toJS;
    final JSObject? aborter = _abortController();

    await dvJsCall(reader, 'addEventListener',
        <JSAny?>['reading'.toJS, readingHandler]);
    await dvJsCall(reader, 'addEventListener',
        <JSAny?>['readingerror'.toJS, errorHandler]);
    try {
      await dvJsCall(reader, 'scan', <JSAny?>[_signalOptions(aborter)]);
      return await done.future.timeout(
        timeout,
        onTimeout: () => throw StateError(
          'nfc.readTag failed: no tag was presented within '
          '${timeout.inSeconds} seconds.',
        ),
      );
    } on StateError {
      rethrow;
    } on Object catch (error) {
      // Denied, or a page that is not on a secure origin, or a scan started
      // with no user gesture behind it. Each is the browser refusing rather
      // than the hardware failing.
      dvJsRefused('nfc.readTag', error);
    } finally {
      await dvJsCall(reader, 'removeEventListener',
          <JSAny?>['reading'.toJS, readingHandler]);
      await dvJsCall(reader, 'removeEventListener',
          <JSAny?>['readingerror'.toJS, errorHandler]);
      if (aborter != null) await dvJsCall(aborter, 'abort');
    }
  }

  /// Writes [value] to the next tag presented.
  ///
  /// False rather than an exception when the tag will not take it — nothing
  /// was presented, it is locked, it was taken away mid-write — because this
  /// is called from a screen somebody is standing at. [lastError] carries
  /// what happened. A refusal by the browser is still an exception: that one
  /// is not about the tag.
  static Future<bool> writeTag(
    String value, {
    String language = 'en',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final Uri? uri = Uri.tryParse(value);
    final bool isUri = uri != null &&
        uri.hasScheme &&
        _uriSchemes.contains(uri.scheme.toLowerCase());

    final JSObject record = JSObject()
      ..setProperty('recordType'.toJS, (isUri ? 'url' : 'text').toJS)
      ..setProperty('data'.toJS, value.toJS);
    if (!isUri) {
      // NDEF puts a language code in every Text record, and a reader that
      // finds none shows the record as empty.
      record.setProperty('lang'.toJS, language.toJS);
    }
    final JSObject message = JSObject()
      ..setProperty('records'.toJS, <JSObject>[record].toJS);

    final JSObject writer =
        dvJsMethod(globalContext, 'NDEFReader')!.callAsConstructor<JSObject>();
    final JSObject? aborter = _abortController();
    try {
      await dvJsCall(
        writer,
        'write',
        <JSAny?>[message, _signalOptions(aborter)],
      ).timeout(
        timeout,
        onTimeout: () {
          lastError = 'No tag was presented within ${timeout.inSeconds} '
              'seconds. Hold one against the reader and try again.';
          return null;
        },
      );
      if (lastError != null) return false;
      lastError = null;
      return true;
    } on Object catch (error) {
      final String reason = dvJsReason(error);
      if (reason.contains('NotAllowedError') ||
          reason.contains('SecurityError')) {
        throw DVWebPermissionDenied('nfc.writeTag', reason);
      }
      // A tag that is read-only, one taken off the reader mid-write, a record
      // too big for the chip. All of them are the tag rather than the caller.
      lastError = 'The tag could not be written: $reason';
      return false;
    } finally {
      if (aborter != null) await dvJsCall(aborter, 'abort');
    }
  }

  /// An AbortController, so a scan left running is stopped.
  ///
  /// Without one the reader keeps listening after the call returns, and the
  /// next read gets the tag the last one was waiting for.
  static JSObject? _abortController() {
    final JSFunction? constructor = dvJsMethod(globalContext, 'AbortController');
    return constructor?.callAsConstructor<JSObject>();
  }

  static JSObject _signalOptions(JSObject? aborter) {
    final JSObject options = JSObject();
    if (aborter != null) {
      final JSAny? signal = dvJsValue(aborter, 'signal');
      if (signal != null) options.setProperty('signal'.toJS, signal);
    }
    return options;
  }

  /// The first record on the tag that carries readable characters.
  ///
  /// Text and URL records both hold what somebody wrote, which is what a
  /// caller asked for. Anything else — a MIME record with a photo in it —
  /// is skipped rather than decoded into mojibake.
  static String? _firstRecord(JSObject event) {
    final JSObject? message = dvJsObject(event, 'message');
    if (message == null) return null;
    final JSAny? records = dvJsValue(message, 'records');
    if (records == null || !records.isA<JSArray<JSAny?>>()) return null;
    final JSArray<JSAny?> list = records as JSArray<JSAny?>;
    for (int i = 0; i < list.length; i++) {
      final JSAny? entry = list.toDart[i];
      if (!entry.isA<JSObject>()) continue;
      final JSObject record = entry! as JSObject;
      final String type = dvJsString(record, 'recordType') ?? '';
      if (type != 'text' && type != 'url' && type != 'absolute-url') continue;
      final String? text = _decode(record);
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  /// The record's data, decoded with the encoding the tag declared.
  ///
  /// UTF-16 tags exist and are written by some card printers. Decoding one as
  /// UTF-8 gives a string of alternating nulls that looks like a read that
  /// worked.
  static String? _decode(JSObject record) {
    final JSAny? data = dvJsValue(record, 'data');
    if (data == null) return null;
    final JSFunction? decoder = dvJsMethod(globalContext, 'TextDecoder');
    if (decoder == null) return null;
    final String encoding = dvJsString(record, 'encoding') ?? 'utf-8';
    final JSObject instance =
        decoder.callAsConstructor<JSObject>(encoding.toJS);
    final JSFunction? decode = dvJsMethod(instance, 'decode');
    if (decode == null) return null;
    final Object? text = decode.callAsFunction(instance, data).dartify();
    return text is String ? text : null;
  }
}
