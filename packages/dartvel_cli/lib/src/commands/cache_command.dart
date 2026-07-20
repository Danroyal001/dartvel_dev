import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart';

class CacheCommand extends Command<void> {
  @override
  final String name = 'cache';

  @override
  String get description => 'Inspect and revalidate Dartvel cache tags.';

  CacheCommand() {
    addSubcommand(_CacheClearCommand());
    addSubcommand(_CacheRevalidateCommand());
    addSubcommand(_CacheInspectCommand());
  }
}

class _CacheClearCommand extends Command<void> {
  @override
  final String name = 'clear';

  @override
  String get description => 'Clear local cache tag metadata.';

  @override
  void run() {
    const DVTestHarness().resetCacheTags();
    stdout.writeln('Cleared cache tag metadata.');
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
      stdout.writeln('No cache keys were tagged with "$tag".');
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
      stdout.writeln('No cache keys are tagged with "$tag".');
      return;
    }
    for (final key in keys) {
      stdout.writeln(key);
    }
  }
}
