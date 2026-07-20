# New Spec v2

# Dartvel — The Complete Vision

> **Flutter's Laravel, Flutter's Expo, Flutter's Next.js, Flutter's Hasura.**
>
> A batteries-included, AI-native, full-stack platform for building Flutter applications.

Flutter remains the rendering engine.

Dartvel becomes the platform. 

---

# Philosophy

Developers should primarily write:

* Pages
* Models
* Backend Functions
* UI
* Business Logic

Everything else should be generated.

---

# Design Goals

* Dart-first
* AI-first
* Convention over configuration
* Zero boilerplate
* End-to-end type safety
* Batteries included
* Compile-time generation
* Production ready
* Native performance
* Flutter compatible

---

# Project Structure

```text
lib/

pages/
models/
backend/
components/
styles/
services/

main.dart
```

These paths are the defaults. Projects may override them under the `dartvel:`
key in `pubspec.yaml`, including glob patterns for file groups, directories, and
subdirectories. The `dartvel:` key may also point to a Dart config file:

```yaml
dartvel: dartvel_config.dart
```

That file must expose a public class extending `DartvelConfig`. The class name
must start with an uppercase letter and must not start with `_`, so the CLI can
import it. YAML config is internally normalized into the same strongly typed
config shape.


No controllers.

No repositories.

No DTOs.

No manual route maps. Generated route maps are supported out of the box.

No signal folders.

---

# Configuration

Everything lives inside:

```yaml
pubspec.yaml
```

under

```yaml
dartvel:
```

Including

* App config
* Auth
* Permissions
* Deployment
* SEO
* PWA
* Multi-tenancy
* AI
* Storage
* Database
* Providers

---

# UI

Two primitives.
Dartvel keeps the primitive surface area small:

```dart
DVBox(...)
DVBox.list(...)

DVText(...)
```

Everything else is built from them.

Images ( .backgroundImage() modifier on DVBox )

Cards ( .card() modifier on DVBox )

Text inputs ( .input() modifier on DVText )

Rows (`DVBox.row(children)`)

Columns (`DVBox.list(children)`)

Buttons ( .onTap() or .onPressed() alias modifier on DVBox or DVText )

Forms ( DVForm does exist )

Lists (`DVBox.list(children)`)

Grids (`DVBox.grid(children)`)

Masonry (`DVBox.masonry(children)`)

Navigation

Containers and Layouts

---

Collection layouts are modes on `DVBox`, not separate widgets.

## Static Layouts

Static content is passed as an exact `List<Widget>` to `DVBox.list`. The default
layout is vertical and maps to Flutter's `Column` for static content.

```dart
DVBox.list([
  DVText("One"),
  DVText("Two"),
  DVText("Three"),
])
```

Single-child boxes use `DVBox(widget)` so the public API stays strongly typed
without `dynamic`, `Object`, or `var`.

```dart
DVBox(DVText("Profile"))
```

Rows, grids, wraps, stacks, horizontally scrollable lists, and scrollable
regions are layout constructors for static children. `DVBox.row` is an inline,
non-scrollable row. Use `DVBox.horizontalScrollable` when the collection should
overflow horizontally:

```dart
DVBox.row([Avatar(user), DVText(user.name)])

DVBox.grid([PhotoCard(a), PhotoCard(b), PhotoCard(c)], columns: 3)

DVBox.wrap([Tag("Flutter"), Tag("Dart"), Tag("Rust")])

DVBox.stack([Background(), Avatar(), Badge()])

DVBox.horizontalScrollable([StoryCard(a), StoryCard(b), StoryCard(c)])

DVBox.list([...]).scrollable()
```

Explicit `DVBox.wrap([...])` or `.wrap()` is a layout mode for collections. It
is not the removed automatic wrapper behavior for arbitrary widget composition.
`wrapLine` remains a compatibility alias, but new code should use `wrap`.

## Dynamic Collections

Runtime collections use `DVBox.builder`. The default is vertical, lazy, and
virtualized where the target platform supports it.

```dart
DVBox.builder(
  posts,
  (post) => PostCard(post),
)
```

`DVBox.builder(...)` returns `DVBoxBuilder`, which is not itself a widget. A
layout method such as `.list()`, `.grid(...)`, `.wrap()`, `.masonry()`,
or `.horizontalScrollable()` must be called.

Builder collections support the same layout modes:

```dart
DVBox.builder(posts, (post) => PostCard(post)).grid(columns: 2)

DVBox.builder(tags, (tag) => TagChip(tag)).wrap()

DVBox.builder(photos, (photo) => PhotoCard(photo)).masonry()

DVBox.builder(stories, (story) => StoryCard(story)).horizontalScrollable()
```

## Generated Model Components

Generated model components are application components, not layout primitives.
They compose `DVBox`, `DVText`, and generated controls internally.

```dart
User.Form()
User.List()
User.Grid()
User.Masonry()
User.Table()
User.Page() // generated default page with a title and User.List()
```

Tables remain model-generated because they include sorting, filtering,
pagination, resizing, keyboard navigation, virtualization, accessibility, and
column management. Tables use the platform-styled table/list design with a
Material data table fallback.

```dart
User.List().builder((context, user) => UserCard(user))

User.Table().builder((context, user) => UserRow(user))
```

This intentionally avoids `DVRow`, `DVColumn`, `DVGrid`, `DVList`,
`DVMasonry`, and `DVWrap`. `DVBox` is the universal layout primitive, `DVText`
is the universal text primitive, and higher-level CRUD experiences are generated
from models.

---

# Styling

Built on Mix.

Supports EVERY Mix modifier.

Shared styles:

```dart
final primary =
    DVStyleModifier()
        .padding(12)
        .rounded(12);
```

N/B: Let's actually use `DVModifier` since it covers widget functionality too, not just styles. We'll keep `DVStyleModifier` as an alias for backword compatibility


Usage

```dart
DVText("Save")
    .styleModifier(primary);
```

N/B: Let's actually use `.modifier()` since it covers widget functionality too, not just styles. We'll keep `.styleModifier()` as an alias for backword compatibility


Fluent modifiers

```dart
.padding()
.margin()
.color()
.backgroundColor()
.shadow()
.width()
.height()
.card()
.rounded()
```

No manual Mix `.wrap()`. Dartvel handles wrapping where necessary.

---

# Pages

Class

```dart
@DVPage()
class UsersPage extends DVClassWidget {
    Widget build(
        BuildContext context
    ) {}
}
```

Functional

```dart
@DVPage()
Widget usersPage(
    BuildContext context
) {}
```

`@DVPage()` alone is enough for page functions. Using both `@DVPage()` and
`@DVFunctionalWidget()` remains valid; Dartvel treats them the same for pages
and performs the generated wrapping internally.

`@DVPage` handles routing, transitions, and the unified Material/Cupertino page
scaffold. Page bodies return Dartvel content directly, usually `DVBox`,
`DVBox.list`, or `DVText`; application page code should not create `Scaffold`
or `CupertinoPageScaffold` manually.

Page shell options are configured on the annotation with const values:

```dart
@DVPage(
    title: 'Settings',
    shell: DVPageShellMode.adaptive,
    showAppBar: true,
    safeArea: true,
    centerTitle: true,
    backgroundColor: 0xFFFFFFFF,
    appBarBackgroundColor: 0xFFF8FAFC,
    appBarActions: const [],
    appBarLeading: null,
    // all Material and Cupertino scaffold features are unified here
)
Widget settingsPage(BuildContext context) {
    return DVBox.list([
        DVText('Settings'),
    ]);
}
```

`DVPageShellMode` supports `adaptive`, `material`, `cupertino`, and `none`.
`adaptive` renders Cupertino page chrome on iOS/macOS and Material page chrome
elsewhere. `scaffold: false` or `shell: DVPageShellMode.none` disables the
generated shell for advanced embedding.

If a page source explicitly returns a `Scaffold` or `CupertinoPageScaffold`,
the generator does not wrap that page with the default `DVPage` shell unless
`@DVPage(scaffold: true)` is set explicitly. This keeps legacy/manual shell
pages working, while Dartvel-authored pages should move scaffold properties to
`@DVPage(...)` and return content only.

---

# Routing

Pages Router.

```
pages/index.dart
```

Generated route clients must import each `DVPage` with Dart deferred imports under the hood.
The generated `dartvel_client/dartvel_client.dart` barrel exposes generated page
wrappers, and route tables instantiate those wrappers instead of importing page
source files eagerly. On web this allows large applications to load each page
bundle when the route is first visited rather than loading every page in the
initial bundle.

Application code should import one generated entrypoint:

```dart
import 'package:my_app/dartvel_client/dartvel_client.dart';
```

That barrel exports Dartvel core, Dartvel Flutter primitives, generated
functions, routes, configuration, environment access, and generated model
helpers.

↓

```
/
```

```
pages/users.dart
```

↓

```
/users
```

```
pages/users/[id].dart
```

↓

```
/users/:id
```

Navigation is strongly typed.

```dart
.navigateToPage(.users)

// For routes with parameters
.navigateToPage(
    .users(id)
)
```

Example:

```dart
DVBox(DVText("Navigate to users")).onPressed(DV.Navigation.to(DVPages.users));

// For routes with parameters
DVBox(DVText("Navigate to user 1"))
    .onPressed(DV.Navigation.to(DVPages.user(id: 1)));
```

---


# State

Local

```dart
final counter =
    context.signal(0);
```

or

```dart
signal(context, 0);
```

The `DV.signal()` helper can also work without a Flutter `BuildContext` in pure
Dart apps. `DVContext` is a universal context object for Flutter, server, CLI,
and web environments.

```dart
DVContext.builder((DVContext context) {
  final count = signal(context, 0);
  return DVText(count.value.toString());
});
```

`DVContext` mirrors useful `BuildContext` capabilities in Flutter apps and
exposes Dartvel-specific context for non-Flutter platforms. Unsupported
Flutter-only context operations fail clearly outside Flutter instead of silently
pretending to work.

---

Global

Register

```dart
DV.globalSignal<Cart>(Cart());
```

Retrieve

```dart
DV.globalSignal<Cart>(); // To retrieve, don't pass a value, just the type.
```

Reactive

```dart
context.global<Cart>();
```

Models become reactive automatically

```dart
user.signal(context);
```

Collections too

```dart
users.signal(context);
```

Read-only

```dart
counter.read();
user.read();
```

Internally powered by Riverpod, so it works in Flutter and pure Dart.
Normal `signal()` tracks by parent widget or context. `globalSignal` tracks by
data type, so each type must be unique. Setting the same type replaces the
previous value for that type.

---

# Models

```dart
@DVModel()
class User(
    String name,
    String email,
);
```

Using the new native Dart data-class syntax. Automatically generates:
* Database schema
* CRUD
* Validation
* Serialization
* Equality, .copyWith, .merge, and .hashCode
* Forms, Pages, Lists, Tables, and generated components (`.Form`, `.Page`)
* APIs
* Queries
* Model sync and presence

---

# Forms

Automatic

```dart
DVForm<User>()
```

Or alias

```dart
User.Form()
// The base class
```

---

Editing

```dart
// Accepts the model as a positional Arg. The Arg type is DVModel, base class for all the models
DVForm<User>(user)
// An instance of the base class
```

Or alias

```dart
// The instantiated object
user.Form()
```

Manual

```dart
DVForm<User>.builder((formControls) { return someComposedWidget; })
```

Editing

```dart
// Accepts the model as a positional Arg. The Arg type is DVModel, base class for all the models
DVForm<User>.builder((formControls) {}, user)
```

Generated controls, such as `formControls.email`. These render with
`DVText.input()`.

Generated validation, such as `formControls.emailIsValid`.

Generated submit ( formControls.submit(), .reset() ).

---

# Backend

Backend code is ordinary Dart.

```dart
@DVBackendFunction()
Future<User> getUser(...) {}
```

Parameters are automatically validated by type, with automatic valudation messages generated. The messages can be customized if needed. Automatic request and response conversion.

Call it like

```dart
await getUser(id);
```

In frontend or backend code. Works the same.

No raw REST (but still available).

No controllers.

No routes.

No generated SDKs (but still available).

No manual openapi configs, they get auto-generated

Just typed functions.

Under the hood, Dartvel compiles backend functions into a high-performance Rust runtime built on Axum and Tokio, exposing them through zero-boilerplate, strongly typed, zero-copy, FFI APIs. Developers continue writing only Dart. 

---


# Streaming Functions

Backend functions may return

```dart
Stream<T>
```

Example

```dart
@DVBackendFunction()
Stream<Message> messages()
```

Automatically translated to efficient streaming endpoints (such as Server-Sent Events or websockets with automatic fallback to polling, can be configured) while preserving Dart's native `Stream<T>` API.

---

All backend data is transmitted as form-data to allow large request sizes if necessary and to be compatible with web. Fields in the form-data are packed as binary flat-buffers. An efficient lightweight boundary is used for the form-data and documented in the request headers. This applies to backend functions and model events.

---

# Scheduling

Backend

```dart
@DVBackendCron(...)
```

Client

```dart
@DVClientCron(...)
```

---

# Queues, Jobs, and Signals

Dartvel has a durable background work layer inspired by Laravel queues and a
typed signal model inspired by Qt signals/slots, Dart streams, Riverpod, and
generated model sync delivery.

## Jobs

Jobs are ordinary typed Dart payloads. The generator discovers `@DVJob`
classes, generates readable dispatch helpers, and registers strongly typed
handlers. No job payload uses `dynamic`, `Object`, or untyped maps in public
APIs.

```dart
@DVJob(queue: 'mail', maxAttempts: 5, backoffSeconds: 60)
class SendWelcomeEmail(String userId)

@DVJobHandler()
Future<void> handleSendWelcomeEmail(SendWelcomeEmail job) async {
  await DV.Notifications.send(...);
}

await DV.Jobs.dispatch(SendWelcomeEmail(user.id));
```

Queues support:
- named queues and generated queue constants
- priorities and delayed execution
- retries, exponential backoff, retry-until timestamps, and max attempts
- dead-letter queues with inspect, retry, discard, and replay commands
- worker scaling, concurrency limits, pause/resume, and graceful shutdown
- job uniqueness and idempotency keys
- scheduled jobs and cron-triggered jobs
- queued signal payloads
- typed progress events and cancellation tokens
- provider adapters for in-memory, database, Redis/Valkey, SQS, Pub/Sub,
  RabbitMQ, Kafka, and platform-native task schedulers where available

CLI:

```bash
dartvel queue work
dartvel queue failed
dartvel queue retry <job-id>
dartvel queue flush --queue mail
```

Runtime guarantees:
- Jobs are persisted before `dispatch` returns unless the configured provider is
  explicitly in-memory/test.
- Failed jobs are never silently dropped.
- Retried jobs preserve the original payload and append attempt metadata.
- Job handlers run with observability trace context and tenant context.
- Unsupported providers fail validation during `dartvel build`.

## Signals

Signals are already part of Dartvel through `context.signal(...)`,
`signal(context, ...)`, reactive models, `DV.globalSignal`, and generated model
sync.
Dartvel should not introduce separate signal/event annotations for the common
case.

```dart
final counter = context.signal(0);
counter.value++;

final userSignal = user.signal(context);
final cart = context.globalSignal<Cart>();
```

Computed values too
```dart
final a = context.signal(1);
final b = context.signal(2);
final c = context.computed(() => a.value + b.value);
```

Computed values remain reactive to changes from their source signals.

---

For background work and cross-client delivery, signals are just typed job
payloads or model sync events:

```dart
await DV.Jobs.dispatch(
  UserCreated(user.id),
  queue: DVQueues.signals,
);
```

Signal guarantees:
- Signal values are exact typed Dart values.
- UI state uses `context.signal` / `signal(context, value)`.
- Model state uses generated reactive model signals.
- Background signal delivery uses `DV.Jobs`.
- Cross-client delivery uses generated model sync.
- Model lifecycle signals are generated for create, update, delete, restore,
  attach, detach, and sync events.
- Model sync applies auth, tenant filters, and policy checks before
  delivery.
- Signals can bridge to native platform events through generated FFI/ffigen or
  JNI/jnigen bindings only. No Flutter platform channels.

---

# Authorization

Authentication identifies users. Authorization decides what they can do.

```dart
@DVPolicy(Post)
class PostPolicy {
  bool update(User user, Post post) => post.authorId == user.id;
}

await DV.Auth.authorize(user, DVPolicyAction.update, post);
final allowed = await DV.Auth.can(user, DVPolicyAction.delete, post);
```

Policy generation:
- `@DVPolicy(ModelType)` classes generate typed policy registries.
- Conventional policy methods include `viewAny`, `view`, `create`, `update`,
  `delete`, `restore`, `forceDelete`, `export`, and `impersonate`.
- Generated model components call policies automatically before rendering
  actions.
- Backend functions and model queries enforce policies even if UI guards are
  bypassed.
- Tenant scoping is part of policy evaluation, not a separate optional filter.

Policies apply to:
- pages
- backend functions
- model queries
- generated forms
- generated tables/lists
- storage objects
- model sync channels
- tenant boundaries

Usage:

```dart
@DVPage(policy: DVPolicies.viewAdmin)
Widget adminPage(BuildContext context) => AdminDashboard();

@DVBackendFunction(policy: DVPolicies.refund)
Future<Refund> refundOrder(Order order) async {}
```

Generated UI can hide disabled actions, but backend enforcement is mandatory.
Unauthorized access returns typed errors with consistent HTTP status mapping and
structured observability events.

---

# Middleware

Dartvel supports middleware for both pages and backend functions.

```dart
@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.tenant, DVMiddlewares.rateLimitCheckout])
@DVPage()
Widget checkoutPage(BuildContext context) {}

@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.csrf, DVMiddlewares.idempotency])
@DVBackendFunction()
Future<Order> createOrder(CreateOrderInput input) async {}
```

Middleware can be global, route/page scoped, layout scoped,
backend-function scoped, model scoped, or storage scoped. Middleware order is
deterministic and generated at build time.

Built-ins:
- auth and policy enforcement
- tenant resolution
- CORS and preflight handling
- CSRF validation
- rate limiting and throttling
- request logging and tracing context
- security headers and CSP
- body limits and upload limits
- compression
- locale detection
- idempotency keys
- cache tags and revalidation hints
- feature flags and experiments
- maintenance mode

Page middleware:
- runs before route activation
- can redirect, block, preload data, set SEO context, or defer route bundles
- supports generated loading/error states
- must not force eager imports of deferred `DVPage`s

Backend middleware:
- runs in the Rust runtime around generated Dart function calls
- receives typed request metadata and typed function metadata
- can short-circuit with typed responses
- must propagate trace IDs, tenant IDs, auth IDs, and idempotency IDs

Middleware must be typed and generated. Unsupported middleware configuration
fails validation during `dartvel build`.

---

# Authentication

Like Firebase, WorkOS and Clerk.

```dart
DV.Auth.currentUser // Nullable, of type DVUser?
```

```dart
DV.Auth.signInWithEmailAndPassword()

DV.Auth.signInWithProvider() // Google, Facebook, Apple, etc.

DV.Auth.signInWithRawOAuth()

DV.Auth.signInWithPasskey() // Triggers the passkey flow for the OS or browser, with safe fallback

DV.Auth.signInWithBiometrics() // Triggers the default biometric flow for the platform, safe fallbac or failure, can be configured. has specific alternatives like DV.Auth.signInWithFingerprint() or DV.Auth.signInWithFaceRecognition()

DV.Auth.signInWithWeb3()

DV.Auth.signOut()

DV.Auth.signUp()

// etc.
// We'll also have prebuilt pages for each one. Just Make the first letter uppercase for the class name, and add `Page`, e.g `DV.Auth.SignInWithEmailAndPasswordPage(). Has inbuilt navigation slugs e.g `.navigateToPage(.signInWithEmailAndPasswordPage)` with the Page suffix too, can be overridden.
```

Providers

* Email
* Google
* Apple
* GitHub
* Gitlab
* Bitbucket
* Microsoft
* Magic Links
* OTP
* LDAP
* SAML

---

# Theme

Global

```dart
DV.Theme
```

- Light (fallback if platform doesn't have a supported system theme e.g embedded devices)
- Dark
- System (default)

Dynamic (default) or manual switching

---

# Platform

```dart
DV.Platform.*
```

Provides:
- Platform detection (DV.Platform.currentPlatform (enum))
- Screen size (DV.Platform.screen.size)
- Safe areas (DV.Platform.screen.safeAreaBounds)
- Breakpoints (DV.Platform.screen.breakPoints)
- Orientation (DV.Platform.deviceOrientation)
- Window (DV.Platform.Window) - Window bounds, properties and functionalities for the app/site. Web uses browser APIs; native platforms use generated FFI/JNI bindings where supported.
- Device type (DV.Platform.type (enum, e.g mobile, desktop, laptop, desktopOrLaptop, tablet, embeddedDisplay, watch, circularWatch, squareWatch, embeddedWithoutDisplay))
- Screen shape (DV.Platform.screen.shape (enum e.g square, rectangle, verticalRectangle, horizontalRectangle, custom))
- Full-screen and kiosk display control:
  - `DV.Platform.display.enterFullscreen()` // Where the platform supports it.
  - `DV.Platform.display.exitFullscreen()`
  - `DV.Platform.display.enableKiosk()` // enters fullscreen and enables kiosk-specific controls and configurable exit protection
  - `DV.Platform.display.disableKiosk()`
  - `DV.Platform.display.isFullscreen`
  - `DV.Platform.display.isKiosk` // .isFullscreen() will still return true so .isKiosk() checks if we're specifically in kiosk mode
  - Native implementations must be generated through FFI/ffigen or JNI/jnigen
    bindings named `display.enterFullscreen`, `display.exitFullscreen`,
    `display.enableKiosk`, and `display.disableKiosk`. Dartvel must not use
    Flutter platform channels for these APIs.

Native APIs, including:
- Android (DV.Platform.isAndroid)
- iOS (DV.Platform.isIOS)
- Windows (DV.Platform.isWindows)
- Linux (DV.Platform.isLinux)
- SONY E-Linux (DV.Platform.isSonyELinux)
- macOS (DV.Platform.isMacOS)
- Web (DV.Platform.isWeb)
- Fuchsia (DV.Platform.isFuchsia)
- Tizen (DV.Platform.isTizen)
- webOS (DV.Platform.isWebOS)
- Amazon (DV.Platform.isAmazon)
- TVs (DV.Platform.isTV, DV.Platform.isAndroidTV, DV.Platform.isAppleTV)
- Watches (DV.Platform.isWatch)
- Foldables (DV.Platform.isFoldable, DV.Platform.isDualFold, DV.Platform.isTriFold)
- Native APIs, Expo-style. (DV.Platform.*)
- Camera (DV.Platform.Camera)
- Media and Files (DV.Platform.FileStorage, proxy to DV.FileStorage)
- Location (DV.Platform.Location and DV.Location proxy)
- Bluetooth (DV.Platform.Bluetooth and DV.Bluetooth proxy)
- NFC (DV.Platform.NFC and DV.NFC proxy)
- Clipboard (DV.Platform.Clipboard, and DV.Clipboard proxy)
- Share (DV.Platform.Share or DV.Share proxy)
- Notifications (DV.Platform.Notifications and DV.Notifications proxy)
- Sensors (DV.Platform.Sensors and DV.Sensors proxy)
- Biometrics (DV.Platform.Biometrics and DV.Biometrics proxy)
- Deep Links (DV.Platform.DeepLinking and DV.DeepLinking proxy)
- Haptics (DV.Platform.Haptics and DV.Haptics proxy)
- Contacts (DV.Platform.Contacts and DV.Contacts proxy)
- Browser extension detection:
  - `DV.Platform.isChromiumExtension`
  - `DV.Platform.isFirefoxExtension`
- Browser extension APIs:
  - `DV.Platform.browserExtension.getManifest()`
  - `DV.Platform.browserExtension.sendMessage(...)`
  - `DV.Platform.browserExtension.tabsCreate(...)`
- Permissions, managed centrally through `pubspec.yaml`. (DV.Platform.*)

All under DV.Platform.*

Browser extension storage is not exposed through `DV.Platform.browserExtension`
to avoid duplicating storage APIs. Use `DV.FileStorage.*` for Chromium and
Firefox extension local storage behavior, with `DV.BlobStorage.*` as an alias.

---


# Database

Supports

* PostgreSQL
* MySQL
* SQLite
* MongoDB
* Turso
* ClickHouse
* BigQuery

Automatic migrations.
Automatic CRUD.
Automatic relationships.
Automatic model sync.

Local development database:
- SQLite is built in as the default zero-config local database
- WAL mode is enabled where supported
- generated migrations work the same locally and in production
- tests can use in-memory SQLite
- local queues/cache/session storage can share SQLite when configured

This is inspired by Bun's built-in SQLite approach: the local database should be
fast, available by default, and require no separate service for common
development and test workflows.

---

# APIs

Generated automatically.

- RPC
- REST
- GraphQL
- OpenAPI and Swagger documentation

No manual endpoint creation, but available if needed.

---

# Model Sync and Presence

Dartvel does not expose a separate `DV.Realtime` namespace. Do not add one.
Model sync and presence are generated capabilities built from models, signals,
and queues, not a separate realtime facade.

- model sync
- collection sync
- generated model subscriptions
- presence generated from authenticated model/session state
- collaborative editing through generated model operations
- reactive models
- WebSockets/SSE transport under the generated layer
- pub/sub rooms and topics as implementation details
- heartbeat and reconnect policies
- backpressure-aware streams
- horizontal fanout through Redis/Valkey, NATS, Kafka, or provider adapters
- no public `DV.Realtime`, `DVRealtime`, `@DVRealtime`, or realtime-specific
  namespace; generated clients expose model-aware APIs instead

```dart
final user = await User.find(id);
final userSignal = user.signal(context);

await user.sync();
await User.watch((users) {
  context.signal(users);
});
```

---

# Mail and Notifications

Dartvel provides an application notification layer, not just low-level device
notification APIs.

```dart
await DV.Notifications.mail.send(
  DVMailMessage(
    from: DVMailAddress('support@example.com'),
    to: [DVMailAddress(user.email)],
    subject: 'Welcome',
    text: 'Thanks for joining',
  ),
);

await DV.Notifications.send(
  user.id,
  DVNotificationMessage(
    title: 'Order shipped',
    body: 'Your order is on the way',
    channels: [
      DVNotificationChannel.email,
      DVNotificationChannel.push,
      DVNotificationChannel.inApp,
    ],
  ),
);
```

Mail:
- typed `DVMailMessage`, `DVMailAddress`, attachments, headers, tags, and
  priority
- templates for text, HTML, and Markdown
- localized templates
- queued sending by default
- provider adapters for SMTP, SES, SendGrid, Mailgun, Postmark, Resend, and
  local/test
- delivery receipts and bounce/complaint webhooks as typed backend functions
- per-tenant sender identities and DKIM/SPF validation checks

Channels:
- email
- in-app
- database notifications
- push
- web push fallback
- SMS
- model sync

Push providers:
- Firebase Cloud Messaging for Android and supported Flutter targets
- APNS for Apple platforms
- Web Push for browsers and browser extensions
- Windows notification platform
- macOS notification platform
- Linux desktop notification portals where available
- Amazon/Tizen/webOS notification capabilities where available
- local/test provider

Runtime behavior:
- `DV.Notifications.send(...)` chooses channels from user preferences,
  notification defaults, and provider availability. Push is preferred where
  available.
- Push delivery falls back to Web Push when a browser/web target cannot use a
  native push provider.
- In-app notifications are model sync signals plus durable inbox records.
- Notification delivery is queued and retryable.
- Provider failures emit observability events and can fall back to secondary
  providers.
- Notification permissions are declared in `pubspec.yaml` and validated at
  build time.
- The `Notification` class exists as a DVModel.

Native push registration and delivery adapters must use generated FFI/ffigen or
JNI/jnigen bindings where native code is required. Browser push uses generated
web bindings. Dartvel must not use Flutter platform channels for these APIs.

Notification features:
- user notification preferences
- quiet hours
- templates
- localization
- delivery receipts
- retries
- queued delivery
- provider fallback
- unsubscribe management
- notification inboxes
- topic subscriptions
- device token registration
- token rotation and revocation
- per-channel rate limits
- tenant-aware branding

---

# File Storage

Unified API, supports:

- S3 (And s3 compatible, e.g MiniIO)
- Cloudflare R2
- Azure Blob
- Google Cloud Storage
- Local
- In-memory blobs (zram if supported, or raw blobs)

`DV.FileStorage.*`

```dart
await DV.FileStorage.put("avatar.png", bytes);
final bytes = await DV.FileStorage.get("avatar.png");
await DV.FileStorage.delete("avatar.png");
```

Streams:
```dart
await DV.FileStorage.putStream("avatar.png", bytesStream);
final bytesStream = await DV.FileStorage.getStream("avatar.png");
```

Alias:
`DV.BlobStorage.*`
Just proxies to DV.FileStorage


---


# Cache

Unified cache layer.

- In-Memory
- Memcache
- Redis (Or Valkey)
- Distributed cache

Cache invalidation and revalidation are first-class:

```dart
await DV.Cache.set('users:list', users, const Duration(minutes: 5));
DV.Cache.tag('users:list', ['users']);
DV.Cache.revalidateTag('users');
```

Caches are per client by default and automatically prefixed by Dartvel.
Permissioned global helpers such as `DV.Cache.globalSet`,
`DV.Cache.globalGet`, `DV.Cache.globalTag`, and
`DV.Cache.globalRevalidateTag` use the backend/global cache when configured.

Supports:
- model query cache
- backend function cache
- page/data cache
- route cache
- cache tags
- stale-while-revalidate
- tenant-aware cache keys
- cache locks
- stampede protection
- generated invalidation from model writes

Rules:
- Cache keys are strongly typed where generated from models/functions.
- Model writes emit invalidation signals for affected model, relation, tenant,
  and custom tags.
- Backend functions can opt into caching with annotations or generated config.
- Page data cache must respect auth, tenant, locale, and policy context.
- Stale-while-revalidate returns stale data only when the policy/auth/tenant
  scope still matches.
- Cache locks prevent stampedes around expensive model queries and backend
  functions.
- Distributed providers must implement atomic compare-and-set or explicit
  lock APIs before Dartvel enables stampede protection.

CLI:

```bash
dartvel cache clear
dartvel cache revalidate users
dartvel cache inspect users:list
```

---

# Multi-tenancy

- Enabled by default
- Shared database or Schema per tenant or Database per tenant
- Automatic tenant resolution
- Automatic filtering

```dart
DV.currentTenant // alias for DV.Tenants.currentTenant
```

---

# SEO

Global defaults

```yaml
dartvel:
  seo:
```

Per-page SEO is provided by generated/class page metadata and applied by the
generated router through `DartvelSeo`.

Supports:
- OpenGraph
- Twitter
- Structured data and content schema
- Meta tags

---

# PWA

- Enabled by default.

Automatic:
* Manifest
* Service Worker
* Offline support
* Install prompts
* Icons
* Background sync
* Permission handling
* Web capabilities where supported, exposed through `DV.Platform`

---

# OTA Updates

Dartvel uses Shorebird for Flutter OTA updates.

```bash
dartvel updates release
dartvel updates patch
dartvel updates rollback
```

Runtime surface:

```dart
final update = await DV.Updates.check();
if (update.available) {
  await DV.Updates.apply();
}

// also: DV.Updates.lockVersion(), DV.Updates.skipImmediateNextVersion(), DV.Updates.rollback()
```

Runtime update checks/apply/rollback use generated bindings named
`updates.check`, `updates.apply`, and `updates.rollback`. Native update
integration must use Shorebird-compatible generated bindings through
FFI/ffigen or JNI/jnigen where native glue is needed. Dartvel must not use
Flutter platform channels for OTA APIs.

Supports:
- channels
- staged rollouts
- forced update prompts
- minimum supported app versions
- rollback
- update health checks
- release notes
- environment targeting
- CI integration
- patch provenance metadata
- crash/health rollback gates
- tenant or cohort targeting where allowed by the store/runtime
- offline update state reporting
- generated update UI primitives built from `DVBox` and `DVText`

Server-side code is versioned separately from client OTA patches. A release/tag
must still create a matching backup branch.

Release safety:
- `dartvel updates patch` refuses to run from a dirty worktree unless
  `--allow-dirty` is passed.
- every OTA patch records the Git commit SHA, Dartvel version, Flutter version,
  Shorebird version, and target channel
- release/tag publishing must create the matching backup branch before or
  immediately after the tag/release is pushed
- if the intended tag already exists, Dartvel increments the patch version and
  creates a new tag/release/backup branch instead of reusing the old name

---

# AI

First-class.

Providers:
- OpenAI
- Claude
- Gemini
- OpenRouter
- Llama/Ollama

Features
- Chat
- Embeddings
- Agents
- MCP
- Transcription
- Structured outputs
- AI-native diagnostics
- AI project context
- Function and tool calling with `@DVAITool(description: ...)`. Tools are
  explicit opt-in by default; ordinary `@DVBackendFunction` functions are not
  exposed as AI tools unless a project-level config enables that behavior.

Tool generation:
- `dartvel build` and `dartvel routes` generate
  `lib/dartvel_client/ai_tools.g.dart`.
- Apps import only `package:dartvel_client/dartvel_client.dart`; the generated
  barrel exports `dartvelAITools`.
- `dartvelAITools` is a typed `List<DVAIToolEntry>` containing the tool name,
  description, source import URI, and file path.
- Projects may set `dartvel.ai.exposeBackendFunctionsAsTools: true` in
  `pubspec.yaml` to expose backend functions as tools. Add `@DVAIHidden()` to
  a backend function that must remain private under that mode.

Tool calls:
```dart
DV.AI.registerTool('sumLedger', (input) {
  final left = input['left'];
  final right = input['right'];
  if (left is! DVJsonNumber || right is! DVJsonNumber) {
    throw ArgumentError('sumLedger requires numeric left and right.');
  }
  return DVJsonNumber(left.value + right.value);
});

final result = await DV.AI.callTool('sumLedger', const {
  'left': DVJsonNumber(2),
  'right': DVJsonNumber(3),
});
```

Tool handlers use `DVJsonObject` and `DVJsonValue` (`DVJsonString`,
`DVJsonNumber`, `DVJsonBool`, `DVJsonList`, `DVJsonMap`, `DVJsonNull`) rather
than loose dynamic maps. The same metadata can map to platform equivalents such
as Android App Functions while remaining available to Dartvel-native AI and
WebMCP.

Structured outputs, transcription, and agents use the same typed JSON model:
```dart
final structured = await DV.AI.structuredOutput(
  'Summarize this ledger',
  const <String, DVJsonValue>{'summary': DVJsonString('string')},
);

final transcript = await DV.AI.transcribe(
  audioBytes,
  mimeType: 'audio/mpeg',
  language: 'en',
);

final agentResult = await DV.AI.runAgent(
  const DVAIAgentRequest(
    goal: 'Reconcile the ledger',
    context: <String, DVJsonValue>{
      'left': DVJsonNumber(4),
      'right': DVJsonNumber(6),
    },
    tools: <String>['sumLedger'],
  ),
);
```

`DVAIAdapter` providers implement chat, embeddings, typed structured output,
transcription, and agent execution. The local adapter provides deterministic
testable behavior so tests do not pass through ignored or empty AI paths.

---

# Monitoring and Observability

Inspired by:
- Laravel Nightwatch
- Hasura
- Vercel
- OpenTelemetry

Built in:
- Logs
- Metrics
- Traces
- Profiling
- Performance analysis
- Error reporting
- Structured diagnostics and fix-recommendations
- Structured, AI-readable logs

Application logging uses the discoverable `DV.ObservabilityAndLogging` service
and the shorter autocomplete-friendly `DV.log` shortcut:

```dart
await DV.log(
  "Checkout completed",
  {"orderId": order.id},
);

await DV.ObservabilityAndLogging.event(
  "checkout_completed",
  {"orderId": order.id},
);
```

---

# Testing

Dartvel has a first-class testing layer.

```bash
dartvel test
dartvel test e2e
dartvel test golden
dartvel test golden --update-goldens
```

Built-ins:
- generated model factories
- database refresh/migrations for tests
- fake auth users
- fake queues/jobs
- fake mail and notifications
- fake storage/cache
- fake AI providers
- backend function tests
- page tests
- golden UI tests
- browser/device E2E tests
- accessibility assertions
- generated test fixtures for models, forms, and policies

```dart
DV.Test.resetQueues();
DV.Test.resetSignals();
DV.Test.resetPolicies();
```

Test conventions:
- unit tests live next to Dart source or under `test/`
- page/widget tests use generated page wrappers, not annotated functions
  directly
- backend function tests call typed generated clients and direct handlers
- generated model factories use exact model types
- fake providers must be explicit: fake auth, fake queue, fake mail, fake push,
  fake storage, fake AI, fake native bindings
- no test should pass because a platform feature is silently ignored
- unsupported targets either use explicit fakes or fail validation

Generated helpers:

```dart
final user = UserFactory().admin().create();
await DV.Test.asUser(user, () async {
  await DV.Auth.authorize(user, DVPolicyAction.view, dashboard);
});
```

CI:
- `dartvel test` runs fast unit/framework tests
- `dartvel test e2e` runs browser/device tests
- `dartvel test native` validates generated FFI/JNI bindings for selected
  targets
- `dartvel test accessibility` runs generated semantics checks
- `dartvel test release` runs the pre-release gate used before tags/releases
- `dartvel test --watch` reruns affected tests on file changes
- `dartvel test golden --update-goldens` refreshes approved golden snapshots
- test sharding and per-file isolation are available in CI
- snapshots and golden tests are first-class

Like Bun's built-in test runner, Dartvel testing should be fast, integrated,
watchable, and require minimal extra setup. Unlike Bun, Dartvel must cover
Flutter widgets, generated backend functions, native bindings, and full-stack
app flows.

---

# Search

Dartvel should provide a generated search abstraction for models and content.

Providers:
- PostgreSQL full-text
- SQLite FTS
- Meilisearch
- Algolia
- OpenSearch/Elasticsearch

```dart
final results = await User.Search.query('ada');
```

Search integrates with queues, model lifecycle signals, tenant scoping, and
authorization policies.

Generated behavior:
- `@DVSearchable()` on model properties generates typed index documents.
- model lifecycle signals enqueue index, update, and delete jobs.
- search results preserve model types and policy filters.
- tenant, locale, and soft-delete filters are applied automatically.
- ranking, facets, highlighting, typo tolerance, and synonyms are configured in
  `pubspec.yaml`.

```dart
@DVModel(searchable: true)
class User (@DVSearchable String name);

final page = await User.Search.query(
  'ada',
  facets: User.SearchFacets(role: ['admin']),
);
```

Search providers are explicit and typed. Small applications and tests can use
the concrete local provider; production applications should configure a
database or hosted search adapter. An unconfigured generated search facade
throws a `StateError` instead of silently returning an empty result:

```dart
User.Search.useProvider(
  DVInMemorySearchProvider<User, UserSearchFacets>(
    records: users,
    document: (user) => '${user.name} ${user.role}',
    facetMatcher: (user, facets) =>
        facets == null || facets.role == null || facets.role!.contains(user.role),
  ),
);
```

No provider may return rows the current user cannot access. If the provider
cannot enforce policy filters directly, Dartvel post-filters and records the
extra cost in observability metrics.

---

# Billing

Dartvel should include an optional billing layer for SaaS/mobile apps.

Providers:
- Stripe
- Paddle
- app-store purchases where supported
- Play Billing where supported

Features:
- subscriptions
- invoices
- usage-based billing
- entitlements
- trials
- webhooks as typed backend functions

Generated behavior:
- billing customers link to authenticated users and tenants
- plans, prices, entitlements, and usage meters are typed config
- checkout/session creation is a typed backend function
- webhooks are generated backend functions with signature validation
- entitlement checks integrate with policies and generated UI guards
- app-store and Play Billing purchases use generated native bindings through
  FFI/ffigen or JNI/jnigen where native glue is required

```dart
await DV.Billing.checkout(
  plan: BillingPlan.pro,
  customer: user,
);

if (await DV.Billing.hasEntitlement(user, Entitlement.analytics)) {
  return AnalyticsDashboard();
}
```

Certain models can be recorded as billable:
```dart
@DVModel(billable: true, nativePrice: 100)
Book(@DVSearchable String title);
```

Native prices use the `nativeCurrency` setting under the `dartvel:` pubspec
key. Localization can auto-convert prices, and conversion rates can be
overridden.

---

# Internationalization and Localization

Qt treats internationalization as a core app concern; Dartvel should too.

Features:
- typed translation keys
- generated locale files
- route locale negotiation
- pluralization
- date/number/currency formatting
- right-to-left layout support
- per-tenant locale defaults
- notification/mail template localization
- SEO alternate locale tags

Generated API:

```dart
class AppText {
  static const settingsTitle = DVTranslationKey('settings.title');
  static const inboxCount = DVTranslationKey('inbox.count');
}

DV.I18n.load(const DVTranslationCatalog(
  locale: LocaleTag.enUS,
  messages: <DVTranslationKey, String>{
    AppText.settingsTitle: 'Settings',
  },
  plurals: <DVTranslationKey, DVPluralForms>{
    AppText.inboxCount: DVPluralForms(
      one: '{count} message',
      other: '{count} messages',
    ),
  },
));

DVText(DV.I18n.t(AppText.settingsTitle)); // or `DVText(DV.I18n.translate(AppText.settingsTitle));` full alias
DVText(DV.I18n.plural(AppText.inboxCount, 3));
DV.I18n.formatCurrency(12.5, code: 'USD');

context.locale.set(LocaleTag.enUS);
```

Rules:
- all generated strings use typed keys
- missing translations fail build in strict mode
- page routes can use path, query, subdomain, or header locale strategies
- forms and validation messages localize automatically
- generated mail/notification templates localize with the same key system
- right-to-left layout flips spacing, alignment, icons, and navigation affordances
  where appropriate
- numbers, dates, currencies, and relative times are locale-aware
- SEO generates canonical and alternate locale metadata

---

# Accessibility

Dartvel-generated UI must preserve Flutter semantics and add generated checks for:
- semantic labels
- keyboard navigation
- focus order
- screen-reader landmarks
- high contrast
- reduced motion
- minimum tap targets
- table/list accessibility

Generated forms, tables, pages, and auth screens must be accessible by default.

Runtime and tooling:
- `dartvel test accessibility` checks generated pages, forms, tables, and common
  components
- generated controls expose labels, hints, roles, states, and validation errors
- generated tables support keyboard navigation, focus restoration, row/column
  announcements, and screen-reader summaries
- motion modifiers respect platform reduced-motion settings
- color modifiers can be checked for contrast in CI
- kiosk/embedded targets support switch control and hardware-key navigation
- accessibility regressions fail the release gate unless explicitly waived with
  a documented reason

Runtime API:
```dart
DVBox(DVText('Submit')).modifier(
  const DVModifier()
      .semanticLabel('Submit order')
      .semanticHint('Sends the order for processing')
      .semanticButton()
      .minimumTapTarget(),
);

final contrast = DV.Accessibility.contrast(
  foreground: Colors.black,
  background: Colors.white,
);

final target = DV.Accessibility.tapTarget(size: const Size(44, 48));
final report = DV.Accessibility.report([contrast, target]);
DV.Accessibility.useReducedMotion(true);
```

`DV.Accessibility` returns typed checks (`DVContrastCheck`,
`DVTappableTargetCheck`, `DVAccessibilityReport`) so CI and release gates can
fail on exact accessibility regressions instead of relying on ignored warnings.

---

# Desktop, Embedded, and Qt-Critical Capabilities

Qt is strong on desktop, embedded, and device-creation workflows. Dartvel should
cover the same categories while keeping Flutter as the renderer.

Desktop:
- native menus
- tray/status icons
- global shortcuts
- multi-window apps
- window state persistence
- file associations
- drag and drop
- clipboard and selection integration
- printing
- system dialogs

Desktop APIs live under `DV.Platform.*` and generated app services:

```dart
await DV.Platform.Window.setTitle('Dartvel Admin');
await DV.Platform.Window.persistState('main');
await DV.Platform.Window.restoreState('main');
await DV.Platform.Tray.show(icon: 'assets/tray.png');
await DV.Platform.Tray.show(
  icon: 'assets/tray.png',
  tooltip: 'Dartvel',
  menu: const <DVTrayMenuItem>[
    DVTrayMenuItem(id: 'open', label: 'Open'),
  ],
);
await DV.Platform.Menus.setApplicationMenu(
  const DVApplicationMenu(<DVMenuItem>[
    DVMenuItem(
      id: 'file',
      label: 'File',
      children: <DVMenuItem>[
        DVMenuItem(id: 'quit', label: 'Quit', shortcut: 'Ctrl+Q'),
      ],
    ),
  ]),
);
await DV.Platform.Shortcuts.register(
  const DVGlobalShortcut(id: 'quick-open', accelerator: 'Ctrl+K'),
);
```

Desktop APIs are backed by generated native bindings registered under
`window.*`, `tray.*`, `menus.*`, and `shortcuts.*`; they must fail if the
binding is missing or rejects the request.

Embedded/device creation:
- kiosk mode
- fullscreen mode
- boot-to-app packaging
- hardware capability manifests
- watchdog/health restart hooks
- offline-first local storage
- serial/USB/Bluetooth/NFC device APIs
- deterministic startup profiling
- startup watchdogs
- crash-safe local queues
- device fleet provisioning
- remote diagnostics
- update channels for kiosk/device fleets

Runtime API:
```dart
final manifest = await DV.Platform.device.capabilityManifest();
final health = await DV.Platform.device.health();

await DV.Platform.device.armWatchdog(
  timeout: const Duration(seconds: 10),
  reason: 'startup',
);
await DV.Platform.device.heartbeat();

final provisioning = await DV.Platform.device.provision(
  const DVFleetProvisioningRequest(
    deviceId: 'kiosk-1',
    fleetId: 'storefront',
    labels: <String, String>{'zone': 'front'},
  ),
);

final diagnostics = await DV.Platform.device.collectDiagnostics();
```

Embedded APIs use generated native bindings registered under
`device.capabilityManifest`, `device.health`, `device.watchdog.*`,
`device.fleet.*`, and `device.diagnostics.*`. They return typed Dartvel models
such as `DVHardwareCapabilityManifest`, `DVDeviceHealth`,
`DVDeviceProvisioningResult`, and `DVDeviceDiagnosticsBundle`.

Qt-style meta-object capabilities:
- generated metadata for pages, models, backend functions, jobs, signals, and
  policies
- runtime discovery for tools/devtools
- typed dynamic property maps for generated admin/devtools views
- signal/slot-like typed connection surfaces through `context.signal`,
  generated model signals, jobs, and model sync

Generated metadata powers:
- devtools inspectors
- AI project context
- generated docs
- admin dashboards
- route explorers
- schema browsers
- permission audits
- native capability manifests

Native implementations still follow the Dartvel rule: generated FFI/ffigen or
JNI/jnigen only, no Flutter platform channels.

---

# Admin, Devtools, and Scaffolding

Other batteries-included frameworks provide strong admin and tooling surfaces.
Dartvel should generate them from the same metadata used by models, pages,
jobs, signals, policies, and middleware.

```bash
dartvel devtools
dartvel admin generate
```

Generated admin/devtools include:
- model CRUD admin
- queue/job dashboard
- failed job retry/discard controls
- mail/notification outbox
- policy and permission explorer
- route/page explorer
- cache/tag explorer
- model sync channel inspector
- search index status
- billing/customer/entitlement views
- logs/metrics/traces views

Admin UI must use `DVBox`, `DVText`, generated model components, and Dartvel
modifiers. It must not introduce new primitive widgets.

---

# Data Import, Export, and Reporting

Dartvel should include typed bulk data workflows:
- CSV, JSON, NDJSON, and Excel import/export
- generated import validation
- row-level error reports
- resumable imports through queues
- tenant-aware exports
- policy-filtered exports
- scheduled reports
- streamed large exports

```dart
await User.Import.csv(file);
await User.Import.resumableCsv(file, queue: 'imports', chunkSize: 500);
await User.Import.ndjson(lines);
await User.Import.resumableNdjson(lines, queue: 'imports', chunkSize: 500);
await User.Import.excel(tabSeparatedRows);
final export = User.Export.ndjson(users);
final spreadsheet = User.Export.excel(users);
final tenantExport = User.Export.csv(
  users,
  options: DVExportOptions<User>(
    tenantId: 'tenant_123',
    policyFilter: (user) => user.active,
    chunkSize: 1000,
  ),
);
await for (final chunk in User.Export.streamNdjson(users)) {
  await DV.Storage.put(chunk.fileName, chunk.bytes);
}
final report = await Order.Report.monthly(...);
final scheduled = Order.Report.scheduleMonthly(cron: '0 8 1 * *');
await Order.Report.dispatchMonthly(
  cron: '0 8 1 * *',
  queue: 'reports',
);
```

Exports use storage providers and queued jobs for large datasets.
Resumable imports dispatch typed `DVImportChunk` payloads through `DVQueues`, so
workers can process large files without holding the entire import in one request.
Tenant-aware and policy-filtered exports use `DVExportOptions<T>`, attach export
metadata to `DVExportResult`, and can stream CSV/NDJSON chunks for large files.
Scheduled reports generate typed `DVScheduledReport` payloads and dispatch them
through `DVQueues`, so cron workers can execute report generation with durable
retry, queue selection, priority, and report-period metadata.

---

# Deployment

## Monolith
Single native backend binary. x64 linux by default, can be targeted optionally.

## Function mode
Each backend function can be deployed independently.

Targets:
- AWS Lambda
- Cloud Run
- Containers
- Edge runtimes
- Fly.io
- Railway
- Bare metal

---

# CLI

Dartvel should feel like a single fast toolkit, not a bag of unrelated tools.
Bun is a useful benchmark here: runtime, package/task runner, shell, test
runner, and bundler are discoverable through one executable.

Project

```bash
dartvel new
dartvel init
dartvel doctor
# etc.
```

Development

```bash
dartvel dev
dartvel watch
dartvel hotreload
```

Database

```bash
dartvel db migrate
dartvel db push
dartvel db pull
dartvel db seed
```

Generate

```bash
dartvel generate page
dartvel generate model
dartvel generate backend-function
dartvel generate form
```

Build

```bash
dartvel build
```

Deploy

```bash
dartvel deploy
dartvel deploy lambda
dartvel deploy edge
```

Observability

```bash
dartvel logs
dartvel traces
dartvel metrics
```

AI

```bash
dartvel ai context
dartvel ai doctor
dartvel ai generate
```

## Shell and Task Runner

Dartvel should provide a cross-platform shell/task surface inspired by Bun's
`Bun.$`, but typed for Dart and safe by default.

```dart
final result = await DV.$('git status --short');
final files = await DV.$('ls **/*.dart').text();
final safe = await const DVShell().runCommand(
  DVShellCommand('git')
      .arg('status')
      .arg('--short')
      .env('CI', 'true'),
);
```

```bash
dartvel task clean
dartvel task build:web
dartvel sh "flutter doctor"
dartvel sh "dart list.dart *.dart | dart filter.dart > report.txt 2> errors.txt"
```

Tasks can live in `pubspec.yaml`, `.dartvel.sh`, or `.dartvel.dart`.

```yaml
dartvel:
  tasks:
    build:web: flutter build web
```

```bash
# .dartvel.sh
task clean: dart run build_runner clean
build:web: flutter build web
```

```dart
// .dartvel.dart
// task check: dart test
void main(List<String> args) {}
```

Requirements:
- cross-platform on Windows, Linux, and macOS
- safe argument escaping by default
- typed stdout/stderr/exit-code result
- glob support
- environment variable helpers
- pipes and redirection
- script files such as `.dartvel.sh` or `.dartvel.dart`
- no shell injection when interpolating values
- works in CI and generated release scripts

## Build and Bundle Tooling

Dartvel should own the full build orchestration:
- route/client generation
- backend generation
- Flutter build
- Rust runtime build
- native binding generation
- web assets and PWA generation
- single-command production bundles where target platforms allow it
- build graph caching
- affected-file incremental rebuilds

`dartvel build` should include `dartvel routes` automatically. Users should not
need to remember separate generation commands for normal workflows.

---

# Package Structure

```dart
package:dartvel/dartvel.dart

package:dartvel/dartvel_core.dart
package:dartvel/dartvel_ui.dart
package:dartvel/dartvel_backend.dart
package:dartvel/dartvel_database.dart
package:dartvel/dartvel_auth.dart
package:dartvel/dartvel_ai.dart
package:dartvel/dartvel_platform.dart
package:dartvel/dartvel_storage.dart
package:dartvel/dartvel_cli.dart
package:dartvel/dartvel_observability.dart
package:dartvel/dartvel_rust_bindings.dart
```

All Dartvel code is valid on all platforms. Native integrations must use FFI/ffigen or JNI/jnigen bindings; unsupported platform targets fail during validation or are excluded from the generated artifact rather than silently ignoring work.

Dartvel also supports rust bindings for writing rust code in dart using constructs
e.g

```dart
var a = DV.Rust.Int(1);
var b = DV.Rust.Int(2);
var c = a + b;
```

Automatically handles FFI on native native platforms and WASM on web

---


# Home Widgets

Allows building home-screen and lock-screen widgets on supported platforms,
such as Jetpack Glance or Remote Compose on Android, using `@DVHomeWidget` on
any widget, whether Flutter-native, `DVClassWidget`, or `DVFunctionalWidget`.
Unsupported targets are excluded from the compiled binary/artifact or fail
validation based on project configuration.

```dart
@DVHomeWidget()
@DVFunctionalWidget()
Widget StepCounterWidget(
    BuildContext context
) {...}
```

Home widgets act like `DVPage` and support the same shell properties. They can
launch and navigate to pages within the app, and a page can navigate back to the
widget. Dartvel generates a page that centers the widget content.

Shares widget tree and state with the parent app

---

# CSRF Protection
In:
- Backend functions
- Forms
- Model queries
- DB queries
- Model sync events


---


# The Vision

Developers write only:
* Pages
* Models
* Backend Functions
* UI
* Business Logic

Dartvel automatically provides:
* Routing
* State management
* CRUD
* Validation
* Forms
* Authentication
* APIs
* Model sync
* Database access
* Storage
* Native device APIs
* Scheduling
* Multi-tenancy
* SEO
* PWA
* Observability
* AI tooling
* Deployment
* Infrastructure
* Native rust bindings

while Flutter remains the rendering engine and Dart remains the only language developers write.

# App store publishing

Automatically handles publishing and distribution for all platforms, similar in
scope to EAS Deploy and Firebase App Distribution.

# Takeaway

- user says I want to build an app for X
- Dartvel already has it covered
