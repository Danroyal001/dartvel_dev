// `dartvel create` must not eat somebody else's pubspec.
//
// `create` scaffolds a project, and one of its steps replaces `pubspec.yaml`
// with the Dartvel template -- correct in an empty directory, where the file
// it replaces is the one `flutter create` just wrote. `init` and `new` are
// aliases of that same command, and `init` is the word a team with an existing
// application reaches for. Running it in their repository rewrote their
// pubspec: every dependency, every version, every bit of configuration they
// had declared, replaced by the scaffold, announced as an information line
// reading "Overwriting pubspec.yaml with Dartvel configuration...".
//
// Nothing else in the tree is destructive like that. The specification says
// `create` makes a project that did not exist and `init` initializes Dartvel
// inside one that does, and that it refuses rather than scaffolds when it
// finds a `pubspec.yaml` it did not write (DV-ADOPT-005). This is the refusal.
import 'dart:io';

import 'package:dartvel_cli/src/commands/init_command.dart';
import 'package:test/test.dart';

/// A pubspec of the kind a team already has: their name, their dependencies,
/// and nothing of Dartvel's.
const String _theirs = '''
name: acme_app
description: An application that existed before Dartvel did.
version: 2.4.0

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  bloc: ^8.1.0
  dio: ^5.5.0
''';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_create_guard_'));
  tearDown(() => root.deleteSync(recursive: true));

  File pubspec() => File('${root.path}/pubspec.yaml');

  test('refuses a project it did not create', () {
    pubspec().writeAsStringSync(_theirs);

    final String? refusal = dvForeignProjectRefusal(root.path);

    expect(refusal, isNotNull,
        reason: 'a pubspec with no dartvel section belongs to somebody else, '
            'and scaffolding over it destroys their dependency list');
    expect(refusal, contains('DV-ADOPT-005'),
        reason: 'the refusal carries the code so `dartvel explain` can '
            'answer for it, like every other refusal');
    // The message has to name the file, because the reader is about to be
    // told no by a command they expected to say yes.
    expect(refusal, contains('pubspec.yaml'));
  });

  test('leaves that pubspec exactly as it found it', () {
    pubspec().writeAsStringSync(_theirs);

    dvForeignProjectRefusal(root.path);

    expect(pubspec().readAsStringSync(), _theirs,
        reason: 'the check itself must not write anything');
  });

  test('allows an empty directory, which is what create is for', () {
    expect(dvForeignProjectRefusal(root.path), isNull);
  });

  test('allows a project Dartvel wrote, so create can be re-run', () {
    // The `dartvel:` key is the marker: the template writes it and nothing
    // else does, so its presence means this pubspec came from here.
    pubspec().writeAsStringSync('''
name: my_app
version: 0.0.1

dependencies:
  flutter:
    sdk: flutter

dartvel:
  pagesDir: lib/pages
''');

    expect(dvForeignProjectRefusal(root.path), isNull,
        reason: 're-running create on a Dartvel project is not the case this '
            'guard exists for');
  });

  test('a commented-out dartvel key does not count as Dartvel\'s own', () {
    // The marker has to be the real key. Someone reading about Dartvel and
    // leaving a commented example in their pubspec still owns that file.
    pubspec().writeAsStringSync('$_theirs\n# dartvel:\n#   pagesDir: lib/pages\n');

    expect(dvForeignProjectRefusal(root.path), isNotNull);
  });
}
