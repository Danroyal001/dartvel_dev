/// Speaking and listening, for voice mode: `DV.Accessibility.speech`.
///
/// In a browser, the Web Speech API (`speechSynthesis` and
/// `SpeechRecognition`, which Chrome names `webkitSpeechRecognition`).
/// Elsewhere, and in a browser without it, an engine that can do neither, so
/// an app shows its text path instead of a dead button -- and the
/// accessibility panel says so beside the voice language
/// ([dvVoiceAvailability]).
library;

import 'package:dartvel_core/dartvel.dart' show DVVoiceLanguage;

import 'speech_silent.dart' if (dart.library.js_interop) 'speech_web.dart' as platform;

/// The device's speech engines.
abstract interface class DVSpeech {
  /// Whether this device can speak.
  bool get canSpeak;

  /// Whether this device can listen.
  bool get canListen;

  /// The language tags of the voices this device has (`en-US`, `yo-NG`).
  Set<String> get voiceLanguages;

  /// Speaks [text] in [language]; completes when it has been said, or failed.
  Future<void> speak(String text, {required DVVoiceLanguage language});

  /// Listens for one phrase in [language]. Null when nothing was heard;
  /// throws [DVSpeechProblem] when recognition fails (no microphone, refused,
  /// language not supported).
  Future<String?> listen({required DVVoiceLanguage language});

  /// Stops speaking and listening at once.
  void stop();

  static DVSpeech? _instance;

  /// The engine this platform has, until a test replaces it.
  static DVSpeech get instance => _instance ??= platform.dvPlatformSpeech();

  static set instance(DVSpeech speech) => _instance = speech;

  /// Back to the platform's engine. For tests.
  static void reset() => _instance = null;
}

/// Why listening failed, in words a person can act on.
final class DVSpeechProblem implements Exception {
  const DVSpeechProblem(this.code, this.message);

  /// The engine's error code: `not-allowed`, `audio-capture`,
  /// `language-not-supported`...
  final String code;

  /// What to tell the person.
  final String message;

  @override
  String toString() => message;
}

/// An engine that can neither speak nor listen: a server rendering for every
/// visitor, a platform without speech, and tests.
final class DVSilentSpeech implements DVSpeech {
  const DVSilentSpeech();

  @override
  bool get canSpeak => false;

  @override
  bool get canListen => false;

  @override
  Set<String> get voiceLanguages => const <String>{};

  @override
  Future<void> speak(String text, {required DVVoiceLanguage language}) async {}

  @override
  Future<String?> listen({required DVVoiceLanguage language}) async => null;

  @override
  void stop() {}
}

/// What the panel says beside [language] on this device: whether its prompts
/// were machine translated, whether the device can speak at all, and whether
/// it has a voice for the language (another language falls back to reading
/// in English; English itself has nothing to fall back to). One sentence; "Voice available." when
/// there is nothing to warn about.
String dvVoiceAvailability(DVVoiceLanguage language, {required DVSpeech speech, bool machineTranslated = false}) {
  final List<String> notes = <String>[
    if (machineTranslated) 'Prompts translated by AI, not yet checked by a native speaker',
    if (!speech.canSpeak)
      'this browser cannot speak; prompts are shown as text'
    else if (!language.hasVoiceIn(speech.voiceLanguages))
      language == DVVoiceLanguage.english
          ? 'no English voice on this device; prompts are shown as text'
          : 'no ${language.englishName} voice on this device; shown as text, read in English',
  ];
  if (notes.isEmpty) return 'Voice available.';
  final String sentence = notes.join('; ');
  return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
}
