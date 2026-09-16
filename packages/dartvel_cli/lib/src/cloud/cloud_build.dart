/// `dartvel build <target> --cloud`: the build, on the repository's own
/// GitHub Actions, followed to the end and brought home into `build/cloud/`.
///
/// Every refusal comes before the dispatch, because a dispatch starts a
/// runner and the thing worth guarding is a run that goes wrong quietly: a
/// workflow on the branch older than the one this command writes, which
/// builds and succeeds at something else; or local commits that were never
/// pushed, which the runner cannot see. The first is refused and the second
/// is said out loud.
///
/// Nothing here is a hosted Dartvel service. The queue is GitHub's, the
/// runners are GitHub's or the repository's own self-hosted ones, the secrets
/// are the repository's, and `GITHUB_API_URL` points the whole thing at a
/// GitHub Enterprise Server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../updates/zip_entries.dart';
import 'cloud_workflow.dart';
import 'github_repository.dart';

typedef DVCloudProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

class DVCloudBuildRequest {
  const DVCloudBuildRequest({
    required this.root,
    required this.target,
    this.profile = 'release',
    this.publish,
    this.dryRun = false,
  });

  /// The application directory.
  final String root;
  final String target;
  final String profile;

  /// A store `dartvel publish` sends the build to in the same run.
  final String? publish;

  /// Passed to that publish as `--dry-run`.
  final bool dryRun;
}

class DVCloudBuild {
  DVCloudBuild({
    Map<String, String>? environment,
    DVCloudProcessRun? processRun,
    void Function(String message)? log,
    this.pollInterval = const Duration(seconds: 10),
    this.findRunTimeout = const Duration(minutes: 3),
  })  : _environment = environment ?? Platform.environment,
        _processRun = processRun ?? _run,
        _log = log ?? ((String m) => stdout.writeln('[dartvel] $m'));

  final Map<String, String> _environment;
  final DVCloudProcessRun _processRun;
  final void Function(String) _log;
  final Duration pollInterval;
  final Duration findRunTimeout;

  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) =>
      Process.run(executable, arguments,
          workingDirectory: workingDirectory, runInShell: Platform.isWindows);

  Future<String?> _out(List<String> command, String dir) async {
    try {
      final ProcessResult r = await _processRun(command.first, command.sublist(1),
          workingDirectory: dir);
      if (r.exitCode != 0) return null;
      final String text = '${r.stdout}'.trim();
      return text.isEmpty ? null : text;
    } on ProcessException {
      return null;
    }
  }

  /// The exit code: 0 built and downloaded, 1 the run failed, 64 usage,
  /// 69 GitHub refused, 77 no token, 78 the repository is not ready.
  Future<int> run(DVCloudBuildRequest request) async {
    if (!dvCloudRunners.containsKey(request.target)) {
      _log('❌ ${request.target} does not build in the cloud. Cloud builds run '
          '${dvCloudTargets.join(', ')}.');
      return 64;
    }

    final String root = p.normalize(p.absolute(request.root));
    final String? top = await _out(<String>['git', 'rev-parse', '--show-toplevel'], root);
    if (top == null) {
      _log('❌ $root is not in a git repository. A cloud build runs on the '
          'repository\'s own GitHub Actions, so it needs one: git init, then '
          'git remote add origin <url> and push.');
      return 78;
    }
    final String? remote = await _out(<String>['git', 'remote', 'get-url', 'origin'], root);
    final DVGitHubRepository? repo = remote == null
        ? null
        : DVGitHubRepository.fromRemote(remote, environment: _environment);
    if (repo == null) {
      _log('❌ This repository has no GitHub remote named origin'
          '${remote == null ? '' : ' ($remote is not one)'}. A cloud build '
          'dispatches to that repository\'s Actions: git remote add origin '
          'https://github.com/<owner>/<repo>.git, then push.');
      return 78;
    }

    final String? token = _token() ?? await _out(<String>['gh', 'auth', 'token'], root);
    if (token == null) {
      _log('❌ No GitHub token. Set GH_TOKEN (or GITHUB_TOKEN) to a token '
          'with the actions:write and contents:read permissions on '
          '${repo.slug}, or run gh auth login.');
      return 77;
    }

    String? ref = await _out(<String>['git', 'symbolic-ref', '--short', '-q', 'HEAD'], root);
    if (ref == null && _environment['GITHUB_ACTIONS'] == 'true') {
      ref = _environment['GITHUB_REF_NAME'];
    }
    if (ref == null || ref.isEmpty) {
      _log('❌ HEAD is detached. A cloud build runs a branch as it is on '
          '${repo.slug}; check one out.');
      return 78;
    }

    final String? flutter = await _flutterVersion(root);
    if (flutter == null) {
      _log('❌ No Flutter version to pin the runner to. Add dartvel.cloud.flutter '
          '(for example 3.44.5) to pubspec.yaml, or put flutter on PATH.');
      return 78;
    }

    final String app = p.posix.joinAll(p.split(p.relative(root, from: p.normalize(top))));
    final String workflow = dvCloudWorkflow(flutterVersion: flutter);
    final File local = File(p.join(top, dvCloudWorkflowPath));
    if (!local.existsSync() || local.readAsStringSync() != workflow) {
      local.parent.createSync(recursive: true);
      local.writeAsStringSync(workflow);
      _log('📝 Wrote $dvCloudWorkflowPath.');
    }

    final _GitHubApi api = _GitHubApi(repo, token);
    try {
      final _Response contents = await api.get(
          '/repos/${repo.slug}/contents/$dvCloudWorkflowPath',
          query: <String, String>{'ref': ref});
      if (contents.status == 401 || contents.status == 403) {
        _log('❌ GitHub refused the token for ${repo.slug} (${contents.status}). '
            'It needs actions:write and contents:read.');
        return 69;
      }
      final String? pushed = contents.status == 200 ? _decodeContent(contents.json) : null;
      if (pushed != workflow) {
        _log('❌ $dvCloudWorkflowPath on ${repo.slug}@$ref '
            '${pushed == null ? 'is not there' : 'is not the one this build writes'}. '
            'The file here is; commit and push it to $ref and run this again. '
            'GitHub also needs it on the default branch before it can be '
            'dispatched at all.');
        return 78;
      }

      await _warnAboutWhatIsNotPushed(api, repo, ref, root);

      final String id = _requestId();
      final _Response dispatch = await api.post(
        '/repos/${repo.slug}/actions/workflows/$dvCloudWorkflowFile/dispatches',
        <String, Object?>{
          'ref': ref,
          'inputs': <String, String>{
            'app': app,
            'target': request.target,
            'profile': request.profile,
            'publish': request.publish ?? '',
            'dry_run': '${request.dryRun}',
            'request': id,
          },
        },
      );
      if (dispatch.status != 204) {
        _log('❌ GitHub did not dispatch $dvCloudWorkflowFile (${dispatch.status}): '
            '${dispatch.message}');
        if (dispatch.status == 404) {
          _log('   It has to be on the default branch of ${repo.slug} as well as $ref.');
        }
        return 69;
      }
      _log('☁️  Dispatched ${request.target} (${request.profile}) on ${repo.slug}@$ref.');

      final int? runId = await _findRun(api, repo, ref, id);
      if (runId == null) {
        _log('❌ The dispatch was accepted and no run for it appeared within '
            '${findRunTimeout.inSeconds}s. See https://${repo.host == 'github.com' ? 'github.com' : repo.host}/${repo.slug}/actions.');
        return 69;
      }

      final Map<String, Object?> run = await _follow(api, repo, runId);
      final String url = '${run['html_url']}';
      if (run['conclusion'] != 'success') {
        _log('❌ The cloud build ${run['conclusion']}: $url');
        return 1;
      }

      final Directory out = Directory(p.join(root, 'build', 'cloud', request.target));
      final int files = await _download(api, repo, runId, out);
      if (files == 0) {
        _log('❌ The run succeeded and uploaded nothing: $url');
        return 1;
      }
      _log('✅ Built in the cloud: $url');
      _log('   $files file(s) in ${p.relative(out.path, from: root)}');
      return 0;
    } finally {
      api.close();
    }
  }

  String? _token() {
    for (final String name in <String>['GH_TOKEN', 'GITHUB_TOKEN']) {
      final String? value = _environment[name];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  Future<String?> _flutterVersion(String root) async {
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      try {
        final Object? doc = loadYaml(pubspec.readAsStringSync());
        final Object? dartvel = doc is Map ? doc['dartvel'] : null;
        final Object? cloud = dartvel is Map ? dartvel['cloud'] : null;
        final Object? pinned = cloud is Map ? cloud['flutter'] : null;
        if (pinned != null && '$pinned'.trim().isNotEmpty) return '$pinned'.trim();
      } on YamlException {
        // The build reports a pubspec that does not parse.
      }
    }
    final String? machine = await _out(<String>['flutter', '--version', '--machine'], root);
    if (machine == null) return null;
    try {
      final Object? decoded = jsonDecode(machine.substring(machine.indexOf('{')));
      final Object? version = decoded is Map ? decoded['frameworkVersion'] : null;
      return version is String && version.isNotEmpty ? version : null;
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static String? _decodeContent(Object? json) {
    if (json is! Map || json['content'] is! String) return null;
    try {
      return utf8.decode(base64.decode('${json['content']}'.replaceAll(RegExp(r'\s'), '')));
    } on FormatException {
      return null;
    }
  }

  Future<void> _warnAboutWhatIsNotPushed(
      _GitHubApi api, DVGitHubRepository repo, String ref, String root) async {
    final String? dirty = await _out(<String>['git', 'status', '--porcelain'], root);
    if (dirty != null) {
      _log('⚠️  There are uncommitted changes here. The cloud builds what is '
          'pushed to $ref, without them.');
    }
    final String? head = await _out(<String>['git', 'rev-parse', 'HEAD'], root);
    final _Response commit = await api.get('/repos/${repo.slug}/commits/$ref');
    final Object? sha = commit.json is Map ? (commit.json! as Map)['sha'] : null;
    if (head != null && sha is String && sha != head) {
      _log('⚠️  $ref on ${repo.slug} is ${sha.substring(0, min(12, sha.length))} and '
          'HEAD here is ${head.substring(0, min(12, head.length))}. The cloud '
          'builds the pushed one.');
    }
  }

  static String _requestId() {
    final Random random = Random.secure();
    return List<String>.generate(
        16, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  Future<int?> _findRun(
      _GitHubApi api, DVGitHubRepository repo, String ref, String id) async {
    final DateTime deadline = DateTime.now().add(findRunTimeout);
    do {
      final _Response runs = await api.get(
        '/repos/${repo.slug}/actions/workflows/$dvCloudWorkflowFile/runs',
        query: <String, String>{
          'event': 'workflow_dispatch',
          'branch': ref,
          'per_page': '30',
        },
      );
      final Object? list = runs.json is Map ? (runs.json! as Map)['workflow_runs'] : null;
      if (list is List) {
        for (final Object? run in list) {
          if (run is Map && '${run['display_title']}'.contains('[$id]')) {
            return (run['id'] as num).toInt();
          }
        }
      }
      await Future<void>.delayed(pollInterval);
    } while (DateTime.now().isBefore(deadline));
    return null;
  }

  /// Polls the run until it completes, saying each step as it changes.
  Future<Map<String, Object?>> _follow(
      _GitHubApi api, DVGitHubRepository repo, int runId) async {
    final Map<String, String> seen = <String, String>{};
    bool announced = false;
    int unanswered = 0;
    while (true) {
      final _Response run;
      try {
        run = await api.get('/repos/${repo.slug}/actions/runs/$runId');
      } on IOException {
        // A dropped connection an hour into a build is not the build failing.
        if (++unanswered >= 30) rethrow;
        await Future<void>.delayed(pollInterval);
        continue;
      }
      if (run.status != 200) {
        if (++unanswered >= 30) {
          return <String, Object?>{'conclusion': 'unknown (GitHub answered ${run.status})', 'html_url': ''};
        }
        await Future<void>.delayed(pollInterval);
        continue;
      }
      unanswered = 0;
      final Map<String, Object?> data = run.json is Map
          ? (run.json! as Map).cast<String, Object?>()
          : <String, Object?>{};
      if (!announced && data['html_url'] != null) {
        _log('   ${data['html_url']}');
        announced = true;
      }
      final _Response jobs = await api.get('/repos/${repo.slug}/actions/runs/$runId/jobs');
      final Object? jobList = jobs.json is Map ? (jobs.json! as Map)['jobs'] : null;
      if (jobList is List) {
        for (final Object? job in jobList) {
          if (job is! Map || job['steps'] is! List) continue;
          for (final Object? step in job['steps'] as List) {
            if (step is! Map) continue;
            final String name = '${step['name']}';
            final String state = step['status'] == 'completed'
                ? '${step['conclusion']}'
                : '${step['status']}';
            final String key = '${job['name']} / $name';
            if (seen[key] == state) continue;
            seen[key] = state;
            final String mark = switch (state) {
              'success' => '✓',
              'skipped' => '-',
              'in_progress' => '▸',
              'queued' || 'pending' || 'waiting' => '·',
              _ => '✗',
            };
            _log('   $mark ${job['name']}: $name${mark == '✗' ? ' ($state)' : ''}');
          }
        }
      }
      if (data['status'] == 'completed') return data;
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<int> _download(
      _GitHubApi api, DVGitHubRepository repo, int runId, Directory out) async {
    final _Response listing = await api.get('/repos/${repo.slug}/actions/runs/$runId/artifacts');
    final Object? artifacts = listing.json is Map ? (listing.json! as Map)['artifacts'] : null;
    if (artifacts is! List) return 0;
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    int written = 0;
    for (final Object? artifact in artifacts) {
      if (artifact is! Map || artifact['expired'] == true) continue;
      final Uri url = Uri.parse('${artifact['archive_download_url']}');
      final File zip = File(p.join(out.path, '.${artifact['id']}.zip'));
      await api.download(url, zip);
      try {
        final Map<String, List<int>> entries = dvReadZipEntries(zip.path, (_) => true);
        for (final MapEntry<String, List<int>> entry in entries.entries) {
          final String target = p.normalize(p.join(out.path, entry.key));
          // A zip names paths, and a name with .. in it is a write anywhere.
          if (!p.isWithin(out.path, target)) continue;
          File(target)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(entry.value);
          written++;
        }
      } finally {
        zip.deleteSync();
      }
    }
    // Artifacts do not keep file modes; the one executable a target produces
    // on its own is the web-server binary.
    final File server = File(p.join(out.path, 'server'));
    if (!Platform.isWindows && server.existsSync()) {
      await Process.run('chmod', <String>['+x', server.path]);
    }
    return written;
  }
}

class _Response {
  const _Response(this.status, this.json);
  final int status;
  final Object? json;
  String get message =>
      json is Map && (json! as Map)['message'] != null ? '${(json! as Map)['message']}' : '';
}

class _GitHubApi {
  _GitHubApi(this.repo, this.token);

  final DVGitHubRepository repo;
  final String token;
  final HttpClient _client = HttpClient();

  void close() => _client.close(force: true);

  Uri _uri(String path, Map<String, String>? query) {
    final Uri base = repo.apiBase;
    return base.replace(
      path: '${base.path}$path',
      queryParameters: query,
    );
  }

  void _headers(HttpClientRequest request) {
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set('X-GitHub-Api-Version', '2022-11-28')
      ..set(HttpHeaders.userAgentHeader, 'dartvel-cli');
  }

  Future<_Response> _send(HttpClientRequest request) async {
    final HttpClientResponse response = await request.close();
    final String body = await utf8.decodeStream(response);
    Object? json;
    if (body.isNotEmpty) {
      try {
        json = jsonDecode(body);
      } on FormatException {
        json = <String, Object?>{'message': body};
      }
    }
    return _Response(response.statusCode, json);
  }

  Future<_Response> get(String path, {Map<String, String>? query}) async {
    final HttpClientRequest request = await _client.getUrl(_uri(path, query));
    _headers(request);
    return _send(request);
  }

  Future<_Response> post(String path, Object body) async {
    final HttpClientRequest request = await _client.postUrl(_uri(path, null));
    _headers(request);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    return _send(request);
  }

  /// Follows GitHub's redirect to storage by hand, because the token belongs
  /// to GitHub and HttpClient would carry it to whatever host is next.
  Future<void> download(Uri url, File into) async {
    HttpClientRequest request = await _client.getUrl(url);
    _headers(request);
    request.followRedirects = false;
    HttpClientResponse response = await request.close();
    int hops = 0;
    while (response.isRedirect && hops++ < 5) {
      final String? location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) break;
      final Uri next = request.uri.resolve(location);
      request = await _client.getUrl(next);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'dartvel-cli');
      if (next.host == repo.apiBase.host && next.port == repo.apiBase.port) {
        _headers(request);
      }
      response = await request.close();
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('Downloading $url answered ${response.statusCode}.', uri: url);
    }
    final IOSink sink = into.openWrite();
    await response.pipe(sink);
  }
}
