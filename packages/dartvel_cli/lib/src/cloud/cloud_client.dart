/// The HTTP side of the Dartvel Cloud protocol, for the CLI.
///
/// Every answer that is not the one asked for becomes a [DVCloudException]
/// carrying the service's [DVCloudRefusal], so a caller says what the service
/// said instead of a status code.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/cloud.dart';

class DVCloudException implements Exception {
  const DVCloudException(this.refusal);

  final DVCloudRefusal refusal;

  @override
  String toString() => refusal.message;
}

/// The service did not answer at all.
class DVCloudUnreachable implements Exception {
  const DVCloudUnreachable(this.url, this.cause);

  final Uri url;
  final Object cause;

  @override
  String toString() => 'Dartvel Cloud at $url did not answer: $cause';
}

class DVCloudClient {
  DVCloudClient(this.base, this.token);

  final Uri base;
  final String token;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 20);

  void close() => _http.close(force: true);

  Uri _uri(String path) => base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/api/$dvCloudApiVersion$path');

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Map<String, String> headers = const <String, String>{},
    Future<void> Function(HttpClientRequest request)? body,
  }) async {
    final Uri uri = _uri(path);
    try {
      final HttpClientRequest request = await _http.openUrl(method, uri);
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..set(HttpHeaders.userAgentHeader, 'dartvel-cli');
      headers.forEach(request.headers.set);
      if (body != null) await body(request);
      return await request.close();
    } on SocketException catch (error) {
      throw DVCloudUnreachable(base, error.message);
    } on HandshakeException catch (error) {
      throw DVCloudUnreachable(base, error.message);
    } on HttpException catch (error) {
      throw DVCloudUnreachable(base, error.message);
    }
  }

  Future<Object?> _json(HttpClientResponse response, int expected) async {
    final String text = await utf8.decodeStream(response);
    Object? json;
    try {
      json = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (response.statusCode != expected) {
      throw DVCloudException(DVCloudRefusal.fromResponse(response.statusCode, json));
    }
    return json;
  }

  Map<String, Object?> _map(Object? json) {
    if (json is! Map) throw const FormatException('Dartvel Cloud answered with something that is not an object.');
    return json.cast<String, Object?>();
  }

  /// Queues [spec] with [source] as its project.
  Future<DVCloudBuild> submit(DVCloudBuildSpec spec, File source) async {
    final HttpClientResponse response = await _send(
      'POST',
      '/builds',
      headers: <String, String>{
        dvCloudBuildHeader: dvCloudSpecHeader(spec),
        HttpHeaders.contentTypeHeader: 'application/zip',
      },
      body: (HttpClientRequest request) async {
        request.contentLength = source.lengthSync();
        await request.addStream(source.openRead());
      },
    );
    return DVCloudBuild.fromJson(_map(await _json(response, 201)));
  }

  Future<DVCloudBuild> build(String id) async =>
      DVCloudBuild.fromJson(_map(await _json(await _send('GET', '/builds/$id'), 200)));

  /// The build's events after [lastEventId], until the service closes the
  /// stream.
  Stream<DVCloudEvent> events(String id, {int? lastEventId}) async* {
    final HttpClientResponse response = await _send(
      'GET',
      '/builds/$id/events',
      headers: <String, String>{
        HttpHeaders.acceptHeader: 'text/event-stream',
        if (lastEventId != null) 'Last-Event-ID': '$lastEventId',
      },
    );
    if (response.statusCode != 200) {
      await _json(response, 200);
      return;
    }
    final DVCloudEventParser parser = DVCloudEventParser();
    await for (final String chunk in response.transform(utf8.decoder)) {
      for (final DVCloudEvent event in parser.add(chunk)) {
        yield event;
      }
    }
  }

  /// Writes the artifact [name] of build [id] to [into].
  Future<void> download(String id, String name, File into) async {
    final HttpClientResponse response =
        await _send('GET', '/builds/$id/artifacts/${Uri.encodeComponent(name)}');
    if (response.statusCode != 200) {
      await _json(response, 200);
      return;
    }
    into.parent.createSync(recursive: true);
    await response.pipe(into.openWrite());
  }

  Future<void> putCredential(String project, String name, List<int> value) async {
    final HttpClientResponse response = await _send(
      'PUT',
      '/projects/$project/credentials/$name',
      headers: <String, String>{HttpHeaders.contentTypeHeader: 'application/octet-stream'},
      body: (HttpClientRequest request) async {
        request.contentLength = value.length;
        request.add(value);
      },
    );
    await _json(response, 204);
  }

  Future<void> deleteCredential(String project, String name) async {
    await _json(await _send('DELETE', '/projects/$project/credentials/$name'), 204);
  }

  /// The credential names set for [project]. Values never leave the service
  /// except to a worker building that project.
  Future<List<String>> credentials(String project) async {
    final Object? json = await _json(await _send('GET', '/projects/$project/credentials'), 200);
    final Object? names = json is Map ? json['names'] : null;
    return <String>[if (names is List) for (final Object? n in names) '$n'];
  }
}
