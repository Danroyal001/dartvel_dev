/// Studio's changes, synced to the project's GitHub repository.
///
/// What was made in Studio -- its pages, components and shortcuts, as the
/// studio/ files a development server writes, and its data models, as the
/// lib/models files `dartvel dev` writes -- goes to the repository as those
/// same files, so the next release is built with them: on a branch of its
/// own with a pull request, or pushed to the base branch. Before anything is
/// sent Studio lists what would change, file by file, with a diff.
///
/// The token is the server's, from `DARTVEL_GITHUB_TOKEN`. Studio never
/// stores one -- a token kept in the application's database would be a
/// credential readable by anything that can read that database -- and no
/// answer carries it. Studio stores the repository's name and base branch.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;

import '../database/adapter.dart';
import '../database/records.dart';
import 'studio_api.dart' show dvStudioPagesShape, dvStudioPagesTable;
import 'studio_model_schema.dart' show dvStudioModelDartSource, dvStudioSnakeCase;
import 'studio_api.dart' show DVStudioModelSpec;
import 'studio_source_files.dart'
    show dvStudioSourceDirectory, dvStudioSourcePath, dvStudioSourceText;

/// What GitHub answered: its status and its JSON.
class DVGitHubReply {
  const DVGitHubReply(this.status, this.body);
  final int status;
  final Object? body;
}

/// One call to GitHub's REST API: [path] under https://api.github.com.
typedef DVGitHubTransport = Future<DVGitHubReply> Function(
  String method,
  String path, {
  Object? body,
});

/// The environment variable the server's GitHub token is read from.
const String dvGitHubTokenVariable = 'DARTVEL_GITHUB_TOKEN';

/// GitHub's API over HTTPS, as [token].
DVGitHubTransport dvGitHubHttps(String token) =>
    (String method, String path, {Object? body}) async {
      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest request =
            await client.openUrl(method, Uri.parse('https://api.github.com$path'));
        request.headers
          ..set('authorization', 'Bearer $token')
          ..set('accept', 'application/vnd.github+json')
          ..set('x-github-api-version', '2022-11-28')
          ..set('user-agent', 'dartvel-studio');
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final HttpClientResponse response =
            await request.close().timeout(const Duration(seconds: 30));
        final String text = await response.transform(utf8.decoder).join();
        Object? json;
        try {
          json = text.isEmpty ? null : jsonDecode(text);
        } on FormatException {
          json = null;
        }
        return DVGitHubReply(response.statusCode, json);
      } finally {
        client.close(force: true);
      }
    };

/// A file Studio would change in the repository.
class DVStudioFileChange {
  const DVStudioFileChange(this.path, this.kind, this.content, this.diff);

  /// Relative to the repository's root.
  final String path;

  /// `added`, `changed` or `removed`.
  final String kind;

  /// What the file would hold; null when it is removed.
  final String? content;

  /// The lines that change, each marked `+`, `-` or ` `.
  final String diff;

  Map<String, Object?> toJson() =>
      <String, Object?>{'path': path, 'kind': kind, 'diff': diff};
}

/// Refused, with a reason a person can act on.
class DVStudioRepositoryRefusal implements Exception {
  DVStudioRepositoryRefusal(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
}

/// The collection the repository's name and base branch are kept in.
const String dvStudioRepositoryTable = 'dartvel_studio_repository';

const DVRecordShape _shape = DVRecordShape(
  collection: dvStudioRepositoryTable,
  key: 'key',
  fields: <String, DVFieldType>{
    'key': DVFieldType.text,
    'repository': DVFieldType.text,
    'base': DVFieldType.text,
  },
);

/// Studio's side of one project's GitHub repository.
class DVStudioRepository {
  DVStudioRepository({
    required this.database,
    required this.storedModels,
    this.token,
    DVGitHubTransport? transport,
  }) : _transport = transport;

  final DVDatabaseAdapter database;

  /// The data models designed in Studio, which go to lib/models.
  final Future<List<DVStudioModelSpec>> Function() storedModels;

  /// The server's token; none means nothing is sent.
  final String? token;

  final DVGitHubTransport? _transport;

  DVRecordAdapter get _records => DVRecordAdapter.over(database);

  static final RegExp _name = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');
  static final RegExp _branch = RegExp(r'^[A-Za-z0-9._/-]+$');

  /// The repository and base branch, or null before one is named.
  Future<({String repository, String base})?> settings() async {
    await _records.ensure(_shape);
    final List<Map<String, Object?>> rows = await _records.find(
      dvStudioRepositoryTable,
      where: DVFilter.equals('key', 'repository'),
    );
    if (rows.isEmpty) return null;
    return (repository: '${rows.first['repository']}', base: '${rows.first['base']}');
  }

  /// Names the repository, `owner/name`, and its base branch.
  Future<void> connect(String repository, String base) async {
    if (!_name.hasMatch(repository)) {
      throw DVStudioRepositoryRefusal(400, 'bad_repository',
          'Name the repository as owner/name, like roastery/site.');
    }
    if (!_branch.hasMatch(base) || base.contains('..')) {
      throw DVStudioRepositoryRefusal(400, 'bad_branch', 'That is not a branch name.');
    }
    await _records.ensure(_shape);
    await _records.delete(dvStudioRepositoryTable,
        where: DVFilter.equals('key', 'repository'));
    await _records.insert(dvStudioRepositoryTable, <String, Object?>{
      'key': 'repository',
      'repository': repository,
      'base': base,
    });
  }

  DVGitHubTransport _github() {
    final String? t = token;
    if (t == null || t.isEmpty) {
      throw DVStudioRepositoryRefusal(409, 'no_token',
          'The server has no GitHub token. Set $dvGitHubTokenVariable in its '
          'environment to a token that may write to the repository.');
    }
    return _transport ?? dvGitHubHttps(t);
  }

  Future<({String repository, String base})> _connected() async {
    final ({String repository, String base})? s = await settings();
    if (s == null) {
      throw DVStudioRepositoryRefusal(409, 'not_connected',
          'Name the repository first.');
    }
    return s;
  }

  static Object? _field(Object? json, List<String> path) {
    Object? at = json;
    for (final String key in path) {
      at = at is Map ? at[key] : null;
    }
    return at;
  }

  Future<Object?> _call(DVGitHubTransport github, String method, String path,
      {Object? body}) async {
    final DVGitHubReply reply = await github(method, path, body: body);
    if (reply.status < 200 || reply.status >= 300) {
      final Object? message = _field(reply.body, <String>['message']);
      throw DVStudioRepositoryRefusal(502, 'github',
          'GitHub answered ${reply.status}${message == null ? '' : ': $message'}.');
    }
    return reply.body;
  }

  /// Every file Studio keeps in the repository, as it would write it now.
  Future<Map<String, String>> _files() async {
    final Map<String, String> files = <String, String>{};
    await _records.ensure(dvStudioPagesShape);
    for (final Map<String, Object?> row in await _records.find(dvStudioPagesTable)) {
      final String? path = dvStudioSourcePath('${row['route']}');
      final Object? document = jsonDecode('${row['document']}');
      if (path != null && document is Map) files[path] = dvStudioSourceText(document);
    }
    for (final DVStudioModelSpec spec in await storedModels()) {
      files['lib/models/${dvStudioSnakeCase(spec.model)}.dart'] =
          dvStudioModelDartSource(spec);
    }
    return files;
  }

  /// Git's name for [text] as a file: what the repository's tree lists.
  static String _blob(String text) {
    final List<int> bytes = utf8.encode(text);
    return sha1
        .convert(<int>[...utf8.encode('blob ${bytes.length}\u0000'), ...bytes])
        .toString();
  }

  Future<String> _head(DVGitHubTransport github, String repository, String base) async =>
      '${_field(await _call(github, 'GET', '/repos/$repository/git/ref/heads/$base'), <String>['object', 'sha'])}';

  /// What would change in the repository's base branch.
  Future<List<DVStudioFileChange>> changes() async {
    final ({String repository, String base}) s = await _connected();
    final DVGitHubTransport github = _github();
    final String head = await _head(github, s.repository, s.base);
    final String tree = '${_field(await _call(github, 'GET', '/repos/${s.repository}/git/commits/$head'), <String>['tree', 'sha'])}';
    final Object? listing = await _call(
        github, 'GET', '/repos/${s.repository}/git/trees/$tree?recursive=1');
    final Map<String, String> there = <String, String>{
      for (final Object? entry in (_field(listing, <String>['tree']) as List?) ?? const <Object?>[])
        if (entry is Map && entry['type'] == 'blob' && _ours('${entry['path']}'))
          '${entry['path']}': '${entry['sha']}',
    };
    final Map<String, String> here = await _files();
    final List<DVStudioFileChange> out = <DVStudioFileChange>[];
    for (final MapEntry<String, String> file in here.entries) {
      final String? sha = there[file.key];
      if (sha == _blob(file.value)) continue;
      final String before =
          sha == null ? '' : await _content(github, s.repository, s.base, file.key);
      out.add(DVStudioFileChange(file.key, sha == null ? 'added' : 'changed',
          file.value, dvStudioLineDiff(before, file.value)));
    }
    for (final String path in there.keys) {
      if (here.containsKey(path) || !path.startsWith('$dvStudioSourceDirectory/')) {
        continue;
      }
      final String before = await _content(github, s.repository, s.base, path);
      out.add(DVStudioFileChange(path, 'removed', null, dvStudioLineDiff(before, '')));
    }
    out.sort((DVStudioFileChange a, DVStudioFileChange b) => a.path.compareTo(b.path));
    return out;
  }

  /// A file Studio writes: its studio/ documents, and a lib/models file of
  /// a model it designed. A studio/ file Studio no longer has is removed; a
  /// model file is only ever written, since code may have added its own.
  static bool _ours(String path) =>
      path.startsWith('$dvStudioSourceDirectory/') || path.startsWith('lib/models/');

  Future<String> _content(
      DVGitHubTransport github, String repository, String base, String path) async {
    final Object? file = await _call(github, 'GET',
        '/repos/$repository/contents/${Uri.encodeComponent(path).replaceAll('%2F', '/')}?ref=$base');
    final String encoded = '${_field(file, <String>['content']) ?? ''}';
    return utf8.decode(base64.decode(encoded.replaceAll('\n', '')));
  }

  /// Sends the changes: on a new branch with a pull request when
  /// [pullRequest], else pushed to the base branch. Returns where to see it.
  Future<Map<String, Object?>> sync({
    required bool pullRequest,
    String? message,
    DateTime Function() clock = DateTime.now,
  }) async {
    final ({String repository, String base}) s = await _connected();
    final DVGitHubTransport github = _github();
    final List<DVStudioFileChange> changes = await this.changes();
    if (changes.isEmpty) {
      throw DVStudioRepositoryRefusal(409, 'nothing_to_sync',
          'The repository already has everything made in Studio.');
    }
    final String head = await _head(github, s.repository, s.base);
    final String baseTree = '${_field(await _call(github, 'GET', '/repos/${s.repository}/git/commits/$head'), <String>['tree', 'sha'])}';
    final String tree = '${_field(await _call(github, 'POST', '/repos/${s.repository}/git/trees', body: <String, Object?>{
      'base_tree': baseTree,
      'tree': <Object?>[
        for (final DVStudioFileChange change in changes)
          if (change.content == null)
            <String, Object?>{'path': change.path, 'mode': '100644', 'type': 'blob', 'sha': null}
          else
            <String, Object?>{
              'path': change.path,
              'mode': '100644',
              'type': 'blob',
              'content': change.content,
            },
      ],
    }), <String>['sha'])}';
    final String title = (message == null || message.trim().isEmpty)
        ? 'Changes made in Studio'
        : message.trim();
    final String commit = '${_field(await _call(github, 'POST', '/repos/${s.repository}/git/commits', body: <String, Object?>{
      'message': title,
      'tree': tree,
      'parents': <String>[head],
    }), <String>['sha'])}';
    if (!pullRequest) {
      await _call(github, 'PATCH', '/repos/${s.repository}/git/refs/heads/${s.base}',
          body: <String, Object?>{'sha': commit, 'force': false});
      return <String, Object?>{
        'pushed': s.base,
        'commit': commit,
        'url': 'https://github.com/${s.repository}/commit/$commit',
      };
    }
    final DateTime now = clock().toUtc();
    String two(int n) => '$n'.padLeft(2, '0');
    final String branch = 'studio/${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    await _call(github, 'POST', '/repos/${s.repository}/git/refs',
        body: <String, Object?>{'ref': 'refs/heads/$branch', 'sha': commit});
    final Object? pull = await _call(github, 'POST', '/repos/${s.repository}/pulls',
        body: <String, Object?>{
          'title': title,
          'head': branch,
          'base': s.base,
          'body': 'Made in Dartvel Studio.\n\n${<String>[
            for (final DVStudioFileChange change in changes)
              '- ${change.kind} `${change.path}`',
          ].join('\n')}',
        });
    return <String, Object?>{
      'branch': branch,
      'url': '${_field(pull, <String>['html_url'])}',
    };
  }
}

/// The lines that differ between [before] and [after]: each line of the
/// result is a line of one of them, marked `-` (only before), `+` (only
/// after) or ` ` (both), with at most two unchanged lines around each change.
String dvStudioLineDiff(String before, String after) {
  final List<String> a = before.isEmpty ? <String>[] : before.trimRight().split('\n');
  final List<String> b = after.isEmpty ? <String>[] : after.trimRight().split('\n');
  // The longest common subsequence, by table: Studio's files are a few
  // hundred lines at most.
  final List<List<int>> lcs = List<List<int>>.generate(
      a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
  for (int i = a.length - 1; i >= 0; i--) {
    for (int j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final List<String> lines = <String>[];
  int i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      lines.add(' ${a[i]}');
      i++;
      j++;
    } else if (j < b.length && (i >= a.length || lcs[i][j + 1] >= lcs[i + 1][j])) {
      lines.add('+${b[j++]}');
    } else {
      lines.add('-${a[i++]}');
    }
  }
  // Two lines of what did not change around each change.
  final List<bool> keep = List<bool>.filled(lines.length, false);
  for (int k = 0; k < lines.length; k++) {
    if (lines[k].startsWith(' ')) continue;
    for (int d = -2; d <= 2; d++) {
      if (k + d >= 0 && k + d < lines.length) keep[k + d] = true;
    }
  }
  final List<String> out = <String>[];
  for (int k = 0; k < lines.length; k++) {
    if (keep[k]) {
      out.add(lines[k]);
    } else if (out.isEmpty || out.last != '…') {
      out.add('…');
    }
  }
  return out.join('\n');
}
