// Everything an application can use must be reachable through the single
// public entrypoint. Core is re-exported with an explicit `show` list, so a
// symbol added to dartvel_core but not listed there is invisible to
// applications even though its own tests pass. This file imports only the
// public barrel; if it compiles, the surface is wired up.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI provider surface is reachable from the public barrel', () {
    expect(AnthropicDVAIAdapter(apiKey: 'k'), isA<DVAIAdapter>());
    expect(OpenAIDVAIAdapter(apiKey: 'k'), isA<DVHttpAIAdapter>());
    expect(OpenRouterDVAIAdapter(apiKey: 'k'), isA<DVAIAdapter>());
    expect(GeminiDVAIAdapter(apiKey: 'k'), isA<DVAIAdapter>());
    expect(OllamaDVAIAdapter(), isA<DVAIAdapter>());
    expect(const LocalDVAIAdapter(), isA<DVAIAdapter>());

    expect(
      const DVAIToolDefinition(name: 'n', handler: _tool).jsonSchema,
      isNotEmpty,
    );
    expect(DVJsonCodec.toJson(const DVJsonString('x')), 'x');
    expect(
      const DVAIProviderException('p', 'm').toString(),
      contains('DVAIProviderException'),
    );
  });

  test('database and cache adapters are reachable', () {
    expect(MemoryDVDatabaseAdapter(), isA<DVDatabaseAdapter>());
    expect(DVMemoryCacheAdapter(), isA<DVCacheAdapter>());
    expect(
      DVDatabaseCacheAdapter(MemoryDVDatabaseAdapter()),
      isA<DVCacheAdapter>(),
    );
    // SqliteDVDatabaseAdapter is named here rather than constructed: on the
    // Flutter test VM it is the dart:ffi implementation, and the point is that
    // the type resolves through the barrel.
    expect(SqliteDVDatabaseAdapter, isNotNull);
  });

  test('queue and job codec surface is reachable', () {
    expect(DVInMemoryQueueAdapter(), isA<DVQueueAdapter>());
    expect(
      DVDatabaseQueueAdapter(MemoryDVDatabaseAdapter()),
      isA<DVQueueAdapter>(),
    );
    expect(const DVJobPayloadCodecs().names, isA<List<String>>());
    expect(
      DVJobPayloadCodec<String>(
        name: 'n',
        encode: (value) => <String, Object?>{'v': value},
        decode: (json) => json['v']! as String,
      ).name,
      'n',
    );
  });

  test('search providers are reachable', () {
    expect(
      MeilisearchProvider<String, String>(
        baseUrl: Uri.https('search.example.com'),
        apiKey: 'k',
        indexName: 'i',
        fromJson: _stringFrom,
      ),
      isA<DVSearchProvider<String, String>>(),
    );
    expect(
      AlgoliaSearchProvider<String, String>(
        applicationId: 'a',
        apiKey: 'k',
        indexName: 'i',
        fromJson: _stringFrom,
      ),
      isA<DVHttpSearchProvider<String, String>>(),
    );
    expect(
      OpenSearchProvider<String, String>(
        baseUrl: Uri.https('search.example.com'),
        indexName: 'i',
        fromJson: _stringFrom,
      ),
      isA<DVSearchProvider<String, String>>(),
    );
    expect(DVSqliteSearchProvider, isNotNull);
    expect(
      const DVSearchProviderException('p', 'm').toString(),
      contains('DVSearchProviderException'),
    );
  });

  test('mail providers are reachable', () {
    expect(ResendMailProvider(apiKey: 'k'), isA<DVMailProvider>());
    expect(SendGridMailProvider(apiKey: 'k'), isA<DVHttpMailProvider>());
    expect(PostmarkMailProvider(apiKey: 'k'), isA<DVMailProvider>());
    expect(
      MailgunMailProvider(apiKey: 'k', domain: 'd'),
      isA<DVMailProvider>(),
    );
    expect(
      SesMailProvider(
        credentials: const DVAwsCredentials(
          accessKeyId: 'a',
          secretAccessKey: 's',
        ),
        region: 'us-east-1',
      ),
      isA<DVMailProvider>(),
    );
    expect(SmtpMailProvider(host: 'h'), isA<DVMailProvider>());
    expect(DVMemoryMailProvider(), isA<DVMailProvider>());
  });

  test('notification providers are reachable', () {
    expect(
      FirebasePushProvider(projectId: 'p', accessToken: _token),
      isA<DVNotificationProvider>(),
    );
    expect(
      TwilioSmsProvider(
        accountSid: 'AC',
        authToken: 't',
        fromNumber: '+15550000000',
      ).kind,
      DVNotificationProviderKind.sms,
    );
  });

  test('storage adapters are reachable', () {
    expect(DVMemoryFileStorageAdapter(), isA<DVFileStorageAdapter>());
    expect(
      S3FileStorageAdapter(
        bucket: 'b',
        region: 'us-east-1',
        credentials: const DVAwsCredentials(
          accessKeyId: 'a',
          secretAccessKey: 's',
        ),
      ),
      isA<DVFileStorageAdapter>(),
    );
  });

  test('auth surface is reachable', () {
    expect(DVPasswordHasher(iterations: 1000).hash('pw'), isNotEmpty);
    expect(LocalAuthProvider(), isA<AuthProvider>());
    expect(
      const AuthException(AuthFailure.invalidPassword, 'no').failure,
      AuthFailure.invalidPassword,
    );

    final oauth = DVOAuth2Client(
      config: DVOAuth2Config.github(
        clientId: 'c',
        redirectUri: Uri.https('app.example.com', '/callback'),
      ),
    );
    expect(oauth.createAuthorization(), isA<DVOAuth2Authorization>());
    expect(const DVOAuth2Tokens(accessToken: 'a').tokenType, 'Bearer');
  });

  test('the shared HTTP and signing seam is reachable', () {
    expect(
      DVHttpRequest(url: Uri.https('example.com')).method,
      'POST',
    );
    expect(
      const DVHttpResponse(statusCode: 200, body: 'ok').isSuccess,
      isTrue,
    );
    expect(dvSendHttpRequest, isA<DVHttpSend>());
    expect(
      DVAwsSigV4.signedHeaders(
        method: 'GET',
        url: Uri.https('example.com', '/'),
        headers: const <String, String>{},
        body: const <int>[],
        credentials: const DVAwsCredentials(
          accessKeyId: 'a',
          secretAccessKey: 's',
        ),
        region: 'us-east-1',
        service: 's3',
        timestamp: DateTime.utc(2026),
      ),
      contains('authorization'),
    );
  });
}

DVJsonValue _tool(DVJsonObject input) => const DVJsonNull();
String _stringFrom(Map<String, Object?> hit) => hit['v']?.toString() ?? '';
Future<String> _token() async => 't';
