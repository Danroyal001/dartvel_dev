/// `contacts.getContacts` through the Contact Picker API.
///
/// Chrome on Android, and nowhere else — not Chrome on the desktop, not
/// Firefox, not Safari. The name is therefore registered only where
/// `navigator.contacts` exists, so every other browser reports it
/// unregistered instead of answering with an empty list that reads as an
/// empty address book.
///
/// It is also not the address book. The person picks which contacts the page
/// sees, one picker at a time, and the page never gets the rest. That is a
/// narrower thing than the native binding returns and the difference is worth
/// knowing: a browser cannot sync contacts, only borrow the ones somebody
/// hands over.
library dartvel_flutter.platform.web.contacts;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_interop.dart';

class DVWebContacts {
  const DVWebContacts._();

  static const Set<String> implemented = <String>{'contacts.getContacts'};

  /// Whether this browser has the Contact Picker.
  static bool get available {
    final JSObject? navigator = dvNavigator;
    if (navigator == null) return false;
    final JSObject? contacts = dvJsObject(navigator, 'contacts');
    return contacts != null && dvJsMethod(contacts, 'select') != null;
  }

  /// The fields worth asking for, in the order a caller expects them.
  static const Map<String, String> _fields = <String, String>{
    'name': 'name',
    'email': 'email',
    'tel': 'phone',
  };

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) register,
  ) {
    register('contacts.getContacts', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return pick(multiple: map['multiple'] != false);
    });
  }

  /// Opens the picker and returns whatever was handed over.
  ///
  /// An empty list means the picker was closed without a choice, which is
  /// somebody declining a single request rather than refusing the capability
  /// — so it is not an exception. A picker that will not open at all, which
  /// is what happens without a user gesture or inside an iframe, is.
  static Future<List<Map<String, String>>> pick({bool multiple = true}) async {
    final JSObject contacts = dvJsObject(dvNavigator!, 'contacts')!;

    // Only the properties this build of the browser supports. Asking for one
    // it does not know throws TypeError and loses the whole pick, and which
    // properties exist has changed between Chrome versions.
    final Set<String> supported = await _supportedProperties(contacts);
    final List<String> wanted = <String>[
      for (final String field in _fields.keys)
        if (supported.isEmpty || supported.contains(field)) field,
    ];
    if (wanted.isEmpty) {
      throw StateError(
        'This browser has a contact picker that offers none of the fields '
        'Dartvel reads: ${_fields.keys.join(', ')}.',
      );
    }

    final JSAny? result;
    try {
      result = await dvJsCall(contacts, 'select', <JSAny?>[
        <JSString>[for (final String field in wanted) field.toJS].toJS,
        JSObject()..setProperty('multiple'.toJS, multiple.toJS),
      ]);
    } on Object catch (error) {
      dvJsRefused('contacts.getContacts', error);
    }

    final Object? decoded = result.dartify();
    if (decoded is! List) return const <Map<String, String>>[];
    return <Map<String, String>>[
      for (final Object? entry in decoded)
        if (entry is Map) _flatten(entry),
    ];
  }

  static Future<Set<String>> _supportedProperties(JSObject contacts) async {
    if (dvJsMethod(contacts, 'getProperties') == null) {
      return const <String>{};
    }
    final Object? decoded =
        (await dvJsCall(contacts, 'getProperties')).dartify();
    return decoded is List
        ? <String>{for (final Object? value in decoded) '$value'}
        : const <String>{};
  }

  /// One contact, flattened to the single-value map the surface returns.
  ///
  /// The picker gives every field as a list, because somebody can have three
  /// phone numbers. `DVContacts.getContacts` is typed `Map<String, String>`
  /// and would stringify the list into `[+44…, +44…]`, which is not a phone
  /// number and is not usable by anything. The first entry is taken and the
  /// count is kept beside it, so an application that needs the others knows
  /// they exist.
  static Map<String, String> _flatten(Map<Object?, Object?> contact) {
    final Map<String, String> flat = <String, String>{};
    _fields.forEach((String field, String key) {
      final Object? value = contact[field];
      if (value is List && value.isNotEmpty) {
        flat[key] = '${value.first}';
        if (value.length > 1) flat['${key}Count'] = '${value.length}';
      } else if (value is String && value.isNotEmpty) {
        flat[key] = value;
      }
    });
    return flat;
  }
}
