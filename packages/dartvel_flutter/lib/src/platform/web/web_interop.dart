/// Reaching APIs the browser may not have.
///
/// `package:web` types every API as though it is there. That is right for
/// `document.title` and wrong for `navigator.bluetooth`: reading a typed
/// getter for something the engine never defined gives undefined, and the
/// first call on it throws a TypeError from deep inside a binding rather than
/// saying "this browser has no Bluetooth". So every optional API in these
/// files is reached by asking for the property first, which is also what
/// decides whether the binding gets registered at all.
///
/// The other half is telling two failures apart. An API the browser does not
/// have leaves its binding unregistered; an API that exists and refuses
/// throws [DVWebPermissionDenied]. [dvJsRefused] is where a caught JS error
/// is sorted into one or the other.
library dartvel_flutter.platform.web.interop;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_capabilities.dart';

/// The global `navigator`, or null where there is none.
JSObject? get dvNavigator => dvJsObject(globalContext, 'navigator');

/// The property [name] of [object] when it is an object, else null.
///
/// Null covers absent, undefined and a property that is a primitive. Every
/// caller is asking "is this API here", and none of those three is.
JSObject? dvJsObject(JSObject object, String name) {
  if (!object.has(name)) return null;
  final JSAny? value = object.getProperty<JSAny?>(name.toJS);
  return value.isA<JSObject>() ? value! as JSObject : null;
}

/// The callable property [name] of [object], or null when it is absent.
JSFunction? dvJsMethod(JSObject object, String name) {
  if (!object.has(name)) return null;
  final JSAny? value = object.getProperty<JSAny?>(name.toJS);
  return value.isA<JSFunction>() ? value! as JSFunction : null;
}

/// Whether [object] has [name] and it is not undefined or null.
bool dvJsHas(JSObject object, String name) =>
    object.has(name) && object.getProperty<JSAny?>(name.toJS) != null;

/// A plain value of the property [name], or null.
JSAny? dvJsValue(JSObject object, String name) =>
    object.has(name) ? object.getProperty<JSAny?>(name.toJS) : null;

/// [name] read as a number, or null when it is absent or not one.
num? dvJsNum(JSObject object, String name) {
  final Object? value = dvJsValue(object, name).dartify();
  return value is num ? value : null;
}

/// [name] read as a string, or null.
String? dvJsString(JSObject object, String name) {
  final Object? value = dvJsValue(object, name).dartify();
  return value is String ? value : null;
}

/// Awaits [value] when it is a promise, and passes anything else straight
/// through.
///
/// Older engines return a value where newer ones return a promise for the
/// same call — `navigator.bluetooth.getAvailability` is one — and a binding
/// that assumed either shape broke on half the browsers it ran on.
Future<JSAny?> dvJsAwait(JSAny? value) async =>
    value.isA<JSPromise<JSAny?>>() ? (value! as JSPromise<JSAny?>).toDart : value;

/// Calls [name] on [object] and awaits whatever comes back.
///
/// Throws [StateError] when the method is missing, which after a feature
/// probe means the browser has half the API — worth saying out loud rather
/// than treating as a refusal.
Future<JSAny?> dvJsCall(
  JSObject object,
  String name, [
  List<JSAny?> arguments = const <JSAny?>[],
]) async {
  final JSFunction? method = dvJsMethod(object, name);
  if (method == null) {
    throw StateError('This browser has no $name on the object it was called '
        'on, though the surrounding API is present.');
  }
  return dvJsAwait(switch (arguments.length) {
    0 => method.callAsFunction(object),
    1 => method.callAsFunction(object, arguments[0]),
    2 => method.callAsFunction(object, arguments[0], arguments[1]),
    _ => method.callAsFunction(
        object, arguments[0], arguments[1], arguments[2]),
  });
}

/// What the browser said about a failure, as near verbatim as it gave it.
String dvJsReason(Object error) {
  final String text = '$error'.trim();
  return text.isEmpty ? 'the browser gave no reason' : text;
}

/// What a browser says when it is refusing rather than failing.
///
/// The DOMException names, plus the phrase browsers use for a call that came
/// from no user gesture — that one arrives as a plain TypeError with the
/// reason only in the message, and `requestFullscreen` outside a click is the
/// commonest refusal in the whole directory.
///
/// Two names are deliberately absent. `NotReadableError` is a camera another
/// application has open, which is a fault rather than a decision.
/// `NotFoundError` means different things to different APIs — a chooser
/// somebody closed, or a machine with no camera in it — so each call site
/// that can produce one decides for itself before reaching here.
const Set<String> _refusalNames = <String>{
  'NotAllowedError',
  'SecurityError',
  'PermissionDeniedError',
  'AbortError',
  'user gesture',
  'user activation',
  'transient activation',
  // Chrome's wording for a Fullscreen or Pointer Lock request that arrives
  // with no user activation behind it, and for one a permissions policy
  // forbids. It is a plain TypeError with the reason only in the message, so
  // matching the name would have sorted the commonest refusal there is into
  // "something went wrong".
  'Permissions check failed',
  'permissions policy',
  'Permissions Policy',
};

/// Turns a caught JS error into the right Dart one and throws it.
///
/// A refusal becomes [DVWebPermissionDenied] so an application can tell it
/// from the "not registered" error an absent API produces. Everything else
/// keeps the browser's own words in a [StateError]: swallowing the text is
/// how a camera held open by another tab became indistinguishable from a
/// camera the person denied.
Never dvJsRefused(String binding, Object error) {
  final String reason = dvJsReason(error);
  if (_refusalNames.any(reason.contains)) {
    throw DVWebPermissionDenied(binding, reason);
  }
  throw StateError('$binding failed: $reason');
}
