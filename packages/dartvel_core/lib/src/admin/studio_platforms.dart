/// Studio's Platforms screen: each platform's own settings, written to the
/// same `dartvel.platforms` object code writes.
///
/// There is one source of truth, the project's configuration, and Studio
/// writes to it rather than keeping a second copy the build would have to
/// reconcile:
///
/// - On a development server, which has the project's source beside it, a
///   change is written into `pubspec.yaml` at once, every other line and
///   comment kept, so it shows up as a diff in the working tree.
/// - On a deployed server, which has no source, the change waits in the
///   database and the GitHub screen sends it as a change to the repository's
///   `pubspec.yaml`, as a pull request or a push, with the diff shown first.
///
/// Either way it reaches the pages with the next build: the snippets are
/// written into the shell every page is made from.
///
/// The HTML runs as it is, with the page's full authority, so editing it is
/// its own permission, [dvStudioEditPlatformsAction]: the application's
/// owner by default, and whoever an application's own answer names.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../config/platforms.dart';
import '../database/adapter.dart';
import '../database/records.dart';
import '../web/document_slots.dart';

/// The permission to change the HTML every page carries.
///
/// The framework's answer is the application's owner: the account its first
/// run created, or, for an application that had accounts before that, every
/// operator it granted Studio to. An application names its own with
/// `DV.Auth.authorization.registerAction(dvStudioEditPlatformsAction, ...)`;
/// the caller it is handed is the Studio account's user id.
const String dvStudioEditPlatformsAction = 'Studio.editPlatforms';

/// Refused, with a status and words a person can act on.
class DVStudioPlatformsRefusal implements Exception {
  DVStudioPlatformsRefusal(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Whether a `document` object holds no snippet at all.
bool dvStudioDocumentIsEmpty(Map<Object?, Object?> document) => document.values.every(
      (Object? slot) => slot == null || (slot is List && slot.isEmpty),
    );

/// [pubspec] with `dartvel.platforms.web.document` set to [document], every
/// other line and comment kept. An empty [document] removes the setting. The
/// same setting at its older home, `dartvel.web.document`, is removed, so
/// the two homes can never disagree.
///
/// Throws [DVStudioPlatformsRefusal] for a project whose `dartvel:` names a
/// Dart config file: the setting is a field of that class, and Studio does
/// not rewrite Dart.
String dvStudioPubspecWithPlatforms(String pubspec, Map<String, Object?> document) {
  final Object? root = loadYaml(pubspec);
  if (root is! Map) {
    throw DVStudioPlatformsRefusal(409, 'bad_pubspec', 'pubspec.yaml is not a map, so Studio cannot change it.');
  }
  final Object? dartvel = root['dartvel'];
  if (dartvel is String) {
    throw DVStudioPlatformsRefusal(
      409,
      'dart_config',
      "This project's settings are written in Dart, in $dartvel. Set the "
          '`platforms` field of its config class there; Studio shows it but '
          'does not rewrite Dart.',
    );
  }
  final bool empty = dvStudioDocumentIsEmpty(document);
  final YamlEditor editor = YamlEditor(pubspec);
  final Map<String, Object?> value = <String, Object?>{
    for (final MapEntry<String, Object?> slot in document.entries)
      if (slot.value is List && (slot.value! as List).isNotEmpty) slot.key: slot.value,
  };
  if (dartvel == null) {
    if (empty) return pubspec;
    editor.update(<Object>['dartvel'], <String, Object?>{
      'platforms': <String, Object?>{
        'web': <String, Object?>{'document': value},
      },
    });
    return editor.toString();
  }
  if (dartvel is! Map) {
    throw DVStudioPlatformsRefusal(409, 'bad_pubspec', 'dartvel: in pubspec.yaml is not a map.');
  }

  final Object? oldWeb = dartvel['web'];
  if (oldWeb is Map && oldWeb.containsKey('document')) {
    editor.remove(<Object>['dartvel', 'web', 'document']);
    if (oldWeb.length == 1) editor.remove(<Object>['dartvel', 'web']);
  }

  final Object? platforms = dartvel['platforms'];
  final Object? web = platforms is Map ? platforms['web'] : null;
  if (empty) {
    if (web is Map && web.containsKey('document')) {
      if (web.length > 1) {
        editor.remove(<Object>['dartvel', 'platforms', 'web', 'document']);
      } else if ((platforms! as Map).length > 1) {
        editor.remove(<Object>['dartvel', 'platforms', 'web']);
      } else {
        editor.remove(<Object>['dartvel', 'platforms']);
      }
    }
  } else if (platforms is! Map) {
    editor.update(<Object>['dartvel', 'platforms'], <String, Object?>{
      'web': <String, Object?>{'document': value},
    });
  } else if (web is! Map) {
    editor.update(<Object>['dartvel', 'platforms', 'web'], <String, Object?>{'document': value});
  } else {
    editor.update(<Object>['dartvel', 'platforms', 'web', 'document'], value);
  }
  return editor.toString();
}

/// The HTML each slot comes to, from the settings and the file contents
/// [files] (path to text) a build or a project supplied. A file nobody
/// supplied comes to nothing rather than failing the screen.
Map<DVDocumentSlot, String> dvStudioEffectiveEdges(Map<Object?, Object?> document, Map<Object?, Object?> files) {
  final DVPlatformSettingsRead read = DVPlatformSettings.fromPubspec(<String, Object?>{
    'web': <String, Object?>{'document': document},
  });
  return dvResolveDocumentSlots(
    read.settings.web.document,
    readFile: (String path) => '${files[path] ?? ''}'.trimRight(),
  );
}

/// The collection a change waiting for GitHub is kept in.
const String dvStudioSettingsTable = 'dartvel_studio_settings';

const DVRecordShape _settingsShape = DVRecordShape(
  collection: dvStudioSettingsTable,
  key: 'key',
  fields: <String, DVFieldType>{
    'key': DVFieldType.text,
    'value': DVFieldType.text,
  },
);

const String _platformsKey = 'platforms.web.document';

/// The `platforms.web.document` saved in Studio and not yet in the
/// repository, or null when nothing waits.
Future<Map<String, Object?>?> dvStudioPendingPlatforms(DVDatabaseAdapter database) async {
  final DVRecordAdapter records = DVRecordAdapter.over(database);
  await records.ensure(_settingsShape);
  final List<Map<String, Object?>> rows =
      await records.find(dvStudioSettingsTable, where: DVFilter.equals('key', _platformsKey));
  if (rows.isEmpty) return null;
  final Object? value = jsonDecode('${rows.first['value']}');
  return value is Map ? value.cast<String, Object?>() : null;
}

/// Keeps [document] as the change waiting for GitHub.
Future<void> dvStudioSavePendingPlatforms(DVDatabaseAdapter database, Map<String, Object?> document) async {
  final DVRecordAdapter records = DVRecordAdapter.over(database);
  await records.ensure(_settingsShape);
  await records.delete(dvStudioSettingsTable, where: DVFilter.equals('key', _platformsKey));
  await records.insert(dvStudioSettingsTable, <String, Object?>{
    'key': _platformsKey,
    'value': jsonEncode(document),
  });
}

/// Problems with [document] as a value of `platforms.web.document`, in the
/// words the build uses. [readFile] answers a snippet file's text, or null
/// when it is not there.
List<String> dvStudioPlatformsProblems(Object? document, String? Function(String path) readFile) {
  if (document is! Map) return <String>['document must be a map with head, bodyStart and bodyEnd.'];
  final DVPlatformSettingsRead read = DVPlatformSettings.fromPubspec(<String, Object?>{
    'web': <String, Object?>{'document': document},
  });
  final List<String> problems = <String>[...read.problems];
  for (final DVDocumentSlot slot in DVDocumentSlot.values) {
    for (final DVHtmlSnippet snippet in read.settings.web.document.of(slot)) {
      final DVWebFileRef? file = snippet.file;
      if (file == null) continue;
      final String? text = readFile(file.path);
      if (text == null) {
        problems.add('dartvel.platforms.web.document.${slot.key}: ${file.path} is not there.');
        continue;
      }
      for (final String problem in dvHtmlSnippetProblems(text, slot: slot)) {
        problems.add('${file.path} (${slot.key}): $problem');
      }
    }
  }
  return problems;
}

/// How a person reads each slot, in Studio and in its documents.
String dvStudioSlotLabel(DVDocumentSlot slot) => switch (slot) {
      DVDocumentSlot.head => 'Inside the head',
      DVDocumentSlot.bodyStart => 'Start of the page body',
      DVDocumentSlot.bodyEnd => 'End of the page body',
    };

/// One sentence on what belongs in each slot.
String dvStudioSlotHelp(DVDocumentSlot slot) => switch (slot) {
      DVDocumentSlot.head =>
        'Tags a browser reads before the page: meta tags, verification tags, '
            'stylesheets, and scripts that must load first.',
      DVDocumentSlot.bodyStart =>
        'Right after the page body opens: the part of a tag manager that '
            'works without scripts.',
      DVDocumentSlot.bodyEnd =>
        'Right before the page body closes, after the page itself: chat '
            'widgets and scripts that can wait.',
    };

/// Forgets the change waiting for GitHub, once it has been sent: from then on
/// the repository holds it, and a later change made in code is not undone by
/// an old copy kept here.
Future<void> dvStudioClearPendingPlatforms(DVDatabaseAdapter database) async {
  final DVRecordAdapter records = DVRecordAdapter.over(database);
  await records.ensure(_settingsShape);
  await records.delete(dvStudioSettingsTable, where: DVFilter.equals('key', _platformsKey));
}
