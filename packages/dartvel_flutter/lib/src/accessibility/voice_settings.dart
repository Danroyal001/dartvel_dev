// ignore_for_file: unused_element, unused_element_parameter
// The input for DVVoiceSettings: a model kept on the visitor's device,
// generated into voice_settings.g.dart by tool/generate_framework_models.dart.
// Edit this, then run the tool; a test fails when the generated file is out
// of date.
import 'package:dartvel_core/dartvel.dart';

/// Where voice mode, its confirmations and receipts sit on the screen.
enum DVVoicePosition {
  /// At the top, the usual place.
  top,

  /// In the middle of the screen, for a narrow field of view.
  centre,
}

/// The reader's voice-mode settings: where it sits and the language it
/// speaks and listens in (a language code from the app's voice languages).
@DVModel(storage: DVModelStorage.device, storageKey: 'dartvel.voice')
class const _DVVoiceSettings({
  final DVVoicePosition position = DVVoicePosition.top,
  final String language = 'en',
});
