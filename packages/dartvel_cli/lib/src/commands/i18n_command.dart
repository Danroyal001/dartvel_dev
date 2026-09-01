/// `dartvel i18n` — extract translatable strings, and check the catalogues.
///
/// Dartvel had typed keys and a catalogue to put them in, and nothing that
/// found them. Every key had to be written twice with no check that the two
/// agreed, which is how a locale silently ends up missing half its strings.
library dartvel_cli.commands.i18n;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../i18n/extract.dart';
import '../utils/logger.dart';

class I18nCommand extends Command<void> {
  I18nCommand() {
    addSubcommand(_I18nExtractCommand());
    addSubcommand(_I18nCheckCommand());
  }

  @override
  final String name = 'i18n';

  @override
  final String description =
      'Extract translatable strings and check locale catalogues.';
}

/// Where catalogues live, and which locales exist.
class _Catalogues {
  const _Catalogues(this.dir, this.locales);

  final Directory dir;
  final List<String> locales;

  static _Catalogues find(String root, List<String> requested) {
    final Directory dir = Directory(p.join(root, 'lib', 'l10n'));
    if (requested.isNotEmpty) return _Catalogues(dir, requested);

    if (!dir.existsSync()) return _Catalogues(dir, const <String>[]);
    final List<String> found = <String>[];
    for (final FileSystemEntity entity in dir.listSync()) {
      if (entity is! File) continue;
      final String name = p.basenameWithoutExtension(entity.path);
      if (entity.path.endsWith('.arb') && name.startsWith('app_')) {
        found.add(name.substring('app_'.length));
      }
    }
    found.sort();
    return _Catalogues(dir, found);
  }

  File fileFor(String locale) => File(p.join(dir.path, 'app_$locale.arb'));
}

/// Every key declared anywhere under lib/, excluding generated output.
Set<String> _projectKeys(String root) {
  final Directory lib = Directory(p.join(root, 'lib'));
  if (!lib.existsSync()) return <String>{};

  final Set<String> keys = <String>{};
  for (final FileSystemEntity entity
      in lib.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Generated catalogues would otherwise declare the keys they were
    // generated from, so every key would look used no matter what.
    if (entity.path.contains('${p.separator}dartvel_client${p.separator}')) {
      continue;
    }
    keys.addAll(dvExtractKeys(entity.readAsStringSync()));
  }
  return keys;
}

class _I18nExtractCommand extends Command<void> {
  _I18nExtractCommand() {
    argParser.addMultiOption(
      'locale',
      abbr: 'l',
      help: 'Locales to write. Defaults to the catalogues already present.',
    );
  }

  @override
  final String name = 'extract';

  @override
  final String description =
      'Collect translatable strings into lib/l10n/app_<locale>.arb.';

  @override
  Future<void> run() async {
    final String root = Directory.current.path;
    final Set<String> keys = _projectKeys(root);

    if (keys.isEmpty) {
      Logger.log('No DVTranslationKey declarations found under lib/.');
      return;
    }

    final List<String> requested =
        (argResults?['locale'] as List<String>? ?? const <String>[])
            .map((String l) => l.trim())
            .where((String l) => l.isNotEmpty)
            .toList();

    final _Catalogues catalogues = _Catalogues.find(root, requested);
    final List<String> locales = catalogues.locales.isEmpty
        // A project with no catalogues yet gets the one its source is written
        // in, so `extract` produces something on a first run rather than
        // reporting that there is nothing to do.
        ? <String>['en']
        : catalogues.locales;

    catalogues.dir.createSync(recursive: true);

    for (final String locale in locales) {
      final File file = catalogues.fileFor(locale);
      final Map<String, String> existing =
          file.existsSync() ? dvParseCatalogue(file.readAsStringSync()) : {};

      file.writeAsStringSync(dvCatalogueJson(
        locale: locale,
        keys: keys,
        existing: existing,
      ));

      final DVI18nReport report = dvCompareCatalogue(
        keys: keys,
        translated: existing.keys.where((String k) => existing[k]!.isNotEmpty)
            .toSet(),
        locale: locale,
      );
      Logger.log('   ${p.relative(file.path, from: root)} — '
          '${keys.length} key(s), ${report.missing.length} untranslated');
    }
  }
}

class _I18nCheckCommand extends Command<void> {
  _I18nCheckCommand() {
    argParser.addFlag(
      'strict',
      negatable: false,
      help: 'Exit non-zero when a locale is missing a translation.',
    );
  }

  @override
  final String name = 'check';

  @override
  final String description =
      'Report untranslated and stale keys in each locale catalogue.';

  @override
  Future<void> run() async {
    final String root = Directory.current.path;
    final Set<String> keys = _projectKeys(root);
    final _Catalogues catalogues = _Catalogues.find(root, const <String>[]);

    if (catalogues.locales.isEmpty) {
      Logger.log('No catalogues in lib/l10n. Run `dartvel i18n extract` first.');
      return;
    }

    var incomplete = 0;
    for (final String locale in catalogues.locales) {
      final File file = catalogues.fileFor(locale);
      final Map<String, String> entries =
          dvParseCatalogue(file.readAsStringSync());
      // An empty string is a key that exists but has not been translated,
      // which is the state extract leaves a new key in -- counting it as
      // translated would make every fresh catalogue look complete.
      final Set<String> translated = entries.entries
          .where((MapEntry<String, String> e) => e.value.isNotEmpty)
          .map((MapEntry<String, String> e) => e.key)
          .toSet();

      final DVI18nReport report = dvCompareCatalogue(
        keys: keys,
        translated: translated,
        locale: locale,
      );

      if (report.isComplete) {
        Logger.log('   $locale — complete (${keys.length} keys)');
        continue;
      }
      incomplete += 1;
      Logger.log('   $locale — ${report.missing.length} untranslated, '
          '${report.stale.length} stale');
      for (final String key in report.missing.toList()..sort()) {
        Logger.log('     untranslated  $key');
      }
      for (final String key in report.stale.toList()..sort()) {
        Logger.log('     no longer declared  $key');
      }
    }

    if (incomplete > 0 && argResults?['strict'] == true) {
      // Only under --strict. A missing translation is a normal state during
      // development, and failing every build on one would mean the check gets
      // turned off rather than fixed.
      exitCode = 1;
    }
  }
}
