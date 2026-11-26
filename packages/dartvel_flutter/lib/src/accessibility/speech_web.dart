/// The Web Speech API. Every call can throw (an API half-implemented, a
/// permission refused); each failure is reported as "cannot", never a crash.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_core/dartvel.dart' show DVVoiceLanguage;

import 'speech.dart';

/// The Web Speech API. Every call can throw (an API half-implemented, a
/// permission refused); each failure is reported as "cannot", never a crash.
final class _BrowserSpeech implements DVSpeech {
  JSObject? get _synthesis => globalContext.getProperty<JSAny?>('speechSynthesis'.toJS) as JSObject?;

  JSFunction? get _recognitionClass =>
      (globalContext.getProperty<JSAny?>('SpeechRecognition'.toJS) ?? globalContext.getProperty<JSAny?>('webkitSpeechRecognition'.toJS))
          as JSFunction?;

  JSObject? _recognition;
  Completer<String?>? _listening;

  @override
  bool get canSpeak => _synthesis != null && globalContext.has('SpeechSynthesisUtterance');

  @override
  bool get canListen => _recognitionClass != null;

  @override
  Set<String> get voiceLanguages {
    final JSObject? synthesis = _synthesis;
    if (synthesis == null) return const <String>{};
    try {
      final JSArray<JSObject> voices = synthesis.callMethod<JSArray<JSObject>>('getVoices'.toJS);
      return <String>{
        for (final JSObject voice in voices.toDart) (voice.getProperty<JSString?>('lang'.toJS)?.toDart ?? ''),
      }..remove('');
    } on Object {
      return const <String>{};
    }
  }

  @override
  Future<void> speak(String text, {required DVVoiceLanguage language}) async {
    final String languageTag = language.speechTag;
    final JSObject? synthesis = _synthesis;
    if (synthesis == null || text.isEmpty) return;
    try {
      final JSFunction utteranceClass = globalContext.getProperty<JSFunction>('SpeechSynthesisUtterance'.toJS);
      final JSObject utterance = utteranceClass.callAsConstructor<JSObject>(text.toJS);
      utterance.setProperty('lang'.toJS, languageTag.toJS);
      utterance.setProperty('rate'.toJS, 0.95.toJS);
      final Completer<void> done = Completer<void>();
      void finish() {
        if (!done.isCompleted) done.complete();
      }
      utterance.setProperty('onend'.toJS, ((JSAny? _) => finish()).toJS);
      utterance.setProperty('onerror'.toJS, ((JSAny? _) => finish()).toJS);
      synthesis.callMethod<JSAny?>('cancel'.toJS);
      synthesis.callMethod<JSAny?>('speak'.toJS, utterance);
      // Some browsers never fire onend for a voice they cannot load.
      await done.future.timeout(Duration(milliseconds: 2000 + text.length * 90), onTimeout: () {});
    } on Object {
      // Shown as text anyway.
    }
  }

  @override
  Future<String?> listen({required DVVoiceLanguage language}) {
    final String languageTag = language.speechTag;
    final JSFunction? recognitionClass = _recognitionClass;
    if (recognitionClass == null) return Future<String?>.value();
    _abortListening();
    final Completer<String?> heard = Completer<String?>();
    _listening = heard;
    try {
      final JSObject recognition = recognitionClass.callAsConstructor<JSObject>();
      _recognition = recognition;
      recognition.setProperty('lang'.toJS, languageTag.toJS);
      recognition.setProperty('interimResults'.toJS, false.toJS);
      recognition.setProperty('maxAlternatives'.toJS, 1.toJS);
      recognition.setProperty('continuous'.toJS, false.toJS);
      recognition.setProperty(
        'onresult'.toJS,
        ((JSObject event) {
          String? text;
          try {
            final JSObject results = event.getProperty<JSObject>('results'.toJS);
            final JSObject first = results.callMethod<JSObject>('item'.toJS, 0.toJS);
            final JSObject alternative = first.callMethod<JSObject>('item'.toJS, 0.toJS);
            text = alternative.getProperty<JSString?>('transcript'.toJS)?.toDart;
          } on Object {
            text = null;
          }
          if (!heard.isCompleted) heard.complete(text);
        }).toJS,
      );
      recognition.setProperty(
        'onerror'.toJS,
        ((JSObject event) {
          final String code = event.getProperty<JSString?>('error'.toJS)?.toDart ?? 'unknown';
          if (heard.isCompleted) return;
          if (code == 'no-speech' || code == 'aborted') {
            heard.complete(null);
          } else {
            heard.completeError(DVSpeechProblem(code, _explain(code)));
          }
        }).toJS,
      );
      recognition.setProperty('onend'.toJS, ((JSAny? _) {
        if (!heard.isCompleted) heard.complete(null);
      }).toJS);
      recognition.callMethod<JSAny?>('start'.toJS);
    } on Object catch (error) {
      if (!heard.isCompleted) heard.completeError(DVSpeechProblem('start', 'Listening could not start: $error'));
    }
    return heard.future.timeout(const Duration(seconds: 15), onTimeout: () {
      _abortListening();
      return null;
    });
  }

  static String _explain(String code) => switch (code) {
        'not-allowed' || 'service-not-allowed' => 'The microphone is blocked for this page. Type instead, or allow the microphone.',
        'audio-capture' => 'No microphone was found. Type instead.',
        'network' => 'Speech recognition needs the internet. Type instead.',
        'language-not-supported' => 'This browser cannot hear that language. Type instead, or choose another language.',
        _ => 'Listening failed ($code). Type instead.',
      };

  void _abortListening() {
    final JSObject? recognition = _recognition;
    _recognition = null;
    if (recognition != null) {
      try {
        recognition.callMethod<JSAny?>('abort'.toJS);
      } on Object {
        // Already stopped.
      }
    }
    final Completer<String?>? listening = _listening;
    if (listening != null && !listening.isCompleted) listening.complete(null);
    _listening = null;
  }

  @override
  void stop() {
    _abortListening();
    try {
      _synthesis?.callMethod<JSAny?>('cancel'.toJS);
    } on Object {
      // Nothing was speaking.
    }
  }
}

DVSpeech dvPlatformSpeech() => _BrowserSpeech();
