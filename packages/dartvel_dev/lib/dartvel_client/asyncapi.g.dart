// GENERATED – do not edit.
library dartvel_client_asyncapi;

/// The generated AsyncAPI 3.0 document for the webhook events this
/// application sends, as JSON. Served by the generated backend at
/// `<apiBasePath>/asyncapi.json`.
const String dartvelAsyncApiJson = r'''
{
  "asyncapi": "3.0.0",
  "info": {
    "title": "dartvel_dev",
    "version": "0.9.0",
    "description": "The webhook events this application sends. The body is Dartvel's envelope: `{id, event, created, data}`. Signed with HMAC-SHA256 over `timestamp.body`, sent as comma-separated `v1=<hex>` entries in `dartvel-webhook-signature` with the timestamp in `dartvel-webhook-timestamp`. Delivery is at least once; a 2xx response acknowledges it."
  },
  "defaultContentType": "application/json",
  "channels": {},
  "operations": {},
  "components": {
    "messages": {}
  }
}
''';
