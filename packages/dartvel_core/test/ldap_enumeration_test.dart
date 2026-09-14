// An LDAP sign-in for a username the directory does not hold must do the work
// a wrong password does. Returning early after an empty search skips the
// second bind, which is a whole round trip to the directory: an attacker
// timing the answer learns which usernames exist without ever guessing one.
//
// The directory here is a fake served on loopback, so what is counted is the
// binds that actually crossed a socket rather than a method call.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/src/auth/ldap.dart';
import 'package:test/test.dart';

class _Tlv {
  _Tlv(this.tag, this.content);
  final int tag;
  final Uint8List content;

  List<_Tlv> get children => _readAll(content);
  String get text => utf8.decode(content);
}

({_Tlv element, int next})? _readOne(Uint8List bytes, int offset) {
  if (offset + 2 > bytes.length) return null;
  final tag = bytes[offset];
  var at = offset + 1;
  var length = bytes[at++];
  if (length & 0x80 != 0) {
    final count = length & 0x7f;
    if (at + count > bytes.length) return null;
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | bytes[at++];
    }
  }
  if (at + length > bytes.length) return null;
  return (
    element: _Tlv(tag, Uint8List.sublistView(bytes, at, at + length)),
    next: at + length,
  );
}

List<_Tlv> _readAll(Uint8List bytes) {
  final out = <_Tlv>[];
  var at = 0;
  while (true) {
    final read = _readOne(bytes, at);
    if (read == null) return out;
    out.add(read.element);
    at = read.next;
  }
}

/// A directory with a service account and some people, answering binds and
/// equality searches the way OpenLDAP does -- except that a bind to a DN that
/// does not exist answers `noSuchObject` (32) when [strictUnknownDn] is set,
/// which some servers do and which must not turn a failed sign-in into an
/// error.
class FakeDirectory {
  FakeDirectory({this.strictUnknownDn = false});

  static const serviceDn = 'cn=service,dc=example,dc=test';
  static const servicePassword = 'service-secret';
  static const baseDn = 'ou=people,dc=example,dc=test';

  final bool strictUnknownDn;
  final Map<String, String> passwords = <String, String>{
    'uid=ada,$baseDn': 'lovelace-1843',
  };

  /// Every bind DN received, in order.
  final List<String> binds = <String>[];

  late final ServerSocket _server;

  int get port => _server.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() => _server.close();

  void _serve(Socket socket) {
    var buffer = Uint8List(0);
    socket.listen((chunk) {
      buffer = Uint8List.fromList(<int>[...buffer, ...chunk]);
      var at = 0;
      while (true) {
        final read = _readOne(buffer, at);
        if (read == null) break;
        at = read.next;
        _answer(socket, read.element);
      }
      buffer = Uint8List.sublistView(buffer, at);
    }, onError: (Object _) {}, cancelOnError: true);
  }

  List<int> _message(int id, List<int> operation) =>
      DVBer.tlv(DVBer.sequence, <int>[...DVBer.int32(id), ...operation]);

  List<int> _result(int tag, int code) => DVBer.tlv(tag, <int>[
        ...DVBer.tlv(DVBer.enumerated, <int>[code]),
        ...DVBer.string(''),
        ...DVBer.string(''),
      ]);

  void _answer(Socket socket, _Tlv message) {
    final parts = message.children;
    var id = 0;
    for (final byte in parts[0].content) {
      id = (id << 8) | byte;
    }
    final operation = parts[1];

    switch (operation.tag) {
      case DVBer.bindRequest:
        final fields = operation.children;
        final dn = fields[1].text;
        final password = fields[2].text;
        binds.add(dn);
        final int code;
        if (dn == serviceDn) {
          code = password == servicePassword ? 0 : 49;
        } else if (passwords.containsKey(dn)) {
          code = passwords[dn] == password ? 0 : 49;
        } else {
          code = strictUnknownDn ? 32 : 49;
        }
        socket.add(_message(id, _result(DVBer.bindResponse, code)));
      case DVBer.searchRequest:
        final fields = operation.children;
        final filter = fields[6].children;
        final attribute = filter[0].text;
        final value = filter[1].text;
        final dn = '$attribute=$value,$baseDn';
        if (passwords.containsKey(dn)) {
          socket.add(_message(
            id,
            DVBer.tlv(DVBer.searchResultEntry, <int>[
              ...DVBer.string(dn),
              ...DVBer.tlv(DVBer.sequence, <int>[
                ...DVBer.tlv(DVBer.sequence, <int>[
                  ...DVBer.string('uid'),
                  ...DVBer.tlv(DVBer.set, DVBer.string(value)),
                ]),
              ]),
            ]),
          ));
        }
        socket.add(_message(id, _result(DVBer.searchResultDone, 0)));
      default:
        // An unbind: the client closes.
        break;
    }
  }
}

void main() {
  late FakeDirectory directory;

  DVLdapAuthenticator authenticator() => DVLdapAuthenticator(
        host: InternetAddress.loopbackIPv4.address,
        port: directory.port,
        baseDn: FakeDirectory.baseDn,
        bindDn: FakeDirectory.serviceDn,
        bindPassword: FakeDirectory.servicePassword,
      );

  Future<void> start({bool strictUnknownDn = false}) async {
    directory = FakeDirectory(strictUnknownDn: strictUnknownDn);
    await directory.start();
    addTearDown(directory.stop);
  }

  test('the fake directory signs in the right password', () async {
    await start();
    final entry = await authenticator().authenticate('ada', 'lovelace-1843');
    expect(entry?.dn, 'uid=ada,${FakeDirectory.baseDn}');
  });

  test('an unknown username binds as often as a wrong password', () async {
    await start();

    directory.binds.clear();
    expect(await authenticator().authenticate('ada', 'not-it'), isNull);
    final wrong = List<String>.of(directory.binds);

    directory.binds.clear();
    expect(await authenticator().authenticate('nobody', 'not-it'), isNull);
    final missing = List<String>.of(directory.binds);

    expect(missing.length, wrong.length,
        reason: 'skipping the password bind answers a miss a round trip '
            'sooner, which names the accounts that exist');
  });

  test('the stand-in bind never names a real account', () async {
    await start();
    directory.binds.clear();
    await authenticator().authenticate('nobody', 'not-it');

    final userBinds =
        directory.binds.where((dn) => dn != FakeDirectory.serviceDn).toList();
    expect(userBinds, hasLength(1));
    expect(directory.passwords.keys, isNot(contains(userBinds.single)),
        reason: 'a failed bind against a real DN counts toward its lockout');
  });

  test('a directory answering noSuchObject for the stand-in is still a '
      'refused sign-in, not a fault', () async {
    await start(strictUnknownDn: true);
    expect(await authenticator().authenticate('nobody', 'not-it'), isNull);
  });
}
