## Unreleased

- **A nested layout sits inside its parent's.** The generated router wrapped
  the root `_layout.dart` first and each deeper layout around it, so
  `lib/pages/docs/_layout.dart` drew around the site header instead of below
  it. The root layout is now outermost.

- **`dartvel build web-server` also compiles the backend into one file.**
  It writes `build/server`, the file `dartvel deploy`'s image runs as
  `/app/server` and `dartvel infra`'s units start as `/opt/<app>/server`,
  and which nothing produced. The build embeds dartvel_shelf's native server
  library for the host and runs `dart compile exe`, so the binary starts
  with nothing beside it. A host with no prebuilt library is told before
  anything is generated, and the web output still builds.
- **`dartvel deploy --target server` builds `web-server`.** It asked for
  `build --platform server`, which is not a platform.

- **`@DVModel(version: false)`, `@DVModel(softDelete: true)`, restore and
  revert are generated.** `version: false` writes without a version check.
  `softDelete: true` makes `destroy()` mark the row, which `find` and `all`
  then skip; `Model.withDeleted.find(id)` and `.all()` read it, and
  `Model.restore(id)` brings it back and publishes
  `DVModelChangeKind.restored`. A model with `history:` gets
  `model.revert(to: entry)`, a new change checked against the version the
  model was read at and refused when it read nothing. A value other than the
  literal `true` or `false` stops the build.

- **Breaking: a generated model built by hand no longer replaces a stored
  row.** `save()` on a model that was not read -- `const Order(id: 'o1', ...)`
  over an existing `o1` -- replaced the row at whatever version it held, the
  lost update Record History exists to refuse. It now throws
  `DVConflictError` (`DV-HISTORY-001`) and leaves the row as it was; a model
  that creates a record, or was loaded, copied or saved, is unaffected.
  Replacing without reading is written at the call:
  `save(onConflict: DVConflict.lastWriteWins)`. A model returned by the
  generated form keeps the version of the model it edits, so the admin still
  saves. GraphQL types carry `dvVersion`, and `saveX` refuses an update of a
  stored record unless it sends back the `dvVersion` it read.

- **A web build on another origin than its API stays signed in.** The
  generated runtime names its backend's origin for credentials in a browser,
  before the session client's first call. On the server,
  `dartvel.server.cors.allowCredentials` is refused with no origins, with
  `methods`, `headers` or `exposeHeaders` set to `any`, or with a plain `http`
  origin off the loopback, and a credentialed policy answers the
  `content-type` and `x-dartvel-csrf-token` headers the generated client
  sends, so a sign-in's preflight passes.

- **A deletion left scheduled when `dartvel.auth.deletionGraceDays` is removed
  is still carried out.** The generated account sweep only ran while a window
  was declared, so a person who asked for deletion under one was kept for
  ever once the project removed it. The sweep now ticks either way, and such a
  deletion is erased at the `erasesAt` the person was given -- not cancelled,
  which only the person may do by signing in, and not brought forward.

- **The generated server starts DV.Privacy's background work.** Where
  `DARTVEL_PRIVACY_KEY` is set, a web process creates the privacy walk's own
  tables and registers its erasure and retention jobs before it serves; a
  worker and a cron process now configure `DV.Privacy` over the shared
  database too, so an erasure queued by a web process runs on a worker; and
  the process that ticks the schedules sweeps retention daily and runs open
  erasures ahead of their deadline hourly, each occurrence claimed through
  the schedule lease.

- **`DV-HTTP-001` and `DV-HTTP-005` stop the build.** `dartvel routes` reads
  every `DV.Http.host('name')` and every absolute URL written as a literal
  (directly, through `Uri.parse`, or as `send`'s second argument) before it
  writes anything. A name nobody declared, or a URL no declared base URL
  covers, is `DV-HTTP-001` wherever it is; a declared host whose `auth.bearer`
  names a backend-scoped secret, used outside the backend directory, is
  `DV-HTTP-005`. Each names the file and line. A URL assembled at runtime is
  not guessed at: the running client refuses it with `DV-HTTP-001`.

- **`dartvel routes` reads `dartvel.http` and installs its hosts at startup.**
  The block was documented and read by nothing, so a project that declared
  its payment gateway in pubspec.yaml met `DV-HTTP-001` on its first
  `DV.Http.host(...)`. Generation now checks the block through the reader the
  running application uses, stops on any key or value it does not understand
  before writing a file, and emits `http.g.dart`, whose
  `configureDartvelHttp()` the client runtime and the web, worker and cron
  server roles call before any application code runs.

- **`dartvel.api.graphql` is read.** `dartvel routes` checks `maxDepth`,
  `maxCost` (`auto` or a whole number of at least 1), `introspection`
  (`development`, `never`, `authenticated`) and `persistedQueries` (`off`,
  `prefer`, `require`) before it writes anything. A key nothing reads stops
  the build, and so does a value the runtime cannot use. The generated
  `buildBackendRouter` installs the declared settings on `DVGraphQL` before
  its first route. A project that declares nothing leaves the runtime's
  settings alone. `/graphql` and `/graphql/stream` pass the whole body to
  `DVGraphQL.executeRequest` and `subscribeRequest`, so a persisted-query hash
  now reaches the manifest. Under `require` the build prints that it extracts
  no client queries yet, so only documents the application loads into
  `DVGraphQL.persistedQueries` itself are answered.

- **The GraphQL fields generated for a model ask its policy.** `posts`
  asks `Post.viewAny`, `post` asks `Post.view` on the record it found,
  `savePost` asks `Post.update` on the stored record (or `Post.create` on the
  new one when none is stored), and `deletePost` asks `Post.delete` on the
  stored record, each before it reads or writes. They sent every request
  straight to `all`, `find`, `save` and `destroy`, so a delete the admin hid
  from somebody could still be sent as a mutation. The caller is
  `DV.Auth.currentUser` unless a server authenticated the request. A model
  no policy answers refuses.

- **`Model.Admin(as:)`.** The generated admin asks the model's policy before
  it offers New, Delete or Save and again before it writes, and `as:` names
  the application's own user the policy is asked about, which a policy
  written against the generated `User` needs. Without it the session's
  `DV.Auth.currentUser` is asked, and a policy that cannot take that refuses
  rather than throwing.

- **The account pages build for the web, and the gate lands on a page.** The
  generated router also serves `DV.Auth.SignInWithEmailAndPasswordPage` at
  `dartvel.auth.pages.signIn` (default `/login`), passing it `from`, and sets
  `dvSignInRoute` to that path. The account routes shipped redirecting a
  signed-out person to `/login` in applications that had no page there, and
  `dartvel build web` refused both the site and the example: the audit read
  the not-found page each gated route landed on, and the sign-up page, and
  found no heading. An application with its own page at the sign-in path
  keeps it. `/login` is no longer a reserved path.

- **`dartvel.auth.deletionGraceDays`.** The number of days a deleted account
  waits before it is erased, during which signing in cancels the deletion.
  `account.g.dart` carries it as `dartvelAccountDeletionGrace`, and the
  generated server installs it, registers the erasure job, and sweeps due
  deletions on the schedule tick in the process that ticks the schedules
  (and in a `cron` process); a `worker` registers the job too. `dartvel
  routes` stops, naming the key, on anything but a whole number from 0 to
  29: a window of thirty days or more would put every account erasure past
  its own thirty-day deadline (DV-PRIVACY-004). Nothing declared keeps
  deletion immediate.

- **The generated backend serves `POST /auth/account/password`,** behind the
  authentication stage and CSRF-checked, and a backend function declaring
  that path stops the build.

- **The prebuilt account pages have routes.** The generated router serves
  `DV.Auth.ProfilePage`, `SecurityPage`, `SessionsPage` and `DeletePage` at
  `/account/profile`, `/account/security`, `/account/sessions` and
  `/account/delete`, each behind `DVAccountPages.requireSession`, and
  `SignUpPage` at `/sign-up` with no gate. `dartvel.auth.pages` moves a page
  (`security: /settings/security`), leaves one out (`delete: false`) or all of
  them (`pages: false`). A page the application put at the same path is the
  application's and gets no generated route. `dartvel routes` stops before
  writing anything, naming the key, on a misspelt page, a value that is not a
  path or `false`, a path with a parameter or a query, two pages at one path,
  and `/login`, `/second-factor` or `/oauth/consent` -- a page behind sign-in
  at the sign-in path would redirect to itself. `router.g.dart` lists
  `dartvelAccountPages`, a `DVAccountPageEntry` per page at its configured
  path, and the gated routes are in `dartvelGuardedRoutes`, so the sitemap
  leaves them out.

- **The generated server wires the account endpoints to mail and erasure.**
  `dartvel routes` writes `account.g.dart` -- `dartvelEmailVerificationMail`,
  the address-change mail with the project's `seo.siteName` (else its package
  name) in the subject and the code only in the body -- and the generated
  server installs it after configuring `DV.Privacy`. An application that
  passes only its provider to `DVAuthEndpoints.install` gets an address change
  that mails the new address and a deletion that erases, or a 503 naming what
  is missing where the process has no mail or no `DARTVEL_PRIVACY_KEY`.

- **A project with a mounted module builds a second time.** `dartvel build`
  checks each module's code against its grant before generating, and that
  check reads the module's generated client too. Once the client existed,
  two lines Dartvel writes into every one were read as the module's own:
  `DV.registerRuntime(baseUrl: () => DartvelRuntime.baseUrl)` as egress to a
  URL built at runtime, and the scheduler in `schedules.g.dart` as cron. So
  the first build passed and every build after `dartvel routes` exited 78
  with DV-MODULE-001, for a module that makes no outbound call and schedules
  nothing. The runtime's own backend registration is no longer egress. The
  same value passed to a declared host, or a registration pointed anywhere
  else, is still unresolved. With no backend schedule, `schedules.g.dart` now
  constructs no scheduler.
- **The generated backend's body limits are enforced by the server, before
  the body is read.** `dartvel.server.maxBodyBytes` sets the largest body the
  native server reads for a route that declares no limit: 1 MiB by default.
  `dartvel routes` refuses a value that is not a positive whole number of
  bytes, including a quoted `"65536"` or `16MB`. The generated `startBackend`
  passes it to `serve()`, with every route's own limit from
  `router.bodyLimits`, and takes a `maxBodyBytes` override. A route declaring
  `uploadLimit` registers `DVBodyLimits.upload` with the server, so an upload
  reads past the server limit, and no other route does. `bodyLimit`
  registers `DVBodyLimits.body`. A route declaring both registers the larger,
  and the Dart check still picks by content type. The crash endpoint
  registers `dartvel.crashes.ingest.maxBytes`, so an ingest limit above the
  server's is not refused first. Raw handlers declaring either key now get
  it too, where before nothing enforced it. Before this, every one of these
  limits was checked in Dart after the native side had already buffered the
  whole body, with no limit. A route's limit is read from `DVBodyLimits` once,
  when `startBackend` builds the router, and the server and the route check
  use that same number. Set `DVBodyLimits` before starting the backend.
- **The generated crash endpoint limits each client source.** With
  `sink: dartvel`, the endpoint passes `DVClientAddress.sourceOf(req)` to
  `DVCrashIngest.accept`, and `dartvel.crashes.ingest.perSourcePerHour` to
  the ingest. That setting defaults to ten installs at their full
  `perInstallPerHour`, and `dartvel routes` refuses it below 1 or below the
  per-install budget. A client writing a new install id per report is
  refused with 429 once its address has stored that many this hour, instead
  of being stored without limit.
- **`dartvel.server.ipv6SourcePrefix` sets how much of an IPv6 address is one
  source.** It defaults to 64, and `dartvel routes` checks it with the
  runtime's own rule: a whole number from 32 to 128, never quoted. Anything
  else stops the build naming the key, because a prefix of 0 would count
  every IPv6 client as one. The generated `startBackend` passes it to
  `DVClientAddress.fromConfiguration`, so every per-source limit counts a
  client's network rather than the address it chose.
- **`dartvel.server.trustedProxies` names the proxies whose forwarded client
  address is believed.** A list of ranges (`127.0.0.1/32`, `10.0.0.0/8`, or a
  bare address), read by `dartvel routes` with the runtime's own parser, so a
  range the server could not read -- or would read wider, like `10.0.0.1/8` --
  stops the build naming the key. `dartvel.server.forwardedHeader` is
  `x-forwarded-for` (the default) or `forwarded`, and nothing else. The
  generated `startBackend` installs `DVClientAddress` from both, plus any
  ranges in `DARTVEL_TRUSTED_PROXIES`, before the router is built, so every
  per-source limit counts the connection's peer unless that peer is a listed
  proxy. A project that names none trusts none.
- **The generated runtime sends `x-dartvel-device`.** Its `DVSessionClient`
  is built with `device: dvSessionDeviceLabel()`, so a session from a native
  client is recorded with its platform and the sessions list can tell devices
  apart.
- **The generated backend serves account changes.** `GET /auth/account`,
  `POST /auth/account/email`, `/auth/account/email/verify` and
  `/auth/account/delete`, behind the authentication stage and CSRF-checked,
  handled by `DVAuthEndpoints`; a function declaring one of these paths stops
  the build.
- **`mfa:` is read by the generator.** A backend function declaring
  `@DVBackendFunction(mfa: ...)` answers a session without the second factor
  with the step-up refusal before its policy is asked or the function runs,
  raw handlers included. A page declaring `@DVPage(mfa: ...)` gets a redirect
  that sends the session to `/second-factor` -- served by
  `DV.Auth.SecondFactorPage` whenever a page declares one -- and back once a
  factor is presented. Generated calls go through `DVStepUp.send`, and the
  runtime installs `DVAuth.installStepUp()`, so a refused call presents the
  challenge and resumes. An `mfa:` value the generator cannot read (anything
  but `DVMfa.required`, `DVMfa.none` or `DVMfa.recent(Duration(...))` with
  literal fields) stops the build naming the file rather than generating the
  route unguarded.
- **A backend function's annotation may span lines.** The declaration under a
  wrapped `@DVBackendFunction(...)` was not found, so its route called a name
  that did not exist; the argument list is now stepped over by counting
  parentheses.
- **The generated backend serves second-factor enrollment.** `GET
  /auth/factors` and `POST /auth/factors/totp`, `/auth/factors/totp/confirm`,
  `/auth/factors/recovery-codes` and `/auth/factors/remove`, behind the
  authentication stage so a session still waiting for its own second factor
  changes nothing, each CSRF-checked and handled by `DVAuthEndpoints`. A
  function declaring one of these paths stops the build, as the sign-in paths
  do.
- **The generated runtime signs `DV.Auth` in through the application's
  backend.** It installs a `DVSessionClient` over `DartvelRuntime.api`, makes
  it `DV.Auth`'s default provider, hands its token to
  `DartvelClient.setAuthToken`, keeps a native token sealed under the key
  `dartvel key` manages, and checks a stored session with the server at launch.
  In a browser no token is kept.
- **The generated backend serves the application's own sign-in.** Under the
  API base path: `POST /auth/sign-up`, `/auth/sign-in`, `/auth/second-factor`
  and `/auth/sign-out` on the request's tenant, and `GET /auth/session`,
  `GET /auth/sessions`, `POST /auth/sessions/revoke` and
  `/auth/sessions/revoke-others` behind the authentication stage, each handled
  by `DVAuthEndpoints`. They are registered before any backend function, so a
  catch-all route cannot shadow them, and a function declaring one of their
  exact paths stops the build. Every POST is CSRF-checked, sign-in included.
- **A generated route answers 401 when signing in is the answer.** A route
  with a quoted `Resource.action` asks `DVBackendPolicy.checkAction`: with no
  session or key on a route whose policy needs a caller it answers 401 with
  `WWW-Authenticate: Bearer` and `no-store`, and every other refusal is still
  the 403 it was, including a key the policy cannot take and a policy that
  takes no caller and says no. The CSRF check still runs first and still
  applies to a session-authenticated state change, bearer or cookie; an API
  key or OAuth token is still exempt.
- **The generated backend authenticates the application's own sessions.**
  Every route's authentication stage -- backend functions, GraphQL, the crash
  endpoint, OpenAPI and health -- now resolves a `Bearer dvs_...` session
  token, which `DartvelClient.setAuthToken` sends, or the `__Host-dv_session`
  cookie into `DVSessionPrincipal.current` on the request's tenant, after the
  platform API's stage and whether or not `dartvel.platformApi` is declared.
  An injected `DVContext` carries it as `context.session` and `context.user`.
  A presented session that does not authenticate -- unknown, rotated away,
  revoked, expired or issued on another tenant -- is a 401 with
  `WWW-Authenticate` and `no-store` on every route, and one carried by the
  cookie clears the cookie. `startBackend` installs the stage over the
  application's database unless the application installed its own first,
  which is where it passes `resolveUser`. `/graphql` and `/graphql/stream`
  pass `authenticated` for a session as for a key. A private backend function
  taking `DVContext` now compiles: its helper copied the parameter list
  verbatim and named a type the generated file imports as `core.DVContext`.
- **The generated client registers `@DVPolicy` classes under the application's
  own answer, as the server does.** `policies.g.dart` used `register`, so
  `configureDartvelRuntime` replaced an answer the application had already
  registered for the same action and resource: the server refused
  `Order.delete` for somebody the client still showed Delete to. It now
  registers through `registerDeclared`, and the client and the server answer
  an action the same way whichever ran first.
- **GraphQL, the crash endpoint, OpenAPI and health run the authentication
  stage.** Each was registered bare -- no tenant scope and no authentication
  stage -- so a key for another tenant was refused with a 401 on a backend
  function's route and not looked at on `/graphql`, where a mutation ran with
  nothing checked, or on the crash endpoint, which stored a report under it.
  All of them now run on the request's tenant and, with
  `dartvel.platformApi` declared, judge an API key or OAuth token as every
  other route does and refuse a bad one with the same 401. `/graphql` and
  `/graphql/stream` pass `authenticated`, and a field's declared policy is
  asked with the key as the caller, so a key's scopes apply to a mutation as
  they do to the backend function it resolves through. The crash endpoint
  refuses a valid key too (403): an install does not report with one, and the
  endpoint declares no action a scope could cover. OpenAPI and health stay
  public -- a partner's tooling sending its key with every request is answered
  -- and so does `/graphql/schema`. The OAuth endpoints are unchanged: each
  authenticates its caller its own way.
- **The generated backend registers `@DVPolicy` classes before any route
  exists.** Every policy class in the application and in the modules it
  merges whose file does not reach Flutter is registered from
  `backend_policies.g.dart` at the top of `buildBackendRouter`, so a route
  declaring `@DVBackendFunction(policy: 'Order.view')` is answered by
  `OrderPolicy.view` with no hand registration, and a module's routes by the
  module's policies. Before, the server registered none: with no
  `DVBackendPolicy.decide` every such route refused, and with a `decide`
  that said yes a route whose policy nobody wrote was opened. `dartvel
  routes` now stops on a route whose `Resource.action` no policy class the
  server can load defines, naming the file -- including one defined only by
  a class that imports the generated client, which the server cannot
  compile. A framework action such as `DVApiKeyResource.viewAny` is left to
  the application to register, and the server refuses to start when it has
  not. A policy class only the client can load is reported on every build.
  A resource parameter may be nullable (`Order? order`), which is how a
  policy answers for a route that has no order to hand it.
- **The generated router serves `/oauth/consent` when
  `dartvel.platformApi.oauth` is on.** The authorization endpoint sends a
  person there, and the route renders `DV.Auth.OAuthConsentPage` with the
  request's query, the generated backend's API base and the generated
  client's headers. Without it every authorization ended on the
  application's not-found page.
- **Generated models persist through `DVRecordTable`, so their tables can be
  erased.** Generated `save()` was a delete then an insert with no version,
  so a model's table had no `_dv_version` column: `dartvel privacy erase` and
  `DV.Privacy.erase` refused every real application, a retention sweep could
  not write at the version it read, history and capture never saw a change,
  and two people saving one record both succeeded while one lost their edit.
  `find`, `all`, `save` and `destroy` now go through a record table carrying
  the tenant scope, the table the tenant resolves to, the sensitive fields and
  the module's database. A model loaded from the database, or copied from one
  with `copyWith`, is saved and destroyed at the version it was read and
  refused with `DVConflictError` when the row has moved; one built by hand
  has read nothing and replaces the row at the version it finds, as `save`
  always has. Created and updated are reported from the write itself. Tables
  carry `_dv_version INTEGER NOT NULL DEFAULT 1` and `_dv_deleted_at`, and
  `.dart_tool/dartvel_schema.g.json` records their types, so `dartvel db
  migrate` adds them to an existing table with the default rather than as
  nullable TEXT -- a NULL version matches no conditional write, and every
  sweep would skip those rows for ever -- and the plan classifies the change
  through the adapter: instant on SQLite, MySQL 8 and PostgreSQL 11+,
  blocking on PostgreSQL 10, where a production rehearsal refuses it without
  an override. The statements written for PostgreSQL add both columns with
  `ADD COLUMN IF NOT EXISTS`. `@DVModel(history: DVHistory(keep: ...))` is
  read, refused when it cannot be, generated into the record table with
  `model.history()`, and carried into `privacy.g.dart`, so an erasure
  removes the log with the row instead of leaving every value it held.
- **A generated backend is an OAuth 2.1 provider when
  `dartvel.platformApi.oauth` is on.** It serves `GET` and `POST
  <api>/oauth/authorize`, `GET <api>/oauth/authorize/request` for the consent
  screen, `POST <api>/oauth/token`, `POST <api>/oauth/introspect`, `POST
  <api>/oauth/revoke` and `GET /.well-known/oauth-authorization-server`, each
  on the request's tenant. Another method is a 405 naming the allowed ones,
  and a CORS preflight is answered only on the token and revocation
  endpoints and the metadata document. The consent answer is checked for a
  CSRF token. A scope may name `DVOAuthToken.introspect`, the framework's
  own action for introspection, without an application policy.
- **A generated backend authenticates API keys and OAuth tokens on every
  route.** With `dartvel.platformApi` declared, each route's lifecycle has an
  authentication stage inside the tenant scope and tracing and outside the
  declared middleware. An `Authorization: Bearer` credential starting `dvk_`
  or `dvat_` is checked against the request's tenant and becomes
  `DVApiPrincipal.current` for the rest of the request; any other bearer is
  the application's and passes through. An invalid, revoked, expired or
  other-tenant credential answers one 401 with one body and
  `WWW-Authenticate: Bearer error="invalid_token"`; a key over its rate plan
  answers 429. `DVBackendPolicy.allows` refuses an action outside the
  principal's scopes before the application's `decide` runs, which then sees
  the principal. A keyed request is refused on a route that declares no
  policy action, and is not asked for a CSRF token. `@DVBackendFunction`
  reads a quoted policy such as `policy: 'Order.view'`, which was dropped and
  left the route unguarded, and stops the build on a quoted policy it cannot
  emit.
- **`dartvel routes` reads `dartvel.platformApi`.** The scopes, rate plans,
  `requireExpiry` and `oauth` lifetimes are parsed before anything is
  written, and a key nothing reads, an action that is not `Resource.action`
  or a rate plan with no window stops the build naming the key. A scope
  naming an action no `@DVPolicy` class in the application or a merged
  module defines stops it with `DV-APIKEY-001`; the check is by resource and
  action together, so `Invoice.view` is not satisfied by an `OrderPolicy`.
  The declaration is generated into `platform_api.g.dart` as
  `dartvelPlatformApi`, exported from the client barrel and parsed at
  startup by the same parser the build used; a project declaring none gets
  `null`.
- **The generated backend's unhandled errors are crash reports.** Each
  process installs `DVServerCrashes` with its role before it does anything
  that can fail. A request that answers 500 is recorded by the web process,
  a schedule that throws by the cron process, and a job dead-lettered after
  its last attempt by the worker, each labelled with that role and the
  pubspec version. Records go in `DARTVEL_CRASH_DIR`, else
  `.dartvel/crashes` beside the application, with the server's install id
  beside them; with `sink: dartvel` they are kept in the application's own
  crash table. A process that cannot install crash reporting says so and
  serves anyway.
- **`dartvel privacy check | export | erase | retention --plan`.** `check`
  lists every model's subject path and retention and fails on
  `DV-PRIVACY-001`. `erase --subject model:id --reason` runs against
  `DATABASE_URL` or the existing SQLite file `dartvel.database` names, under
  `DARTVEL_PRIVACY_KEY`, with the analytics adapters when analytics is
  declared; it needs `--yes`, or a typed `yes` at a terminal outside CI, and
  refuses before deleting anything when a table it reaches is missing or has
  no `_dv_version`. Its output names the subject by pseudonym. `export`
  writes the archive to `--out`, and replaces a file only with `--force`.
  `retention --plan` reports deletions, anonymizations and rows held by a
  longer retention without creating a table or writing a row; `retention`
  without `--plan` is refused.
- **Privacy declarations are read at generation.** `dartvel routes` reads
  every `@DVModel`'s `subject:`, `retain:`, `@DVModel.retain` and `onErase`
  before writing anything, stops on a sensitive field no subject path reaches
  (`DV-PRIVACY-001`) and warns on personal data with no retention
  (`DV-PRIVACY-002`), through `DVPrivacy.check`. It refuses a subject field
  the model does not declare, one holding a model rather than an id, a path
  through an undeclared model, a dated retention with no timestamp to
  measure from, and a subject model with no `id` or `slug` to delete rows
  by. `privacy.g.dart` registers every declaring model in
  `dartvelPrivacyModels`, so the generated server's `DV.Privacy` walks them.
- **The generated backend accepts crash reports when the application sends
  them there.** With `dartvel.crashes.sink: dartvel` the backend serves
  `POST <apiBasePath>/_dartvel/crashes` through `DVCrashIngest`, storing
  reports in the application's database under the declared per-install
  limit and size; the body limit is enforced where the body is read. With
  any other sink there is no endpoint, since nothing would read what it
  accepted. The generated client passes `DartvelRuntime.api` so the runtime
  reaches the same backend.
- **Generated pages sit under the consent banner, and iOS without a tracking
  usage description is a build error.** When `dartvel.analytics` is declared
  every generated route wraps its page in `DVConsentBanner`, since a banner
  an application has to remember to place is one nobody sees. `dartvel
  routes` reports `DV-ANALYTICS-002` through the consent policy's own check
  when a category is declared `tracking: true` and `ios/Runner/Info.plist`
  has no `NSUserTrackingUsageDescription`, which iOS needs before it shows
  App Tracking Transparency -- a key inside a comment does not count.
- **`dartvel.crashes` is checked when the client is generated.** `dartvel
  routes` parses the section with the runtime's own `DVCrashConfig.parse`
  before it writes anything, and refuses a value it cannot honour naming the
  key, where the runtime would have found out on a device. A build mode it
  disables is reported as `DV-CRASH-009`. The generated
  `installDartvelCrashReporting` hands the checked declaration to the
  runtime, so the sample rate, the breadcrumb size, the per-release limit and
  the identity consent category are the ones the pubspec declares.
- **The generated client installs crash reporting.** `configureDartvelRuntime`
  calls the new `installDartvelCrashReporting()`, after the platform
  bindings (on Android they find the directory records are kept in), which
  installs `DV.Crashes` for the application under the pubspec's `version` as
  its release -- `unversioned`, said in every report, when there is none.
  Nothing installed the crash runtime before, so a real application recorded
  no crash at all.
- **`dartvel.analytics` is read at generation and started by the app.**
  `dartvel routes` checks `dartvel.analytics` before writing anything and
  stops on a key or value it does not understand -- `consnet:`,
  `tracknig: true`, `default: grant`, `required: "yes"`, a store other than
  `database`, a flag category the consent policy does not declare, or a
  category name that is not a Dart name -- where each used to be skipped or
  read as false. It writes `analytics.g.dart` (the checked settings,
  `ConsentCategories.<name>` constants, `configureDartvelAnalytics`) and
  `privacy.g.dart` (`configureDartvelBackendPrivacy`), both core-only and
  exported from the barrel. The client runtime starts analytics over the
  device's own database after the platform bindings, which on Android find
  the directory it goes in; the generated server
  starts it over the application's database and configures `DV.Privacy`
  from `DARTVEL_PRIVACY_KEY`.
- **A generated worker runs the application's `@DVJob` handlers.**
  `jobs.g.dart` imported `dartvel_flutter`, which a server cannot load, so
  the generated backend registered no handler and every `DARTVEL_ROLE=worker`
  process refused to start. It is now the server half and imports only
  `dartvel_core`: payloads, codecs, `DVJobQueues`, the handlers a server can
  run and `registerDartvelJobs()`, plus `dartvelClientOnlyJobHandlers`, naming
  each handler that cannot run there and why. A handler goes to the new
  `client_jobs.g.dart` when its body names `DV`, or when it uses what its own
  file declares and that file reaches Flutter -- directly, through another
  file of the application, through the generated barrel, or through a
  package whose pubspec depends on the Flutter SDK. A handler's file is only
  imported when its body uses something the file declares, so a handler
  written against core in a file that imports the barrel still runs on the
  server. `dartvel routes` warns for each client-only handler. The barrel
  exports both halves and the client runtime calls
  `registerDartvelClientJobs()`.
- **Every generated backend role shares the store `DATABASE_URL` names.**
  `startBackend` and each role of `dartvelMain` register the job codecs and
  server handlers and call `DVProcessStores.install()`, so a web process
  dispatches onto the database queue a worker works; a declared web process
  with no `DATABASE_URL` says its jobs reach no worker. A worker with no
  `DATABASE_URL`, or no handler a server can run, exits 78 naming it, and
  names each client-only job it cannot run. A process that ticks schedules
  claims each occurrence through `DVDatabaseScheduleLease` on that database;
  a declared `cron` process with no `DATABASE_URL` exits 78 instead of
  starting, unless `DARTVEL_SCHEDULE_LEASE=none` says it is the only one, and
  one on a SQLite file says the claim holds on one host only. A worker or
  cron process given `DARTVEL_HEALTH_PORT` answers `GET /healthz` there and
  nothing else; no port, no endpoint. `--max-jobs` bounds a worker.
- **`dartvel queue work` works the application's queue.** In a Dartvel
  project it regenerates and runs `.dart_tool/dartvel_server.dart` as a
  worker on `--queue` bounded by `--max-jobs`, instead of draining the CLI
  process's own empty queue with no handler registered. Outside a project it
  still works the process's queue.
- **No test in the CLI moves the process working directory, and the suite
  runs at the default concurrency again.** Twenty-four suites set
  `Directory.current` so the command under test would find their temporary
  project. That value is one for the whole process, so whichever suite ran
  beside them read the wrong tree -- `release_coupling`, `middleware_keys`,
  `banned_names` and `shell_command` failed in turn, a different one each
  run. `concurrency: 1` narrowed it without ending it, because the engine
  hands a suite's slot on before the suite has closed. `admin`, `devtools`,
  `ai`, `analyze`, `build`, `db`, `generate`, `import`, `inspect`, `plugin`,
  `preview`, `publish`, `task` and `test` now take a `root` and read the
  working directory only when given none, which is what the CLI does;
  `task` runs its command in that root and `test` starts its runner there,
  as `build` now starts `flutter`, the terminal toolchain and the embedders,
  rather than wherever the process happens to be. `readDartvelCliVersion`
  takes `from`. `working_directory_test` runs every suite that mentions the
  working directory with a setter that refuses, and fails naming the suites
  that tried.
- **`dartvel infra plan` and `provision` accept several backend instances,
  workers and cron `enabled: false`.** The command hands the renderer the
  default capabilities, which now say the generated backend reads
  `DARTVEL_PORT` and `DARTVEL_ROLE`, so the specification's own services
  block plans: one unit per instance on its own port, one per worker and
  queue, and a cron unit. `logs.ship` is still refused and still applies
  nothing.
- **The generated backend runs as `web`, `worker` or `cron`, on
  `DARTVEL_PORT`.** `dartvel routes` writes `.dart_tool/dartvel_server.dart`,
  the entry point a deployment compiles, which calls the new generated
  `dartvelMain(arguments)`. It reads `DARTVEL_ROLE` or `--role`,
  `DARTVEL_PORT` and `DARTVEL_QUEUE` through `DVProcessConfiguration`, and
  exits 78 naming the variable when one cannot be honoured -- a port that is
  not 1 to 65535, an unknown role -- instead of falling back to the generated
  port. `web` serves on `DARTVEL_PORT`, else the generated port; given no
  role it is the whole deployment and ticks the schedules, and declared
  `web` it leaves them to the cron process and says so. `worker` works
  `DVQueueWorker` over `DARTVEL_QUEUE` and serves nothing. `cron` ticks the
  schedules and serves nothing. Worker and cron start the preview, modules,
  tenancy and AI tools the way `startBackend` does. `startBackend` binds
  `port`, then `DARTVEL_PORT`, then the generated port, refuses in a worker or
  cron process, starts the schedules only where the process ticks them, and
  takes `process`, `scheduleLease`, `scheduleClock` and `scheduleTick`.
  `dartvelStartBackendSchedules` takes `clock` and `lease`, so cron processes
  sharing a `DVCacheScheduleLease` fire an occurrence once. The preview still
  starts before anything else. The entry point cannot register `@DVJob`
  handlers or a queue adapter itself (`jobs.g.dart` imports
  `dartvel_flutter`), so a worker started from it refuses to start until
  something that runs first registers them.
- **`dartvel deploy --functions` for Cloud Run binds the port Cloud Run
  assigns.** Its Dockerfile set `ENV DARTVEL_PORT=$PORT`, which Docker
  expands when the image is built, when `PORT` is unset, so the server was
  handed an empty port. The image now reads `PORT` when the container starts
  (`CMD ["/bin/sh", "-c", "DARTVEL_PORT=\"$PORT\" exec /app/server"]`), and
  an unset `PORT` still reaches the server empty, which refuses to start
  naming `DARTVEL_PORT`. Every Dockerfile says that the image is one whole
  process given no `DARTVEL_ROLE` -- serving and ticking the schedules -- and
  how to run it as `web`, `cron` and `worker` containers instead. The
  tests run each image's command and read the result through the backend's
  own `DVProcessConfiguration`.
- **The generated runtime gives the shared window store its application
  key store.** The store now encrypts world anchor tokens under the
  application key and refuses them when it has no key store, and it has no
  application id to name one by, so an application nobody wired refused every
  anchor even on a desktop with a keyring. The generated runtime sets
  `DVWindowSharedStore.defaultAppKeys = () => dvAppKeyStoreFor('<package>')`,
  the key store `dartvel key` manages under the same name, before any tuned
  store is made. Nothing asks the keyring anything until a token is written;
  where the platform has no key custody the token is still refused.
- **The generated backend starts a preview before anything else runs.**
  `startBackend` calls `DVPreviewServer.start(Platform.environment)` as its
  first statement, so a backend deployed as a preview captures outbound mail
  and notifications, namespaces its queues and uses its own database before a
  module, tool or schedule is registered, and exits instead of serving when
  it cannot establish any of that. `startBackend` takes `previewMembership`
  for members previews and passes it to `serve`. In any other environment the
  generated backend behaves as before.

- **`@DVModel.model3dField()` is generated like any other media field.** The
  model carries `model3dFields`, the upload limits by field; `viewer3D()`
  renders the first 3D field in a `DVModel3DViewer`; the generated page and
  card render that viewer where the field appears; the field is written and
  read as JSON and gets a bundled factory default. A 3D field declared as
  anything but `DVSceneAsset`, or an annotation argument other than `poster`,
  `maxSizeMb` and `maxTriangles` written as a literal, fails generation with
  the reason rather than generating a field with no limit.

- **`dartvel db pull --local` prints `@DVModel` suggestions from the drift
  tables, isar collections and sqflite `CREATE TABLE` statements a project
  already has.** Column types map to model field types with nullability kept;
  a column with no model field type is named as not mapped rather than
  dropped. Suggestions are printed and never applied, and no sensitive field
  is guessed: the output says sensitivity was not inferred. `db pull` without
  the flag is unchanged.

- **`dartvel db migrate --plan`, `--dry-run --against snapshot` and
  `--production`.** `--plan` prints the class of every change the migration
  would make -- instant, online or blocking, from the SQLite library the CLI
  links -- and applies nothing, nor creates a database that is not there.
  `--dry-run --against snapshot` rehearses against
  `.dartvel/db/production.snapshot.json` (or `--snapshot <file>`): production's
  provider, server version, columns and row counts, gated as production, and
  exits 1 when the gate would refuse. `--production` refuses a blocking change
  without `--allow-blocking <reason>` (`DV-SCHEMA-002`), and a real run's
  override is appended to `.dartvel/db/schema_overrides.jsonl`; a dry run logs
  nothing. A provider the CLI has no connection to, with no snapshot, has
  nothing to classify its changes with, so against production they need the
  override. `--against` without `--dry-run` or `--plan` is refused rather than
  applied.

- **A string earlier in a file no longer hides a secret read from the
  secrets check.** `dvExtractSecretUses` stripped `//` and `/*` without
  knowing where a Dart string began, so
  `final u = 'https://api.example.com'; DV.Secrets.get('STRIPE_KEY');` lost
  everything after the URL's `//` and the read was never reported. A `/*` in
  a string, such as a glob, hid every read to the end of the file. Raw strings,
  triple-quoted strings, interpolations holding quotes and escaped quotes
  broke it the same way, and an undeclared or backend-scoped secret passed
  DV-SECRETS-001 and DV-SECRETS-002. The check now reads source with the lexer
  module trust uses, moved to `lib/src/analysis/dart_source_lexer.dart`, so
  there is one lexer and not two. It also no longer reports a read written
  inside a string or a nested block comment, it counts `DVSecrets().get(...)`
  as module trust already did, and each finding carries the line of the read.

- **`dartvel inspect adoption` reports what is Dartvel-managed and what is
  not: routes, models, screens and functions.** The managed half is generated
  pages, the graph's models and backend functions. The unmanaged half is host
  `GoRoute` paths, classes annotated `@freezed`, `@JsonSerializable`,
  `@MappableClass` or `@collection` and drift tables, files outside
  `pagesDir` that build a `Scaffold`, and `shelf_router` routes. Each kind
  says how it was counted and what it cannot see, and a route path that could
  not be read is listed as not measured instead of being left out of both
  counts. `--json` emits the same inventory.

- **`dartvel routes` fails on a route both the host router and a page define
  (DV-ADOPT-002), and on a model that already has a generated serializer
  (DV-ADOPT-003).** Both are checked before anything is written. Host routes
  are read from `GoRoute(path: ...)` calls, with nested routes joined to their
  parent, shell routes not prefixing, and parameter names ignored when
  comparing; a path that is not a plain string literal is logged as unchecked
  rather than passed. A model conflicts when `@freezed`, `@JsonSerializable`
  or `@MappableClass` sits anywhere in its annotation stack, or the class
  refers to generated `_$Name` code. Previously `@DVModel()` above
  `@freezed` generated no model at all and said nothing, because the model
  generator's pattern steps over `@pragma` only.


- **`dartvel.memory` reaches the running application, and doctor checks it.**
  The generated client installs the `memory` section and each device
  profile's `platform`, `ram` and `memory` override with `DVMemory.configure`
  at startup, so `DV.Memory.allocate` applies the declared defaults and
  per-target ceilings. A project that declares none generates nothing.
  `dartvel doctor` reports configuration mistakes, fails a device profile
  whose resolved memory budget exceeds its declared `ram`, and warns with
  `DV-MEMORY-004` when `touchPages` is forced on a configured mobile or
  embedded platform.
- **`dartvel init` adds Dartvel to a project that already exists, and is no
  longer an alias of `create`.** As an alias it replaced the adopting
  project's pubspec with the scaffold template. It now inserts the Dartvel
  dependency (`dartvel_core`, plus `dartvel_flutter` for a Flutter
  application) and a `dartvel:` key, and nothing else: every original line,
  comment and blank line is kept, and the edit is refused rather than written
  when it cannot be proven to be insertions only. The plan is printed first
  with a compatibility report -- the SDK constraint against Dartvel's floor,
  and every package the project shares with Dartvel against Dartvel's
  constraint, with a blocked `mix` pin naming the `dartvel_mix` drop-in. A
  check that cannot be made is reported as unchecked, never as compatible.
  `pagesDir` and `backendDir` are written out, and mapped away from
  `lib/pages` or `lib/backend` when the project's own files there would be
  claimed as pages or served as endpoints. `--dry-run` writes nothing;
  applying needs a yes at a terminal or `--yes`, refuses a blocked plan, and
  replaces the pubspec with one rename, refusing if it changed after the plan
  was shown. `create`'s DV-ADOPT-005 refusal now points at `init`.

- **`dartvel docs` builds the application's own reference from the project
  graph.** It covers models and fields (types, relations, policies, generated
  surfaces, and example data built from each field's type), backend functions
  (signature, doc comment and the request lifecycle stages in the order the
  generated backend runs them), the route index (pages, generated model pages,
  mounted module pages), jobs and cron, a policy matrix of resource against
  action, the module map with what each module was granted, and the
  diagnostics glossary from the registry `dartvel explain` reads. Descriptions
  are doc comments, read through each node's source mapping. A sensitive field
  is named, marked and never valued. Decision records under `docs/decisions`
  (or `dartvel.docs.decisions`) link to the nodes they name as
  `` `model:Order` ``, `` `function:checkout` `` and so on, and those nodes
  link back. `DV-DOCS-001` is reported for a name that no longer exists, and
  `DV-DOCS-002` for a node whose mapping no longer holds its declaration.
  `graph.json` in the site is byte-for-byte the graph `dartvel mcp` hands an
  agent. Output is byte-deterministic. `--output`, `--fatal-warnings`, and
  `--serve`, which serves on loopback and rebuilds on change.

- **The project graph marks a sensitive field wherever it sits in its
  annotation stack, and reads a backend function with middleware under its
  annotation.** `@DVModel.sensitiveField(encrypted: true)`, and a sensitive
  field with `@DVModel.searchableField()` under it, were described as ordinary
  fields to `dartvel inspect` and to an agent over `dartvel mcp`. The model
  generator already accepted both. A function with `@DVUseMiddleware` below
  `@DVBackendFunction` was read as an unannotated file named after itself, at
  line 1.

- **Generated output is byte-identical for identical inputs, and
  `dartvel generate --check` fails when it is stale.** Every generated file
  used to open with a wall-clock `// BUILD:` stamp, so every regeneration
  rewrote every file whether or not anything had changed. The stamps are gone.
  The generator version is recorded once, in the
  `lib/dartvel_client/dartvel_client.dart` header. `dvGenBuildId`, which
  `dartvel dev` prints when the backend starts, is now a hash of the generated
  backend routes instead of a time. `--check` regenerates two copies of the
  project in a scratch location and writes nothing into the project. It exits
  non-zero and prints `DV-GEN-001` for each path the generator would change,
  and `DV-GEN-002` for each path that differs between the two copies.

- **`dartvel flags list` and `dartvel flags prune`.** `list` prints every
  declared flag with its type, compiled default, owner, expiry and settle
  mode. `prune` prints the flags past their expiry, each with every
  `file:line` of application code that still reads it — generated output and
  the declarations themselves excluded — or says it has no remaining reads and
  can be deleted outright. The reads are the point: deleting a flag means
  deleting the branches it guards, and a list of due names without them is a
  list of reasons to leave the flags in. `set`, `rollout`, `off` and
  `override` change rules a deployment serves and are not here yet.

- **`@DVFlags()` generates typed `Flags` accessors** into
  `lib/dartvel_client/flags.g.dart`. A flag named by a string can be misspelt,
  and a misspelt flag does not throw — it misses and answers its default for
  ever — so each `@DVFlag` field becomes a `DVFeatureFlag<T>` member carrying
  its key, compiled default, owner, expiry, settle mode and, for an enum, its
  values, with its doc comment. `Flags.all` and `registerDartvelFlags()`
  declare them to the runtime. Refused rather than generated around: a flag
  with no `expires:` or `owner:`, a public `@DVFlags` class, a type a flag
  cannot carry (flags hold `bool`, `String`, `int`, `double` and enums; a
  structure is configuration), an impossible date, and a name declared twice.
  A flag past its expiry is a `DV-FLAGS-004` warning naming its owner.


- **`dartvel create` refuses to scaffold over a project it did not create
  (`DV-ADOPT-005`).** One of its steps replaces `pubspec.yaml` with the
  scaffold template. In an empty directory the file being replaced is the one
  `flutter create` wrote a second earlier, which is the intent. In a directory
  that already holds an application it replaced every dependency, version and
  setting the team had declared — and `init` and `new` are aliases of this
  same command, so the word someone with an existing project reaches for first
  was the destructive one. It announced itself as an information line reading
  "Overwriting pubspec.yaml with Dartvel configuration...". Nothing else in
  the CLI destroys a file it did not write. The check runs before
  `flutter create`, because after that there is no way to tell whose pubspec
  is on disk; a `dartvel:` key marks one the template wrote, and a
  commented-out example does not count as one.

- **`dartvel create` no longer pins a new project to a three-release-old
  `dartvel_shelf`.** The scaffold interpolates a version constant for
  dartvel_core, dartvel_flutter and dartvel_cli, but wrote `dartvel_shelf:
  ^0.3.0` as a literal beside them. A caret on a 0.x version stops at the next
  minor, so every project created since shelf 0.4.0 asked for `>=0.3.0 <0.4.0`
  and resolved a shelf from before most of what the project used existed. It
  is `dartvelShelfVersion` now, bumped by `tool/bump_version.dart` with
  everything else. The test that was supposed to cover this read the list of
  packages the constant feeds rather than the constraints the template writes,
  so the one wrong constraint was the one it could not see; it now reads the
  rendered pubspec.
- The site and the example applications declare the packages they are built
  against. All three said `^0.2.1` -- core, flutter and cli -- and `^0.3.0`
  for shelf, while the packages were at 0.5.0 and 0.6.0. Each resolves through
  `pubspec_overrides.yaml`, so nothing here ever built against the constraint
  and nothing failed; a reader copying the file got a release from before the
  features the application demonstrates. `tool/bump_version.dart` bumps them
  with the packages, and `tool/check_constraints.dart` fails the release if
  any application, or any scaffold constraint, stops admitting what is being
  published.

- `dartvel.windowing.enabled` reaches the runtime. The capability has taken
  the parameter since it was written and no build ever passed one, so a
  project that switched windows off still got them, and a window that
  degraded blamed the target rather than the line that withdrew them
  (`DV-WINDOW-005`).

## 0.5.0

- The package no longer ships `lib/builder.dart`, a build_runner Builder that
  wrote nothing and that no `build.yaml` ever declared, so it could not run
  even if a project asked it to. With it goes the `build` dependency every
  install of the CLI was resolving. Nothing imported it; if you did, the
  replacement is `dart run dartvel_cli:dartvel routes`.
- `dartvel create` no longer scaffolds a `build_runner` setup. Dartvel's code
  generation is `dart run dartvel_cli:dartvel routes`, which `dartvel dev` and
  `dartvel build` run for you, so a new project was resolving and downloading
  a builder it never used -- and being pointed at the retired
  `dartvel_generator` path. Add `build_runner` back yourself if some other
  package's builders need it (`json_serializable`, `freezed`,
  `flutter_vscode`); `dartvel dev` and `dartvel build` still run it when it is
  declared. The scaffolded README now has a "Generating" section naming
  `dartvel routes`.
- A home widget's preview page names itself with a level-1 heading of its
  title when it has no bar to carry one. `dartvel build web` audits every
  page for a level-1 heading, and the preview route rendered the widget and
  nothing else, so every application with a home widget failed its own web
  build on that page. With `showAppBar: true` the bar's title is the heading
  and the body does not repeat it; a widget that builds its own Scaffold is
  left alone, since a heading above one would break its layout.
- Image variants, NextFaster's other half. `dartvel build web` writes every
  raster image declared under `flutter.assets` at each configured width
  narrower than it, into `assets/_dartvel/img/<width>/`, and hands the
  application what it wrote as `DARTVEL_IMAGES`: `DVImageView` then asks for
  the width its slot needs on this screen. Never wider than the image, and
  never a width that was not written, so no variant is a 404. A GIF is left
  out, since resizing keeps one frame of an animation. Nor is a variant ever
  a bigger download than its source: re-encoding can undo compression the
  source already had -- the example's 1200-wide PNG came out larger at 1080
  -- and then the source's own bytes are written at that width instead.
- `dartvel.images` in pubspec.yaml: `widths`, `quality` and `remoteHosts`.
  A web-server build carries it into dartvel_routes.json for the server's
  `/_dartvel/image`, which resizes images from those hosts and no others.
- The semantics capture reads the slot each image was laid out in, from the
  page, and the prefetch manifest carries it. A link can then prefetch the
  variant for the visitor's pixel ratio rather than the build's. Those
  images stay out of a page's head, because which file a visitor needs
  depends on a screen the head cannot know.
- A web-server build marks guarded routes `"guarded": true` in
  dartvel_routes.json, from the router's own list, and carries
  `dartvel.web.server.streaming: shell` into the manifest. The server needs
  both to send a route's head before its data: a guarded route's answer
  depends on the request, so it is the one kind of route that must not be
  sent early.
- Pages are split out of main.dart.js on the web. Every page was imported
  `deferred`, but the generator copied each private page's body into the
  router, which is eager, so dart2js found all of it reachable from `main()`:
  the site built with three of its four pages having no deferred part at all
  (`deferredLibraryParts:{p0:[],p1:[],p2:[0],p3:[]}`). A lowered body now goes
  into `lib/dartvel_client/pages/<page>.g.dart`, which only the router's
  deferred import reaches, and every page gets parts of its own that
  `loadLibrary()` fetches.
- The service worker precaches those parts. A page's code used to be in
  main.dart.js, which every visit caches; once it is in a part, a page never
  opened online would fail to load offline.
- Each prerendered page names its own code and first-frame images in its
  head. dart2js writes which part files each deferred import loads into
  main.dart.js; `dartvel build web` reads that table with the generated
  router and adds a `<link rel="preload">` for the page's parts, so a page
  opened directly downloads them alongside main.dart.js instead of a round
  trip after it boots. The semantics capture now also records the images each
  page fetches while it renders, which are preloaded the same way -- as
  `fetch` with `crossorigin` for the bytes Flutter reads, since a preload
  requested any other way is not reused and the image downloads twice.
- The same lists are written to `dartvel_prefetch.json`, which a link reads to
  prefetch a page's images before the visitor gets there.
- A launch splash on every platform, from `dartvel.splash`, with nothing to
  install and nothing to run. The files `flutter create` writes open every
  application on white -- Android's launch theme, iOS's launch storyboard,
  and on the web a blank page for as long as main.dart.js takes -- and macOS
  on black. `dartvel build` now writes the colour and an optional image into
  each: the web shell and so every prerendered page, Android's launch
  background plus the API 31 splash that ignores it, the iOS storyboard with
  a dark-mode colour set, the macOS view and the Linux view. With nothing
  configured the colour is `dartvel.pwa.backgroundColor`, the image the
  project icon, and dark mode gets `#121212` rather than white. On the web
  the splash sits under Flutter's view, so the application covers it the
  moment it paints, and it is hidden with scripting off, where the page's
  content is the noscript block. A launch file somebody designed is left
  alone unless `dartvel.splash.overwrite` is set; Windows needs nothing,
  since its runner shows the window only on the first frame.
- `@DVClientCron` schedules run while a page is on screen rather than from the
  moment the router is created. The timer they started there had no owner:
  it was never stopped, creating a second router started a second one so
  every schedule ran twice, and a widget test that built the router ended
  with it still running -- which is why eight of the example's tests failed.
- Generated code passes the analyzer a Flutter project runs, where an info is
  a failure. Three things in it did not, in any application that used them:
  an AI tool's schema with `const` on one value and not its siblings, a
  redundant `const` in the sitemap entries, and a route target named after a
  page directory with an underscore in it.
- **A route's typed target is lowerCamelCase: `/next_shift` is
  `DVRoutes.nextShift`.** It was `DVRoutes.next_shift`, which Dart's style
  lint rejects. The old name is still generated, as a deprecated alias for
  the new one, so code written against it keeps compiling; it goes in the
  next minor release.
- The renderer starts downloading while the page parses. CanvasKit is 7 MB
  and nothing asked for it until flutter_bootstrap.js had arrived and run;
  index.html, and so every prerendered page, now preconnects to gstatic and
  preloads the CanvasKit files itself. The variant is chosen with the
  loader's own test -- the smaller `chromium` build where Blink has
  ImageDecoder and the ICU break iterators -- and each file is requested the
  way the loader requests it, so in Chrome both are fetched once and the
  loader takes them from the preload. No hints are written for a `--wasm`
  build or a loader told where CanvasKit is or which variant to use, since a
  hint for the wrong file is 7 MB for nothing.
- A web-server build writes `dartvel_prefetch.json` too, keyed by route
  pattern -- parameterised ones included, which the static build cannot
  serve -- so the server can name each route's own deferred parts and images
  in the head it sends. The shell is left alone: it is served for every
  route, and one route's list written into it would be wrong for all the
  others.
- `dartvel preview` streams `shell` as the deployed server does: the head,
  with the route's own parts, before the data; a guarded route waits and
  keeps its status; a record found hidden after the flush is a noindex page.
  It had only the older split, head after the data, so a developer
  previewing `shell` watched every page wait on the resolver and deployed
  something that behaved differently.

## 0.4.1

Fixes two faults the published 0.4.0 carried.

- The 0.4.0 binary reported itself as 0.3.2. `dartvel --version` prints a
  constant that no pubspec mentions, and the bump to 0.4.0 missed it. Because
  `dartvel update` compares the same constant with the latest release, every
  0.4.0 install offered itself 0.4.0 as an update, installed it, and offered
  it again.
- `dartvel create` wrote `^0.2.1` for dartvel_core, dartvel_flutter and
  dartvel_cli, and has since 0.3.0. A caret on a 0.x version stops at the next
  minor, so every new project resolved Dartvel 0.2.x. It writes `^0.4.0` now.
  **A project created with 0.3.x or 0.4.0 still says `^0.2.1`; change those
  three constraints to `^0.4.0` by hand.**
- Both versions are now moved by the release tooling and checked by the gate
  that runs before publishing, so a mismatch stops the publish itself.
- Headless Chrome is one shared copy per machine, in the user cache, instead of
  one per project under `.dart_tool`. A build already in the shared cache is
  reused whichever puppeteer release pins which, so projects resolving
  different puppeteer versions no longer each download their own 380 MB
  browser.

## 0.4.0

- `dartvel build android` writes the Activity, the capture provider and the
  permissions an application declares under `dartvel.android.permissions`,
  plus the two permissions the framework binds whether or not a project asked:
  `VIBRATE` and `USE_BIOMETRIC`. Both are normal permissions, granted at
  install with no dialog, which is exactly why their absence was invisible --
  the application ran, the binding was registered, and the call threw where
  nobody was looking.
- Only normal permissions are ever added on a project's behalf. A dangerous
  one would put a question in front of its users that its author never wrote,
  and there is a test asserting `BLUETOOTH_CONNECT`, `CAMERA`,
  `READ_CONTACTS`, `ACCESS_FINE_LOCATION` and `POST_NOTIFICATIONS` never
  appear in a manifest that asked for nothing.
- `dartvel db migrate` runs the statements it prints. It used to print a line
  per model, say they were synced successfully, and execute nothing at all.
  For Postgres or MySQL it writes the statements out and says it did not run
  them, because the CLI has no connection to a managed database.
- Declared middleware runs. Ten of the nineteen keys now reach the generated
  router in the order declared; the annotation previously had one reader, a
  check that the name was spelled correctly, which then dropped the list.

## 0.3.2

- Corrected the constraints on sibling Dartvel packages, which named the
  previous release rather than the one published alongside them. A caret on a
  0.x version stops at the next minor, so `dartvel_core: ^0.2.1` excluded the
  0.3.1 published beside it -- a user installing the 0.3.1 set resolved 0.2.x
  for every sibling and got none of what that release contained. `dart pub
  publish --dry-run` could not see it, because it resolves against
  pubspec_overrides.yaml and every sibling points at a local path.

## 0.3.1

- `dartvel update` fetches the latest published binary and replaces the running
  one, verifying its checksum first and keeping the old binary alongside. A
  no-op when already current.
- `@DVFunctionalWidget` generates a widget class rather than a function, so a
  generated component can be const and can reach a BuildContext without every
  caller threading one.
- Lowered page and widget bodies carry the imports they were written against,
  and a body that reaches for a private symbol is refused with a message naming
  it rather than emitting generated code that does not compile.

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
