// Studio's changes, synced to the project's GitHub repository.
//
// What was made in Studio -- pages, components, shortcuts, data models --
// goes to the repository as the files code uses, so the next release carries
// it: on a branch with a pull request to review, or pushed straight to the
// base branch. Before anything is sent, Studio shows what would change, file
// by file, as a diff somebody can read.
//
// The token is the server's (DARTVEL_GITHUB_TOKEN): Studio never stores one,
// and no answer ever carries it.
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha1;
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _token = 'ghp_secret_do_not_echo';

/// A repository the size of a test: commits are file maps.
class _GitHub {
  final Map<String, Map<String, String>> commits = <String, Map<String, String>>{
    'c0': <String, String>{
      'README.md': 'The roastery\n',
      'studio/pages/about.json': '{\n  "route": "/about"\n}\n',
      'studio/pages/old.json': '{\n  "route": "/old"\n}\n',
    },
  };
  final Map<String, String> refs = <String, String>{'main': 'c0'};
  final List<Map<String, Object?>> pulls = <Map<String, Object?>>[];
  final Map<String, Map<String, String>> trees = <String, Map<String, String>>{};
  final List<String> authorizations = <String>[];
  int _next = 1;

  static String blob(String text) {
    final List<int> bytes = utf8.encode(text);
    return sha1.convert(<int>[...utf8.encode('blob ${bytes.length}\u0000'), ...bytes]).toString();
  }

  Future<DVGitHubReply> call(String method, String path, {Object? body, required String token}) async {
    authorizations.add(token);
    final Uri uri = Uri.parse(path);
    final List<String> s = uri.pathSegments;
    expect(s.take(3).join('/'), 'repos/roastery/site');
    final String tail = s.skip(3).join('/');
    final Map<String, Object?> b = (body as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    if (method == 'GET' && tail.startsWith('git/ref/heads/')) {
      final String? sha = refs[tail.substring('git/ref/heads/'.length)];
      return sha == null
          ? const DVGitHubReply(404, <String, Object?>{})
          : DVGitHubReply(200, <String, Object?>{'object': <String, Object?>{'sha': sha}});
    }
    if (method == 'GET' && tail.startsWith('git/commits/')) {
      final String sha = tail.substring('git/commits/'.length);
      return DVGitHubReply(200, <String, Object?>{'tree': <String, Object?>{'sha': 'tree-$sha'}});
    }
    if (method == 'GET' && tail.startsWith('git/trees/tree-')) {
      final Map<String, String> files = commits[tail.substring('git/trees/tree-'.length)]!;
      return DVGitHubReply(200, <String, Object?>{
        'tree': <Object?>[
          for (final MapEntry<String, String> f in files.entries)
            <String, Object?>{'path': f.key, 'type': 'blob', 'sha': blob(f.value)},
        ],
      });
    }
    if (method == 'GET' && tail.startsWith('contents/')) {
      final String file = Uri.decodeComponent(tail.substring('contents/'.length));
      final String? text = commits[refs[uri.queryParameters['ref']]]![file];
      return text == null
          ? const DVGitHubReply(404, <String, Object?>{})
          : DVGitHubReply(200, <String, Object?>{
              'encoding': 'base64',
              'content': base64.encode(utf8.encode(text)),
            });
    }
    if (method == 'POST' && tail == 'git/trees') {
      final Map<String, String> files = <String, String>{
        ...commits['${b['base_tree']}'.replaceFirst('tree-', '')]!,
      };
      for (final Object? entry in b['tree']! as List<Object?>) {
        final Map<Object?, Object?> e = entry! as Map<Object?, Object?>;
        if (e.containsKey('sha') && e['sha'] == null) {
          files.remove(e['path']);
        } else {
          files['${e['path']}'] = '${e['content']}';
        }
      }
      final String sha = 't${_next++}';
      trees[sha] = files;
      return DVGitHubReply(201, <String, Object?>{'sha': sha});
    }
    if (method == 'POST' && tail == 'git/commits') {
      final String sha = 'c${_next++}';
      commits[sha] = trees['${b['tree']}']!;
      return DVGitHubReply(201, <String, Object?>{'sha': sha});
    }
    if (method == 'POST' && tail == 'git/refs') {
      refs['${b['ref']}'.replaceFirst('refs/heads/', '')] = '${b['sha']}';
      return const DVGitHubReply(201, <String, Object?>{});
    }
    if (method == 'PATCH' && tail.startsWith('git/refs/heads/')) {
      refs[tail.substring('git/refs/heads/'.length)] = '${b['sha']}';
      return const DVGitHubReply(200, <String, Object?>{});
    }
    if (method == 'POST' && tail == 'pulls') {
      pulls.add(b);
      return DVGitHubReply(201, <String, Object?>{
        'number': pulls.length,
        'html_url': 'https://github.com/roastery/site/pull/${pulls.length}',
      });
    }
    return const DVGitHubReply(404, <String, Object?>{});
  }
}

Request _request(String method, String path, {Object? body}) => Request(
      method: method,
      url: Uri.parse('http://localhost/__studio/api/$path'),
      headers: Headers(<String, String>{
        'x-dartvel-csrf-token': 'test-token-test-token-test-token',
        if (body != null) 'content-type': 'application/json',
      }),
      bodyStream: body == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    );

void main() {
  late _GitHub github;
  late MemoryDVDatabaseAdapter database;

  DVStudioApi api({String? token = _token}) => DVStudioApi(
        database: database,
        gitHub: (String method, String path, {Object? body}) =>
            github.call(method, path, body: body, token: token ?? ''),
        gitHubToken: token,
      );

  Future<(int, Map<String, Object?>, String)> call(DVStudioApi api, String method,
      String path, {Object? body}) async {
    final Response response =
        await api.respond(_request(method, path, body: body), path);
    final String text = utf8.decode(await response.body!.bytes());
    return (response.status, (jsonDecode(text) as Map).cast<String, Object?>(), text);
  }

  setUp(() async {
    github = _GitHub();
    database = MemoryDVDatabaseAdapter();
    final DVStudioApi studio = api();
    for (final Map<String, Object?> page in <Map<String, Object?>>[
      <String, Object?>{'route': '/about', 'title': 'About us'},
      <String, Object?>{'route': '/landing', 'title': 'Landing'},
    ]) {
      await studio.respond(
          _request('PUT', 'pages', body: <String, Object?>{'document': page}), 'pages');
    }
  });

  test('before a repository is named, Studio says so and sends nothing',
      () async {
    final (int status, Map<String, Object?> body, _) =
        await call(api(), 'GET', 'repository');
    expect(status, 200);
    expect(body['connected'], isFalse);
    final (int refused, _, _) = await call(api(), 'POST', 'repository/sync',
        body: <String, Object?>{'mode': 'pullRequest'});
    expect(refused, 409);
    expect(github.authorizations, isEmpty);
  });

  test('without the server\'s token, Studio says where to put it, and no '
      'answer carries a token', () async {
    await call(api(token: null), 'PUT', 'repository',
        body: <String, Object?>{'repository': 'roastery/site', 'base': 'main'});
    final (int status, Map<String, Object?> body, String text) =
        await call(api(token: null), 'GET', 'repository');
    expect(status, 200);
    expect(body['token'], isFalse);
    expect(text, contains('DARTVEL_GITHUB_TOKEN'));

    await call(api(), 'PUT', 'repository',
        body: <String, Object?>{'repository': 'roastery/site', 'base': 'main'});
    final (_, _, String withToken) = await call(api(), 'GET', 'repository');
    expect(withToken, isNot(contains(_token)));
  });

  test('what would change is shown file by file, as a diff somebody can '
      'read', () async {
    await call(api(), 'PUT', 'repository',
        body: <String, Object?>{'repository': 'roastery/site', 'base': 'main'});
    final (_, Map<String, Object?> body, _) = await call(api(), 'GET', 'repository');
    final Map<String, Map<String, Object?>> changes = <String, Map<String, Object?>>{
      for (final Object? c in body['changes']! as List<Object?>)
        '${(c! as Map)['path']}': (c as Map).cast<String, Object?>(),
    };
    expect(changes['studio/pages/landing.json']?['kind'], 'added');
    expect(changes['studio/pages/about.json']?['kind'], 'changed');
    expect(changes['studio/pages/about.json']?['diff'], contains('+  "title": "About us"'));
    expect(changes['studio/pages/old.json']?['kind'], 'removed');
    expect(changes.containsKey('README.md'), isFalse,
        reason: 'only what Studio writes is Studio\'s to change');
  });

  test('a pull request carries the changes on a branch of their own; the '
      'base branch is untouched until it is merged', () async {
    await call(api(), 'PUT', 'repository',
        body: <String, Object?>{'repository': 'roastery/site', 'base': 'main'});
    final (int status, Map<String, Object?> body, _) = await call(
        api(), 'POST', 'repository/sync',
        body: <String, Object?>{'mode': 'pullRequest', 'message': 'Landing page'});
    expect(status, 200);
    expect(body['url'], 'https://github.com/roastery/site/pull/1');
    expect(github.refs['main'], 'c0');
    final String branch = '${github.pulls.single['head']}';
    expect(branch, startsWith('studio/'));
    final Map<String, String> files = github.commits[github.refs[branch]]!;
    expect(files['studio/pages/landing.json'], contains('"/landing"'));
    expect(files.containsKey('studio/pages/old.json'), isFalse);
    expect(files['README.md'], 'The roastery\n');
    expect(github.authorizations.toSet(), <String>{_token});
  });

  test('pushed, the base branch has the changes, and nothing is left to sync',
      () async {
    await call(api(), 'PUT', 'repository',
        body: <String, Object?>{'repository': 'roastery/site', 'base': 'main'});
    final (int status, _, _) = await call(api(), 'POST', 'repository/sync',
        body: <String, Object?>{'mode': 'push', 'message': 'From Studio'});
    expect(status, 200);
    expect(github.refs['main'], isNot('c0'));
    final (_, Map<String, Object?> after, _) = await call(api(), 'GET', 'repository');
    expect(after['changes'], isEmpty);
  });
}
