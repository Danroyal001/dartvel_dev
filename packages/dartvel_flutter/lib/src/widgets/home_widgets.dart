/// What an application sends to its own home-screen widgets.
///
/// The specification's line is "shares widget tree and state with the parent
/// app", and half of it is a platform fact rather than a feature worth
/// arguing with. A home widget is composed in the launcher's process on
/// Android and by the system on iOS and macOS. Neither can host a Flutter
/// engine, so no arrangement of this library could put a Flutter widget on a
/// home screen, and one claiming to would be claiming something the platform
/// does not offer.
///
/// What is genuinely shared is the tree and the state at `/widgets/<id>`:
/// the page Dartvel generates builds the same widget, in the application's
/// own tree, under the same signals, globals and providers as every other
/// page -- which is why a home widget's tap opens it there rather than
/// somewhere that would need its own copy of everything.
///
/// What crosses to the surface on the home screen is data, and this is that
/// crossing. It is one value per widget because that is what both platforms'
/// generated views draw; a widget that needs more than a line of text is
/// asking for a view the application composes, and that is the page.
library dartvel_flutter.widgets.home_widgets;

import 'package:dartvel_core/dartvel.dart' show dvHomeWidgetDataKey;

import '../../dartvel_flutter.dart' show DVNativeBridge;

/// The application's side of a home widget's data.
class DVHomeWidgets {
  const DVHomeWidgets._();

  /// Puts [text] where the home-screen widget with [id] reads it.
  ///
  /// Answers whether the value was stored, and answers false rather than
  /// throwing on every target that has nowhere to put a widget -- an
  /// application publishing on a timer should keep running on the web and on
  /// a desktop, where there is no home screen and no binding.
  ///
  /// False is also the answer when the native side could not write: no App
  /// Group on the extension, or an APK built with plain `flutter build`,
  /// which has none of the classes `dartvel build android` writes. Those all
  /// fail quietly on the device, and reporting success over the top would
  /// bury the one signal there is.
  ///
  /// The key is derived here rather than on each platform. Three halves read
  /// it -- this, the generated Swift, the generated Java -- and a key with
  /// two spellings is a correctly built and correctly signed widget showing
  /// its placeholder for ever.
  static Future<bool> publish(String id, String text) async {
    // An empty id makes a key no widget ever asks for, so the write would go
    // nowhere and saying it worked would send whoever wrote the call looking
    // at the home screen rather than at the empty string they passed.
    if (id.isEmpty) return false;
    final bool? stored = await DVNativeBridge.invoke<bool>(
      'homeWidgets.publish',
      <String, Object?>{'key': dvHomeWidgetDataKey(id), 'text': text},
    );
    return stored ?? false;
  }
}
