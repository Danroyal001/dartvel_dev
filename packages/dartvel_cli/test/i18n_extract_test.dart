// Collecting the translatable strings out of a project.
//
// Dartvel had typed keys and a catalogue to put them in, and nothing that
// found them. Every key had to be written twice -- once as a constant and
// again in each locale file -- with no check that the two agreed, which is how
// a locale silently ends up missing half its strings.
//
// The checks that matter are the ones a human reading two files cannot do:
// which keys a locale has not translated, which translations name a key that
// no longer exists, and which plural forms a language needs that the catalogue
// does not provide.
import 'package:dartvel_cli/src/i18n/extract.dart';
import 'package:test/test.dart';

const String _keys = '''
class AppText {
  static const settingsTitle = DVTranslationKey('settings.title');
  static const inboxCount = DVTranslationKey('inbox.count');
}
''';

void main() {
  group('finding keys', () {
    test('it finds every declared key', () {
      final Set<String> found = dvExtractKeys(_keys);
      expect(found, <String>{'settings.title', 'inbox.count'});
    });

    test('double quotes count too', () {
      expect(dvExtractKeys('const a = DVTranslationKey("a.b");'),
          <String>{'a.b'});
    });

    test('a key used inline is found', () {
      // Not every key is a named constant; some are written at the call site.
      expect(
        dvExtractKeys("DVText(DV.I18n.t(const DVTranslationKey('page.title')))"),
        <String>{'page.title'},
      );
    });

    test('a key inside a comment is not a key', () {
      // The most common false positive: an example in a doc comment becomes a
      // key nobody ever translates, and then a missing-translation report that
      // cries wolf gets ignored.
      const String source = '''
// const old = DVTranslationKey('removed.key');
/// Example: DVTranslationKey('doc.example')
const real = DVTranslationKey('real.key');
''';
      expect(dvExtractKeys(source), <String>{'real.key'});
    });

    test('a key inside a string literal is not a key', () {
      const String source =
          r'''const help = "write DVTranslationKey('name') to declare one";''';
      expect(dvExtractKeys(source), isEmpty);
    });

    test('an interpolated key is skipped rather than guessed at', () {
      // A key assembled at runtime cannot be extracted, and emitting the
      // literal fragment would put a key in the catalogue that never matches.
      expect(dvExtractKeys(r"DVTranslationKey('page.$name')"), isEmpty);
    });

    test('the same key twice is one key', () {
      expect(
        dvExtractKeys("DVTranslationKey('a'); DVTranslationKey('a');"),
        <String>{'a'},
      );
    });
  });

  group('comparing against a catalogue', () {
    test('it reports what a locale has not translated', () {
      final DVI18nReport report = dvCompareCatalogue(
        keys: <String>{'settings.title', 'inbox.count'},
        translated: <String>{'settings.title'},
        locale: 'fr',
      );

      expect(report.missing, <String>{'inbox.count'});
      expect(report.isComplete, isFalse);
    });

    test('it reports translations for keys that no longer exist', () {
      // The other direction, and the one nobody notices: a key is renamed and
      // every locale keeps the old string forever.
      final DVI18nReport report = dvCompareCatalogue(
        keys: <String>{'settings.title'},
        translated: <String>{'settings.title', 'settings.old'},
        locale: 'fr',
      );

      expect(report.stale, <String>{'settings.old'});
    });

    test('a complete locale reports nothing', () {
      final DVI18nReport report = dvCompareCatalogue(
        keys: <String>{'a'},
        translated: <String>{'a'},
        locale: 'fr',
      );
      expect(report.isComplete, isTrue);
      expect(report.missing, isEmpty);
      expect(report.stale, isEmpty);
    });
  });

  group('writing a catalogue', () {
    test('a new locale file has every key, untranslated', () {
      final String arb = dvCatalogueJson(
        locale: 'fr',
        keys: <String>{'b.key', 'a.key'},
        existing: const <String, String>{},
      );

      expect(arb, contains('"@@locale": "fr"'));
      expect(arb, contains('"a.key": ""'));
      expect(arb, contains('"b.key": ""'));
    });

    test('keys are sorted, so a regenerated file has a readable diff', () {
      // An unordered map means every extraction reshuffles the file and the
      // diff is the whole thing, which is how translation review stops
      // happening.
      final String arb = dvCatalogueJson(
        locale: 'fr',
        keys: <String>{'z.key', 'a.key', 'm.key'},
        existing: const <String, String>{},
      );
      expect(arb.indexOf('a.key'), lessThan(arb.indexOf('m.key')));
      expect(arb.indexOf('m.key'), lessThan(arb.indexOf('z.key')));
    });

    test('existing translations are kept', () {
      // Extraction must never overwrite work. This is the one behaviour that,
      // if wrong, destroys something a person spent hours on.
      final String arb = dvCatalogueJson(
        locale: 'fr',
        keys: <String>{'a.key', 'b.key'},
        existing: const <String, String>{'a.key': 'Bonjour'},
      );
      expect(arb, contains('"a.key": "Bonjour"'));
      expect(arb, contains('"b.key": ""'));
    });

    test('a translation whose key is gone is kept, not silently dropped', () {
      // Dropping it discards a translation over what may be a temporary
      // rename. The report names it; a human decides.
      final String arb = dvCatalogueJson(
        locale: 'fr',
        keys: <String>{'a.key'},
        existing: const <String, String>{'a.key': 'A', 'old.key': 'Ancien'},
      );
      expect(arb, contains('"old.key": "Ancien"'));
    });

    test('it round-trips', () {
      final String arb = dvCatalogueJson(
        locale: 'fr',
        keys: <String>{'a.key'},
        existing: const <String, String>{'a.key': 'Bonjour'},
      );
      expect(dvParseCatalogue(arb), <String, String>{'a.key': 'Bonjour'});
    });

    test('parsing ignores the @@locale marker and @-annotations', () {
      // ARB metadata is not a translation, and counting it as one makes every
      // catalogue look like it has a key nobody declared.
      const String arb = '{"@@locale":"fr","a":"A","@a":{"description":"x"}}';
      expect(dvParseCatalogue(arb), <String, String>{'a': 'A'});
    });
  });
}
