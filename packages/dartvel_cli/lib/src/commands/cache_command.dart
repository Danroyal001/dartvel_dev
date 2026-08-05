import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart';

class CacheCommand extends Command<void> {
  @override
  final String name = 'cache';

  @override
  String get description => 'Inspect and revalidate the Dartvel cache.';

  CacheCommand() {
    addSubcommand(_CacheClearCommand());
    addSubcommand(_CacheRevalidateCommand());
    addSubcommand(_CacheInspectCommand());
    addSubcommand(_CachePurgeCommand());
  }
}

/// Cache tags live in the memory of whichever process registered them, so a
/// separate CLI invocation cannot see a running application's tags. Saying so
/// is better than printing "no keys were tagged", which reads as a finding.
const String _tagScopeNote =
    'Note: cache tags are held in the process that registered them, so this '
    'reflects the CLI process only, not a running application.';

/// Opens the persistent cache table shared with an application.
Future<SqliteDVDatabaseAdapter> _openDatabase(String path) async {
  if (!File(path).existsSync()) {
    throw UsageException(
      'No database exists at "$path".',
      'Pass --database with the path the application configured for '
          'DVDatabaseCacheAdapter.',
    );
  }
  return SqliteDVDatabaseAdapter.file(path);
}

class _CacheClearCommand extends Command<void> {
  @override
  final String name = 'clear';

  @override
  String get description =>
      'Clear a persistent cache, or local cache tag metadata.';

  _CacheClearCommand() {
    argParser
      ..addOption(
        'database',
        help: 'Path to the SQLite database backing DVDatabaseCacheAdapter.',
      )
      ..addOption(
        'table',
        defaultsTo: 'dartvel_cache',
        help: 'Cache table name, when it was customised.',
      );
  }

  @override
  Future<void> run() async {
    final path = argResults?['database'] as String?;
    if (path == null) {
      const DVTestHarness().resetCacheTags();
      stdout
        ..writeln('Cleared cache tag metadata.')
        ..writeln(_tagScopeNote)
        ..writeln(
          'To clear a persistent cache, pass --database with its path.',
        );
      return;
    }

    final database = await _openDatabase(path);
    try {
      final table = argResults!['table'] as String;
      // Going through the adapter validates the table name as a plain SQL
      // identifier and creates the table when it is absent, so a fresh cache
      // reports "0 entries" instead of raising a raw SQLite error.
      await DVDatabaseCacheAdapter(database, tableName: table).initialize();
      final removed = await database.execute('DELETE FROM $table');
      stdout.writeln('Cleared $removed cache entr'
          '${removed == 1 ? 'y' : 'ies'} from "$table" in $path.');
    } finally {
      database.close();
    }
  }
}

class _CachePurgeCommand extends Command<void> {
  @override
  final String name = 'purge';

  @override
  String get description =>
      'Remove expired entries from a persistent cache, reclaiming space.';

  _CachePurgeCommand() {
    argParser
      ..addOption(
        'database',
        help: 'Path to the SQLite database backing DVDatabaseCacheAdapter.',
      )
      ..addOption('table', defaultsTo: 'dartvel_cache');
  }

  @override
  Future<void> run() async {
    final path = argResults?['database'] as String?;
    if (path == null) {
      throw UsageException(
        'Provide --database with the path to the persistent cache.',
        usage,
      );
    }

    final database = await _openDatabase(path);
    try {
      final removed = await DVDatabaseCacheAdapter(
        database,
        tableName: argResults!['table'] as String,
      ).purgeExpired();
      stdout.writeln('Purged $removed expired entr'
          '${removed == 1 ? 'y' : 'ies'}.');
    } finally {
      database.close();
    }
  }
}

class _CacheRevalidateCommand extends Command<void> {
  @override
  final String name = 'revalidate';

  @override
  String get description => 'Revalidate a cache tag and print affected keys.';

  @override
  void run() {
    final args = argResults?.rest ?? const <String>[];
    if (args.length != 1 || args.single.trim().isEmpty) {
      throw UsageException('Provide a cache tag to revalidate.', usage);
    }
    final tag = args.single.trim();
    final keys = const DVCacheTags().revalidateTag(tag).toList()..sort();
    if (keys.isEmpty) {
      stdout
        ..writeln('No cache keys were tagged with "$tag".')
        ..writeln(_tagScopeNote);
      return;
    }
    stdout.writeln('Revalidated "$tag"; affected keys:');
    for (final key in keys) {
      stdout.writeln(key);
    }
  }
}

class _CacheInspectCommand extends Command<void> {
  @override
  final String name = 'inspect';

  @override
  String get description => 'Inspect cache keys attached to a tag.';

  @override
  void run() {
    final args = argResults?.rest ?? const <String>[];
    if (args.length != 1 || args.single.trim().isEmpty) {
      throw UsageException('Provide a cache tag to inspect.', usage);
    }
    final tag = args.single.trim();
    final keys = const DVCacheTags().keysForTag(tag).toList()..sort();
    if (keys.isEmpty) {
      stdout
        ..writeln('No cache keys are tagged with "$tag".')
        ..writeln(_tagScopeNote);
      return;
    }
    for (final key in keys) {
      stdout.writeln(key);
    }
  }
}
