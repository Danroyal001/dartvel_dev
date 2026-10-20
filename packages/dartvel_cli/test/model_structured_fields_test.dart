import 'dart:io';

import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A list, a map or another model as a field arrives from JSON as
/// List<dynamic> / Map<String, dynamic>; a plain cast of that throws at run
/// time. The generated readers rebuild it element by element instead.
void main() {
  test('list, map and nested-model fields are rebuilt, not cast', () async {
    final root = await Directory.systemTemp.createTemp('dartvel_structured_fields_');
    try {
      Directory(p.join(root.path, 'lib', 'models')).createSync(recursive: true);
      Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
      File(p.join(root.path, 'lib', 'models', 'tracker.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Tracker {
  final String id;
  final Map<String, Status>? statuses;
  final List<String> tags;
  final List<Status>? history;
  final Status? latest;
  final List<int?>? scores;
  const _Tracker({required this.id, required this.statuses, required this.tags, required this.history, required this.latest, required this.scores});
}

@DVModel()
class _Status {
  final String id;
  final String note;
  const _Status({required this.id, required this.note});
}
''');

      await ModelGenerator.generate(root: root.path, pkgName: 'structured_app', buildId: 'test-build');
      final content = File(p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart')).readAsStringSync();

      expect(content, contains('Object? _dvAsJson(Object? value) =>'));
      // From JSON.
      expect(content, contains("statuses: json['statuses'] == null ? null : ((_dvAsJson(json['statuses']) as Map).map((key, value) => MapEntry(key as String, StatusParser.fromJson(Map<String, Object?>.from(_dvAsJson(value) as Map)))))"));
      expect(content, contains("tags: (_dvAsJson(json['tags']) as List).map((item) => item as String).toList()"));
      expect(content, contains("history: json['history'] == null ? null : ((_dvAsJson(json['history']) as List).map((item) => StatusParser.fromJson(Map<String, Object?>.from(_dvAsJson(item) as Map))).toList())"));
      expect(content, contains("latest: json['latest'] == null ? null : (StatusParser.fromJson(Map<String, Object?>.from(_dvAsJson(json['latest']) as Map)))"));
      expect(content, contains("scores: json['scores'] == null ? null : ((_dvAsJson(json['scores']) as List).map((item) => item == null ? null : (_dvAsNum(item).toInt())).toList())"));
      expect(content, isNot(contains("json['statuses'] as Map<String, Status>?")));
      expect(content, isNot(contains("json['tags'] as List<String>")));
      // From a stored record, which may hold the value as JSON text.
      expect(content, contains("(_dvAsJson(row['statuses']) as Map)"));
      expect(content, isNot(contains("row['tags'] as List<String>")));
      // Primitives are unchanged.
      expect(content, contains("note: json['note'] as String"));
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
