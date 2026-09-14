## Unreleased

- **Erasure, subject-access export and retention, as a runtime (`DVPrivacy`).**
  Each model declares how its rows reach the person they belong to —
  `DVSubject.self`, `.field(column)`, or `.through(column, parent:)` for a row
  that belongs to somebody through another row — and the walk over those
  declarations is resolved before anything is changed, so a row reached
  through a parent the same erasure deletes is still found. Personal data no
  subject path reaches is refused at construction (`DV-PRIVACY-001`); personal
  data with no retention is a warning (`DV-PRIVACY-002`). `erase` removes a row
  outright even from a soft-delete table, because a row marked deleted still
  holds everything it held; deletes the change log of every erased or
  anonymized row, because a log entry holds earlier values and a revert would
  put them back; and removes a sensitive field's ciphertext rather than
  trusting a key it cannot destroy. A row kept under `DVRetain(years:,
  because:)` is anonymized, names the subject by pseudonym, bumps its version
  so a writer holding the old row conflicts instead of re-saving it, and is
  reported with its `because:` (`DV-PRIVACY-003`). An adapter the erasure could
  not reach makes it incomplete (`DV-PRIVACY-009`), never a quiet success. The
  signed receipt names the subject by pseudonym and stops verifying the moment
  a field of it is edited. A tombstone log lets `replayErasures` erase a
  subject again when a backup is restored (`DV-PRIVACY-005`). `export` walks
  the same graph and leaves out another subject's identifier
  (`DV-PRIVACY-006`). Retention sweeps run in resumable batches, preview with
  `planRetention`, and let a longer retention hold what a shorter one would
  delete (`DV-PRIVACY-007`, `DV-PRIVACY-008`). Erasures and sweeps run on
  `DVQueues`; every export and erasure is recorded through Record History by
  pseudonym. `DVOfflineStorePrivacyAdapter` erases a device's copy, queued
  writes included.


- **Semantic search, as a runtime (`DVSemanticIndex`).** Search over a
  model's records by meaning, built on what already exists: writes enqueue an
  embedding job on `DVQueues` and embed nothing inline, keyword and hybrid
  modes use the model's `DVSearchProvider`, and `DVAIEmbedder` wraps any
  `DVAIAdapter`. Keyword stays the default mode. There is no default
  embedder (`DV-SEMANTIC-001`): vectors from two models are not comparable,
  so an index is a generation named after its embedder, dimensions and
  chunking. A new embedder builds its generation alongside the old one
  (`DV-SEMANTIC-003`); writes land in both, queries keep answering from the
  old one, embedded with the old model, until `backfill(complete: true)`
  switches over, and a backfill that fails part-way resumes rather than
  re-embedding what it already did. Vectors of another length are refused.
- **Scope goes into the vector query.** A k-nearest query filtered afterwards
  shows one tenant another's rows or none of their own, so a tenant- or
  policy-scoped model on an adapter that cannot filter is refused
  (`DV-SEMANTIC-002`), and
  expressible predicates are pushed down. Every loaded row is still checked
  against the caller's tenant and policy, whatever the adapter was asked to
  do. What only a policy can decide is post-filtered with refill up to a
  bound, and a page cut short by that bound says so (`bounded`,
  `DV-SEMANTIC-005`) rather than looking complete. Long fields are chunked,
  a record is returned once with the chunk that matched, and `retrieve`
  hands an AI feature rows without sensitive fields; a sensitive field cannot
  be embedded at all. A record whose embedding job dead-lettered is reported
  by `absentRecords()` (`DV-SEMANTIC-004`), since nobody reports a result
  they never saw. Embedding costs are recorded on a `DVMeters` counter, and a
  tenant past a blocking limit is refused (`DV-SEMANTIC-007`) before the
  query is embedded, not quietly answered by keyword search.
  `DVInMemoryVectorAdapter` is the reference adapter for development and
  tests; pgvector and the search services' vector APIs are not built yet.
- **Crash reporting and release health, as a runtime (`DVCrashReporting`).**
  A crash is written to disk by the handler, synchronously and with nothing
  awaited, and sent by the next launch: a handler runs in a process that is
  already going down, and a write that waits for a round trip finishes after
  the process does. Recovery marks a report sent before deleting it, so a
  process that dies between the two does not send it twice, and a record cut
  short by the crash that wrote it is dropped and named (`DV-CRASH-005`) rather
  than sent half-read. Breadcrumbs are a ring buffer redacted on the way in —
  the logger's key list as substrings, fields declared sensitive as exact names,
  and resolved secret values in every string — so a card number in a backend
  call's payload never reaches the stored bytes. Reports group by error type
  and the top application frames with framework frames trimmed, never by
  message or line, so an id in a message does not split one bug and the same
  message from two places does not merge two; an override fingerprint wins
  where the default is wrong. Past a per-release limit a device's crashes are
  counted but not written (`DV-CRASH-004`), and the count is kept in the store
  because a crash loop is a sequence of restarts. Non-fatal errors are sampled
  (`DV-CRASH-008`); crashes never are. `DVHangWatchdog` files one hang per
  freeze (`DV-CRASH-007`). `DVReleaseHealth` counts crash-free sessions and
  users from sessions that started — a device offered a release that never
  opened it is in its cohort and not its denominator — and
  `DVReleaseHealthGate` holds a rollout when any cohort falls below threshold,
  even inside a healthy release average (`DV-CRASH-010`). Reports stored as
  files on `dart:io` targets and in memory elsewhere.
- **Outbound webhooks (`DVWebhooks`, `DV.Webhooks`).** Events are declared
  (`DVWebhookEvent`) and emitting a name that is not declared is refused
  (`DV-WEBHOOK-006`), so the catalog a customer reads cannot drift from what
  the code sends. A payload is serialized once at emit: a model through
  `toPublicJson`, so its sensitive fields are absent by construction, with the
  event's declared sensitive fields removed wherever they appear in a map.
  Each delivery is signed with HMAC-SHA256 over `timestamp.body`, the key read
  from `DVSecrets` at every attempt, and a rotation sends both signatures only
  until its overlap ends (`DV-WEBHOOK-007`) — a retry after that is not signed
  with the rotated-out key. Delivery rides the job layer and goes out through
  `DV.Http`, one queue per subscription, and a job always attempts the oldest
  undelivered delivery for its endpoint: the queue re-queues a failed job at
  the back, so a job that named its own delivery would have let event 2
  overtake a failing event 1. Subscriptions drain concurrently, so an endpoint
  that takes thirty seconds to answer delays its own deliveries and nobody
  else's. A delivery that exhausts its attempts is dead-lettered
  (`DV-WEBHOOK-004`) and the next proceeds; an endpoint that keeps failing is
  disabled, its owner told through `onDisabled`, and its queue flushed
  (`DV-WEBHOOK-003`). The endpoint address is untrusted input: it must be
  HTTPS, and it is refused when it resolves to a private, loopback,
  link-local, carrier-grade NAT, reserved or cloud-metadata address — IPv4
  mapped or embedded in IPv6 is judged as the IPv4 address it is — both at
  subscribe time and again at every attempt, since DNS can change in between,
  and every redirect hop is checked the same way (`DV-WEBHOOK-002`). Every
  delivery is recorded; the payload is dropped after `retention` while the
  record is kept, and a replay past the window is refused (`DV-WEBHOOK-005`)
  rather than sent with an empty body.


- **Sessions, as a runtime (`DVSessions`).** A session is a record of a
  signed-in device, and its token is a bearer credential, so the store holds
  only the token's hash: a dump of the session table is not a list of working
  sessions. The token is reissued on every privilege boundary — `rotate`,
  `elevate` (claims) and `completeMfa` (second factor) — and the old one stops
  authenticating in the same write, because a stable identifier across a
  boundary is session fixation. Revocation is checked on the next request, so
  `revoke(id)` and `revokeOthers(token)` sign a device out at once rather than
  at expiry (`DV-SESSION-002`). Idle and absolute timeouts both apply, and
  rotation keeps the original sign-in time, so a session kept alive by
  rotating still ends. `list(userId, currentToken:)` shows every live device,
  newest first, by a listed id that is never the token. Memory and
  `DVDatabaseSessionStore` drivers; the database one issues only the SQL the
  in-memory adapter runs, so it works with no database configured and on
  SQLite alike.
- **`DVMfa` is a policy, not a sign-in method.** `DVMfa.required` needs a
  second factor at some point in the session and `DVMfa.recent(window)` needs
  one within the window — step-up, which is what a payout wants.
  `requireMfa(token, policy)` answers with the session, `DVMfaRequired`
  (`DV-SESSION-001`) when the factor is missing or stale, or `DVSessionInvalid`
  when there is no live session to ask about.
- **Second factors: TOTP and recovery codes (`DVSecondFactors`).** TOTP per
  RFC 6238, checked against the RFC's own test vectors, with a provisioning
  URI for a QR code. Every account records the last time step it accepted and
  advancing it is a compare-and-set in the store, so the same six digits
  cannot sign in twice — not inside their window, and not from two requests
  racing. The secret is sealed with `DVFieldCipher` and never stored as the
  base32 an app is shown; enrollment stays pending until a code proves the app
  has it, and that code cannot then sign in. Recovery codes are kept only as
  salted HMACs, shown once, spent on use, and replaced wholesale on
  regeneration; a `DVRecoveryCodes` printed into a log prints a count.
- **`DVSessionCookie` sets the session cookie with attributes an application
  cannot weaken:** `HttpOnly`, `SameSite=Lax` or `Strict`, and `Secure` with a
  `__Host-` name outside development. `SameSite=None` is refused as a
  configuration error naming the setting (`DV-SESSION-003`) rather than set as
  a quietly cross-site cookie.
- **Offline-first stores, as a runtime (`DVOfflineStore`).** A model's writes
  go to a local `DVRecordTable` at once — so the same read and write calls
  work in a tunnel as on Wi-Fi — and to an ordered mutation log that `replay`
  sends to the server. The failures it exists for are the silent ones, and
  each has a test that fails when the guard is removed: two replays started
  by one reconnect share one run instead of sending the log twice; a mutation
  whose acknowledgement was lost is resent with the same id and the server
  side (`DVRecordTableRemote`) applies it once; a transient failure stops
  replay rather than sending later writes ahead of an earlier one; a write at
  the log's bound — by count or by the age of the oldest queued write — is
  refused with `DVOfflineQueueFullError` (`DV-OFFLINE-002`) and nothing
  queued is dropped; a permanent refusal moves to the dead letters
  (`DV-OFFLINE-003`) and replay continues. Conflicts use the `DVConflict`
  vocabulary record history already has, and `DVConflict.ask` is refused for
  an offline model (`DV-HISTORY-002`), since offline there is nobody to ask.
  `lastWriteWins` compares the declared clock rather than arrival order, and
  `DVOfflineClock` stamps writes with the offset the server last reported, so
  a device with the wrong date does not win every conflict
  (`DV-OFFLINE-004`, once). Each record has a `DVSyncState` — pending,
  syncing, synced, conflicted or rejected — readable and watchable. A
  memory-backed store says it will not survive the application closing
  (`DV-OFFLINE-001`). Not yet generated from `@DVModel(offline:)`: see the
  specification's status for what is absent.

- **Feature flags, as a runtime: `DVFeatureFlag` and `DVFlags`.** A flag
  answers from one pure function of a rule set and an evaluation context —
  identity, tenant, device, organization role, app version, platform, locale
  and declared attributes — so a phone and a backend function given the same
  two reach the same answer. A read resolves a debug-only override, then the
  synced `DVFlagRules`, then the default compiled into the build; with nothing
  synced it answers the default and says so once (`DV-FLAGS-001`). A
  percentage rollout buckets on the first eight bytes of
  `SHA-256("key:subject")` mod 10,000, so a person keeps their answer across
  devices and reinstalls, two 10% flags pick different tenths, and raising a
  percentage only adds people; a rollout with no subject holds the default
  rather than rolling a die (`DV-FLAGS-005`). A rule value of the wrong type
  holds the default instead of being coerced (`DV-FLAGS-006`) — `"true"` is not
  a bool and `2.5` is not an int. Stale rules stay in force and report past
  `maxAge` (`DV-FLAGS-009`), because a kill switch that expires back to on is
  worse than one a day old. `onNextLaunch` pins a flag for the process,
  `withOverrides` scopes overrides to a zone so a test's flags never leak, and
  an exposure is recorded once per flag per context per session, or reported
  as withheld when consent is (`DV-FLAGS-007`). `@DVFlags()` and `@DVFlag` are
  the declarations the generator reads.

- **`DV.Http`: outbound HTTP with the failure paths built in.** Declared hosts
  (`DV.Http.declare`, or the `dartvel.http.hosts` block through
  `declareFromConfig`) carry a base URL, a bearer credential named by secret
  and resolved through Secrets when the request is sent, a timeout, a retry
  policy, a circuit breaker and a concurrency limit. Requests and responses are
  the same WinterCG `Response` and `Headers` the inbound side uses. Retries are
  idempotency-aware: `GET`, `HEAD`, `PUT` and `DELETE` retry on 429, 5xx and
  transport failures; a `POST` retries only with an idempotency key, sending
  the same key each time, and asking to retry one without a key sends it once
  and logs `DV-HTTP-003`. An open breaker fails fast with a typed error naming
  the host and when it will try again (`DV-HTTP-002`), and lets exactly one
  probe through after its cooldown. A timed-out request keeps its pool slot
  until it really finishes, and its later failure is observed rather than
  escaping as an uncaught error. A call inside a span sends a `traceparent`
  for a child span. `DV.Test.fakeHttp` answers by host name, refuses any
  request no stub answers (`DV-HTTP-004`), and replays fixtures recorded from
  real responses.

- **Usage metering, as a runtime (`DVMeters`).** A `DVMeterDefinition`
  records against the current tenant — never the process — so each customer's
  total is theirs, and two instances on one database see one number. Every
  recording carries an idempotency key, from the call or from a
  `DVMeters.withIdempotencyKey` scope (the request or job id), and a key seen
  before is discarded (`DV-METER-002`) — including a late retry that would
  otherwise land in the next period; a recording with no key is refused
  rather than given a generated one that differs on the retry. A limit needs
  a declared behaviour (`DV-METER-005`): `block` refuses and does not count,
  `throttle` counts and admits, `allowAndBill` counts and reports the overage,
  each raising `DV-METER-004`. Enforcement is serialised per tenant and meter,
  so ten simultaneous calls against a limit of three admit three. `notifyAt`
  thresholds are announced once, as they are crossed (`DV-METER-003`). Usage
  lands in the tenant's billing period, falling back to the calendar month
  and saying so (`DV-METER-010`); periods are half-open, a resolver answering
  a period that does not contain the instant is refused, and a late record is
  accepted into its closed period within the grace (`DV-METER-007`) or counted
  in the open one after it (`DV-METER-008`). Gauges bill on their average or
  peak. `DVLevelLimit` checks a level such as seats by querying it and writes
  nothing. `DVMemoryMeterStore` and `DVDatabaseMeterStore`, tested on the
  in-memory adapter and SQLite.

- **Metered usage reaches the billing provider (`DVMeterReporter`).** A
  closed period's usage is sent through `DVBillingProvider.recordUsage` under
  a key made of the tenant, the meter and the period, so a report sent twice —
  or retried after a response was lost — is billed once. A period is refused
  while it can still receive usage, before its end plus the grace, because a
  report sent then leaves out whatever arrives late. A gauge is billed as a
  whole number rounded up. A period with no usage sends nothing; a meter with
  no price on the tenant's plan is counted and not billed (`DV-METER-009`). A
  report that fails, or a tenant with no billing customer, is queued rather
  than dropped (`DV-METER-006`), and `retryPending` sends the queue again;
  `DVDatabaseMeterReportQueue` keeps it across restarts and instances.
  `reconcile` lists where Dartvel's figure and the provider's differ, per
  tenant per meter, and changes nothing.

- **Versioned writes, record history and soft delete, as a runtime
  (`DVRecordTable`).** A write carries the version it read and lands through a
  conditional `UPDATE ... WHERE _dv_version = ?`, so a write against a row that
  moved is refused with `DVConflictError` (`DV-HISTORY-001`) holding what this
  session wrote, what the row holds and what was read — instead of silently
  replacing the change that moved it, which is the lost update both writers
  would have seen as success. A write to an existing row with no version read
  is refused for the same reason. `DVConflict` resolves a conflict when the
  caller says how: `ask` (the default, and not a legal offline strategy),
  `serverWins`, `lastWriteWins`, `fieldMerge` and a typed `resolver`.
  `history: DVHistory(keep: ...)` records each change's actor, tenant,
  transaction and changed fields, with `sensitive` fields recorded as changed
  and never as values — the history table is checked for the plaintext, not
  just the returned object. A change whose entry cannot be written is undone
  (`DV-HISTORY-005`). `revert(to:)` adds a change rather than rewinding, keeps
  every entry in between, reports the sensitive fields it could not put back
  (`DV-HISTORY-003`) and takes the same version check as any write.
  `softDelete` marks rather than removes; `restore` is refused when a live
  record holds a unique field (`DV-HISTORY-006`). Inside `DV.transaction` every
  write registers its own inverse, so a later failure takes the write and its
  entry with it. Tested on the in-memory adapter and SQLite; the statements are
  the subset Postgres and MySQL already run.

- **A transaction has an identifier: `DVContext.transactionId`.** The same
  for every context in one unit of work — a nested call joins the outer one —
  and different between two, so a history entry can name the transaction that
  wrote it.

- **A Postgres server that declines TLS no longer breaks the connection that
  asked.** `sslMode: prefer` is the default and its whole purpose is to ask
  for TLS and carry on without it — the ordinary shape of a local or
  containerised Postgres that was never given a certificate. Asking means
  listening to the socket for the single byte the server answers with, and a
  `Socket` is a single-subscription stream. When the answer is `S` the socket
  is replaced by a `SecureSocket`, which is a new stream, so the adapter could
  listen to it; when the answer is `N` the code carried on with the *same*
  socket and the adapter's first act — `connection.input.listen(...)` — threw
  `Bad state: Stream has already been listened to`. The mode whose job is
  falling back to plaintext could not produce a usable connection at all, and
  the state error masked whatever the server had really said, so every
  failure in that path reported the same Dart-level symptom instead of its
  cause. The subscription that read the answer now stays and feeds the stream
  the adapter reads, which is what the MySQL adapter had already been doing
  for the same reason. Bytes the server sends in the same segment as its
  refusal are relayed rather than dropped.

- `MemoryDVDatabaseAdapter` runs the SQL Dartvel itself issues, so the
  framework can be run and tested without a database. It understood four
  statement shapes -- `select 1`, `select * from t`, an unscoped insert and an
  unscoped delete -- and threw `ArgumentError` on everything else, which meant
  the development adapter could not back the framework's own surfaces:
  `DVPageStore`, `DVDatabaseCacheAdapter` and `DVDatabaseQueueAdapter` all
  failed on their first statement. Studio rendered "Could not read pages"
  where the pages should have been, and `DVTest.fakeDatabase()` was a fake no
  Dartvel code could use. It now interprets `CREATE TABLE`/`DROP TABLE`,
  `INSERT` (including an explicit `rowid`), `UPDATE ... SET ... WHERE`,
  `DELETE ... WHERE`, and `SELECT` with `DISTINCT`, a column subset,
  `COUNT(*) AS alias`, `WHERE` conditions joined by `AND` over
  `= != <> < <= > >= IS NULL IS NOT NULL`, multi-key `ORDER BY` with `rowid`
  and `ASC`/`DESC`, `LIMIT` and `OFFSET` -- binding `?` in the order the
  statement writes it, and following SQL's rule that a comparison against
  null never matches. The cache and queue adapters are now held to the same
  shared contracts on it that they are on SQLite.

  Anything outside that subset -- a join, a subquery, `OR`, SQLite's FTS5
  `MATCH`, `ALTER TABLE` -- still throws, and the message now names the
  statement it refused. An in-memory adapter that guessed at a query it had
  not parsed would be worse than one that cannot run it: wrong rows look
  exactly like right ones.

- A kiosk says when it blocks a route. `routes.allow` was parsed, scanned by
  doctor and given `DV-KIOSK-006` for a route being blocked, and the redirect
  that did the blocking reported nothing -- so a kiosk sending `/admin` back
  to its home page looked exactly like a link that was wrong.
  `DVKioskDegradation.routeBlocked` is the member that names it, and it was
  assigned nowhere until now. The block is logged at `debug`, the level the
  registry gives that code, with the route and where it went.
- An exit result carries the degradation rather than a code spelled out
  beside it. `DVKioskExitResult.degradation` is `lockedOut` after
  `maxAttempts`, `noPolicy` in a build with no kiosk policy, and `none`
  otherwise; `code` derives from it. The codes were string literals written
  next to the enum members that mean the same thing -- two places to change
  and one of them silently stale -- and `DVKioskDegradation.lockedOut` was
  assigned nowhere at all, so a caller could only learn what had happened by
  matching the text of a code.

- Diagnostic codes for the sections the third pass added: `DV-STORE` (store
  publishing and privacy declarations), `DV-RELEASE` (backend release
  management), `DV-HISTORY` (record history and optimistic concurrency),
  `DV-ORG` (organizations and invitations), `DV-ANALYTICS` (product analytics
  and consent) and `DV-APIKEY` (platform API keys, scopes and the OAuth
  provider). Specified, not built; `dartvel explain` can answer them.

- The diagnostic registry carries the codes the specification added for
  protocol versioning, offline-first models, schema evolution, client
  schedules, 3D scenes and PDF export. `dartvel explain` answered "unknown
  code" for twenty codes the document publishes, and the test that exists to
  catch exactly that disagreement was failing. Its row pattern also skipped
  any family with a digit in it, so the whole `DV-3D` family was outside the
  check in both directions; it is inside it now.

- `dvKioskLocksWindows` reports whether a running kiosk policy holds the
  surface to one window -- true in `device` scope, which the specification
  defines as one application with no windows. The windowing capability reads
  it, so `open()` under a device kiosk names the kiosk (`DV-WINDOW-002`)
  rather than reporting the target as incapable of windows.

## 0.5.0

- The `DV.Database` docs say whose code generation the `build_runner` step
  they describe is: drift's. Dartvel's own generation is `dart run
  dartvel_cli:dartvel routes`, and the build_runner path through
  `dartvel_generator` is retired, so a step that just said "run code
  generation" now reads as the retired one.
- `DVImageVariants`: the widths images are resized to (Next.js's defaults
  unless `dartvel.images.widths` says otherwise), the one address a variant
  is asked for by, and the checks a server applies to a request for one -- a
  width outside the set, a path out of the site, a host not in
  `dartvel.images.remoteHosts`, credentials in an address. The widget, the
  link prefetch and the server all call it, so all three name the same file:
  a prefetch of a slightly different address is a second download, not a
  cache hit.
- `dartvel.web.server.streaming: shell` -- `DVPageStreaming.shell`, alongside
  `head` (`true`) and `off` (`false`), which read and write exactly as
  before. `DVWebServerSettings.streaming` stays, now true for either kind of
  streaming; `streamingMode` says which.
- `dvHeadParts` splits a page's head into what no render of its shell
  changes and what page data writes -- the SEO block, a stray title or
  description, the icon, the structured data. The first part is identical in
  every render of one shell, which is what makes it safe to send before the
  data exists.
- `DVRoutePreloads` reads the prefetch manifest a web-server build writes
  and gives a served route its own `<link rel="preload">` list, by the
  pattern the request matched: its deferred parts as scripts, its images as
  they are fetched, nothing the shell already names and no image drawn
  through a variant, since which file that is depends on the screen.
- `dvShellFirstChunks` is shell-first streaming as one function, the route's
  preloads in its first write, and both servers stream through it -- the
  deployed one and `dartvel preview`, which had only the older head-after-data
  split, so the page previewed was not the page served.

## 0.4.0

Breaking: `DVFieldCipher` takes its randomness through a named constructor.
`DVFieldCipher.secure(keyring)` is what an application wants; the unnamed
constructor is `@visibleForTesting` and exists so a test can supply a
deterministic source. A cipher that silently accepted a seeded `Random` in
production was a key generator with no entropy.

- The Android permission table gained the names the capture bridge resolves at
  run time, so a request can never name a permission the manifest lacks --
  Android refuses an undeclared permission instantly, with no dialog, and the
  answer is indistinguishable from a person tapping Deny.
- Billing gained usage meters, trials, invoices and a webhook receiver, with
  every grant keyed by a real customer identity rather than `toString()`. The
  default `toString()` of an ordinary object is the same constant for every
  instance, so passing a logged-in user filed every user under one key.
- Webhooks are applied newest-wins per subscription. Providers do not
  guarantee order, and a stale `active` arriving behind a cancellation handed
  a cancelled customer their entitlement back with a valid signature.

## 0.3.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.3.1

- Kept web-compatible: the distributed cache hashes in 32-bit arithmetic, and
  the LDAP client is behind a conditional export. Both broke `flutter build web`
  outright.
- The main barrel exports Request, Response and Headers again; the full wire
  type set moved to `package:dartvel_core/http.dart`.

## 0.3.0

Four queue brokers, both network databases reachable over TLS, static
generation that produces pages, and a page that can have a body.

### Queues, on real brokers

Seven adapters now: in-memory, database, Redis, SQS, RabbitMQ, Pub/Sub and
Kafka. The four that talk to a network service are verified in CI against the
real thing -- ElasticMQ, RabbitMQ's own image, Google's emulator and Apache
Kafka -- rather than against a fake that agrees with whatever the adapter does.

That distinction found nine bugs which every unit test had passed: a backoff
sent as an initial delay, an AMQP channel limit above the server's,
delivery-mode written to the wrong bit, publishes returning before the broker
had them, a payloadType that would have stopped every handler matching, a Fetch
reply parsed with three fewer fields than it has, offset commits sent to a
broker that was not the group's coordinator, and a first coordinator lookup
that is always refused and always retriable.

Each adapter is written around what its service actually offers. SQS and
Pub/Sub refuse `pending` rather than returning an empty list, because an empty
list reads as "there is nothing" when the truth is "I cannot see". Kafka is a
log, so it has no dead letters, no priority and no out-of-order retry, and
`lag` gives the honest version of a backlog: a distance, not a list.

### Databases

PostgreSQL and MySQL both negotiate TLS, which is what a managed endpoint
requires -- Aurora, Neon, Supabase, PlanetScale and Cloud SQL all demand it and
most refuse plaintext, so before this the adapters reached localhost and
nothing else. `sslMode` takes libpq's names, so a connection string copied from
a provider's console pastes in unchanged.

A refusal is fatal at `require` and above. Falling back would put the password
on the wire in the clear while the caller believed the connection was
encrypted.

### Pages can have bodies

A private `@DVPage` input had to be a single expression, so every page needing
a local, a loop or a condition was written as a one-line wrapper around a
public helper. Block bodies are lowered into the generated widget now.

`@DVFunctionalWidget` and `@DVBackendFunction` still require expression bodies.

### Static generation

`dartvel build web` writes a page per route and expands parameterised routes
through the application's own resolvers. `@DVModel(generatePublicPages: true)`
now generates the route as well as the paths -- it previously produced a list
of addresses that all resolved to the application's own not-found page.

A page no route serves is refused rather than written.

### The web output

Crawler-visible HTML is built from the page's semantics tree rather than from
string literals in the source, so it carries real headings, anchors and
landmarks instead of one paragraph per source line. Pages gained structured
data, a stylesheet for `sitemap.xml`, and an `.htaccess` that path URLs need
and that nothing was writing.

In-app links push the route instead of tearing the document down and rebuilding
the whole application, which is what a real anchor in the semantics tree does
by default.

## 0.2.1

- First published release.

Dartvel's packages are published under the `dartvel_dev` name on pub.dev.
`dartvel` was taken on 2026-08-06 by an unrelated package, so the published
identifier carries a suffix while the command stays `dartvel`.
