import '../dartvel_client/dartvel_client.dart';

Future<void> webhooks() async {
  // docs:start webhooks-emit
  DV.Webhooks.declare(const DVWebhookEvent(
    'order.paid',
    sensitiveFields: <String>{'cardLast4'},
  ));

  await DV.Webhooks.subscribe(
    url: 'https://partner.example.com/hooks',
    events: <String>{'order.paid'},
    signingSecret: 'PARTNER_WEBHOOK_SECRET', // a secret's name
  );

  await DV.Webhooks.emit('order.paid', <String, Object?>{'orderId': 'o-42'});
  // docs:end
}

// docs:start webhooks-verify
bool isGenuine(Map<String, String> headers, String body, String secret) =>
    DVWebhookSignature.verify(
      secret: secret,
      timestamp: headers['dartvel-webhook-timestamp']!,
      body: body,
      header: headers['dartvel-webhook-signature']!,
      tolerance: const Duration(minutes: 5),
    );
// docs:end

// docs:start graphql-field
void registerGraphQL() {
  DVGraphQL.registerQuery(DVGraphQLField(
    'serverTime',
    'String!',
    resolve: (Map<String, Object?> args, Object? parent) =>
        DateTime.now().toIso8601String(),
  ));
}
// docs:end

Future<void> tenancy() async {
  // docs:start tenancy-scope
  final String tenant = DV.currentTenant; // 'default' when nothing resolved one

  await DV.withTenant('acme', () async {
    // Tenant-scoped models, cache keys and dispatched jobs belong to acme here.
    final List<Invoice> invoices = await Invoice.all();
    DV.log('${invoices.length} invoices for acme');
  });
  // docs:end
  DV.log(tenant);
}

Future<void> privacy() async {
  // docs:start privacy-erase
  final DVExportArchive archive = await DV.Privacy.export(subject: 'user-1042');

  final DVErasureResult result = await DV.Privacy.erase(
    subject: 'user-1042',
    reason: 'Deletion request from the account page',
  );
  // docs:end
  DV.log('${archive.toJson()} ${result.complete}');
}

Future<void> jobs() async {
  // docs:start jobs-dispatch
  await SendWelcomeEmail(userId: 'user-1').dispatch();

  // Override the declared settings for one dispatch.
  await SendWelcomeEmail(userId: 'user-2').dispatch(
    queue: 'priority-mail',
    maxAttempts: 10,
  );
  // docs:end
}

void queues() {
  // docs:start jobs-adapter
  // Jobs survive a restart and are shared by every worker on this database.
  DV.Jobs.useAdapter(DVDatabaseQueueAdapter(DV.Database.adapter));
  // docs:end
}

Future<void> work() async {
  // docs:start jobs-work
  await DV.Jobs.work(queue: 'mail', maxJobs: 10);
  final dead = await DV.Jobs.deadLetters('mail');
  // docs:end
  DV.log('$dead');
}

Future<void> apiKeys() async {
  // docs:start platform-api-keys
  final DVIssuedApiKey issued = await DV.Auth.apiKeys.issue(
    user: DV.Auth.currentUser,
    actor: DV.Auth.currentUser?.id,
    scopes: <String>['orders:read'],
    name: 'Warehouse sync',
    ratePlan: 'standard',
    expiresIn: const Duration(days: 90),
  );
  // Show issued.secret once. Clients send it as Authorization: Bearer <secret>.
  // docs:end
  DV.log(issued.key.toString());
}
