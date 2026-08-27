// The spec offers focused entrypoints (`package:dartvel_dev/dartvel_ai.dart` and
// friends) alongside the umbrella import. Each one re-exports the flutter
// barrel through a `show` list, so a subsystem's entrypoint can compile while
// omitting the very types needed to configure it — the facade is reachable but
// no adapter is. These tests import one entrypoint at a time and construct the
// pieces an application needs, so an incomplete list fails to compile.
import 'package:dartvel_dev/dartvel_ai.dart' as ai;
import 'package:dartvel_dev/dartvel_auth.dart' as auth;
import 'package:dartvel_dev/dartvel_database.dart' as db;
import 'package:dartvel_dev/dartvel_storage.dart' as storage;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dartvel_ai can configure the facade it exposes', () {
    // The point of the entrypoint: reach DV.AI *and* something to configure
    // it with.
    final adapter = ai.AnthropicDVAIAdapter(apiKey: 'k');
    expect(adapter, isA<ai.DVAIAdapter>());
    ai.DV.AI.configure(adapter);

    expect(ai.OpenAIDVAIAdapter(apiKey: 'k'), isA<ai.DVAIAdapter>());
    expect(ai.OpenRouterDVAIAdapter(apiKey: 'k'), isA<ai.DVAIAdapter>());
    expect(ai.GeminiDVAIAdapter(apiKey: 'k'), isA<ai.DVAIAdapter>());
    expect(ai.OllamaDVAIAdapter(), isA<ai.DVAIAdapter>());
    expect(const ai.LocalDVAIAdapter(), isA<ai.DVAIAdapter>());

    // Tool registration needs the typed JSON values too.
    ai.DV.AI.registerTool(
      'ping',
      (input) => const ai.DVJsonString('pong'),
      description: 'Answers pong.',
      parameters: const <String, ai.DVJsonValue>{
        'type': ai.DVJsonString('object'),
      },
    );
    expect(ai.DV.AI.hasTool('ping'), isTrue);

    ai.DV.AI.configure(const ai.LocalDVAIAdapter());
    const ai.DVAIToolRegistry().clear();
  });

  test('dartvel_auth can configure providers and hash passwords', () {
    auth.DV.Auth.configure(auth.DVLocalAuthProvider());

    final hasher = auth.DVPasswordHasher(iterations: 1000);
    expect(hasher.verify('pw', hasher.hash('pw')), isTrue);

    expect(auth.LocalAuthProvider(), isA<auth.AuthProvider>());
    expect(
      const auth.AuthException(auth.AuthFailure.unknownAccount, 'no').failure,
      auth.AuthFailure.unknownAccount,
    );

    final oauth = auth.DVOAuth2Client(
      config: auth.DVOAuth2Config.google(
        clientId: 'c',
        redirectUri: Uri.https('app.example.com', '/callback'),
      ),
    );
    expect(oauth.createAuthorization(), isA<auth.DVOAuth2Authorization>());
  });

  test('dartvel_database can configure the facade it exposes', () async {
    final adapter = db.MemoryDVDatabaseAdapter();
    expect(adapter, isA<db.DVDatabaseAdapter>());
    db.DV.Database.configure(adapter);
    expect(await db.DV.Database.query('select 1'), isNotEmpty);

    expect(
      db.DVDatabaseCacheAdapter(adapter),
      isA<db.DVCacheAdapter>(),
    );
    expect(db.SqliteDVDatabaseAdapter, isNotNull);
  });

  test('dartvel_storage can configure the facade it exposes', () async {
    final adapter = storage.DVMemoryFileStorageAdapter();
    expect(adapter, isA<storage.DVFileStorageAdapter>());
    storage.DV.Storage.configure(adapter);

    await storage.DV.Storage.put('a.bin', <int>[1, 2, 3]);
    expect(await storage.DV.Storage.get('a.bin'), <int>[1, 2, 3]);

    expect(
      storage.S3FileStorageAdapter(
        bucket: 'b',
        region: 'us-east-1',
        credentials: const storage.DVAwsCredentials(
          accessKeyId: 'a',
          secretAccessKey: 's',
        ),
      ),
      isA<storage.DVFileStorageAdapter>(),
    );
  });
}
