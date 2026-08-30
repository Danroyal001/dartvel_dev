// LDAP against a real OpenLDAP.
//
// The encoding tests pin the bytes; this is the only thing that shows a
// directory accepts them. Almost every mistake in BER produces a server that
// closes the connection with no explanation, so "it worked against my own
// decoder" means very little here.
//
// Two behaviours matter more than the happy path, and both authenticate when
// they are wrong: a bind with an empty password, which many servers answer as
// an anonymous bind and therefore with success, and a username containing
// filter metacharacters, which rewrites the search rather than failing it.
@Tags(<String>['live'])
library;

import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  final String? host = io.Platform.environment['DARTVEL_LDAP_HOST'];
  if (host == null || host.isEmpty) {
    test('skipped: DARTVEL_LDAP_HOST is not set', () {}, skip: true);
    return;
  }

  final int port =
      int.tryParse(io.Platform.environment['DARTVEL_LDAP_PORT'] ?? '') ?? 389;
  final String baseDn =
      io.Platform.environment['DARTVEL_LDAP_BASE'] ?? 'dc=example,dc=org';
  final String adminDn =
      io.Platform.environment['DARTVEL_LDAP_ADMIN'] ?? 'cn=admin,$baseDn';
  final String adminPassword =
      io.Platform.environment['DARTVEL_LDAP_PASSWORD'] ?? 'adminpassword';

  DVLdapAuthenticator authenticator({String userFilter = 'uid'}) =>
      DVLdapAuthenticator(
        host: host,
        port: port,
        baseDn: baseDn,
        bindDn: adminDn,
        bindPassword: adminPassword,
        userFilter: userFilter,
      );

  test('the service account binds, which proves the encoding is accepted', () async {
    final DVLdapClient client =
        await DVLdapClient.connect(host: host, port: port);
    addTearDown(client.close);

    expect(await client.bind(adminDn, adminPassword), isTrue);
  });

  test('a wrong service password is refused rather than throwing', () async {
    final DVLdapClient client =
        await DVLdapClient.connect(host: host, port: port);
    addTearDown(client.close);

    // Result code 49 is a failed login, not a fault, and must not surface as
    // an exception a caller has to distinguish from a network error.
    expect(await client.bind(adminDn, 'wrong-password'), isFalse);
  });

  test('a search finds the seeded user', () async {
    final DVLdapClient client =
        await DVLdapClient.connect(host: host, port: port);
    addTearDown(client.close);
    await client.bind(adminDn, adminPassword);

    final List<DVLdapEntry> found = await client.search(
      baseDn: baseDn,
      filter: 'uid=ada',
      attributes: const <String>['cn', 'uid'],
    );

    expect(found, hasLength(1));
    expect(found.single.dn.toLowerCase(), contains('uid=ada'));
    expect(found.single.first('uid'), 'ada');
  });

  test('the right password authenticates', () async {
    final DVLdapEntry? user =
        await authenticator().authenticate('ada', 'lovelace');

    expect(user, isNotNull);
    expect(user!.first('uid'), 'ada');
  });

  test('the wrong password does not', () async {
    expect(await authenticator().authenticate('ada', 'not-the-password'),
        isNull);
  });

  test('an unknown user does not', () async {
    expect(await authenticator().authenticate('nobody', 'lovelace'), isNull);
  });

  test('an empty password never authenticates', () async {
    // The dangerous one. A bind with a DN and no password is an *anonymous*
    // bind to many directories, which succeeds -- so a blank password would be
    // a valid login for every account.
    expect(await authenticator().authenticate('ada', ''), isNull);
  });

  test('a wildcard in the username does not match every account', () async {
    // Unescaped, `*` makes the filter `uid=*` and the directory returns every
    // user. Binding as the first would authenticate whoever came back.
    expect(await authenticator().authenticate('*', 'lovelace'), isNull);
  });

  test('a filter metacharacter cannot rewrite the search', () async {
    // The LDAP equivalent of SQL injection, and it authenticates rather than
    // erroring when it works.
    expect(
      await authenticator().authenticate('ada)(uid=*', 'lovelace'),
      isNull,
    );
  });

  test('a large attribute value survives the long-form length', () async {
    // Crosses the 127-byte boundary on the wire, which is where a short-form
    // length bug actually bites.
    final DVLdapClient client =
        await DVLdapClient.connect(host: host, port: port);
    addTearDown(client.close);
    await client.bind(adminDn, adminPassword);

    final List<DVLdapEntry> found = await client.search(
      baseDn: baseDn,
      filter: 'uid=${'a' * 200}',
    );

    // No match is the point; the request has to be well-formed enough for the
    // server to answer at all rather than dropping the connection.
    expect(found, isEmpty);
  });
}
