## Unreleased

- **A provisioned host's backend believes the client Caddy reports.** With
  `proxy: { adapter: caddy }`, every backend unit `dartvel infra` renders sets
  `DARTVEL_TRUSTED_PROXIES` to the address Caddy dials it on, the same
  constant the Caddyfile's upstreams are written from. Without it every
  request reached the backend from Caddy's address, and every per-source
  limit counted the whole internet as one client. A host with no proxy trusts
  none. Units already provisioned are reported as drifted by `dartvel infra
  check` until the next apply writes the new line.

- **One client address, and a header believed only from a trusted proxy.**
  `DVClientAddress` resolves who a request came from: the connection's peer
  address, unless the peer is in the configured trusted proxies, in which case
  `X-Forwarded-For` (or `Forwarded`, when that is the configured header) is
  walked from the right and the first hop that is not a trusted proxy is the
  client. A hop that does not parse stops the walk and nothing left of it is
  read; a request with no peer address has no client address, never a
  header's. `DVCidr` ranges refuse what is not exactly a range, including
  `10.0.0.1/8`. `DVClientAddress.fromConfiguration` reads the pubspec's list
  plus `DARTVEL_TRUSTED_PROXIES`, and `DVClientAddress.install` sets the
  process's resolver, which trusts no proxy until one is installed.
- **Per-source limits count the client, not what it wrote.** The sign-in and
  sign-up endpoints' `sourceOf` and `CommonMiddleware.rateLimit`'s default
  identifier took the first `X-Forwarded-For` entry -- the rate limit also
  `CF-Connecting-IP`, `X-Real-IP`, `Fastly-Client-IP`, `True-Client-IP` and
  `Forwarded` -- so a client wrote a new one per request and was never
  counted twice, and every request without one shared a bucket. Both use
  `DVClientAddress` now; a request with no peer address counts as `unknown`.
  The rate limit no longer reads `remoteAddress` or `ip` from a map-shaped
  request; `peerAddress` is the key. `DVWaf.countryHeader` believes its
  header only from a trusted proxy, and the country is otherwise unknown.

- **`Request.peerAddress`, and addresses as values.** A request carries the
  address at the other end of its connection when the server that built it
  had one (`dartvel_shelf` sets it from the socket); null otherwise, and never
  a header. `DVIpAddress` compares by meaning rather than spelling -- an
  IPv4-mapped IPv6 address is its IPv4 address, and IPv6 prints in RFC 5952
  form -- and refuses what is not strictly an address, including IPv4 with a
  leading zero. `DVPeerAddress` is an address with an optional port, read from
  `1.2.3.4:80`, `[2001:db8::1]:80` or a bare address.
- **`@DVBackendFunction(mfa:)` and `@DVPage(mfa:)`.** Both annotations take a
  `DVMfa`: `DVMfa.required` for a second factor at some point in the session,
  `DVMfa.recent(Duration(...))` for one within the window.
  `DVAuthEndpoints.requireMfa(policy)` is the gate a generated route runs:
  nobody signed in is a plain 401, a caller on an API key or OAuth token is 403
  (it has no factor to present), and a session without a recent enough factor
  is `stepUpRequired` -- 401 with `insufficient_user_authentication` and
  `max_age`. `DVStepUp.send` is how a generated call answers that: it presents
  `DVStepUp.challenge` and sends the call once more. Only an `mfa_required`
  answer is a step-up, calls refused together share one challenge, and a
  dismissed or failed challenge returns the refusal without sending again.
- **Second factors, as endpoints.** `DVAuthEndpoints` now also handles the
  signed-in person's factors: `factors` (whether an authenticator is active
  and how many recovery codes are left, never a code), `beginTotp` (the secret
  and its `otpauth://` URI), `confirmTotp`, `recoveryCodes` and
  `removeFactor`. Beginning activates nothing -- sign-in asks for no code
  until one from the app confirms it. Recovery codes are answered once and
  kept only as salted HMACs; a new set replaces every earlier code, and
  generating one needs a second factor within `stepUpWindow` (ten minutes by
  default), because a stolen session printing itself recovery codes would
  keep the account after the session was revoked. Removing the authenticator
  takes a code or a recovery code in the same request, however recent the
  session's factor, and removes every recovery code with it. Each change
  rotates the session. `DVAuthEndpoints.stepUpRequired` is the refusal for a
  missing or stale factor: 401 with RFC 9470's
  `insufficient_user_authentication` and `max_age`. `DVAccountDirectory`
  (implemented by `LocalAuthProvider`) lets the authenticator list the account
  under its address.

- **The application's own sign-in, as endpoints.** `DVAuthEndpoints` handles
  sign-up, sign-in, a second factor, sign-out, the current session, the
  signed-in person's sessions, revoking one and revoking the others; the
  generated backend serves them. `DVAuthEndpoints.install(credentials:
  DVCredentialGuard(provider: ...), secondFactors: ...)` names the provider,
  and until then signing in is a 503 saying so. Credentials go through the
  guard, so an unknown account and a wrong password get one answer after the
  same floor of time, velocity limits apply per account and per source, and a
  breached password is refused at sign-up. A session is issued with
  `DVSessions` on the request's tenant and replaces one the request already
  carried. A browser -- a request with `Origin` or `Sec-Fetch-*`, which a
  script cannot remove -- gets it only in the `__Host-dv_session` cookie
  (`HttpOnly`, `Secure`, `SameSite=Lax`, `Path=/`); a native client that asks
  with `x-dartvel-session-delivery: token` gets the `dvs_` token only in the
  body. An account with a second factor gets a session carrying
  `DVSession.mfaPendingClaim`, which the authentication stage refuses on every
  route with `Bearer error="insufficient_user_authentication"`; a TOTP code
  or a recovery code at `/auth/second-factor`, counted against the account's
  velocity limit, completes it through `DVSessions.completeMfa`, and only the
  rotated token carries the person's privilege. Sign-out revokes on the
  server and clears the cookie. The sessions endpoints answer for the
  signed-in person's own sessions on the request's tenant: another person's
  session id is 404, and revoking the others keeps this one. Nothing presented
  is logged or echoed, and every answer is `no-store`. `DVSession.toJson` and
  `DVSession.fromJson` describe a session without its token.

- **A route refused for want of a caller says so.**
  `DVBackendPolicy.checkAction` answers `DVPolicyDecision.allowed`,
  `unauthenticated` or `forbidden`, and `allowsAction` is it answering
  allowed. `unauthenticated` is the one case where signing in would change
  the answer: nobody authenticated, `decide` is not set, and the registered
  policy's user parameter is not nullable
  (`DV.Auth.authorization.requiresCaller`). Every other refusal -- outside a
  key's scopes, an action nothing registered, `decide` saying no, a caller the
  policy cannot take, the policy saying no -- stays `forbidden`.

- **A route's policy is asked about the signed-in person.**
  `DVBackendPolicy.allowsAction` asked a registered policy with the API key
  principal or nobody, so a policy written against the application's user
  refused everybody signed in with a session. `DVBackendPolicy.callerFor`
  now picks the caller: the key or OAuth principal when the platform API
  authenticated the request; otherwise the application's user when the
  policy can take it -- a policy taking `Object?` can, so `user is Account`
  answers for a signed-in account -- then `DVSessionPrincipal` for a policy
  written against that. The choice is made from the types the registry holds
  for the policy (`DV.Auth.authorization.acceptsCaller`) rather than from a
  name the generator assembled. A GraphQL subscription keeps the session
  caller as it keeps a key's, since its stream starts outside the request.

- **The application's own session is a caller.** `DVSessionAuthentication` is
  the authentication stage for a session: a `Bearer dvs_...` token or the
  `__Host-dv_session` cookie (`dv_session` in development) becomes
  `DVSessionPrincipal.current` -- the session, its user id and tenant, the
  application's user from `resolveUser`, and the membership in the
  organization on the request's tenant -- and an injected `DVContext` carries
  it as `context.session` and `context.user`, beside `context.apiPrincipal`.
  A presented session that does not authenticate -- unknown, rotated away,
  revoked, expired, issued on another tenant, or whose user `resolveUser` no
  longer finds -- is one 401 with no reason in it, and one carried by the
  cookie clears the cookie. The user and the membership are read on every
  request rather than kept from sign-in, so a role changed mid-session applies
  to the next request. Any other bearer token, an API key and an OAuth token
  pass through untouched, and a session presented to a process that installed
  no stage is a 503 rather than ignored. `DVSessions` tokens now start with
  `dvs_`, a session records the tenant it was issued on (a `tenant` column in
  `DVDatabaseSessionStore`), and `check(token, tenant:)` refuses one from
  another tenant without recording its use.

- **A GraphQL field runs under the policy of what it resolves through.**
  `DVGraphQLField(policy: 'Order.create')` is asked the way a backend
  function's route asks it -- scopes, then the registry, then `decide` --
  before the resolver runs, on queries, mutations, nested fields and
  subscriptions; a refused field is null with a `FORBIDDEN` error and its
  resolver never runs. A root field declaring no policy answers no API key or
  OAuth token, as a route declaring no policy action already does. A
  subscription captures the caller and the tenant when `DVGraphQL.subscribe`
  is called, because its stream is started wherever somebody listens.

- **`@DVPolicy` registrations are a layer the application's own wins over,
  and a route's `Resource.action` is answered by the registry.**
  `DV.Auth.authorization.registerDeclared` is what the generated client and
  server register policy classes with; `register` is the application's, and
  for the same action and resource it is asked instead, whichever ran first.
  `declaredPolicies` and `overriddenPolicies` say which is which. `Order?` and
  `Order` key the same resource. `canAction(user, 'Order.view', resource:)`
  asks by name, refusing a caller or resource the policy cannot take -- a
  policy taking `Order` asked without an order -- and saying why once, rather
  than throwing a cast error. `DVBackendPolicy.allowsAction` is the gate a
  generated route with a quoted `Resource.action` calls: a principal outside
  its scopes is refused, then an action nothing registered is refused even
  when `decide` says yes, then `decide` answers if the application set one,
  and otherwise the registered policy does, with the principal and no
  resource. `DVBackendPolicy.verifyRegistered` refuses to start a server whose
  routes name an action nothing registered. `DVBackendPolicy.allows` is
  unchanged for a reference such as `DVPolicies.refund`.

- **`DVPlatformApiAuth` manages the current organization's API keys and
  OAuth clients through `DV.Auth.authorization`.** `apiKeys.issue`, `list`,
  `rotate` and `revoke`, and `oauthClients.register`, `list` and `revoke`,
  act on the organization on the current tenant and ask the policy
  registered for `DVApiKeyResource` or `DVOAuthClientResource` (`create`,
  `viewAny`, `update`, `delete`), which sees the organization, the key or
  client, and the scopes asked for. With no policy, or nobody signed in, the
  answer is no and nothing is written. Another organization's key or client
  named by id is answered as not found. A rate plan the declaration does not
  have is refused at issue. A third-party principal is refused by its scopes
  first.

- **`@DVModel(history: DVHistory(keep: ...))`.** The annotation field the
  Record History section designs, read by `dartvel routes`: a generated
  model declaring it writes its change log with every change and reads it
  back with `model.history()`.

- **`DVOAuthEndpoints` serves the OAuth provider over HTTP.** Authorization
  sends a valid request to `/oauth/consent` with its parameters, shows an
  unknown client or unregistered redirect URI without redirecting, and sends
  any other error back to the client with its state; the consent answer
  needs `DVOAuthEndpoints.resolveUser` to name a signed-in person and
  answers the redirect as JSON. The token endpoint serves
  `authorization_code` with PKCE, `refresh_token` and `client_credentials`.
  Token, introspection and revocation take only a form POST, refused before
  anything in a GET or a JSON body is looked at, so a refused exchange spends
  no code; a repeated parameter or a client authenticating two ways is
  `invalid_request`. Introspection answers only a confidential client or a
  key or token whose scopes cover `DVOAuthToken.introspect`, and only for
  tokens on the request's tenant. Every token response and error is
  `no-store` with `Pragma: no-cache`; the token and revocation endpoints and
  the RFC 8414 metadata document allow any origin, the authorization
  endpoint none. `dartvel.platformApi.oauth.issuer` fixes the metadata's
  issuer, which is otherwise the request's origin and then not cacheable.
  `DVOAuthProvider.authenticateClient` is public. Errors are fixed text and
  only an error's type is logged.

- **`DVRecordTable` can hold a tenant's rows in a shared table, and a delete
  holds to the version it read.** `scope: DVRecordScope('dv_tenant', tenant)`
  matches every read, update, delete, restore check and history lookup on
  the column, fills it on a write, and refuses a write naming another value,
  so two tenants can each keep an `o1` without either reading, updating or
  deleting the other's; history and captured changes are recorded under the
  scope's tenant. A schema-qualified table name (`acme.orders`, which
  `schemaPerTenant` resolves to) is accepted, and nothing else that is not
  an identifier. `delete(id, base:)` is refused with `DVConflictError` when
  the row has moved since `base` was read, and a hard delete that matches no
  row because another writer moved it in between now throws instead of
  returning, having logged and captured a deletion that did not happen.
  `DVWriteResult.inserted` says whether a write created the record, which
  `version == 1` cannot, since an update that changed nothing stays at one.

- **`DVPlatformApi` is the authentication stage of a generated backend.**
  `authenticateRequest` resolves a `dvk_` key or `dvat_` access token in an
  `Authorization: Bearer` header on the current tenant, applies the key's
  declared rate plan, and answers `DVApiAuthentication.none` for any other
  header. Every credential refusal is the same 401; a store that fails is a
  503 that logs the error type only; a platform credential reaching a
  process with no platform API installed is a 503 rather than ignored. It
  builds `DVOrganizations`, `DVApiKeys` and, when OAuth is on,
  `DVOAuthProvider` over the application's database on first use.
  `DVApiPrincipal.current` and `DVApiPrincipal.actingAs` carry the caller in
  a zone. `DVBackendPolicy.allows` refuses a policy outside the current
  principal's scopes with `DV-APIKEY-002` before `decide` is asked.

- **`DVPlatformApiConfig` parses `dartvel.platformApi`.** Scopes as a list
  of `Resource.action` or `{actions, description}`, rate plans as
  `{maxRequests, window}` with the window written as `15m`, `1h` or `7d`,
  `requireExpiry`, and `oauth` as `true` or a map of code, access-token and
  refresh-token lifetimes. Anything else throws
  `DVPlatformApiConfigError` naming the key, including a misspelt key, an
  empty scope and a plan with no window, which is never defaulted.

- **A crash reporter no longer stops a web application from starting, and a
  crash has one fingerprint on every platform.** `dvCrashReportId` drew its
  random part below `1 << 32`, which is 0 on the web, where shifts are
  32-bit, so `nextInt(0)` threw. Installation starts a session with a report
  id, so every generated web application threw before its first frame, and
  the site build reported it only as "Captured 0 of N routes". The id now
  draws two 16-bit halves. The fingerprint hash multiplied past 2^53, where
  web integers are doubles and round, so one bug reported from a browser
  and from a phone fell into two groups. Each 32-bit multiply is now done in
  16-bit halves, exact on both; the value the VM computes is unchanged, so
  existing groups keep their names. `crash_web_numbers_test` compiles a probe
  with dart2js and runs it under node, since the VM every other test runs on
  shows neither.

- **A server process records its unhandled errors, with its role.**
  `DVServerCrashes.install` puts the crash runtime in a web, worker or cron
  process, and every report it writes carries `DVCrashContext.role` and the
  device class `server`. `DVServerCrashes.record` records an error as
  unhandled -- never sampled, written before it returns, never throwing and
  never re-entering itself -- and sends soon after, because a server does
  not restart to send; what an earlier process left is sent at install.
  `DVScheduler` takes `onFailure`, told about each task that throws as it
  happens, where a failure used to be appended to a list a served process
  never read. `DVQueues.onJobDeadLettered` is told about the last failed
  attempt of a job only, so one poison job is one report rather than
  `maxAttempts`. `DVCrashSink.repository` keeps a backend's own reports in
  its crash table without a request to itself, and
  `dvServerCrashDirectoryFor` puts records in `DARTVEL_CRASH_DIR`, else
  `.dartvel/crashes` beside the application, and never at `/`.

- **`@DVModel` declares a subject path and retention.** `subject:` takes
  `DVSubject.self`, `#field`, `DVSubject.field('column')` or
  `DVSubject.through('column', parent: 'Model')`; `retain:` takes
  `DVRetention.days(n)` or `DVRetention.indefinite`. `@DVModel.retain(years:,
  because:)` marks the field whose row a law requires to keep, and
  `@DVModel.sensitiveField(onErase: DVErase.anonymize)` says an erasure
  replaces the field and keeps the row. `DVRetention.days` takes `from`
  optionally, with `DVRetention.delete` and `DVRetention.anonymize` for
  `then:`, and `DVPrivacyModel` refuses a dated retention with no `from`
  column: no sweep could ever find such a row expired.

- **Crash reports can go to the deployment's own backend.**
  `DVCrashSink.dartvel(endpoint:)` posts a report and returns when the
  backend has it or has refused it for good (400, 413, 422), so a report the
  backend will never accept is not sent again on every launch; a 5xx, a 404
  or no answer throws and leaves the record for the next launch. On the
  backend, `DVCrashIngest` accepts a body, refuses one over `maxBytes` (413)
  or one that is not a whole report with a usable id, install id and release
  (400), treats a resend as delivered (200) without storing it twice or
  spending the install's budget, counts rather than stores past
  `perInstallPerHour` (202, with `DV-CRASH-004` once an hour), and answers
  503 when the store fails, without the failed attempt spending the budget.
  Nothing a report carries is logged or answered on any of those paths, and
  a store's error is logged by its type alone, because a database error
  quotes the values it could not insert. `DVDatabaseCrashReportRepository`
  keeps reports in `dv_crash_reports`, and `.application()` asks the
  application's `DV.Database` on each call. `dartvel.crashes` accepts
  `sink: dartvel` and `ingest: {perInstallPerHour, maxBytes}`, read as
  strictly as the rest.

- **`dartvel.crashes` is read strictly.** `DVCrashConfig.parse` reads
  `enabled`, `disabledIn` (debug, profile, release), `sink`,
  `nonFatalSampleRate` (0 to 1), `breadcrumbs`, `fullReportsPerRelease` and
  `identity.consent`, and refuses anything it cannot honour with an
  `ArgumentError` naming the key: a string where a boolean belongs, a sample
  rate of 25, a misspelt or unknown key, a sink this build does not have.
  Every setting has a default, which is why none is defaulted when it is
  wrong -- a replaced setting looks exactly like an honoured one.
  `toDeclaration` writes back what `parse` reads, so a generated runtime
  parses the rules its build checked.

- **A crash report's user id is bound to consent, and its flags are the ones
  in force.** `DVCrashIdentity` holds the account an install is signed in as
  and hands a report the id only through `DVConsent.boundIdentity`, read when
  the report is written: no grant, no id, and the report still arrives; a
  withdrawal takes effect on the next crash. A consent policy that does not
  declare the category is no identity rather than an exception inside the
  crash handler. `DVCrashContext.userId` carries it, and is absent from the
  JSON when null. `dvCrashFlagsSnapshot()` is every declared flag's answer
  when the report is written, through the new `DVFlags.peek`: no exposure is
  recorded (a crash must not count somebody into an experiment), no
  diagnostic reported and nothing pinned, and a flag settled on next launch
  answers with the value this process kept, which is what the crashing code
  was running on. A context that cannot be read is an empty snapshot, not a
  lost report.

- **Crash records have somewhere to go in a browser.** `DVFileCrashStore`
  throws on the web by design, so a web build had no store a crash handler
  could write to before the page went away. `DVKeyValueCrashStore` keeps
  records, sent notes and the per-release count in any synchronous
  `DVCrashKeyValue` -- `localStorage` in dartvel_flutter -- under a prefix,
  so it shares the page's storage without reading other keys as records,
  and the count survives a reload loop the way the file store's survives a
  restart.

- **`DV.Analytics` and `DV.Privacy` have a runtime to be.**
  `DVAnalyticsRuntime.start` builds consent and the pipeline over one
  database, keeps an install id in it across launches, reads the stored
  consent, connects Feature Flags' exposure when
  `DVAnalyticsSettings.flagExposureCategory` names a category, and installs
  the analytics privacy adapters -- and an event tracked before all that has
  finished waits for it. Judged at the call instead, an event tracked in the
  first milliseconds of a launch was checked against the declared default,
  so a category defaulting to granted recorded somebody who had withdrawn
  it. A pipeline that cannot start drops events with the reason.
  `DVPrivacyRuntime` holds the configured `DVPrivacy`, from
  `DARTVEL_PRIVACY_KEY` (hex or base64, at least 32 bytes, no default) or
  `configure`, and adds every installed adapter to it whichever is
  configured first. `DVAnalyticsSettings.fromConfig` reads `dartvel.analytics`
  (`store`, `consent`, `flags.category`, `sessionCap`) and
  `DVConsentPolicy.fromConfig` now refuses what it does not understand: an
  unknown key, a category body that is not a map, and a `required` or
  `tracking` that is not a boolean, each of which used to be read as absent
  or false. `dvLocalAnalyticsDatabase` opens a device's own SQLite file for
  consent in the per-user data directory each platform keeps
  (`dvAnalyticsDirectoryFor`, `DARTVEL_ANALYTICS_DIR` wins), and holds it in
  memory on the web, under `flutter test`, and where there is no such
  directory.

- **Sign-ups that hit a taken address count against the source.** A sign-up
  that signs somebody in cannot hide that an address was free, so
  `DVCredentialGuard.signUp` makes probing for accounts through it expensive
  instead: each `accountExists` refusal is recorded against the source that
  sent it, and a source over its `perSource` budget is refused with
  `DV-EDGE-005` before the challenge, the breach check or the provider runs.
  Nothing is counted against the address itself -- a sign-in lockout that
  only taken addresses could trip would be the same oracle again -- and a
  sign-up that creates an account counts for nothing. `DVVelocityLimiter`
  gains `checkSource` and `recordSourceFailure` for limits of that shape.

- **An LDAP username the directory does not hold costs a bind.**
  `DVLdapAuthenticator.authenticate` returned as soon as the user search came
  back empty, skipping the password bind, so a miss answered a whole round
  trip to the directory sooner than a wrong password and the difference
  listed the usernames that exist. A miss now binds the supplied password to
  a random DN under no entry, and discards the answer: RFC 4513 asks for
  invalidCredentials there, and a directory answering noSuchObject has still
  refused a sign-in rather than failed. The stand-in DN is never the typed
  username, because a failed bind against a real entry counts toward its
  lockout.

- **A sign-in no longer says whether the account exists.**
  `LocalAuthProvider.signIn` threw `AuthFailure.unknownAccount` with "No
  account exists for that e-mail address." for a missing account and
  `AuthFailure.invalidPassword` with "That password is incorrect." for a
  wrong password, which let anyone test which e-mail addresses had accounts;
  only an application that wrapped its provider in `DVCredentialGuard` was
  spared. Both are now `AuthException.invalidCredentials`
  (`AuthFailure.invalidCredentials`, "That e-mail address and password do
  not match an account."), the same refusal the guard gives. The work is the
  same too: a miss verifies the password against a dummy hash made once, by
  the provider's own hasher, when the provider is constructed. It used to
  hash the password and then verify it, which is twice the work of a wrong
  password and answered a miss measurably slower. `signUp` hashes the
  password before looking the address up, so a taken address no longer
  answers before the hash. `AuthFailure.unknownAccount` and
  `AuthFailure.invalidPassword` are deprecated rather than removed, so
  existing switches compile; no Dartvel provider throws them, and
  `DVCredentialGuard` still collapses a provider that does, behind its
  refusal floor, which remains the defence for a provider whose lookup
  itself takes time.

- **The processes of a deployment share a store, from `DATABASE_URL`.**
  `DVProcessStores.install` puts `DVQueues` on a database with
  `DVDatabaseQueueAdapter`, unless an adapter was already configured. Outside
  a preview that database is `DATABASE_URL` alone, read through `DV.Secrets`
  -- environment, then systemd credentials, then `.env` -- on a connection of
  its own: `DV.Database` is left for the application to configure, and
  `DARTVEL_DATABASE`, a preview's variable, is ignored, so a production deploy
  copied from a preview's settings does not put its jobs on the preview's
  database. In a preview it is the adapter `DVPreviewServer.start` already
  configured with the preview's own database. Without a store it installs
  nothing; a `DATABASE_URL` it cannot read throws
  `DVProcessConfigurationError` without repeating the URL.
  `scheduleLeaseFor(process)` is a `DVDatabaseScheduleLease` on that database
  for any process that ticks the schedules, and null for one that ticks none
  or was told `DARTVEL_SCHEDULE_LEASE=none`. A declared `cron` process with no
  shared store throws instead of starting: nothing in the process can tell
  whether it is the only cron process, and a second one fires every schedule
  again rather than failing.
- **`DVDatabaseScheduleLease` claims an occurrence in the application's
  database.** A row keyed to the task and the occurrence's instant in UTC in
  `dartvel_schedule_leases`, so the database's uniqueness decides between two
  processes on Postgres, MySQL or a SQLite file; an insert that fails is a
  lost claim only when the row is there afterwards, and otherwise rethrows, so
  the scheduler records it and runs nothing. Held for `hold` (two days) and
  never released.
- **`DVProcessHealth.serve` is the health endpoint of a worker or cron
  process.** `GET` and `HEAD /healthz` answer `200 {"status": "ok", "role":
  ...}`; every other path is 404 and every other method 405, so the port
  serves nothing of the application.
- **`DVProcessConfiguration` reads `DARTVEL_HEALTH_PORT`,
  `DARTVEL_SCHEDULE_LEASE` and `--max-jobs`.** `healthPort` is validated like
  `DARTVEL_PORT` and refused for a web process, which answers on its own
  port. `scheduleLeaseWaived` takes only `none`, and is refused for a process
  that ticks nothing. `maxJobs` is a worker's `--max-jobs`, at least 1, and is
  refused for any other role.
- **`DVQueueWorker.run` returns how many jobs completed and takes `maxJobs`,**
  returning once that many completed or a pass completed none.
- `DVDatabase.configuredAdapter` is the adapter `configure` was given, or
  null, without resolving a tenant's database or throwing.
  `DVTestHarness.unconfigureQueues` returns `DVQueues` to a process that
  configured nothing.
- **Two workers on one database queue no longer run a job twice.**
  `DVDatabaseQueueAdapter.reserve` read the next queued row and then marked
  it by id, so two workers polling one table both read the row before either
  marked it and both ran the job. It now claims the row with an `UPDATE` that
  only matches while the row is still queued and counts the claim only when
  it changed a row; a worker that loses a row reads the next one rather than
  reporting an empty queue.
- **`SqliteDVDatabaseAdapter.file` waits for another connection's write
  lock.** It sets `PRAGMA busy_timeout` (`busyTimeoutMilliseconds`, 5000 by
  default) before anything else, so a web process, a worker and a cron
  process sharing one file wait the milliseconds another write takes instead
  of failing at once with "database is locked".
- **`dartvel.infra` provisions several backend instances, workers and a cron
  unit.** `DVInfraBackendCapabilities` now defaults every flag to true,
  because the generated backend reads `DARTVEL_PORT` and `DARTVEL_ROLE`; a
  flag set false still refuses the declaration, for a backend generated
  before. Backend units bind `dartvel.server.port`, `+1`, `+2`... through
  `DARTVEL_PORT`. With `cron: { enabled: true }` every backend unit is
  `DARTVEL_ROLE=web` and `<app>-cron.service` is `DARTVEL_ROLE=cron`; with
  `enabled: false` every backend unit is `web`, no unit ticks the schedules
  and a note says so (this was refused); with cron unstated the first
  backend unit keeps no role and ticks and the rest are `web`. Worker units
  are `DARTVEL_ROLE=worker` with `DARTVEL_QUEUE`. A unit that used to say
  `DARTVEL_ROLE=backend`, which the backend refuses as unknown, no longer
  does. The Caddyfile balances every instance in one `reverse_proxy` with
  `lb_policy round_robin`, `lb_try_duration 5s` and `fail_duration 30s`, so
  a stopped instance leaves the rotation. `logs.ship` and the container and
  onprem adapters are still refused.
- **A backend process is told its role and port, and refuses what it cannot
  honour.** `DVProcessConfiguration.resolve` reads `DARTVEL_ROLE` (or
  `--role`) as `web`, `worker` or `cron`, `DARTVEL_PORT`, and a worker's
  `DARTVEL_QUEUE` (a comma-separated list, `default` when unset). A port that
  is not a whole number from 1 to 65535 -- empty, signed, padded, hex, out of
  range -- throws `DVProcessConfigurationError` instead of falling back to
  the generated port, and so does an unknown role, a `--role` that disagrees
  with the variable, or a queue named for a process that works none.
  `ticksSchedules` is true for `cron` and for a process given no role, which
  is the whole deployment; a process declared `web` leaves them to the cron
  process.
- **`DVQueueWorker` is the loop a worker process runs.** It works each named
  queue in turns of `batch` jobs, waits `idle` when a pass found nothing, and
  stops when `until` completes. It refuses to start on the process-local
  default queue, which no other process can dispatch to, and with no job
  handler registered, which would dead-letter everything it reserved.
  `DVQueues.adapterConfigured` and `DVQueues.hasHandlers` are new.
- **A schedule can fire once across several processes.** `DVScheduler` takes
  a `lease`, claimed for each occurrence before it runs; `DVCacheScheduleLease`
  claims it with `writeIfAbsent` on any `DVAtomicCacheAdapter` (Redis,
  Memcached), keyed to the occurrence's instant in UTC so timers that land
  seconds apart claim one key. An occurrence another process claimed is
  skipped; a store that cannot be reached runs nothing and records the
  failure rather than running unguarded.

- **What an alert writes reads its value the way Studio shows it.** A firing
  rule's summary -- the first line of its incident, the notification body,
  the pager summary and `DV-ALERT-001` -- printed the raw reading, so an
  incident read "errorBudgetBurn catalog-search is 6.703703703703697, above 6".
  `DVSignalRef.format(value)` is new and writes a burn rate as `6.7×`, a
  latency in milliseconds to a tenth, a crash rate or fleet health as a
  percentage, and a count or metric with at most two decimals, never rounding
  a real value to `0`. The summary uses it for the reading and the threshold
  alike, so a latency threshold keeps its fraction of a millisecond. Only the
  text changed; readings keep their numbers.

- **A service level whose window saw no requests has no budget reading, not
  a full one.** `DVServiceLevels.status` reported `budgetConsumed: 0` when
  samples were read and no request arrived between them, so a service that
  stopped answering showed its whole budget left. It is now null, like
  `errorRate` and `burnRate` already were, and `hasData` is false.
  `DVServiceLevelStatus.requests` is new: the requests the window saw, 0 for
  this case and null with fewer than two samples. `DVErrorBudgetDecision`
  gains `unmeasured`, the levels whose budget could not be read; `hold` is
  unchanged and still holds only on an exhausted budget.
  `DVErrorBudgetReleaseGate` already held a rollout on an unread budget and
  now holds on this one too, saying the level saw no requests rather than
  that it has no samples (`evidence['noTraffic']`).

- **An incident an alert opened is never published under the alert's name.**
  An alert titles its incident after its rule (`Alert catalog-search-burn`)
  and a crash spike after its release, and `DVStatusSnapshot.build` published
  that title the moment anyone posted a public update without renaming the
  incident first. `DVIncident.titleSource` (`alert`, `crash` or `human`, kept
  through storage) records who wrote the title, and `DVIncident.publicTitle`
  is what the snapshot and `DVStatusSubscribers.announce` now use: the title
  as given when a person wrote it, otherwise `Issue affecting <components>`,
  or `Service issue` when none are named. The public update is still
  published; holding it back until a rename would leave the page reading as
  operational during a declared incident. `openIncident` attributes the title
  to its `source`, and `update(title:)` to the update's. An incident stored
  before this change is read as titled by whatever opened it, so an alert
  incident a person renamed before upgrading shows the neutral title until it
  is renamed again.

- **On Android and iOS the application key is in the keyring or it is
  refused; it is never kept in a file.** `DVAppKeyStores.choose` used to hand
  both platforms `DVFileAppKeyStore` under the home directory, which no
  platform key store protects. iOS now gets the Keychain, and Android gets
  the Android Keystore store passed as the new `androidKeystore:` factory
  (`dvAppKeyStoreFor` in dartvel_flutter supplies it). Without one, the store
  is `DVUnavailableAppKeyStore`, and every call on it refuses. Both are
  wrapped in `DVMigratingAppKeyStore`, which moves a key an earlier version
  left at the old file path into the keyring the first time it reads. The
  file is removed only after the keyring copy reads back equal. A keyring
  that refuses, drops or alters the write leaves the file in place and
  throws, and writes go to the keyring alone. A keyring that cannot answer
  throws the new typed `DVAppKeyStoreUnavailable` (store, reason, platform
  status) rather than falling back. `DVAppKeyStores.platform` takes
  `platform:` and `androidKeystore:`, and asks for a Secret Service only on
  Linux. `DVAppKeyStores.legacyFilePath` names the old path.
  `DVDescribedAppKeyStore` lets a store defined elsewhere say where it keeps
  the key.

- **The Keychain store works on iOS, keeps its item on this device, and
  refuses with a reason.** `DVKeychainAppKeyStore` is available on iOS as
  well as macOS. Its item is written
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and not synchronizable,
  so it never syncs to iCloud Keychain or restores onto another device.
  Replacing a key updates the item in place: the old delete-then-add could
  lose the key when the add was refused. A failing `OSStatus` is a
  `DVAppKeyStoreUnavailable` from `dvKeychainRefusal`, which names a device
  not unlocked since boot (`errSecInteractionNotAllowed`), a missing
  entitlement, and an absent keychain. `debugItemAttributes()` reads back the
  item's accessibility class and sync flag.

- **An alert's state says who it reached, who it missed and whether it is
  resolving; an incident entry says who wrote it.** `DVAlertState` gains
  `deliveredTo`, `missed` (each unreached user, pager or unresolvable team
  with the reason from the latest attempt), `resolvingSince` and
  `lastNotifiedAt`, all read-only; `DVAlerting.pendingResolves(rule)` names
  the pagers still owed a resolve. `DVIncidentEntry.actor` is kept through
  storage and set by `update(actor:)` and `resolve(actor:)`; the public
  snapshot never carries it.

- **Consent to keep world anchors comes from the application's consent
  records.** `DVConsentSpatialConsent(consent, category:, anchors:)` answers
  `DVSpatialConsent` from `DVConsent`: keeping a world anchor is agreed to
  while the declared category is granted under the policy version in force,
  so a grant recorded under an older version does not count, and sharing an
  anchor is never agreed to here. A category that is required or granted by
  default is refused at construction, since either is a grant nobody gave.
  Its `anchors` store is the one to hand the runtime: a write runs only while
  the agreement holds (`DVSpatialAnchorNotStored` otherwise), and a token read
  after the agreement lapsed is deleted rather than returned. A withdrawal --
  including one `DVConsent` could not record -- deletes every kept token, not
  only the ones an open scene names; `enforce()`, called after `load()`,
  deletes tokens kept under an agreement that lapsed while nothing was
  listening. `privacyAdapter()` is the Data Compliance adapter `xr:anchors`:
  an erasure of the install, or of a user its consent records name, deletes
  the tokens, including when Product Analytics' consent adapter has already
  replaced those ids with the pseudonym; an export lists the anchor ids and
  never a token.

- **A world anchor token that was not stored is not marked stored.** A
  session wrote the token the OS handed back and marked the anchor persisted
  before the write had succeeded, and the session's queue swallowed the
  failure: `isPersisted` said true, nothing was on disk, and the mark stopped
  every later attempt. A failed write now leaves the anchor unpersisted and
  logs an error naming the anchor and, for a `DVSpatialAnchorNotStored`, the
  store's reason -- never the token. Consent is asked again once the OS hands
  the token over, so a withdrawal made while the OS was persisting stops that
  token too. `DVSpatialAnchorStore` gains `ids()`, so a withdrawal or an
  erasure can reach tokens no open scene names; an implementation outside
  Dartvel has to add it.

- **XR: the platform-independent runtime for presenting a scene in space.**
  `DVSpatialCapability` (with `headset()` and `glasses()`) reads a
  capability report strictly: a field not reported is false, and a member
  this version does not know is dropped. `DVSpatialConvention.poseToWorld`
  converts a device pose into the scene's world by change of basis through
  the same matrix a document in that convention gets, and refuses a
  non-unit orientation. Scene nodes carry a typed `DVAnchor` (plane, image,
  hand, world) that round-trips in the document; the graph places an
  anchored node at a rigid frame, hides it, or leaves it at the origin, and
  refuses a mirrored frame. `DVXRDevice` is the adapter contract, one method
  per binding the specification names, with `DVXRFakeDevice` as a strict
  headless device. `DVXRRuntime.present` opens a volume or immersive space or
  says why not (`DV-WINDOW-014`/`015`, `DV-XR-006`, `DV-WINDOW-004`), keeps
  immersive spaces exclusive, and a `DVSpatialSession` asks for the camera
  before passthrough, falls back to a full space lit by the studio with
  `DV-XR-001`, closes the space and the session when the application leaves
  the screen, the camera permission is revoked, the event stream breaks or
  the session ends, persists a world anchor only with consent and only as the
  OS token (`DV-XR-003` when it does not re-localize), delivers hand and
  controller rays in world space and gaze only as a selected node, applies
  the comfort policy (`DV-XR-005`) and reports a sustained frame-rate drop
  once (`DV-XR-007`). No pose, anchor position or light probe reaches a
  report. Presented flat, a scene with anchors or the passthrough environment
  still renders and says so once (`DV-XR-002`, `DV-XR-001`). No native
  binding exists yet on any target.

- **A flag resolution names the rule that decided it, and a debug override
  can reach the whole process.** `DVFlagResolution.rule` is the index of the
  rule that served the value or held the default (`DV-FLAGS-005`/`006`), null
  for a default or an override. `DVFlags.setDebugOverride(flag, value)` and
  `clearDebugOverride` put an override in force for every read in a debug
  build, under any `withOverrides` zone, notify `DVFlags.changes`, refuse a
  value the flag cannot read, and do nothing in a release build.
  `DVFlags.overridesInForce` and `overridesAllowed` are what `resolve` hands
  `evaluate`, so a tool evaluating another context answers as the app does.

- **A preview process starts as a preview or not at all.**
  `DVPreviewServer.start(environment)` returns null and installs nothing
  outside `DARTVEL_ENVIRONMENT=preview`. In a preview it switches capture on
  first, then refuses to start (`DVPreviewStartupException`) when the preview
  settings cannot be read, when `DARTVEL_QUEUE_NAMESPACE` is not
  `preview-<name>`, when `DARTVEL_DATABASE` is missing, does not carry the
  preview's digest or equals `DARTVEL_PRODUCTION_DATABASE`, when
  `DATABASE_URL` cannot be read, or when a members preview has no membership
  check. Only after every check passes are the queues namespaced and
  `DV.Database` configured from `DATABASE_URL` aimed at the preview's own
  database; `DV.Database.configure` then refuses a server adapter naming any
  other database. `wrap(handler)` puts a handler behind the preview's access
  gate. Capture no longer waits for a startup call either: a process whose
  environment says preview captures mail and notifications, and runs no
  undeclared schedule, from its first send, including a job worker that never
  starts a server. Preview deployments now also write
  `DARTVEL_PRODUCTION_DATABASE`, on create and on redeploy.

- **`DVDatabaseConnection` resolves a database from the environment.**
  `DATABASE_URL` (postgres, mysql, sqlite, with `sslmode`) gives the server
  and credentials and `DARTVEL_DATABASE` names the database on it, so one
  preview secret with no database in it serves every branch.
  `DVDatabaseConnection.parse` refuses a server URL that names no database,
  `open()` returns the matching adapter, and printing a connection never
  prints its password.

- **Queues live under `DARTVEL_QUEUE_NAMESPACE`.** `DVQueues` dispatches,
  works, lists and flushes `<namespace>.<queue>` when `useNamespace` sets a
  namespace or, in a process whose environment says preview,
  `DARTVEL_QUEUE_NAMESPACE` names one; outside a preview the variable is
  ignored. A preview therefore never reserves a
  production job and production never reserves a preview's. A process with no
  namespace cannot name a queue under a `preview-` namespace, and a process in
  a preview with no namespace uses no queue at all. Applied in `DVQueues`
  rather than in each adapter, so every adapter gets it. `retry` and
  `discard` still take a job id as given.

- **3D Scenes: the platform-independent runtime.** `DV3DSceneDocument`
  states its units, up axis and handedness, keeps node ids, child order and
  keys a newer version wrote, encodes canonically, and refuses a duplicate id,
  an undeclared asset or a non-finite or zero-scale transform at decode.
  `DVSceneGraph` converts that basis into right-handed Y-up metres and picks
  against each node's true local shape. `DVSceneAssetPolicy` refuses a stored
  key under another tenant, an unlisted host or an undigested asset before any
  request; `DVSceneAssetLoader` verifies the digest and reads models with
  `DVGltf`, which counts triangles and bounds through the node hierarchy
  without decoding geometry. `DVSceneRuntime` drives a `DVSceneRenderer`
  adapter -- one upload per asset, every resource released once, the previous
  scene kept on screen while an update loads, and `DV-3D-001` reported once
  per boot per cause -- and `DV.Test.fake3D()` substitutes the headless
  `DVSceneRecordingRenderer`. No renderer is configured by default: until a
  Flutter GPU adapter exists, every scene presents its poster.

- **A media player and capture runtime that report what the device did.**
  `DVMediaController` is the platform-independent player behind
  `DVBox.video`/`DVBox.audio`: `state`, `position`, `duration`, `buffered` and
  `error` are read-only `DVMediaSignal`s moved only by backend reports. Play is
  not `playing` until the backend says so; a backend that says playing while
  the position stops advancing is reported `stalled`; a position measured
  before a seek completed never moves the scrubber back. Protected content
  with no `DVDrmAdapter` for its scheme is refused before the backend sees it
  (`DV-MEDIA-102`); an adaptive stream on a backend without streaming falls
  back to the source's progressive rendition (`DV-MEDIA-101`) or is refused.
  Background audio requested without the capability declared warns
  (`DV-MEDIA-103`) and pauses with the application. Audio focus
  (`DVAudioFocus`) is taken on play and given back on pause, completion,
  failure, platform loss and dispose.
  `DVMediaCapture` records audio and video into a `DVFile`: the capability
  report is checked before permission is asked, a refusal is
  `DVCapturePermissionRefused` (`DV-MEDIA-104`), `capturing` follows the
  device's confirmations, and backgrounding, a revoked permission or a lost
  device end the session as `DVCaptureInterrupted` with the partial file.
  Recordings are created 0600 in a 0700 directory before the device writes.
  Backends, focus, DRM, permissions and timers are interfaces with fakes.

- **`@DVModel.model3dField(poster:, maxSizeMb:, maxTriangles:)`.** A model
  field that holds a `DVSceneAsset`. `DVModel3DFieldPolicy.validate` refuses
  an upload that is over the size (before parsing it), is not a glTF model, or
  draws more triangles than the budget, with every reason;
  `DVModel3DFieldPolicy.accept` turns a valid upload into the field value,
  pinned to its bytes by SHA-256 and under the tenant's storage key.

- **Scene documents are content.** `DV3DSceneContent` runs scene documents
  through the content workflow as the `scene` kind, and only a published
  version reaches `DV3DSceneStore`; a withdrawal removes it. A
  `DV3DSceneBundle` carries published scenes and their approvals to installed
  applications, decodes every scene before anything is applied, and refuses a
  scene shipped twice or shipped and removed at once; `DV3DSceneBundleInstaller`
  applies a version once and rolls back by forgetting and re-shipping the
  previous bundle. A document's keys from a newer version now encode in sorted
  order, so a scene read back from the workflow encodes to the same bytes.

- **Schema Evolution's tracker and Backend Release Management agree on where
  a migration stands and whether it may contract.** Verification is now its
  own recorded state: `DVSchemaEvolution.verify` records that every chunk
  agrees for the whole window, a discrepancy recorded afterwards takes it
  away, and the tracker reports `DVReleaseMigrationPhase.verified` while it
  stands. Reads then move with `switchReads`, in a release of their own,
  while both shapes are still written (`readSwitched`). The contract, which
  stops writing the old shape, now reports `contracted` rather than
  `readSwitched`. Before, a rollback planned against the tracker could restore
  a release that reads a column nobody writes any more. The contract and the
  later drop are decided by `DVContractDecision`, the same decision
  `DVContractStepGate` makes, so a contract the gate holds because the release
  being replaced still reads the old shape is refused by the tracker too.
  Before, the tracker contracted straight from verify. A saved state that has
  no verification recorded reads as not verified.

- **A Platform Memory arena can be lent to a worker.** `DVPlatformMemory` is
  a `DVWorkerLendable`, so `DV.Workers.run(task, input: slice.addresses,
  lend: [arena])` hands a worker an arena's addresses and the worker writes
  in place, which the caller reads through the slice without a copy. While
  lent, `reset()`, `dispose()` and lending it again throw. An address is not
  a Dart view, and the native backing frees a segment when its last view is
  collected, so an arena disposed under a worker was a use-after-free, and
  one reset under it handed the worker's bytes out again. The pool keeps the
  arena reachable until it gives it back: with the worker's answer, or, for a
  cancelled or timed-out run, only once the isolate has exited. A disposed
  arena cannot be lent.

- **Expand/contract runs as phases with gates, and its backfill is a
  verified, throttled job.** `DVSchemaEvolution` walks expand, dual-write,
  backfill, verify and contract, and refuses a release that already ran a
  phase, because each phase is its own deploy. The read switch needs every
  chunk backfilled, every chunk verified, and no dual-write discrepancy inside
  the whole verification window (`DV-SCHEMA-004`, `DV-SCHEMA-007`); the
  contract, and the later drop of the old column, are refused while a client
  on a protocol older than the expand's still calls (`DV-SCHEMA-005`), and a
  missing client histogram is refused rather than read as none.
  `DVSchemaEvolutionStore` keeps the state in the database, and its
  `phaseSource` answers Backend Release Management's `DVMigrationPhaseSource`
  through `DVSchemaEvolution.releasePhase`. `DVBackfill` copies a column in
  chunks by key and records each chunk after writing it, so a restart resumes
  after the last one and a pause holds across restarts; `verify` hashes each
  recorded chunk on both shapes -- a swapped pair of values is caught where a
  count agrees -- names a mismatched chunk (`DV-SCHEMA-004`) and reports a
  chunk that verified and then diverged as a dual-write discrepancy
  (`DV-SCHEMA-007`). `DVBackfillThrottle` starts at the
  `dartvel.database.tier` rate (500, 2,000 or 10,000 rows/s), halves when
  replica lag or write latency crosses `dartvel.database.backfill`'s budget,
  steps back up by a tenth of the starting rate while under it, and reports
  staying below its floor past its patience once (`DV-SCHEMA-003`).
  `DVSchemaBackfills` runs a backfill as slices on `DVQueues`, each queueing
  the next, and a paused one stops queueing itself.

- **Platform memory: a budget reserved once and handed out arena-style.**
  `DVPlatformMemory` reserves its budget up front in power-of-two segments
  (native heap through FFI on native targets, typed data on web) and hands
  out `DVInt`/`DVDouble`/`DVBool` scalars and `MemorySlice` lists over
  int8..int64, float32 and float64 storage. A list larger than a segment is
  chunked with shift-and-mask indexing and never split when it fits one.
  `reset()` makes the arena reusable and invalidates every handle given out
  before it, including a `transformAsync` that was waiting to resume;
  `dispose()` releases it. `securedBytes` reports what was granted, and less
  than asked is recorded as `DV-MEMORY-001`; an exhausted arena throws
  `DV-MEMORY-002` without consuming anything, `int64` on web-js throws
  `DV-MEMORY-003`, and `touchPages` on a mobile or embedded target is refused
  as `DV-MEMORY-004`. `DVMemory.allocate` applies `dartvel.memory` defaults,
  per-target ceilings and device-profile overrides, and registers each arena
  for aggregate usage. The four codes are registered, and the registry check
  now reads codes the specification lists in a text block as well as tables.

- **A sweep or erasure no longer removes a row rewritten after it was read.**
  `DVPrivacy.sweepRetention` read the expired rows, then deleted or
  anonymized each by key alone, so a session renewed between the read and
  the write was removed anyway, and its history and captured changes with it.
  An erasure had the same gap: a row moved to another customer after the walk
  was deleted as the subject's, and a kept row anonymized from a stale read
  took the version the rewrite already held, so the writer that raced it
  could save the erased value back without a conflict. Each write now applies
  only at the version read (a sweep also requires the retention timestamp it
  read), and history purge and capture follow only a write that applied. A
  sweep leaves a contended row for the next run, reports it in the new
  `DVRetentionSweep.skipped`, and counts it in `remaining` while it is still
  expired. An erasure, `replayErasures` and `DVOfflineStorePrivacyAdapter`
  read the row again and erase it at its new version while it still belongs
  to the subject; a row that no longer does is left alone and kept out of
  what record adapters are handed.

- **`DV.Workers` runs on web workers in a browser.** A web build now picks a
  web worker per task wherever the page has `Worker`, and runs inline only
  where it does not. The page sends the task's registered name and its input
  to a worker script -- `DVWorkerTasks.script`, compiled from an entry that
  registers the same tasks and calls `dvWebWorkerMain` from
  `package:dartvel_core/web_worker.dart` -- and a task that is not registered
  or an input that cannot be cloned fails by name before a worker is started.
  Cancelling or timing out terminates the worker, and a script that fails to
  load, or an error nothing in the worker caught, is a crash rather than a
  page waiting forever. The pool is sized from `navigator.hardwareConcurrency`.
  Exercised end to end by compiling a page and a worker with dart2js and
  running them under Node with a `Worker` built on `worker_threads`; that
  proves the runner through dart2js's real interop and says nothing about any
  one browser. It found that reading a task through the pool's erased types
  was a covariance TypeError in dart2js on the first run.

- **What a web worker and its page say to each other.** A web worker is a
  separately loaded script that cannot be handed a Dart function, so a task
  crosses by a name registered on both sides with `DVWorkerTasks.register`,
  and one name for two functions is refused. `dvWorkerUnportable` names the
  first value structured clone would refuse and where it sits -- a class
  instance, a function, a map keyed by something other than a string --
  where a browser throws a `DataCloneError` naming nothing.
  `dvWorkerHandle` is the worker's side of a request: progress, then a value
  or a failure, always a final answer, including for a task the worker does
  not have, a result that cannot be cloned back, and a request it cannot
  read. `dvWebWorkerCapability` reports a web worker as supported with
  limitations and shared memory only on a cross-origin-isolated page, and
  `DV-WORKER-004` is logged once when bytes were copied because it is not.

- **Native memory lent to a worker by address.** `DVWorkerBuffer.allocate`
  gives zero-filled memory outside the Dart heap, and
  `DV.Workers.run(task, input: buffer.lease, lend: [buffer])` hands a worker
  its address: the worker, or native code it calls, reads and writes it in
  place, and the caller sees the writes without a byte copied either way. A
  buffer is passed, not shared -- while it is lent the caller cannot read it,
  free it or lend it to a second run, which throws in the caller's frame. It
  comes back with the worker's answer, but a run that was cancelled or timed
  out keeps it until its isolate has actually exited, because that isolate
  may still be writing and memory freed under it would crash somewhere else,
  later. A blocking native call made on a worker leaves the caller its event
  loop. Web builds get the same names, which refuse, and
  `capability.zeroCopyNative` is false there.

- **`DV.Workers`: declared offloadable work on a bounded pool.**
  `DVWorkers.run(task, input: ..., onProgress:, cancellation:, timeout:)`
  runs a top-level or static `DVWorkerTask` on its own isolate on the VM, and
  its future always completes exactly once -- with the value, with what the
  task threw, cancelled, timed out, or as a crash when the worker ended
  without answering, including a worker that exited, died of an uncaught
  asynchronous error, or awaited something nothing could complete. Input,
  result or captured state that cannot cross the boundary fails by name
  (`DV-WORKER-002` for a capture) and frees its slot. Cancelling or timing
  out kills the isolate rather than forgetting it, and the slot is held until
  the isolate has actually exited, so the bound counts threads that are
  really running. The pool is sized from a `DVWorkerProfile` -- one core left
  for the UI, never more than eight -- rather than from a number the
  application sets, and saturation is logged once per episode as
  `DV-WORKER-005`. `DVCancellation.until(signal, ended)` binds a run to a
  lifecycle so no progress or result reaches an owner that has gone. Where
  there are no threads the pool runs work inline and says so once through
  `DV.log` as `DV-WORKER-001`; `DVWorkers.capability` reports which mechanism
  carries the work and whether memory is shared or copied.

- **A retention sweep's deletes reach the capture log and the warehouse.**
  `DVPrivacy.sweepRetention` removed and anonymized expired rows with SQL of
  its own beside `DVRecordTable`, so no change was captured: a warehouse fed
  by `DVCaptureConsumer` kept exactly the rows the source removed for
  retention, an anonymizing sweep left the personal values standing there,
  and the capture log kept every earlier value of both. The same was true of
  an erasure with no `DVCapturePrivacyAdapter` registered, of
  `replayErasures` after a restore, and of `DVOfflineStorePrivacyAdapter`
  over a captured table. Each removal now purges the log's values for the
  row and captures an erased delete, or the anonymized row, through the new
  `DVCapture.recordErasure` -- once per row, since the walk leaves a record
  to the capture adapter when one is registered -- while sweeps stay batched
  and resumable and `planRetention` still captures nothing. Separately, an
  erasure captured the delete of a row already gone at version 0, which
  `DVWarehouseSink` rightly ignores as older than the row it holds, so an
  erasure only reached the sinks the adapter erased directly; the delete is
  now one version past the newest the log or the removed row knows of.

- **A transaction belongs to the flow that opened it.** The active
  transaction was a static field, so two requests served by one isolate found
  each other's: a `DV.transaction` in one joined the other's open transaction,
  one request's failure ran the other's compensations, and `afterCommit` work
  fired on the wrong commit or not at all. The transaction now lives in the
  zone its body runs in, so nesting within one flow still joins -- through
  every await, timer and microtask the body schedules -- and an unrelated flow
  never does. `DVTransactionRunner.activeContext` is null once the transaction
  has committed or rolled back, including to work the body left unawaited, and
  `afterCommit` callbacks and compensations run outside the transaction: a
  `DV.transaction` opened from one is a new transaction rather than a join onto
  one that is over, whose callbacks were silently dropped. `isolated: true` is
  unchanged.

- **Schema changes are classified by the adapter, and planned.** A schema
  change is described (`DVAddColumn`, `DVAddIndex`, `DVAddNotNull`,
  `DVChangeColumnType`, `DVRenameColumn`, `DVDropColumn`, `DVCreateTable`,
  `DVRawSchemaChange`) and `DVDatabaseAdapter.classify(change)` answers
  `instant`, `online` or `blocking` for the server the adapter is connected
  to, version included: PostgreSQL (a default is a rewrite before 11,
  `NOT NULL` is online from 12), MySQL 8 (with the point releases that brought
  `INSTANT`), and SQLite/Turso from the library actually linked. A MariaDB or
  pre-8 MySQL server, the in-memory adapter and hand-written SQL classify
  nothing. `DVSchemaPlanner` treats an unclassifiable change as blocking
  (`DV-SCHEMA-006`), refuses a blocking type change as written and plans its
  expand/contract instead -- only when the expand itself does not block, and
  saying what the contract step will cost (`DV-SCHEMA-001`). `DVSchemaDeployGate`
  refuses a blocking change against production without an override that
  carries a reason, and returns the record to log (`DV-SCHEMA-002`).
  `DVSchemaSnapshot` carries a production server's provider, version, columns
  and row counts, so a plan rehearsed against it classifies as production
  would. `classify` is an extension over the adapter contract rather than a new
  abstract member, so adapters written elsewhere keep compiling; one that
  implements `DVSchemaClassifier` teaches the planner.

- **Alerting, service levels and status pages, as a runtime.** A
  `DVServiceLevel` samples cumulative counts from a source that already exists
  and reports burn rate over a trailing window and budget consumed scaled by
  how much of the window was observed, so ten minutes of history is ten
  minutes of the month; a restart in either count restarts both, and
  `DV-ALERT-003` is raised once per exhaustion. `DVErrorBudgetGate` reads
  exhausted levels before a deploy. `DVSignalRef` resolves metrics (missing
  when unregistered, no data when quiet), nearest-rank trace percentiles,
  crash rate from release health, a level's two-window burn, and
  application-registered queue, kiosk and quota readers. `DVAlerting` moves a
  `DVAlertRule` through pending and firing only after a positive
  `forDuration`, resolves after the signal has stayed clear (five minutes at
  least, so a hovering signal pages once), delivers through
  `DV.Notifications` to users and teams and through `DVAlertPager` adapters
  (`DVPagerDutyPager`, Events API v2) under one dedup key per episode, retries
  only the targets that missed a firing and keeps a refused resolve queued
  until the pager takes it (`DV-ALERT-001`, `002`, `006`), opens a
  `DVIncident`, and reports rules with no target or that fire on most days
  with no action taken (`DV-ALERT-005`). `DVStatusSnapshot` publishes
  component health without check detail and only public incident updates;
  `DVStatusPageClient` serves the last snapshot marked stale with the time it
  was true when the application is unreachable, errors or hangs
  (`DV-ALERT-004`); `DVStatusSubscribers` announces public updates.

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

- **Organizations, memberships and invitations, as a runtime
  (`DVOrganizations`).** A tenant stays the data boundary and an organization
  is the group of people on it: one organization per tenant, refused a second
  (`DVTenantAlreadyOrganized`), and a tenant with none is a personal tenant, on
  which resolving a membership is `DV-ORG-006` rather than a quiet "no role".
  Renaming, transferring and closing never touch the tenant, so a personal
  tenant becomes an organization by creating one on it. Roles are typed
  (`DVOrgRole`), ordered by declaration, and refuse to compare across two
  declarations; an undeclared name is `DV-ORG-001`. `DVMembership.grants`
  checks the organization as well as the rank, so an owner of one organization
  is nobody in another, and it is what an `authorization` policy calls.
  Invitations are `DVAuthTokens` magic links or passcodes: single use,
  expiring by the organization's clock as well as the token store's, never
  stored, bound to the invited address (a forwarded link is refused and spent,
  and the invitation stays pending to resend), refused for an existing member
  (`DV-ORG-002`) and for a role above the inviter's own. Seats are a query over
  memberships under a declared rule (every member, at roles, active within a
  period) and a `DVLevelLimit` for `DV.Meter`; a refused acceptance is
  `DV-METER-004`. Counting and joining run under one lock per organization, so
  five acceptances racing for two seats admit two. The last owner cannot leave
  or be demoted, including by two owners demoting each other at once
  (`DV-ORG-003`). Transfer promotes the successor before demoting the owner and
  rolls back with an enclosing `DV.transaction`; closing is restorable within a
  grace period and refuses work meanwhile (`DV-ORG-004`). Verified SSO domains
  join at their declared role, exact domain only (`DV-ORG-005`). Every
  membership change carries its actor and transaction in Record History.

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
