/// NFC on Linux: neard, over the bus.
///
/// A tag on a kiosk is how a member taps in, how a technician unlocks staff
/// mode, how a pallet identifies itself at a loading bay. Linux answers that
/// through neard, which exports adapters, the tag currently on the reader and
/// the records written to it. Reading and writing are different jobs and both
/// are here now: writing is the half a kiosk needs to hand somebody a card --
/// a locker key, a visitor badge, a pallet label.
///
/// The distinction this file exists to keep is between silences. A machine
/// with no neard and a reader with nobody's card on it are the same absence
/// of an answer, and telling them apart is the difference between "hold your
/// card nearer" and "this unit's reader is not running".
library;

import 'dart:async';

import 'package:dbus/dbus.dart';

/// The neard bindings.
class DVLinuxNfc {
  DVLinuxNfc._();

  static const String _service = 'org.neard';
  static const String _adapter = 'org.neard.Adapter';
  static const String _record = 'org.neard.Record';
  static const String _tag = 'org.neard.Tag';

  static const Set<String> bindings = <String>{
    'nfc.isAvailable',
    'nfc.readTag',
    'nfc.writeTag',
  };

  /// Why the last read or write did not do what was asked, when the reason is
  /// not simply "no tag".
  static String? lastError;

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind, {
    DBusClient? bus,
  }) {
    bind('nfc.isAvailable',
        (Object? _) => isAvailableOn(bus ?? DBusClient.system()));
    bind('nfc.readTag', (Object? _) => readTagOn(bus ?? DBusClient.system()));
    bind('nfc.writeTag', (Object? arguments) {
      final Map<Object?, Object?> a =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return writeTagOn(
        bus ?? DBusClient.system(),
        '${a['value'] ?? ''}',
        language: a['language'] is String ? a['language']! as String : 'en',
      );
    });
  }

  /// Whether this machine has a reader that could read something now.
  ///
  /// A powered adapter, not merely a present one: an adapter that exists and
  /// is switched off would otherwise tell somebody to tap a reader that
  /// cannot read.
  static Future<bool> isAvailableOn(DBusClient bus) async {
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await _managedObjects(bus);
    for (final Map<String, Map<String, DBusValue>> interfaces
        in objects.values) {
      final Map<String, DBusValue>? adapter = interfaces[_adapter];
      if (adapter == null) continue;
      final DBusValue? powered = adapter['Powered'];
      if (powered is DBusBoolean && powered.value) return true;
    }
    return false;
  }

  /// What is written on the tag currently on the reader, or null when there
  /// is none.
  ///
  /// Null is the normal state of a reader nobody has tapped, not a fault: an
  /// exception here would make every idle moment look like one.
  static Future<String?> readTagOn(DBusClient bus) async {
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await _managedObjects(bus);
    final List<DBusObjectPath> records = <DBusObjectPath>[
      for (final MapEntry<DBusObjectPath, Map<String, Map<String, DBusValue>>> e
          in objects.entries)
        if (e.value.containsKey(_record)) e.key,
    ]..sort((DBusObjectPath a, DBusObjectPath b) => a.value.compareTo(b.value));
    for (final DBusObjectPath path in records) {
      final Map<String, DBusValue> record = objects[path]![_record]!;
      // A Text record carries its words; a URI record carries the address.
      // Both are what somebody wrote on the tag, which is what a caller
      // asked for.
      final DBusValue? representation =
          record['Representation'] ?? record['URI'];
      if (representation is DBusString && representation.value.isNotEmpty) {
        return representation.value;
      }
    }
    return null;
  }


  /// The URI schemes an NDEF URI record is worth writing for.
  ///
  /// An allow list rather than "anything with a colon". A value like
  /// `Type2:something` parses as a URI with the scheme `type2`, and writing
  /// that as a URI record produces a tag no reader can follow -- while the
  /// same value as text is exactly what somebody meant.
  static const Set<String> _uriSchemes = <String>{
    'http', 'https', 'ftp', 'ftps', 'sftp', 'file', 'smb', 'nfs',
    'mailto', 'tel', 'sms', 'geo', 'urn',
  };

  /// Writes [value] to the tag currently on the reader.
  ///
  /// Almost every way this goes wrong still looks like it worked, which is
  /// why so little of it is a straight call:
  ///
  ///   * a URI written into a Text record reads back as the right characters
  ///     and does nothing when a phone touches it;
  ///   * an NDEF Text record with no language code shows as empty on some
  ///     readers, so a tag that was written reads as blank;
  ///   * a read-only tag refuses at the chip, and somebody told only
  ///     "failed" presents the same card again;
  ///   * an empty record is indistinguishable from a tag never written.
  ///
  /// False with [lastError] set, rather than an exception: this is called
  /// from a screen somebody is standing at, and the reason is the thing they
  /// need.
  static Future<bool> writeTagOn(
    DBusClient bus,
    String value, {
    String language = 'en',
  }) async {
    final String text = value.trim();
    if (text.isEmpty) {
      lastError = 'There is nothing to write. A tag written with an empty '
          'record reads the same as one that was never written.';
      return false;
    }

    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
        await _managedObjects(bus);
    // _managedObjects has already said why, and "neard is not running" must
    // not be replaced by "no tag on the reader" -- they send somebody to
    // different places.
    if (lastError != null) return false;

    final List<DBusObjectPath> tags = <DBusObjectPath>[
      for (final MapEntry<DBusObjectPath, Map<String, Map<String, DBusValue>>> e
          in objects.entries)
        if (e.value.containsKey(_tag)) e.key,
    ]..sort((DBusObjectPath a, DBusObjectPath b) => a.value.compareTo(b.value));
    if (tags.isEmpty) {
      lastError = 'There is no tag on the reader. Hold one against it and '
          'try again.';
      return false;
    }

    final DBusObjectPath path = tags.first;
    final DBusValue? readOnly = objects[path]![_tag]!['ReadOnly'];
    if (readOnly is DBusBoolean && readOnly.value) {
      lastError = 'That tag is read-only: it was locked when it was made, '
          'and presenting it again will not help.';
      return false;
    }

    final Uri? uri = Uri.tryParse(text);
    final bool isUri = uri != null &&
        uri.hasScheme &&
        _uriSchemes.contains(uri.scheme.toLowerCase());
    final Map<DBusValue, DBusValue> attributes = <DBusValue, DBusValue>{
      const DBusString('Type'):
          DBusVariant(DBusString(isUri ? 'URI' : 'Text')),
      if (isUri)
        const DBusString('URI'): DBusVariant(DBusString(text))
      else ...<DBusValue, DBusValue>{
        const DBusString('Representation'): DBusVariant(DBusString(text)),
        // NDEF puts a language code in every Text record, and a reader that
        // finds none shows the record as empty.
        const DBusString('Language'): DBusVariant(DBusString(language)),
        const DBusString('Encoding'): DBusVariant(const DBusString('UTF-8')),
      },
    };

    try {
      await bus.callMethod(
        destination: _service,
        path: path,
        interface: _tag,
        name: 'Write',
        values: <DBusValue>[
          DBusDict(DBusSignature('s'), DBusSignature('v'), attributes),
        ],
        replySignature: DBusSignature(''),
      );
      lastError = null;
      return true;
    } on DBusMethodResponseException catch (error) {
      // What neard said, because it is the chip's own answer: the tag was
      // taken off the reader, the record did not fit, the tag is formatted
      // for something else. A caller told "failed" learns none of it.
      final String detail = error.response.values
          .whereType<DBusString>()
          .map((DBusString v) => v.value)
          .join('; ');
      lastError = detail.isEmpty
          ? 'neard refused the write.'
          : 'neard refused the write: $detail';
      return false;
    } on Object catch (error) {
      lastError = 'The tag could not be written: $error';
      return false;
    }
  }
  static Future<Map<DBusObjectPath, Map<String, Map<String, DBusValue>>>>
      _managedObjects(DBusClient bus) async {
    try {
      final DBusRemoteObjectManager manager = DBusRemoteObjectManager(
        bus,
        name: _service,
        path: DBusObjectPath('/'),
      );
      final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> objects =
          await manager.getManagedObjects();
      lastError = null;
      return objects;
    } on DBusServiceUnknownException {
      lastError = 'neard is not on the bus: no NFC service is running.';
      return const <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
    } on Object catch (error) {
      lastError = 'The neard service could not be read: $error';
      return const <DBusObjectPath, Map<String, Map<String, DBusValue>>>{};
    }
  }
}
