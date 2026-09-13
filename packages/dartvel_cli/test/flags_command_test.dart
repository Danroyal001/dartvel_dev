// `dartvel flags list` and `dartvel flags prune`.
//
// Flags are debt with an owner and a date on them. `list` answers "what is
// declared, and whose is it"; `prune` answers "what is due for deletion, and
// what still reads it" — because deleting a flag means deleting the branches it
// guards, and a list of names without the code that uses them is a list of
// reasons to leave the flag in.
import 'dart:io';

import 'package:dartvel_cli/src/commands/flags_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String declarations = '''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
abstract class _Flags {
  @DVFlag(owner: 'payments', expires: '2026-12-01')
  static const bool newCheckout = false;

  @DVFlag(owner: 'search', expires: '2026-11-01', settle: DVFlagSettle.onNextLaunch)
  static const String recommender = 'baseline';

  @DVFlag(owner: 'feed', expires: '2027-02-01')
  static const int pageSize = 20;
}
''';

/// A file that reads two of the flags, the way application code does.
const String checkout = '''
import 'dartvel_client/dartvel_client.dart';

bool showNewCheckout() => Flags.newCheckout.value;

String label() {
  if (Flags.newCheckout.value) return 'Pay';
  return 'Checkout';
}

int rows() => Flags.pageSize.value;
''';

Future<Directory> project({String flags = declarations, String? app}) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_flags_command_');
  Directory(p.join(root.path, 'lib', 'flags')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'flags', 'flags.dart')).writeAsStringSync(flags);
  if (app != null) {
    File(p.join(root.path, 'lib', 'checkout.dart')).writeAsStringSync(app);
  }
  // A generated file that names every flag. It is output, not a use.
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'dartvel_client', 'flags.g.dart'))
      .writeAsStringSync('// Flags.newCheckout Flags.recommender Flags.pageSize');
  return root;
}

void main() {
  test('list names every flag with its type, owner, expiry and settle mode',
      () async {
    final Directory root = await project();
    addTearDown(() => root.deleteSync(recursive: true));

    final String out = await dvFlagsList(root: root.path, pkgName: 'app');

    for (final String expected in <String>[
      'newCheckout',
      'bool',
      'payments',
      '2026-12-01',
      'recommender',
      'String',
      'onNextLaunch',
      'pageSize',
      'int',
      'feed',
    ]) {
      expect(out, contains(expected));
    }
  });

  test('list on a project with no flags says so rather than printing nothing',
      () async {
    final Directory root = await project(flags: 'void main() {}\n');
    addTearDown(() => root.deleteSync(recursive: true));

    expect(await dvFlagsList(root: root.path, pkgName: 'app'),
        contains('No flags are declared'));
  });

  test('prune lists the flags past expiry and the code that still reads them',
      () async {
    final Directory root = await project(app: checkout);
    addTearDown(() => root.deleteSync(recursive: true));

    final String out = await dvFlagsPrune(
      root: root.path,
      pkgName: 'app',
      now: DateTime.utc(2026, 12, 2),
    );

    expect(out, contains('newCheckout'));
    expect(out, contains('recommender'));
    expect(out, isNot(contains('pageSize')),
        reason: 'pageSize expires in 2027 and is not due');
    // Every place newCheckout is read, by file and line.
    expect(out, contains('lib/checkout.dart:3'));
    expect(out, contains('lib/checkout.dart:6'));
    // recommender is due and nothing reads it: safe to delete outright.
    expect(out, contains('no remaining reads'));
  });

  test('neither the generated file nor the declaration counts as a use',
      () async {
    final Directory root = await project(app: checkout);
    addTearDown(() => root.deleteSync(recursive: true));

    final String out = await dvFlagsPrune(
      root: root.path,
      pkgName: 'app',
      now: DateTime.utc(2026, 12, 2),
    );

    expect(out, isNot(contains('dartvel_client')));
    expect(out, isNot(contains('lib/flags/flags.dart:')));
  });

  test('prune with nothing due says so', () async {
    final Directory root = await project(app: checkout);
    addTearDown(() => root.deleteSync(recursive: true));

    final String out = await dvFlagsPrune(
      root: root.path,
      pkgName: 'app',
      now: DateTime.utc(2026, 9, 1),
    );

    expect(out, contains('No flags are past their expiry'));
  });
}
