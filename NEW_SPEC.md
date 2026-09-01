# New Spec v2

# Dartvel — The Complete Vision, to be implemented

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

DVBox.wrapLine([Tag("Flutter"), Tag("Dart"), Tag("Rust")])

DVBox.stack([Background(), Avatar(), Badge()])

DVBox.horizontalScrollable([StoryCard(a), StoryCard(b), StoryCard(c)])

DVBox.list([...]).scrollable()
```

Explicit `DVBox.wrapLine([...])` or `.wrapLine()` is a layout mode for
collections. It is not the removed automatic wrapper behavior for arbitrary
widget composition. `wrap` remains a compatibility alias, but new code should
use `wrapLine`.

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
layout method such as `.list()`, `.grid(...)`, `.wrapLine()`, `.masonry()`,
or `.horizontalScrollable()` must be called.

Builder collections support the same layout modes:

```dart
DVBox.builder(posts, (post) => PostCard(post)).grid(columns: 2)

DVBox.builder(tags, (tag) => TagChip(tag)).wrapLine()

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

Annotated models are private generation inputs. `@DVModel() class _User ...`
generates the public `User` class in `dartvel_client`, and application code
imports that generated public class from `dartvel_client/dartvel_client.dart`.
The generated public class owns the ergonomic static model-aware API:

```dart
User.Form(user);
User.List(users, builder: (user) => UserCard(user));
User.Table(users, columns: 3);
User.Page(users);
```

The annotated `_User` class is not exported and should not be referenced by
application code. Do not generate or call extra top-level model component
wrappers; generated public model methods are the only model component API.

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

Pages are private generation inputs. The currently supported page input shape
is a private expression-bodied function:

```dart
@DVPage()
Widget _usersPage(
    BuildContext context
) => DVBox.list([
    DVText('Users'),
]);
```

If a page needs a larger body while full body lowering is still in progress,
wrap that body in a public helper and keep the annotated input expression-bodied:

```dart
@DVPage()
@pragma('vm:entry-point')
Widget _usersPage(BuildContext context) => buildUsersPage(context);

Widget buildUsersPage(BuildContext context) {
    return DVBox.list([
        DVText('Users'),
    ]);
}
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
Widget _settingsPage(BuildContext context) {
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

## Routing engine

The generated router targets **`go_router`** as its runtime engine. This is a
deliberate, load-bearing choice, not an incidental dependency:

- Type safety and code generation are Dartvel's responsibility, not the
  router's. Dartvel emits the strongly typed `DVPages`/`DVRoutes` surface, so
  `go_router`'s own (stringly-typed by default) API is never exposed to
  application code, and a second code generator such as `auto_route`'s
  `build_runner` pass is intentionally avoided — it would compete with Dartvel's
  generator over the same concern.
- Dartvel is URL-first. Static web generation, web-server rendering, and
  `sitemap.xml` all require that every route map to exactly one canonical URL.
  `go_router`'s URL-as-source-of-truth model is the correct foundation for that;
  deep links resolve to paths directly with no separate mapping layer.

`go_router` is an implementation detail behind the generated navigation surface.
Application code must use `DV.Navigation`, `DVPages`, and `.navigateToPage(...)`
rather than importing or calling `go_router` directly, so the engine can evolve
(for example, generating onto `StatefulShellRoute` for nested-stack navigation)
without breaking application code.

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
DV.global<Cart>(Cart());
```

Retrieve

```dart
DV.global<Cart>(); // To retrieve, don't pass a value, just the type.
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
Normal `signal()` tracks by parent widget or context. `DV.global` tracks by
data type, so each type must be unique. Setting the same type replaces the
previous value for that type.

---

# Models

```dart
@DVModel()
class _User(
    String name,
    String email,
);
```

Annotated models are private schema inputs by validation: `@DVModel() class
_User ...` generates the public `User` type. Generated static members such as
`User.Form(...)`, `User.List(...)`, `User.Table(...)`, and `User.Page(...)`
belong to that generated public class.

Pages, functional widgets, backend functions, jobs, AI tools, and models are
private generation inputs. This is a hard generator rule:
`@DVModel() class User`, `@DVPage() Widget usersPage(...)`,
`@DVFunctionalWidget() Widget button(...)`, and
`@DVBackendFunction() Future<User> getUser(...)` must fail with clear rename
messages that instruct the developer to rename them to `_User`, `_usersPage`,
`_button`, and `_getUser`. Application
code references only the generated public API from
`dartvel_client/dartvel_client.dart`, such as `UsersPage`, `Button`,
`getUser`, and `User`.

Until full body lowering is implemented, private `@DVPage`,
`@DVFunctionalWidget`, and `@DVBackendFunction` function inputs must use
expression bodies so Dartvel can emit readable generated public code without
source-local `part` files:

```dart
@DVPage()
Widget _usersPage(BuildContext context) => DVBox.list([DVText('Users')]);

@DVFunctionalWidget()
Widget _featureCard(String title) => DVBox(DVText(title));

@DVBackendFunction()
Future<String> _getEcho(String input) async => 'Echo: $input';
```

Generated page and backend scaffolds use that shape. Block-bodied private page,
functional widget, and backend function inputs fail until full body lowering is
implemented. Public annotated functional widget inputs always fail.

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
Future<User> _getUser(String id) async => User.find(id);
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
Stream<Message> _messages() => Message.stream();
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
class _SendWelcomeEmail(String userId)

@DVJob.handler()
Future<void> _handleSendWelcomeEmail(SendWelcomeEmail job) async =>
    DV.Notifications.send(...);

await DV.Jobs.dispatch(SendWelcomeEmail(user.id));

// Or with the queue, priority, attempts and backoff the annotation declares,
// which plain DV.Jobs.dispatch cannot know:
await SendWelcomeEmail(userId: user.id).dispatch();
```

Job metadata is grouped under the job annotation: the handler is
`@DVJob.handler()`, not a standalone `@DVJobHandler`. That also leaves the
`DVJobHandler` typedef — the runtime handler function type — meaning what it
already means. Like private page and backend-function inputs, a private handler
must use an expression body until generated body lowering exists.

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
`signal(context, ...)`, reactive models, `DV.global`, and generated model
sync.
Dartvel should not introduce separate signal/event annotations for the common
case.

```dart
final counter = context.signal(0);
counter.value++;

final userSignal = user.signal(context);
final cart = context.global<Cart>();
```

Derived values come from operating on signals — there is no separate computed
construct:

```dart
final a = context.signal(1);
final b = context.signal(2);
final c = a + b;
```

`c` is a signal. Adding, subtracting, comparing or concatenating signals
produces a signal that tracks its sources and changes when they change, so a
derived value is simply a value and there is nothing extra to reach for.

Because the result is itself a signal, derivations compose:

```dart
final total = (price * quantity) + shipping;
final inStock = stock > 0;
final canShip = agreed & paid;
final fullName = firstName + ' ' + lastName;
```

An operand may be another signal or a plain value. Reactivity rides on the
sources: reading a source inside the derivation subscribes the element exactly
as it would in a build method, so a derived signal stays current without
subscription bookkeeping of its own.

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
Widget _adminPage(BuildContext context) => AdminDashboard();

@DVBackendFunction(policy: DVPolicies.refund)
Future<Refund> _refundOrder(Order order) async => Refund.create(order);
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
Widget _checkoutPage(BuildContext context) => Checkout.Page();

@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.csrf, DVMiddlewares.idempotency])
@DVBackendFunction()
Future<Order> _createOrder(CreateOrderInput input) async => Order.create(input);
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

Authentication is provider-backed. Applications configure a typed
`DVAuthProvider` implementation for their identity service; calling an auth
method without a configured provider fails with a clear configuration error.
`DVLocalAuthProvider` is available only as an explicit development/test
adapter and must not be mistaken for production authentication.

Providers

* Email
* Google
* Apple
* GitHub
* Gitlab
* Bitbucket
* Microsoft
* Magic Links (`DVAuthTokens.issueMagicLink` / `redeemMagicLink`)
* OTP (`DVAuthTokens.issueOtp` / `redeemOtp`)
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
  - These four remain valid as sugar over `DV.Platform.display.kiosk`. The
    policy they obey — the two scopes, session reset, exit protection and what
    each target actually enforces — is specified in
    [Kiosk Mode](#kiosk-mode); a runtime call never changes policy, only
    state.

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
- presence generated from authenticated model/session state, via
  `DVPresence` — channel membership keyed on identity rather than
  connection, tenant-scoped, expiring on silence because a crashed
  client never sends a departure
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
- MCP, both directions: `DVMcpServer` exposes the registered AI tools to an
  MCP client, and `DVMcpClient.adoptTools()` registers an external
  server's tools so `DV.AI` calls them like its own
- Transcription
- Structured outputs
- AI-native diagnostics
- AI project context
- Function and tool calling with `@DVAITool(description: ...)`. Tools are
  explicit opt-in by default; ordinary `@DVBackendFunction` functions are not
  exposed as AI tools unless a project-level config enables that behavior.

Tool generation:
- `dartvel build` and `dartvel routes` generate typed AI tool metadata inside
  the Dartvel client output.
- Apps import only `package:dartvel_client/dartvel_client.dart`; the generated
  barrel exports `dartvelAITools`. Do not import generated sibling files
  directly from application code.
- `dartvelAITools` is a typed `List<DVAIToolEntry>` containing the tool name,
  description, source import URI, and file path.
- Projects may set `dartvel.ai.exposeBackendFunctionsAsTools: true` in
  `pubspec.yaml` to expose backend functions as tools. Add `@DVAIHidden()` to
  a backend function that must remain private under that mode.

Framework tools are a separate registry from application tools, and the
separation is load-bearing rather than tidy:

- `dartvel mcp` serves Dartvel's own tools — the inspectors over the project
  graph, migration planning, doctor, and build validation — to a coding agent
  working on the application.
- `DVMcpServer` serves the application's tools, the ones `DV.AI.registerTool`
  and `@DVAITool` declare, to whatever the application exposes them to.

Framework tools must never enter the process-global tool registry. Application
AI tool exposure is explicit opt-in with `@DVAIHidden()` as the escape, and a
framework surface that let itself be adopted into that registry would make an
agent building the app indistinguishable from an agent the app serves to its
users — one of which can read the project's schema. The same redaction rule
applies to both: a `@DVModel.sensitiveField()` is described, never valued.

Agent-produced code has no privileged path. It passes the same typed
validation as hand-written code and carries the same provenance in source
mappings, so `dartvel inspect generated` can say what produced a given line
regardless of who asked for it.

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
- PostgreSQL full-text (`DVPostgresSearchProvider`)
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
- `@DVModel.searchableField()` on model properties generates typed index documents.
- model lifecycle signals enqueue index, update, and delete jobs.
- search results preserve model types and policy filters.
- tenant, locale, and soft-delete filters are applied automatically.
- ranking, facets, highlighting, typo tolerance, and synonyms are configured in
  `pubspec.yaml`.

```dart
@DVModel(searchable: true)
class _User (@DVModel.searchableField() String name);

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
class _Book(@DVModel.searchableField() String title);
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
- multi-window apps — see [Multi-Window](#multi-window)
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
- kiosk mode and fullscreen mode — specified in [Kiosk Mode](#kiosk-mode),
  which owns the policy, the two scopes, enforcement per target and exit
  protection. They are named here because they are embedded capabilities, not
  restated, so there is one place a rule can be wrong
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

---
# Kiosk Mode

Stability: `Contract` · Status: `Designed`

(The `## Bindings` subsection declares Stability `Draft`; every other
subsection inherits the section labels, per Specification Status.)

Kiosk has two scopes, and everything below applies to both unless a rule says
which:

- **`device`** — the whole device is the kiosk. One application, one display
  or all displays, no windows (`open()` presents in place, `DV-WINDOW-002`).
- **`display`** — one window owns one display in kiosk mode and the
  application keeps ordinary windows on the others. The window kind is
  specified in Multi-Window › Kiosk windows; the policy it obeys is specified
  here.

A kiosk is a device — or a display — that runs one application for whoever
walks up to it: lobby displays, point-of-sale, self-checkout, ticketing,
wayfinding, medical intake, factory HMI, the customer-facing screen beside a
cashier. Kiosk mode is the set of guarantees that make that true — the
application fills the display, cannot be left by the user, restarts if it dies,
forgets each user when they walk away, and can be operated and exited by staff
without a keyboard hanging off the back.

## Kiosk restricts the surface, not the content

Kiosk mode changes what the *device or display* permits — fullscreen, input
confinement, no OS chrome, no escape, no second window on that surface — and
nothing about what the *application* permits. Routes still run their
middleware; policies still apply; tenant and locale resolve normally; a deep
link that would be refused outside kiosk is refused inside it. Nothing in this
section is a security boundary for application data; the Authorization and
Sensitive Model Fields sections are. Kiosk is a boundary for the *user's
ability to leave*.

## Two ways in

**Declared.** Configuration or a device profile sets the policy, and the built
artifact starts in kiosk at boot. This is the production path: boot-to-app on
eLinux images, Android lock-task launchers, Windows assigned access, TV
single-app profiles. There is no window of unlocked UI at startup.

```yaml
dartvel:
  kiosk:
    enabled: true
    scope: device
    home: /welcome
```

In `display` scope, the declaration names the kiosk windows — the route each
shows, the display it owns, the policy it obeys — and they open at boot before
anything else:

```yaml
dartvel:
  kiosk:
    enabled: true
    scope: display
    policies:
      customerDisplay:
        home: /customer-display
        routes: { allow: [/customer-display/**] }
        session: { idleTimeout: 60s, onIdle: reset }
        exit: { method: adminAuth }
    windows:
      customer:
        route: /customer-display
        display: Customer            # a display name from the device profile,
                                     # or primary | secondary | index:N
        policy: customerDisplay
```

Named policies are available to code as `DVKioskPolicies.customerDisplay`, so
a kiosk window opened at runtime (`DV.Window.open(..., kind: kiosk)`) uses a
declared policy rather than an ad-hoc one. There is no policy that is not in
the declaration.

**Runtime, under the declared policy.** `DV.Platform.display.kiosk` (device
scope) and `win.kiosk` (display scope) transition between kiosk and a
supervised *staff mode* for maintenance, configuration and troubleshooting.
Neither can enable kiosk where the policy did not declare it, and neither can
disable kiosk without satisfying the declared exit method. A build with no
kiosk policy has no kiosk runtime: the calls exist, report `DV-KIOSK-005`, and
change nothing.

```dart
DV.Platform.display.kiosk.state       // DVSignal<DVKioskState> — device scope
DV.Platform.display.kiosk.policy      // DVKioskPolicy, read-only
DV.Platform.display.kiosk.enforcement // DVKioskEnforcement — what the device honours

await DV.Platform.display.kiosk.exit(DVKioskExitRequest.pin('4821'));
await DV.Platform.display.kiosk.resume();
await DV.Platform.display.kiosk.resetSession(reason: DVKioskResetReason.idle);

customer.kiosk!.state                 // the same shape, per window — display scope
DV.Window.kiosks                      // DVSignal<List<DVWindow>>

enum DVKioskState { off, active, staffMode, resetting, locked, failed }
```

`enableKiosk()`, `disableKiosk()`, `isKiosk` and `isFullscreen` on
`DV.Platform.display` remain valid as sugar over `kiosk.resume()`,
`kiosk.exit(...)`, and `kiosk.state`. `DV.Kiosk` is the alias per the proxy
pattern. In `display` scope `DV.Platform.display.kiosk` refers to the device,
which is *not* in kiosk; the windows that are appear in `DV.Window.kiosks`.

## Policy

```yaml
dartvel:
  kiosk:
    enabled: true
    scope: device                     # device | display
    home: /welcome                    # attract / idle-return route
    routes:
      allow: [/welcome, /order/**, /help]   # default: all application routes
      external: block                 # block | allowlist
      externalAllow: []
    input:
      systemGestures: block           # edge swipes, home, recents, app switch
      hardwareKeys: block             # except accessibility keys, always
      shortcuts: block                # OS and browser shortcuts
      clipboard: disabled
      textSelection: disabled
    session:
      idleTimeout: 90s
      idleWarning: 15s                # countdown route/overlay before reset
      onIdle: reset                   # reset | home | none
      clearOnReset: [signals, forms, sharedStore, auth, clientCache]
    display:
      fullscreen: true
      hideCursor: auto                # auto (touch-only) | always | never
      screenDim: 5m                   # burn-in / power; 0 disables
      wake: onTouch
    windows: false                    # device scope: no windows (alias of
                                      # windowing.kiosk.allowWindows); in display
                                      # scope, `windows:` is the kiosk-window map
    notifications: suppress           # system-level; in-app inbox still works
    updates:
      apply: maintenanceWindow        # immediate | maintenanceWindow | staffMode
      window: "02:00-04:00"
    exit:
      method: pin                     # none | pin | gesture+pin | adminAuth | remote | hardwareCombo
      pin: secret:KIOSK_EXIT_PIN      # a DV.Secrets reference, never a value
      gesture: cornerTaps(5)
      maxAttempts: 5
      lockoutFor: 10m
      audit: true
```

In `display` scope the same keys live under `policies.<name>`, with two
differences the scope forces: `session.clearOnReset` may not contain `auth` or
an un-namespaced `sharedStore` (see Sessions), and `input.hardwareKeys`
defaults to `passthrough` (see Enforcement).

Device profiles may set or override any of this and are where displays get
their names (`displays: { Customer: { index: 1 } }`). A runtime `exit()` never
changes policy, only state. `dartvel doctor` validates that the declared
policy is enforceable on each configured target and that every declared kiosk
window's display exists in the profile.

## Sessions

A kiosk serves strangers in sequence, so **a session is anonymous and
disposable by default**. The idle reset — and any explicit `resetSession()` —
clears everything listed in `clearOnReset` and then navigates to `home`. After
reset, nothing a previous user typed, viewed, or authenticated is reachable
from that kiosk.

What a reset may clear depends on scope, and the difference is the point:

| `clearOnReset` entry | `device` scope | `display` scope |
|---|---|---|
| `signals` | all page and global signals | the kiosk window's page signals |
| `forms` | all | the kiosk window's |
| `sharedStore` | the whole store | keys under `kiosk.<name>.*` only |
| `auth` | `DV.Auth.signOut()` | **not permitted** — the session is the staff window's |
| `clientCache` | all | entries tagged to the kiosk window's routes |

A display-scoped policy that lists `auth` or an un-namespaced `sharedStore`
fails validation: a customer display timing out must not sign the cashier out.

- `idleWarning` presents a generated countdown (built from `DVBox`/`DVText`,
  restyleable) so a slow user is not cut off without notice.
- `onIdle: home` returns to the attract route without clearing state — for
  informational displays with no user data. `dartvel analyze` flags it when
  models with `sensitiveField` are reachable from allowed routes
  (`DV-KIOSK-009`).
- Reset is a transaction over local state: partial resets are not observable.
- Reset emits `DV.lifecycle.kiosk` transitions (`resetting → active`) — per
  window in display scope — and an observability event with the reason, never
  with user data.
- State a kiosk window shows *from* the staff window (the cart on a customer
  display) travels through model sync or shared keys the staff window writes
  under `kiosk.<name>.*`. A reset clears the kiosk side; the staff window's
  next write repopulates it. The staff window never has to know a reset
  happened.

## Exit protection

Exit is the one thing kiosk must make hard, and the one thing staff must be
able to do. The methods are a closed set:

| Method | Meaning | Where it degrades |
|---|---|---|
| `none` | device management owns exit; the app never exits itself | — |
| `pin` | numeric secret from `DV.Secrets` | never |
| `gesture+pin` | hidden gesture reveals the pin prompt | touchless devices → `pin` via hardware combo |
| `adminAuth` | `DV.Auth` session passing `DVPolicyAction.exitKiosk` | offline device → `pin` fallback if configured |
| `remote` | fleet command via `device.fleet.*` | disconnected device → cannot exit remotely |
| `hardwareCombo` | declared key combination | devices without keys |

Rules:

- Attempts are rate-limited (`maxAttempts`, `lockoutFor`); the lockout is
  `DVKioskState.locked`, visible on the kiosk and reported.
- Every attempt, success or failure, is an audit event with actor (if any),
  method, and outcome. The pin value never appears anywhere.
- The pin is a `DV.Secrets` reference resolved on device from the secure store;
  it is not in `pubspec.yaml`, not in the bundle, and rotates through the
  ordinary rotation hook.
- Staff mode is a state, not an unlock: the application is still running, still
  fullscreen by default, with the policy's restrictions lifted and a visible
  staff banner. `resume()` returns to kiosk and resets the session.
- In `display` scope, `adminAuth` is the natural method and needs no prompt on
  the kiosk display: the request comes from a peer window whose authenticated
  session passes `DVPolicyAction.exitKiosk`. The customer display never shows
  a pin pad unless its policy says `pin`.
- Deep links, notifications and OS intents do not constitute an exit path:
  under kiosk they are honoured only within `routes.allow`.

## Health and fleet

Kiosk composes with the embedded capabilities rather than duplicating them:

- `autostart` and `restartOnFailure` are honoured by the target's supervisor
  (systemd unit on eLinux images, lock-task launcher on Android, assigned
  access on Windows).
- The watchdog is armed on boot with `reason: 'startup'` and heartbeat runs
  from the application lifecycle; a missed heartbeat restarts the application,
  and a restart loop (more than `n` in `m` minutes) enters a generated
  diagnostics screen instead of looping forever (`DV-KIOSK-008`).
- Fleet commands: `kiosk.reload`, `kiosk.exit`, `kiosk.lock`, `kiosk.staffMode`,
  `kiosk.resetSession`, `kiosk.screenshot` (policy-gated; never during a
  visible user session). In display scope each command addresses a named kiosk
  window.
- OTA: `updates.apply: maintenanceWindow` defers `DV.Updates.apply()` to the
  window; `staffMode` applies only when staff are present; `immediate` is for
  displays with no user session. A forced update outside the window shows the
  generated update UI and resets the session first.

## Enforcement

What a device can actually enforce is a capability, reported honestly:

```dart
final e = DV.Platform.display.kiosk.enforcement;   // or customer.kiosk!.enforcement
e.fullscreen;        // can hold fullscreen
e.escapeBlocked;     // user cannot reach the OS from the app
e.systemGestures;    // edge/home/recents intercepted
e.hardwareKeys;      // power/volume/home intercepted
e.singleApp;         // OS prevents other apps from surfacing
e.strength;          // DVKioskStrength: device | supervised | fullscreenOnly
e.inputScope;        // DVKioskInputScope: device | display — display scope only
```

`inputScope` exists because a keyboard is a device and a touchscreen is a
display. Touch on an owned display is confinable per display wherever the OS
reports which display a touch came from; pointer input is confinable while the
kiosk window is focused; hardware keys and OS shortcuts are device-wide or
nothing. A display-scoped policy that blocks `hardwareKeys` therefore either
blocks them for the whole device — which the staff terminal will notice — or
not at all, and `enforcement.inputScope` says which (`DV-KIOSK-010`). The
honest default for display scope is `input.hardwareKeys: passthrough` with
touch and pointer confinement.

| Target | Mechanism | Strength | Label |
|---|---|---|---|
| eLinux (Sony) image / bundle | DRM/EGL fullscreen, no compositor, systemd supervision | `device` | `Supported` |
| Android (device owner / DPC) | Lock Task Mode, launcher replacement | `device` | `Supported` |
| Android (no device owner) | screen pinning | `supervised` | `Supported with limitations`¹ |
| iPadOS / iOS | Single App Mode via MDM; Guided Access | `device` / `supervised` | `Supported with limitations`² |
| Windows | Assigned Access / shell replacement; fullscreen + key hooks | `device` / `supervised` | `Supported with limitations`³ |
| macOS | fullscreen + presentation options | `fullscreenOnly` | `Supported with limitations` |
| Linux desktop | fullscreen; compositor-dependent gesture blocking | `supervised` | `Supported with limitations` |
| Tizen / webOS | single-app TV model; launcher/boot config | `device` | `Supported with limitations`⁴ |
| Web / PWA | Fullscreen, Keyboard Lock and Pointer Lock APIs | `fullscreenOnly` | `Supported with limitations`⁵ |
| Browser extension | not applicable | — | `Unsupported` |
| Watch | not applicable | — | `Unsupported` |
| Terminal (`-cli`/`-tui`) | full-screen alternate buffer; escape is the shell's | `fullscreenOnly` | `Supported with limitations` |

Display scope adds a requirement rather than a row: it needs
`capability.displayKiosk`, which requires multi-window and addressable
displays — the Windows, macOS and Linux rows (labelled per the Multi-Window
matrix) and eLinux multi-head configurations, where per-output DRM makes it the
strongest case. Everywhere else `scope: display` degrades to the in-place
fullscreen page described in Multi-Window › Kiosk windows.

¹ Screen pinning can be exited by the user with a known gesture; the app
reports `strength: supervised` and `DV-KIOSK-001`.
² iOS cannot enter Single App Mode programmatically; the declared policy is
realized by MDM, and the runtime API can only detect it. Guided Access is
user-managed and reported as `supervised`.
³ Assigned Access requires a provisioned account; without it the app is
fullscreen with key hooks and reports `supervised`.
⁴ TV platforms are single-app by construction, but exit is the remote's home
button and is not interceptable on consumer sets; kiosk on TVs means "boot to
app and return to it", reported as such.
⁵ The browser reserves `Esc` and cannot be prevented from leaving fullscreen;
`fullscreenOnly` is the honest label. Dedicated browser kiosk modes (launch
flags, ChromeOS kiosk apps) raise it to `device` when detected.

`Unsupported` appears here where it does not in the windowing matrix because
kiosk *is* the capability — there is no "present it another way" fallback for
locking a watch. The API still exists on those targets and reports
`DV-KIOSK-004`.

## Diagnostics

```dart
enum DVKioskDegradation {
  none, enforcementReduced, exitWeaker, noPolicy, unsupportedTarget,
  routeBlocked, bindingMissing, lockedOut, inputScopeWidened,
}
```

| Code | Reason | Level |
|---|---|---|
| `DV-KIOSK-001` | requested enforcement reduced (e.g. `device` → `supervised`) | `warning` at boot, once |
| `DV-KIOSK-002` | exit method degraded (e.g. `gesture+pin` → `pin` on touchless device) | `info` |
| `DV-KIOSK-003` | exit attempt failed; lockout after `maxAttempts` | `info`, audited |
| `DV-KIOSK-004` | kiosk requested on a target without kiosk capability | `info` |
| `DV-KIOSK-005` | runtime kiosk call with no declared policy | `warning` |
| `DV-KIOSK-006` | route outside `routes.allow` requested and blocked | `debug` |
| `DV-KIOSK-007` | native kiosk binding missing or refused | `error` |
| `DV-KIOSK-008` | restart loop detected; diagnostics screen shown | `error` |
| `DV-KIOSK-009` | `onIdle: home` with sensitive fields reachable from allowed routes | `warning` (analyze) |
| `DV-KIOSK-010` | display-scoped input confinement is device-wide on this platform | `warning` at boot, once |

`DV-KIOSK-001` and `010` fire once per boot, not per interaction: reduced
enforcement is a deployment fact the operator needs to know, not a stream.
`dartvel doctor --target <t>` reports the same findings before the build ships.

## Accessibility under kiosk

Kiosk blocks *escape*, never *access*. Switch control, screen readers,
hardware-key navigation and high-contrast/reduced-motion settings remain
available; `input.hardwareKeys: block` explicitly exempts accessibility keys
and the platform's accessibility shortcut. A generated accessibility toggle
may be placed on the attract route. `dartvel test accessibility` runs against
kiosk builds with the policy applied, and an accessibility regression under
kiosk fails the release gate like any other.

## Interaction with other sections

- **Multi-Window**: in `device` scope `kiosk.windows: false` is canonical and
  `open()` presents in place (`DV-WINDOW-002`); `windowing.kiosk.allowWindows`
  remains a compatibility alias. In `display` scope the kiosk window is a
  window kind that owns its display, specified under Multi-Window › Kiosk
  windows; this section owns the policy it obeys.
- **OTA**: governed by `kiosk.updates`; forced updates reset the session first.
- **Notifications**: system notifications are suppressed on the kiosk surface;
  in-app inbox and model-sync delivery continue.
- **Secrets**: the exit pin is a device-resolved secret; kiosk shared keys are
  encrypted with the application key as elsewhere.
- **Studio**: a kiosk panel shows fleet state, enforcement per device and per
  kiosk window, exit audit, session-reset counts, and lets an authorized
  operator issue fleet commands. Screenshots are policy-gated and never taken
  during a user session.
- **i18n**: the attract route may rotate locales; a session reset returns the
  kiosk to the profile's default locale.

## Configuration precedence

`deviceProfiles.<profile>.kiosk` overrides `dartvel.kiosk`; a `--device-profile`
build selects the profile. Runtime never changes policy. `dartvel inspect kiosk
--json` prints the effective policy per target and per kiosk window, with the
source of each value.

## Bindings

Stability: `Draft` · Status: `Designed`

Generated FFI/ffigen or JNI/jnigen bindings only, per the standing rule:

- `display.enterFullscreen`, `display.exitFullscreen` (existing)
- `display.kiosk.enable`, `display.kiosk.disable`, `display.kiosk.state`
  (the existing `display.enableKiosk` / `display.disableKiosk` names remain as
  aliases) — device scope
- `window.kiosk.enable`, `window.kiosk.disable`, `window.kiosk.state` —
  display scope, together with `window.display.assign`, `window.pin` and
  `window.unpin` from Multi-Window
- `kiosk.input.lock`, `kiosk.input.unlock` — gestures, keys, shortcuts, with a
  display argument where the platform can scope them
- `kiosk.enforcement.query`
- `kiosk.supervisor.register` — autostart / restart integration
- android: `kiosk.lockTask.start`, `kiosk.lockTask.stop`
- windows: `kiosk.assignedAccess.query`
- web: generated bindings over Fullscreen, Keyboard Lock and Pointer Lock
- fleet: `device.fleet.command` carries the `kiosk.*` commands above

A missing or refusing binding fails typed (`DV-KIOSK-007`), never silently.

## Testing

```dart
DV.Test.fakeKiosk(
  policy: DVKioskPolicies.customerDisplay,
  enforcement: DVKioskEnforcement.supervised(inputScope: DVKioskInputScope.device),
);

await customer.kiosk!.exit(DVKioskExitRequest.pin('0000'));
expect(customer.kiosk!.state.value, DVKioskState.active);       // wrong pin
expect(DV.Test.kioskAuditEvents.last.outcome, DVKioskExitOutcome.rejected);
```

Idle reset is testable with a fake clock; the e2e suite runs the attract →
session → idle → reset loop on eLinux and Android runners, and the
two-display staff/customer scenario on desktop runners with virtual displays;
the accessibility suite runs with the policy applied.

## Performance contracts

Measured: boot-to-kiosk-ready time (device) and boot-to-kiosk-window-ready
(display), idle-reset duration, exit-prompt latency after gesture, watchdog
heartbeat jitter, restart-loop detection time. Diagnostics: a reset that
exceeds its budget (user-visible dead time), an attract route that allocates
per frame (burn-in displays run for years), an allowed route that navigates
externally, and a kiosk-window reset that touched state outside its namespace.

## Security

- Exit protection is rate-limited and audited; the pin is a device-resolved
  secret and never logged.
- Deep links, intents and notifications cannot leave `routes.allow`.
- Session reset is transactional; in device scope it clears auth, so a
  walk-away user's identity is unreachable afterwards; in display scope it
  cannot reach the staff session at all.
- Remote commands require fleet authentication; `kiosk.exit` remotely is
  audited with the issuing operator.
- Enforcement strength and input scope are reported, never overstated: an
  application on a `fullscreenOnly` target must not be described to an
  operator as locked.

## Deliberately absent

- **Device-owner / MDM provisioning.** Dartvel integrates with Lock Task,
  Assigned Access, Single App Mode and TV launchers; it does not replace the
  device management that provisions them. `dartvel doctor` says which is
  required.
- **A custom Android launcher.** Lock Task under a device owner is the
  supported mechanism; shipping a launcher is a product, not a framework
  feature.
- **A promise of screen-capture prevention on web.** The browser does not
  offer it; the spec does not claim it.
- **Kiosk as a runtime toggle without a declared policy.** See Two ways in.
- **Inline per-window policies.** `DVWindowKiosk.policy` names a declared
  policy, so every kiosk the device can enter is visible in
  `dartvel inspect kiosk`.
- **A kiosk manager on `DV.Window`.** Display-scoped kiosk is `win.kiosk` on a
  window and `DV.Window.kiosks` as a list; there is no `DV.Window.kiosk`
  manager object, for the same reason there is no `DVWindowManager`.

# Terminal Rendering

A Dartvel application can present itself in a terminal instead of a window,
without being a different application. The same widgets, the same pages, the
same generated model pages and Studio documents — drawn as cells rather than
pixels.

The point is not novelty. It is that a powerful application can live on a
powerful machine and be driven from anywhere: a server with no desktop, a
container, a phone over SSH. The application does not change; only where its
frames land does.

## Two ways in, and they are different

**A terminal-only build.** `dartvel build linux-cli` produces a binary that
renders in a terminal. It contains **no GUI backend at all** — not a window
that stays closed, not a fallback, nothing. It resolves the way
`sony-elinux-iso` already does: a suffix naming a base platform and a
presentation, not a new platform.

```
dartvel build linux-cli      dartvel build linux-tui
dartvel build windows-cli    dartvel build windows-tui
dartvel build macos-cli      dartvel build macos-tui
dartvel build fuchsia-cli    dartvel build fuchsia-tui
```

`-tui` and `-cli` are the same target under two names. `-tui` says what it
does; `-cli` says where it runs.

**A dual-mode build**, only when asked for. `dartvel build linux` produces a
GUI binary containing no terminal code. It carries both backends **only** if
the application opts in:

```yaml
dartvel:
  terminal: true
```

## What each build contains

| Build | GUI backend | Terminal backend |
|---|---|---|
| `dartvel build linux` | yes | **no** |
| `dartvel build linux` with `dartvel.terminal: true` | yes | yes |
| `dartvel build linux-cli` / `linux-tui` | **no** | yes |

There is no configuration under which an application gets a backend it did
not ask for. A GUI build without the opt-in is byte-for-byte what it is today;
a terminal build carries no window-server code it would never call.

## Nothing is carried by an application that did not ask

This is a constraint on the implementation, not a preference. A rendering
backend costs binary size for every user who never reaches it, so the
presentation is resolved at **build time** — from the `-cli`/`-tui` suffix or
the `dartvel.terminal` key — and only the backends an application asked for
are linked. The default on every desktop target is GUI alone.

That rules out the obvious shortcut of always shipping both and choosing at
startup. It is simpler, and it makes every application pay for a capability
most of them will never use.

## How a dual-mode application starts

For an application that opted into both, launching from a shell:

1. **GUI by default.** A terminal is where the command was typed, not
   necessarily where the application belongs.
2. **`--tui` starts in the terminal**, skipping the GUI entirely. This is the
   explicit path, and it is the one to reach for over SSH.
3. **No display available, and the application offers both** — a machine with
   no desktop installed, a headless container, a bare SSH session — the
   application says so and offers the alternative rather than choosing for the
   user:

   ```
   No display server is available.
   This app can run in your terminal instead. Continue in TUI mode? [Y/n]
   ```

The prompt exists because both silent answers are wrong. Silently redrawing as
text is indistinguishable from a bug at the moment it happens, and failing
outright wastes a capability the application was built with. Asking costs one
keystroke and is unambiguous.

An application that did **not** opt into terminal rendering has none of this:
no prompt, no flag, no branch. It fails to find a display exactly as it does
today.

## What the application can observe

```dart
DV.Platform.surface            // DVRenderSurface.gui | DVRenderSurface.terminal
DV.Platform.terminal           // null unless surface is terminal
DV.Platform.terminal.size      // columns and rows, as a signal
DV.Platform.terminal.graphics  // DVTerminalGraphics.kitty | .ansi
```

`DV.Platform` stays the stable surface, as it does for every other platform
capability; a terminal is another thing it reports on rather than a namespace
of its own.

`size` is a signal, so a layout responds to a resized terminal through the same
reactive path a resized window uses, not a parallel one.

## What a terminal costs

Stated rather than glossed, because a rendering mode that pretends to be
lossless is worse than one with documented edges:

- **Fidelity depends on the terminal.** Full-quality rendering uses the Kitty
  graphics protocol; where it is unavailable, rendering degrades to ANSI cells,
  which is coarser. Which one is active is reported by
  `DV.Platform.terminal.graphics` rather than guessed at.
- **Frames cost bandwidth over a slow link.** A 60fps animation redrawn across
  SSH is not free the way a local compositor is.
- **Pointer input is whatever the terminal reports**, and some report none.

## Windows in a terminal

`DV.Window.open(...)` is not a special case here. Terminal rendering is a
surface with a particular set of capabilities, and the windowing model already
describes what happens when a surface cannot honour a request: it presents the
route another way and reports why.

In a terminal, `open()` **navigates** — the route is presented as a page, with
`DVWindowPresentation.page` and `DVWindowDegradation.capabilityUnsupported`
(`DV-WINDOW-001`), exactly as on a phone. Application code does not branch on
whether it is in a terminal; it observes the presentation it got, the same way
it already does everywhere else.

### Why not spawn a second terminal

It is the obvious idea and it defeats the purpose. Opening a new terminal
*emulator* window requires a window server — which is the thing terminal
rendering exists to work without. On the machine where this matters most, a
server reached over SSH, there is exactly one pty and nothing to spawn into.

A multiplexer is the one honest exception: where the application is running
under `tmux` or similar, real additional surfaces exist and a window request
could be given one. That is a capability to detect, not to assume, and it is
deliberately left out of the first implementation. A feature that works only
under one multiplexer, and silently degrades everywhere else, is harder to
reason about than one that always navigates.

So the rule is: **navigate, and say so.** If multiplexer surfaces are added
later they raise the presentation from `page` to `window` for applications that
already work either way, because those applications were reading the
presentation rather than assuming it.

### Tab workspaces

`DVTabWorkspace` needs no terminal-specific behaviour. Tabs are a layout, and a
layout renders in cells as readily as in pixels. Tearing a tab out into its own
window degrades the same way `open()` does, and for the same reason.

## The embedder

Terminal rendering is driven by a Dartvel fork of a Flutter terminal embedder,
maintained the way the television and embedded forks are: pinned to the Flutter
version Dartvel ships, patched where upstream is short.

Upstream is a research project and does not need to already do everything —
that is what the fork is for. Producing a distributable binary rather than only
a development run, and whatever else Dartvel requires, is work the fork carries
rather than a reason to wait.
# Multi-Window

Stability: `Contract` · Status: `Designed`

(The `## Bindings` subsection below declares its own labels — Stability
`Draft` — because it tracks a flag-gated upstream surface; every other
subsection inherits the section labels, per Specification Status.)

Desktop-class applications are made of windows. The hard part is not opening
one; it is defining what a window *means* across targets that disagree about
whether windows exist at all.

## A window is a route

Every Dartvel window hosts exactly one route. This is the single decision that
makes one API possible across platforms that implement "another window" in four
unrelated ways:

| Platform family | "Open a window" means | Content addressed by |
|---|---|---|
| Windows / macOS / Linux | native window, same engine | route |
| Web | `window.open('/route')`, separate instance | URL (the route) |
| Android | new task, separate engine | deep link (the route) |
| iPadOS | new `UIScene`, separate root | scene activation URL (the route) |

Dartvel is URL-first — static generation, server rendering and sitemaps already
require every route to map to one canonical URL — so windows inherit that for
free. The route is the serialization of "what this window shows". Anything a
window shows is therefore deep-linkable, restorable after a restart, and
subject to the same middleware, policies, tenant scope and locale as any
navigated page, because it is one. A window with no route is not expressible.

**Identity is the canonical URL.** Route *and* parameters:
`DVPages.order(id: 1)` and `DVPages.order(id: 2)` are two distinct windows;
opening `DVPages.order(id: 1)` twice focuses the existing one. Query
parameters participate in identity only when the page declares them as
identity (`@DVPage(windowIdentity: [...])`); undeclared query parameters are
view state and do not create a second window.

## Surface

`DV.Platform.Window` grows from "the current window" into the window manager,
with `DV.Window` as its alias per the established proxy pattern. There is one
namespace; the existing `setTitle` / `persistState` / `restoreState` members
read as sugar over `DV.Window.current` and remain valid.

```dart
DV.Window.current                  // DVWindow — the window this code runs in
DV.Window.main                     // DVWindow — see "Main window"
DV.Window.all                      // DVSignal<List<DVWindow>>
DV.Window.capability               // DVWindowingCapability
DV.Window.displays                 // DVSignal<List<DVDisplay>> (read-only)
DV.Window.kiosks                   // DVSignal<List<DVWindow>> — windows in kiosk mode
DV.Window.shared                   // DVWindowSharedStore

final win = await DV.Window.open(
  DVPages.orders,
  options: DVWindowOptions(
    size: Size(900, 620),
    constraints: BoxConstraints(minWidth: 480, minHeight: 320),
    title: 'Orders',
    kind: DVWindowKind.regular,      // regular | dialog | popup | tooltip | satellite | kiosk
    owner: null,                     // required for dialog/popup/tooltip/satellite
    modality: DVWindowModality.none, // none | window | application
    duplicate: false,                // true: a second window on the same URL
    display: null,                   // DVDisplayHint — which display, never where on it
    kiosk: null,                     // DVWindowKiosk — kiosk kind only
  ),
);

final class DVDisplay {
  final String id;                 // stable for the display's connection
  final String name;               // from the device profile, else OS-reported
  final Rect bounds;               // logical pixels
  final double devicePixelRatio;
  final bool isPrimary;
  final DVWindow? kioskOwner;      // set while a kiosk window owns this display
}

DVDisplayHint.primary
DVDisplayHint.secondary            // first non-primary, in OS order
DVDisplayHint.byIndex(1)
DVDisplayHint.byId(id)
DVDisplayHint.byName('Customer')   // device profiles name displays; see Kiosk Mode

DV.Window.byRoute(DVPages.orders);   // DVWindow? — existing window for a URL
await DV.Window.closeAll(except: [DV.Window.main]);
```

`DV.Navigation` gains a target rather than a second API:

```dart
DV.Navigation.to(DVPages.orders, window: DVWindowTarget.newWindow);
DV.Navigation.to(DVPages.orders, window: DVWindowTarget.current);   // default
```

### DVWindow

```dart
win.id;              // stable for the window's life; not persisted
win.route;           // DVRoute — what it shows, including parameters
win.kind;            // DVWindowKind
win.owner;           // DVWindow? — null for regular windows
win.lifecycle;       // DVSignal<DVWindowLifecycle>
win.presentation;    // DVWindowPresentation: window | page | dialog | overlay
win.degradation;     // DVWindowDegradation
win.isVirtual;       // presentation != window
win.isMain;
win.display;         // DVSignal<DVDisplay?> — null for virtual windows
win.kiosk;           // DVWindowKiosk? — null unless kind == kiosk

win.size;            // DVSignal<Size>
win.setSize(Size);   // no-op on virtual windows, logged at debug
win.setTitle(String);// maps to page title on virtual windows
win.setFullscreen(bool);
win.minimize(); win.maximize(); win.restore();
await win.close();   // closes the window, or pops the route — same call
```

**There is no `activate()` and no `focus()`.** `open()` opens, focuses and
activates. Bringing an existing window forward is the same verb: opening a URL
a window already shows focuses that window. `DV.Window.byRoute(r)` exists for
*reading* whether a window exists; to bring it forward, open its route. One
verb, idempotent by URL; a deliberate second window says `duplicate: true`.

**Placement is not part of the contract.** There is no `position` and no
`setPosition`. Wayland forbids app-positioned windows, Flutter's windowing API
exposes none, and web, Android and iPadOS delegate placement to the OS. The
only placement input is `DVDisplayHint` — *which display*, never where on it —
and it is best-effort by name.

## Kinds, ownership and modality

| Kind | Meaning | Owner | Fallback presentation |
|---|---|---|---|
| `regular` | top-level peer window | none | pushed page |
| `dialog` | owned, focus-taking | required | modal route |
| `popup` | owned, transient, dismiss on outside interaction | required | overlay |
| `tooltip` | owned, non-interactive, follows anchor | required | overlay |
| `satellite` | owned, non-modal companion (palette, inspector) | required | overlay |
| `kiosk` | owns one display; fullscreen, pinned, exit-protected | none | fullscreen page in the current surface |

- Owned windows close when their owner closes, in reverse open order. An owned
  window cannot outlive its owner; a request with a closed owner fails typed
  (`DV-WINDOW-007`) rather than adopting `main`.
- `modality: window` (default for `dialog`) blocks input to the owner only.
  `modality: application` blocks all windows of the application and is
  honoured only where the OS supports it; elsewhere it degrades to
  `window` and reports `DV-WINDOW-008` at `debug`. Nothing is blocked that the
  platform cannot block — a fake application-modal that leaks input is worse
  than an honest window-modal.
- `popup` and `tooltip` on desktop are the native window kinds the Flutter
  windowing API provides for exactly this purpose, which is why menus and
  tooltips align to the cursor instead of clipping to the parent window.

## Kiosk windows

A kiosk window is a regular window that owns a display and carries a policy it
cannot be argued out of. It is how one application serves a customer-facing
display and a staff terminal at once: the staff window is ordinary; the
customer window is kiosk. It is also how one process drives a signage wall —
one kiosk window per display.

```dart
final customer = await DV.Window.open(
  DVPages.customerDisplay,
  options: DVWindowOptions(
    kind: DVWindowKind.kiosk,
    display: DVDisplayHint.byName('Customer'),
    kiosk: DVWindowKiosk(policy: DVKioskPolicies.customerDisplay),
  ),
);

customer.kiosk!.state;          // DVSignal<DVKioskState>
customer.kiosk!.enforcement;    // what this platform honours for one display
await customer.kiosk!.resetSession();

// From the staff window, already authenticated:
await customer.kiosk!.exit(DVKioskExitRequest.adminAuth());
```

Rules:

- **It owns its display.** `DVDisplay.kioskOwner` is set for the window's
  life. Another window requesting that display is placed on a different one
  and reports `DV-WINDOW-011`. If the display disconnects, the kiosk window
  degrades to a fullscreen page in the current surface (`DV-WINDOW-010`) and
  reclaims the display when it returns — the reclaim is `open()` of the same
  URL, so it is idempotent.
- **It is pinned.** Fullscreen, no move, no resize, no minimize; those requests
  are refused and logged at `debug` (`DV-WINDOW-012`). A user close request is
  refused. The window closes only through `kiosk.exit(...)` satisfying the
  policy's exit method, or through application exit.
- **Its policy is a declared kiosk policy.** `DVWindowKiosk.policy` names a
  policy from `dartvel.kiosk.policies` (see Kiosk Mode); the window inherits
  its `routes`, `input`, `session`, `display`, `notifications` and `exit`
  sections. Input confinement for *one* display is platform-limited — a
  keyboard is a device, not a display — and `enforcement.inputScope` reports
  `display` or `device` rather than implying more than is true.
- **Its session is its own.** A kiosk window's idle reset clears its page
  signals and the shared keys under `kiosk.<name>.*`; it does not sign out the
  application or touch other windows. The staff terminal is unaffected by the
  customer display timing out. (Device-scoped kiosk clears the application
  session; display-scoped never does. See Kiosk Mode › Sessions.)
- **Exit can come from a peer.** `adminAuth` is satisfied by any window whose
  authenticated session passes `DVPolicyAction.exitKiosk`, so staff exit the
  customer display from the terminal they are already signed into. Every exit
  is audited with the actor.
- **It keeps the process alive.** Kiosk windows count as regular windows for
  the exit policy: closing the staff window does not take the signage down.
- **Declared kiosk windows open at boot**, from `dartvel.kiosk.windows`, before
  workspace restore and before `main` presents. They are never part of a
  persisted workspace; a kiosk window comes from policy, not from state.
- **Where no display can be owned** — a phone, a single-display desktop with
  the display already in use, a terminal — `kind: kiosk` degrades like every
  other kind: the route is presented as a fullscreen page and reported. Device
  scope is the right tool for a single-display device; display scope is for
  the second one.

## Main window and process exit

The first window opened is `main`. It is a peer for every purpose except two:

- **Restore anchor.** Workspace restore and deep links with no target land in
  `main`.
- **Exit policy.** `exit: lastWindow` (default on desktop) ends the process
  when the last *regular or kiosk* window closes; owned windows do not count.
  `exit: mainWindow` ends the process when `main` closes; `exit: explicit`
  never exits on window close (tray-resident applications).

If `main` closes under `exit: lastWindow` while other regular windows remain,
the oldest remaining regular window becomes `main`. `DV.Window.main` is a
signal-backed getter so tray and workspace code follows the promotion.

On targets without a process to exit in this sense (web, Android tasks,
iPadOS scenes) the policy is a no-op and is reported once by `dartvel doctor`.

## Lifecycle

```dart
enum DVWindowLifecycle {
  requested, creating, created, ready, active,
  inactive, minimized, maximized, fullscreen,
  closing, closed, failed,
}
```

Lifecycle is a generated read-only enum signal per Lifecycle Signals: the
runtime owns transitions, application code observes. Guarantees:

- `requested → creating → created → ready` occurs exactly once per window.
  `ready` means the route has resolved and the first frame is presented.
- `active` / `inactive` track OS focus. Exactly one window is `active` at a
  time per engine; on separate-engine targets each engine reports its own.
- `minimized` / `maximized` / `fullscreen` are display states entered from
  `active` or `inactive` and return there.
- `closing` is observable and cancellable: a page may register
  `context.window.onCloseRequest(() async => confirmDiscard())`; returning
  `false` returns the window to its prior state. The OS "force close" path
  (process kill) bypasses this and is why the shared store exists.
- `failed` is terminal and only reachable before `ready`; a window that fails
  after `ready` is `closed` with a logged reason.
- Virtual windows run the same states over their route's page lifecycle, so
  observers do not branch on `isVirtual`.

## open() never fails

Where a real window cannot be created, `open()` presents the route the way the
platform can: `regular` becomes a pushed page, `dialog` a modal route, and
`popup`, `tooltip` and `satellite` overlays. The returned `DVWindow` is real
either way, `DV.Window.all` lists virtual windows alongside real ones, and
`close()` pops the route. **Application code never branches on capability.**

Failing is removed; reporting is not. Every fallback carries a stable code, is
written to observability through `DV.log`, and is readable on the window.

```dart
enum DVWindowDegradation {
  none, capabilityUnsupported, kioskLocked, gestureRequired,
  platformRefused, disabledByConfig, ownerClosed, modalityReduced,
  displayUnavailable, displayOwned, pinned,
}
```

| Code | Reason | Level |
|---|---|---|
| `DV-WINDOW-001` | target has no multi-window capability | `debug` |
| `DV-WINDOW-002` | kiosk mode active; the surface stays locked | `info` |
| `DV-WINDOW-003` | web popup blocked — called outside a user gesture | `warning` |
| `DV-WINDOW-004` | platform refused (OS window limit, task creation denied) | `warning` |
| `DV-WINDOW-005` | `windowing.enabled: false` in configuration | `info` |
| `DV-WINDOW-006` | native binding missing or refused the request | `error` |
| `DV-WINDOW-007` | owned window requested with a closed owner | `warning` |
| `DV-WINDOW-008` | application modality reduced to window modality | `debug` |
| `DV-WINDOW-009` | restored route missing, unauthorized, or unresolvable | `info` |
| `DV-WINDOW-010` | kiosk window's display unavailable; presented in place, fullscreen | `warning` at boot, once |
| `DV-WINDOW-011` | window requested on a kiosk-owned display; placed elsewhere | `info` |
| `DV-WINDOW-012` | move/resize/minimize/close refused on a pinned kiosk window | `debug` |
| `DV-WINDOW-013` | `display:` hint matched no connected display; the OS placed the window | `warning` |

Levels are calibrated to whether the developer can act. A phone has no windows
and the fallback is the intended behaviour, so warning on every call would
train people to ignore the channel; a blocked popup and a refused task are
fixable. `dartvel analyze performance` aggregates degradations per call site,
so a site that always degrades is one finding, not a thousand log lines.

`DV-WINDOW-006` is the one `error`: a binding that is present but refuses is a
platform integration defect, not a capability limit, and it must not be dressed
up as graceful degradation. It still degrades — the route is still presented —
but it is reported as the bug it is.

Honest about what degrades: `setSize` and `constraints` are no-ops on a virtual
window and log at `debug`; `setTitle` maps to the page title; opening N windows
on a phone yields N stacked routes. A workspace UI should still read
`capability.multiWindow` when deciding whether to *offer* "open in new window"
— degrading a call is right, advertising a control that surprises is not.
Kiosk degradation is not a security hole: kiosk restricts the surface, not the
content, and the route still faces the same middleware and policies.

## Capability

```dart
final cap = DV.Window.capability;
cap.multiWindow;        // can a second OS-level window exist
cap.sameEngine;         // do windows share one engine (object handover)
cap.tearOut;            // can a tab detach into a window by drag
cap.inPageViews;        // web: in-page multi-view embedding
cap.ownedWindows;       // native popup/tooltip/satellite kinds
cap.applicationModal;   // OS supports app-wide modality
cap.displays;           // more than one display is addressable
cap.displayKiosk;       // a window can own one display in kiosk mode
```

Capability is a snapshot at process start plus a signal for the two things
that change at runtime — `displays` and kiosk state — so a workspace can hide a
"move to display" control the moment the display is unplugged.

## Deep links and external open requests

An OS-level request to open a route — deep link, app link, file association,
`dartvel://` URL, a second launch of a single-instance desktop application —
is delivered to `DV.Window.open(route)` with `DVWindowOptions.external`. It is
therefore idempotent by URL: a link to an order already on screen focuses that
window; a link to a new order opens one (or navigates, on targets without
windows). Middleware and policies run before presentation as for any route.
Single-instance behaviour on desktop is on by default (`singleInstance: true`)
and is what makes "second launch focuses the running app" true.

## Shared window state

Two handover modes, chosen automatically from `capability.sameEngine`:

- **sameEngine** (desktop, web in-page views): the moved content is the same
  Dart object tree, so signals, in-flight requests and scroll positions survive
  by construction.
- **shared** (web `window.open`, Android tasks, iPadOS scenes): the new window
  is a separate engine, so state crosses through a watched store — one writer
  publishes, every other window is notified and its signals update.

`DV.Window.shared` is a typed, watched key-value store scoped to application,
tenant and user. One API on every platform, desktop included:

```dart
await DV.Window.shared.set('workspace.activeTab', DVJsonString(tab.id));
final tabId = DV.Window.shared.signal<DVJsonString>('workspace.activeTab');

// or declared at the signal, with the wiring generated:
final activeTab = context.signal('', shared: 'workspace.activeTab');
```

A store rather than message passing: a message is delivered once, to whoever
is listening at that instant; a window opened five seconds later gets nothing
and crash recovery has nothing to read. A store has no delivery moment — late
joiners read current state on open, and the same bytes that sync a running
window restore a crashed one. This is why there is **no `DV.Window.broadcast`**:
the store publishes state, which a late or restarted window can read; a message
API would publish events, sitting alongside model sync doing a worse version of
its job.

What varies per target is which of the store's two jobs the OS performs:

| Target | Notification | Persistence |
|---|---|---|
| Windows / macOS / Linux | in-process — signals | platform key-store-backed file via `DV.FileStorage` |
| Android | `OnSharedPreferenceChangeListener` | `SharedPreferences` |
| iPadOS | KVO | `NSUserDefaults` |
| Web | `storage` event | `localStorage` |

Rules:

- **Keys are namespaced.** `workspace.*` is reserved for `DVTabWorkspace`;
  application keys must not start with `dv.` or `workspace.`. A violating key
  is a build error where static, a typed runtime failure otherwise.
- **Encryption is Dartvel's, not the store's.** Values are encrypted with the
  application key (Secrets and Environments) before the write, so the backing
  store is a dumb byte sink on every target — one code path, one threat model.
  Encryption is whole-store, never per key.
- **Writes are coalesced.** A signal changing per frame must not write per
  frame; shared writes are debounced and batched per flush (`debounceMs`).
- **Last write wins, per key.** Keys are the conflict unit. State that needs
  merge semantics is model state — use a model.
- **Large values spill.** Anything over `spillThresholdKb` goes to
  `DV.FileStorage` with an encrypted pointer left behind; the pointer write is
  the notification.
- **The store is not for model data.** Models converge through model sync,
  which applies auth, tenant filters and policy checks before delivery;
  duplicating rows into the store would bypass all three. The store holds view
  state: active tab, tab order, layout, scroll offsets, drafts.
- **`DV.Secrets` values never reach it.** A backend-scoped secret on a client
  is a `DV-SECRETS-001` violation regardless of encryption; that stays a build
  error.
- **Entries are ephemeral by contract**, session-scoped and swept by age
  (`sweepAfter`). A crashed application leaves a readable store — that is the
  recovery feature — but a stale one is collected rather than kept.
- **An undecryptable store is discarded, not fatal**, and reported through
  `DV.log`.

Genuinely separate processes — a second *instance*, which `singleInstance`
prevents by default — fall outside preference listeners and degrade to polling
at `pollMs`, reported once by `dartvel doctor`.

## Persistence and restore

```dart
await DV.Window.persistWorkspace('default');
await DV.Window.restoreWorkspace('default');
```

A persisted workspace is the ordered list of regular windows — each as
canonical URL, kind, size, display hint and title — plus the `workspace.*`
shared keys. It is tenant- and user-scoped like all stored state. Owned windows
are never persisted; they are derived from their owners' pages.

Kiosk windows are excluded from persistence by contract; they open from
`dartvel.kiosk.windows` before anything else.

`restoreOnLaunch: true` restores `default` at boot, before `main` presents,
so the user sees their workspace rather than a flash of the home route.
Restore is defensive: a URL whose route no longer exists, no longer resolves,
or is no longer authorized for the current user is skipped and reported
(`DV-WINDOW-009`, `info`) rather than opening an error page in a window.
If nothing restores, `main` opens the home route.

## Inheritance and scope

A window inherits **theme, locale, tenant, auth session and module scope** from
the application; none is per-window. The one per-window surface is `title`.
This is a rule, not a limitation to be lifted: a per-window theme would be the
first thing a workspace's shared store could not represent, and a per-window
tenant would be a data-isolation hole with a friendly name.

**Shortcuts** are focus-scoped by default: a page's shortcuts fire only when
its window is `active`. `DV.Platform.Shortcuts.register` (global shortcuts)
stays global and fires regardless of focus, as its name says.

**Accessibility**: each real window is its own semantics tree and announces
its title on `ready` and on focus gain, matching platform convention. Virtual
windows announce as route changes. `dartvel test accessibility` covers both.

## Platform matrix

| Target | Multi-window | Mechanism | Handover | Owned kinds | Label |
|---|---|---|---|---|---|
| Windows | yes | Flutter windowing (`RegularWindow`, FFI) | sameEngine | yes | `Experimental`¹ |
| macOS | yes | Flutter windowing | sameEngine | yes | `Experimental`¹ |
| Linux | yes | Flutter windowing; Wayland: never placement | sameEngine | yes | `Experimental`¹ |
| Web | yes | `window.open(route)`; in-page multi-view | shared / sameEngine² | overlay only | `Supported with limitations` |
| Browser extension | in-page only | multi-view tier; `tabsCreate` for routes | sameEngine² | overlay only | `Supported with limitations` |
| Android | yes | task-per-window via engine groups | shared | no | `Supported with limitations` |
| iPadOS | yes | `UIScene` | shared | no | `Supported with limitations` |
| iOS (iPhone) | no | navigation fallback | — | overlay only | `Supported with limitations`³ |
| Fuchsia | plausible | view-based compositor | sameEngine | tbd | `Experimental` |
| Tizen / webOS | no | single-fullscreen app model | — | overlay only | `Supported with limitations`³ |
| eLinux / embedded | no by policy | kiosk stays locked | — | overlay only | `Supported with limitations`³ |
| Watch | no | navigation fallback | — | overlay only | `Supported with limitations`³ |
| Terminal (`-cli`/`-tui`) | no | navigation fallback; multiplexer surfaces deferred | — | overlay only | `Supported with limitations`³ |

¹ **Upstream dependency, stated plainly.** Flutter's desktop windowing API
(`RegularWindow`, `RegularWindowController`, `WindowRegistry`, window-backed
dialogs and tooltips) ships behind `flutter config --enable-windowing` and
still uses framework-internal imports on the application side. Dartvel is the
churn absorber: the generated bindings under `window.*` are the only code
touching that surface, so an upstream rename is a Dartvel point release rather
than an application change. Out-of-tree embedders (the television and
embedded forks) implement windowing by overriding `createWindowingOwner`, which
is how a future TV or Fuchsia row could turn on without touching this
contract. Desktop rows stay `Experimental` for as long as the flag exists.

² Web is two tiers by design: `window.open` for OS-level windows, and in-page
multi-view embedding for panels and workspace regions. The second tier serves
the browser-extension targets, where `open()` of a regular window maps to
`DV.Platform.browserExtension.tabsCreate(route)` and an owned kind maps to an
in-page overlay.

³ The *capability* is unsupported; the *API* is not. `capability.multiWindow`
reports false and no OS window is created, but `open()` presents the route, so
application and workspace code compiles and runs unchanged. No target is
labelled `Unsupported`, because the label describes what an application can
rely on, and every target can rely on `open()` presenting the route.

Display-scoped kiosk (`capability.displayKiosk`) requires `multiWindow` and
`displays`; it is available on the desktop rows and on eLinux multi-head
configurations, with per-display enforcement reported as described under
Kiosk Mode › Enforcement.

## Configuration

```yaml
dartvel:
  windowing:
    enabled: true
    singleInstance: true          # desktop: second launch focuses, not forks
    exit: lastWindow              # lastWindow | mainWindow | explicit
    restoreOnLaunch: true
    workspace:
      persist: true
      tearOut: auto               # auto | disabled
    sharedState:
      encrypt: true               # informational; cannot be disabled
      debounceMs: 50
      spillThresholdKb: 32
      pollMs: 250                 # separate-process fallback only
      sweepAfter: 24h
    web:
      inPageViews: true
      openInNewWindow: true
    android:
      freeform: auto
    # kiosk policy lives under dartvel.kiosk (see Kiosk Mode);
    # windowing.kiosk.allowWindows remains a compatibility alias of
    # dartvel.kiosk.windows in device scope.
```

`sharedState.encrypt` is shown for discoverability and validates as `true`;
setting `false` is a build error, because a per-project opt-out is how the one
project that mattered ships plaintext drafts.

## Bindings

Stability: `Draft` · Status: `Designed`

Generated FFI/ffigen or JNI/jnigen bindings only, per the standing rule:

- desktop: `window.open`, `window.close`, `window.setTitle`, `window.setSize`,
  `window.setFullscreen`, `window.minimize`, `window.maximize`,
  `window.restore`, `window.observeLifecycle`, `window.displays`,
  `window.display.assign`, `window.pin`, `window.unpin`,
  `window.instance.acquire` (single-instance lock)
- android: `window.task.open`, `window.task.close` (JNI, engine groups)
- ios: `window.scene.request`, `window.scene.close`
- web: generated bindings over `window.open`, `localStorage`, the `storage`
  event, and the multi-view embedder API; extension targets add `tabs.create`
- shared store: `window.shared.get`, `window.shared.set`,
  `window.shared.observe`; desktop needs no `observe`, since notification is
  in-process

A missing or refusing binding fails typed (`DV-WINDOW-006`), never silently.

## Inspection, Studio and the project graph

Windows and tabs are project-graph nodes. `dartvel inspect windows --json`
answers like every other inspector: the static picture (which routes declare
window identity, workspace pages, configured exit and restore policy) and,
against a running app, the live window list with route, kind, owner, lifecycle
state, presentation, degradation, handover mode, and the capability report per
configured target. Studio's window inspector renders the same data and lets
an operator close, focus (via open) and inspect a window's shared keys —
values shown decrypted only to an authorized session, never logged.

## Testing

```dart
DV.Test.fakeWindowing(
  const DVWindowingCapability(multiWindow: false),   // simulate a phone
);
DV.Test.fakeWindowing(DVWindowingCapability.desktop());

final win = await DV.Window.open(DVPages.orders);
expect(win.presentation, DVWindowPresentation.page);
expect(win.degradation, DVWindowDegradation.capabilityUnsupported);
```

Fakes are explicit; no test passes because windowing was silently absent.
Golden tests run per window, keyed by route, and `dartvel test e2e` drives
real tear-out on desktop runners where the flag is available.

## Performance contracts

Measured: time from `open()` to `ready` (real and virtual), tear-out handover
time on same-engine targets, shared-store write rate and coalescing ratio,
store size and spill count, and restore-on-launch duration. Diagnostics:
a call site that always degrades, a shared key written more than once per
frame before coalescing, a workspace whose restore exceeds the startup budget,
and owned windows outliving the frame budget on close.

## Security

- A window presents a route, so middleware and policies run before
  presentation; there is no window-level bypass of auth, tenant or policy.
- Kiosk keeps the surface locked (`DV-WINDOW-002`); content still presents in
  place under the same policies.
- Web `open()` requires a user gesture for real windows; the platform enforces
  it and Dartvel reports it (`DV-WINDOW-003`) rather than attempting a bypass.
- The shared store is encrypted with the application key and never holds
  `DV.Secrets` values or model rows.
- Restore never opens a route the current user is not authorized for.

## Compatibility

`DV.Platform.Window.setTitle` / `persistState` / `restoreState` continue to
work as sugar over `DV.Window.current`; `dartvel migrate-code` rewrites them to
the explicit form on request. No existing surface is removed.

## Deliberately absent

Closed as a list so they are not reopened item by item:

- **A second windowing namespace.** `DV.Window` (= `DV.Platform.Window`) is
  the whole surface. No `DVWindowManager`, no `DV.Windows`, no `DVWindowing` —
  not as a public type, not as a documented name, ever. Anything the
  implementation needs beyond `DV.Window` and `DVWindow` is private.
- **Window placement / `setPosition`** — three targets could honour it, one
  refuses; not a capability. Display hint only.
- **`activate()` / `focus()`** — `open()` is the one verb; idempotent by URL.
- **`DV.Window.broadcast` / messaging** — the store publishes state; events
  belong to model sync.
- **`DVTab.widget(...)`** — a tab without a route cannot tear out on any
  separate-engine target, cannot deep-link, cannot restore. Make a page.
- **Per-window theme, locale, tenant or auth** — inheritance is the rule.
- **Spawning terminal emulators for windows** — requires the window server
  terminal rendering exists to avoid; multiplexer surfaces deferred.
- **Store encryption opt-out** — whole-store, always on.

# Tab Workspaces

Stability: `Contract` · Status: `Designed`

`DVTabWorkspace` is a generated application component — like `User.Table()`,
composed from `DVBox` and `DVText`, introducing no new primitive — that owns
the tab strip, reordering, tear-out and re-dock, wired to `DV.Window`.

```dart
@DVPage(title: 'Workspace')
Widget _workspacePage(BuildContext context) => DVTabWorkspace(
      initialTabs: [
        DVTab(DVPages.orders),
        DVTab(DVPages.customers),
        DVTab(DVPages.reports),
      ],
      workspace: 'default',          // persistence name; null disables
    );
```

A tab is a route — the same identity a window has — which is what makes
tear-out navigation rather than surgery.

- **Reorder** — drag within the strip; on TV and watch the strip renders as a
  platform-appropriate switcher and reorder is a context action. Pure UI; no
  windowing capability required.
- **Tear-out** — drag beyond the strip, or a context-menu action where drag is
  unavailable. Gated on `capability.tearOut`; executes
  `DV.Window.open(tab.route)`. Where `tearOut` is false the drag gesture is
  absent rather than broken, and the explicit "open in new window" affordance
  is shown only where `capability.multiWindow` is true.
- **Re-dock** — dragging a tab into another window's strip. Same-engine targets
  hit-test across windows and hand the object over; separate-engine targets
  re-dock by adoption: the receiving workspace adds the route, the source
  closes it. Same convergence, two steps.
- **Empty-window rule** — a workspace window whose last tab leaves closes
  itself; if the OS closes a workspace window around its tabs, they fold into
  `main`. Workspace state policy, not window callbacks, so tear-out, re-dock
  and cleanup are one transition.
- **Duplicate tabs** — a route already open as a tab focuses that tab; a
  deliberate second tab says `DVTab(route, duplicate: true)`, mirroring
  `open()`.
- **Persistence** — layout, tab order and active tab persist under the
  workspace name through `persistWorkspace` / `restoreWorkspace`, tenant- and
  user-scoped.

Capability-shaped, never capability-broken:

```text
tearOut: true       → detachable tabs                        (desktop, iPad)
tearOut: false,
  multiWindow: true → tabs plus explicit "open in new window" (web, Android)
multiWindow: false  → tabs only; open() navigates            (iPhone, TV, watch, kiosk, terminal)
```

Web tear-out by drag is false because a drag ending on the desktop cannot open
a popup without a gesture-attributed call; web gets the explicit affordance,
which satisfies the gesture requirement.

Tear-out on a separate-engine target is: write the tab's `workspace.*` shared
keys, open the window at the route, let the new engine read them on boot. The
route carries identity and the store carries state, so a slow-starting window
loses nothing — the state is waiting for it.

Tear-out never produces a kiosk window: kiosk windows come from policy, not
from a gesture, and a tab dragged out of a strip is a regular window.

Sharing is always explicit at the signal declaration. A workspace does not
implicitly share its tabs' page signals, because implicit persisted writes of
arbitrary signal values are both a redaction risk and a write-amplification
one.

# Dartvel Studio

Dartvel Studio is the admin section every Dartvel application ships with —
WordPress's admin for a Flutter platform. Every app is fully self-contained,
frontend and backend, regardless of publish target: the app carries the tools
to manage itself.

Studio provides:
- **Page management with a visual builder.** Pages are managed like WordPress
  content, edited with a builder that sits between a free canvas (Figma) and a
  page-based editor (WordPress/FlutterFlow) — Framer's middle ground.
- **Model management.** Generated model CRUD, driven by the same metadata the
  admin already uses.
- **Backend function and workflow building.** Drag-and-drop composition of
  backend behaviour, Webflow/FlutterFlow-style. A `DVWorkflowDocument` is a
  serializable step tree — `call`, `set`, `condition`, `return` — that
  `DVWorkflows.run` executes directly, so saving publishes, and
  `toDartSource()` exports as an ordinary `@DVBackendFunction`, so the builder
  can be dropped. Steps call actions registered with
  `DVWorkflows.registerAction`, which is the same code an application calls.
  A workflow fails loudly: an unknown action or variable stops the run and
  names the step, rather than yielding null and reporting success.

## The page builder

The builder manipulates **real widgets, not a canvas facsimile**. No
CustomPaint re-implementation of the UI: the editing surface instantiates the
same `DVBox`/`DVText`/generated components the running app renders, so what is
edited is what ships. It must be feature-rich enough that Dartvel itself could
be rebuilt with it.

- Drag/drop inserts and moves actual widgets. `DVStudioPalette` is the source
  list, `DVStudioCanvas` renders the document as real widgets with selection
  and drop targets layered over it, and `DVStudioEditorController` owns
  selection and a bounded undo/redo history — an editor without undo is not an
  editor, since a mis-drop that cannot be reversed loses work.
- Properties, modifiers, gestures, and actions are edited on the selected
  widget through `DVStudioInspector`; actions bind to `DV.Navigation`,
  backend functions, and signals.
- View-code at any time (Figma/Webflow-style), and full code export: a page
  document exports to the same private `@DVPage` source a hand-written page
  uses, with no builder runtime required afterwards.

The load-bearing primitive is the **page document**: a serializable widget
tree (`DVPageDocument`) that the builder edits, the renderer instantiates as
real widgets, the store persists through `DV.Database`, and the exporter lowers
to Dart source. Everything else in the builder is UI over these four
operations.

```dart
final document = DVPageDocument(route: '/pricing', title: 'Pricing');
// Editor operations — what drag/drop and the inspector call:
final editor = DVPageDocumentEditor(document);
editor.insert(DVPageNode.text('Plans'), parent: document.root.id);
editor.update(nodeId, (node) => node.withProperty('fontSize', 24));
editor.move(nodeId, parent: otherId, index: 0);

// The same document, three ways out:
DVPageDocumentRenderer(document)   // real widgets, in-app and in-editor
document.toDartSource()            // full code export, @DVPage form
await DVPageStore().save(document) // persisted, immediately publishable
```

## Publishing

- Saving publishes: stored documents are served to running apps immediately —
  page content is data, like WordPress posts.
- **A stored document overrides the compiled page.** A compiled `@DVPage` is
  the entrypoint an app ships with, not a permanent fixture: the editor has to
  be able to change it, or a shipped page could never be edited, only added
  to. Deleting the document restores the compiled page, so an edit is always
  revertible.
- Routes with no compiled page at all are served from the store too, so the
  editor can add pages as well as edit them.
- A page already on screen reloads when its own document is saved, so an edit
  reaches a running app without navigation.
- Compiled export: `document.toDartSource()` emits the page as ordinary
  `@DVPage` source for projects that want the builder out of the loop.
- OTA on command: `dartvel updates patch` pushes builder-made changes to
  installed applications. Documents travel as a `DVPageBundle` — a versioned
  set of pages plus the routes it withdraws — and `DVPageBundleInstaller`
  writes them into the store on apply. Applying a version twice is a no-op,
  because a patch can be delivered more than once and re-applying it would
  undo edits made since. A rollback ships the previous bundle rather than
  inverting one, which is the only way to be sure what an app ends up with.

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

# Secrets and Environments

A secret compiled into a client bundle ships to every visitor. Because Dartvel
compiles both ends from one project, it can make that a build error rather than
a code-review habit — no stack assembled from separate frontend and backend
repositories can.

Secrets are **backend-scoped by default**. Reaching one from client-reachable
code is a typed build error, `DV-SECRETS-001`. Genuinely public values — a
publishable Stripe key, a map tile token — opt in explicitly, and the opt-in is
visible in the declaration rather than inferred from a call site.

## Declaration

Secrets are declared under `dartvel:` in `pubspec.yaml`. **Names and scopes
only; never values.**

```yaml
dartvel:
  secrets:
    PAYSTACK_SECRET:
      scope: backend            # default; may be omitted
      required: [production, staging]
    PUBLIC_STRIPE_KEY:
      scope: client             # ships to the bundle, deliberately
      required: [production]
    OPENAI_API_KEY:
      scope: backend
      required: []              # optional everywhere
```

The declaration is what makes the rest possible: an enumerable set is what
`dartvel deploy` validates, what rotation iterates, and what an inspector can
report. An undeclared name used through `DV.Secrets` is a build error naming
the pubspec key to add, because a typo in a secret name is otherwise a runtime
failure in production.

A `scope: client` secret must carry the `PUBLIC_` prefix. There is one client
opt-in, not two: the prefix is the marker in the environment and the generated
`env.g.dart`, and the declaration is where it is justified.

## Access

```dart
final key = DV.Secrets.get('PAYSTACK_SECRET');     // throws if unresolved
final opt = DV.Secrets.maybeGet('OPENAI_API_KEY'); // null if unresolved
final url = DV.Secrets.getOr('CACHE_URL', 'memory://');
DV.Secrets.has('PAYSTACK_SECRET');
```

Resolution order is process environment, then `.env` for local development,
then values supplied by `DV.Secrets.configure(...)`. Vault and KMS adapters
plug in behind the same call, so application code never learns where a value
came from.

## What is guaranteed, and by which layer

Stated separately because the layers have different strengths, and a reader
deciding what to rely on needs to know which is which.

1. **Values never reach a client bundle.** Only `PUBLIC_`-prefixed variables are
   emitted into the generated `env.g.dart`, and a web build resolves the process
   environment to nothing at all — the browser implementation returns null by
   construction and `DV.Secrets.get` throws `DVSecretNotFoundException` naming
   the backend function to fetch the value through. This is a structural
   guarantee: it holds whether or not any analysis runs.
2. **`DV-SECRETS-001` reports a backend-scoped secret reached from client
   code.** A diagnostic over the declared set and the generated client's import
   graph. It is a strong signal, not a proof — a value routed through an
   indirection it cannot follow is a false negative, which is exactly why layer
   1 is structural and layer 2 is advisory on top of it.
3. **`dartvel deploy` refuses to ship when a declared secret required for the
   target environment does not resolve.** Checked against the declaration, so a
   secret forgotten in a new environment fails the deploy rather than the first
   request that needs it.

## Redaction

Secret values are excluded from logs, traces, diagnostics and error messages by
construction — the same exclusion set as `@DVModel.sensitiveField()`, which
remains the single normative list. An exception raised while resolving a secret
names the key, never the value.

## The application key

The secrets above are backend-scoped. A client also needs a key — for the
shared window store, and for anything else Dartvel encrypts at rest on a
device — and it is a different key with a different threat model. Conflating
the two is how a device key ends up on a server, or a server key in a bundle.

```bash
dartvel key generate     # writes to the platform key store, never the repo
dartvel key rotate
dartvel key status
```

The application key is **never in the bundle and never in `pubspec.yaml`**.
That is this section's own rule rather than caution: only `PUBLIC_`-prefixed
values reach the generated `env.g.dart`, and a key shipped to every visitor
encrypts nothing. A server-side framework can keep such a key in an
environment file because it lives on a machine the operator controls; an
application's store lives on the user's device, so the key must come from
somewhere the user's own OS protects.

| Target | Key custody |
|---|---|
| Windows | DPAPI-protected, per user |
| macOS / iPadOS | Keychain, app-scoped |
| Linux | Secret Service (libsecret), keyring-backed |
| Android | Android Keystore, hardware-backed where available |
| Web | non-extractable WebCrypto `CryptoKey` in IndexedDB |

Generated at first run, per install and per user, so it is not a shared secret
and there is nothing to leak into version control. The web row is the
strongest in one specific way: a non-extractable `CryptoKey` cannot be read
back even by the application's own JavaScript, so it survives an XSS that
would trivially lift a string from `localStorage`.

Rotation re-encrypts in place through the same hook shape as below. Backend
encryption of model fields at rest uses the server-held key from `DV.Secrets`
in the ordinary way; these two never meet.

## Rotation

```dart
DV.Secrets.onRotate('PAYSTACK_SECRET', (String value) async {
  await paymentGateway.reconfigure(value);
});
```

Rotation hooks fire when a resolver reports a new value, so a long-lived client
holding a connection can rebuild it without a restart. A secret with no hook is
simply re-read on next access.

## Testing

`DV.Test.withSecrets({...})` supplies values for the duration of a test and
restores the previous state after, so a suite never depends on the developer's
environment and a forgotten override cannot leak into the next test.

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
dartvel dev          # aliases: run, start
```

`dartvel dev` is the whole loop. It watches the configured sources and does
only what a change needs:

| Changed | What happens |
| --- | --- |
| A page or widget | Regenerate, then Flutter's own hot reload |
| A backend function | Regenerate, restart the backend, reload the app — the generated client changed with it |
| Rust | Rebuild the native runtime and restart the backend; no Dart changed, so the app is left alone |
| An env file | Regenerate, restart the backend, reload the app |

Hot reload and hot restart are Flutter's: `r` and `R` reach the running
`flutter run`. Nothing is rebuilt to show a changed widget.

Unchanged content costs nothing. Each watched path is digested, so a
touched-but-identical file does no work — editors save on focus loss and build
tools stamp mtimes, and acting on the event rather than the content would
restart a backend for a stray save.

There is no separate `dartvel watch` or `dartvel hotreload`. The second name in
particular was wrong: it never asked Flutter to reload anything, so the command
that sounded like it handled reloading was the one that did not.

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
Widget _stepCounterWidget(
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


# The Golden Path

Dartvel provides one clearly recommended path from project creation to
production. Advanced customization is always available, but the default
experience is:

```text
Create
→ Model
→ Page
→ Function
→ Generate
→ Run
→ Test
→ Build
→ Deploy
→ Observe
→ Upgrade
```

## Create the project

```bash
dartvel new my_app
cd my_app
dartvel dev
```

`dartvel new` scaffolds the default project structure (`lib/pages`,
`lib/models`, `lib/backend`, `lib/components`, `lib/styles`, `lib/services`,
`main.dart`, `pubspec.yaml`).

`dartvel dev` starts the complete local Dartvel environment: the Flutter
application, the Dartvel backend, the code generator, analyzer integration, the
zero-config SQLite database, the model sync runtime, the cron scheduler, the
storage emulator, notification preview, Dartvel Studio, and the observability
collector.

```text
Dartvel is ready

App:        http://localhost:3000
Backend:    http://localhost:3001
Studio:     http://localhost:3002
Database:   Connected
Model sync: Running
Cron:       Running
Generator:  Watching
```

There is no `DV.Realtime` runtime; model sync is generated from models,
signals, and queues.

## Define a model

Annotated models are private generation inputs (`_`-prefixed) and generate the
public class.

```dart
@DVModel()
class _User(
  final String name,
  final String email,
  final DVImage? avatar,
  final String? biography,
);
```

Dartvel generates the schema, migration, CRUD, validation, serialization,
queries, forms, list, table, page, REST/RPC/GraphQL/OpenAPI surfaces, model
sync support, and admin representation for the public `User` type.

## Create a page

```dart
@DVPage()
Widget _usersPage(BuildContext context) => User.List();
```

File location determines the route (`lib/pages/users.dart` → `/users`).

## Add backend behavior

```dart
@DVBackendFunction()
Future<User> _createUser(String name, String email) async =>
    User.create(name: name, email: email);
```

The function is called identically from frontend or backend code:

```dart
final user = await createUser(name, email);
```

## Generate, migrate, test, build, deploy, observe, upgrade

```bash
dartvel generate
dartvel db migrate
dartvel test          # or: unit | widget | backend | integration | migration | platform
dartvel build android # see Build targets
dartvel deploy        # or: cloud-run | lambda | container | fly | railway
dartvel logs          # dartvel metrics | dartvel traces | dartvel studio
dartvel upgrade --plan && dartvel compatibility-check && dartvel upgrade
```

During development, generation happens incrementally through `dartvel dev`.

The golden path is the recommended path, not the only path. Every layer retains
escape hatches (see Pluggability).

---

# Lifecycle Signals

Dartvel does not introduce a `DVService` lifecycle abstraction. Lifecycle state
is modelled as generated, read-only **enum signals** — the same signal system
described under State. Their conceptual type is `DVSignal<TEnum>`: a read-only
reactive value that can be read directly, observed, exposed through `DV.global`,
consumed by modules and generated diagnostics, and displayed in Dartvel Studio.
The generator owns the transitions; application code observes rather than
assigns.

## Application lifecycle

```dart
enum DVAppLifecycle {
  uninitialized, initializing, booting, ready, backgrounded,
  suspended, resuming, shuttingDown, stopped, failed,
}
```

```dart
DV.lifecycle.app.listen((state) async {
  if (state == DVAppLifecycle.booting) {
    DV.global<PaymentGateway>(
      PaystackGateway(secret: DV.Secrets.get('PAYSTACK_SECRET')),
    );
  }
});
```

## Page lifecycle

```dart
enum DVPageLifecycle {
  created, resolving, loading, ready, entering, active,
  inactive, leaving, disposing, disposed, failed,
}

context.lifecycle.page.listen((state) {
  if (state == DVPageLifecycle.active) {
    DV.log('page_view');
  }
});
```

## Module, request, transaction, and build lifecycles

```dart
enum DVModuleLifecycle {
  discovered, resolving, validating, loading, loaded, mounting,
  mounted, active, suspended, unmounting, unloaded, failed,
}

enum DVRequestLifecycle {
  received, contextCreated, decoding, tenantResolving, tenantResolved,
  authenticating, authenticated, securityChecking, rateLimitChecking,
  validating, authorized, transactionStarting, executing, preparingResponse,
  committing, encoding, completed, cancelled, rollingBack, failed,
}

enum DVTransactionLifecycle {
  created, active, preparing, committing, committed, rollingBack,
  rolledBack, compensating, compensated, cancelled, failed,
}

enum DVBuildLifecycle {
  idle, scanning, analyzing, generating, validating, compiling,
  bundling, completed, failed,
}
```

Access points:

```dart
DV.lifecycle.app
DV.lifecycle.build
DV.Modules.store.lifecycle
context.lifecycle.page          // in a page
context.lifecycle.request       // in a backend function
context.lifecycle.transaction   // in a transaction
```

The CLI, Studio, analyzer, and external tools observe the same canonical state.

---

# Backend Function Request Lifecycle

Every `@DVBackendFunction` runs through a generated request lifecycle. When the
first parameter is a `DVContext`, it is injected automatically and is never
treated as a client-supplied argument.

```dart
@DVBackendFunction()
Future<User> _getUser(DVContext context, String id) async => User.find(id);
```

Generated stages (each updates `context.lifecycle.request`):

```text
1. Request received
2. Trace and correlation identifiers created
3. Transport envelope decoded (form-data + binary flat-buffers)
4. DVContext created
5. Environment resolved
6. Tenant resolved
7. Authentication resolved
8. Origin, CORS, and CSRF rules evaluated
9. Rate and quota limits evaluated
10. Parameters decoded
11. Parameters validated
12. Authorization policies evaluated
13. Transaction opened where required
14. Function executed
15. Reversible operations recorded
16. Deferred operations prepared
17. Transaction committed
18. After-commit operations dispatched
19. Response encoded
20. Metrics, logs, and traces finalized
21. Response returned
```

Most functions never observe the lifecycle manually; it primarily supports
plugins, observability, security, debugging, Studio, and advanced behavior.

## Function configuration

```dart
@DVBackendFunction(
  transaction: DVTransactionMode.auto,
  authentication: DVAuthentication.required,
  rateLimit: '100/hour',
)
Future<Order> _createOrder(DVContext context, OrderInput input) async =>
    Order.create(input);
```

## Raw HTTP paths

Raw HTTP exposure stays part of `@DVBackendFunction`; there is no separate
`@DVRawRoute` primitive.

```dart
@DVBackendFunction(rawPath: '/payments/webhook')
Future<void> _paymentWebhook(DVContext context) async =>
    Payments.acceptWebhook(context);

@DVBackendFunction(rawPathSuffix: '/public')
Future<Product> _getProduct(String id) async => Product.find(id);
```

`rawPath` exposes an exact custom path. `rawPathSuffix` keeps the generated path
and appends a suffix (`/dartvel/functions/products/getProduct/public`). The two
are mutually exclusive.

---

# Modules

A Dartvel module is a **complete, composable Dartvel application boundary**. A
module may contain pages, models, backend functions, components, styles, assets,
cron functions, configuration, storage namespaces, database migrations,
permissions, SEO/PWA configuration, AI tools, observability, and other modules.

A module can be run, built, and deployed independently; embedded into another
Dartvel application; mounted as a micro-site or micro-app; used as a
backend-only capability; distributed as a Dart package; or maintained inside a
monorepo. A module is itself a valid Dartvel project:

```bash
cd modules/store
dartvel dev            # runs the store standalone
```

## Module declaration

In the module's `pubspec.yaml`:

```yaml
dartvel:
  module:
    id: store
    name: Store
    version: 1.0.0
    routes:
      base: /
    exports:
      pages: true
      functions: true
      models: [Product, Cart, Order]
    auth:
      mode: inherited
    theme:
      mode: inherited
```

## Parent mounting

In the parent application's `pubspec.yaml`:

```yaml
dartvel:
  modules:
    store:
      source:
        path: modules/store
      mount: /store
      deployment: embedded   # embedded | split-backend | federated | backend-only
      auth: inherit
      theme: inherit
      globals: scoped
```

Route bases are rewritten automatically: the standalone `/products/:id` becomes
`/store/products/:id`. The parent receives generated, typed access:

```dart
DV.Modules.store                 // namespace
DV.Modules.store.lifecycle       // DVSignal<DVModuleLifecycle>
DV.Modules.store.config
DV.Modules.store.manifest
DV.Modules.store.assets.logo     // asset paths rewritten on mount

.navigateToPage(.store.home)
.navigateToPage(.store.product(product.id))
```

## Deployment modes

- **embedded** — compiled into the parent artifact while keeping its namespace.
  Best for feature modules, large monoliths, monorepos, and closely coupled
  product areas.
- **split-backend** — UI ships in the parent; module backend functions deploy as
  a separate service, and generated clients call it automatically. Best for
  independently scaled domains and gradual service migration.
- **federated** — built and deployed as an independent Dartvel application,
  mounted into the parent's route/navigation system. The module publishes a
  signed manifest (identifier, version, routes, capabilities, assets, auth/theme
  modes, public functions, public signals, compatibility requirements,
  deployment location, integrity signature); the parent verifies it before
  integration. Best for micro-sites, micro-frontends, partner and white-label
  sections.
- **backend-only** — contributes models, backend functions, cron functions, AI
  tools, storage behavior, and migrations, but no pages.

A standalone module runs as its own application but may still export typed
contracts to other Dartvel applications.

## Modules as micro-sites and micro-apps

A micro-site or micro-app is just a module with its own route tree, page index,
SEO defaults, sitemap entries, theme, assets, models, backend, deployment
policy, and PWA configuration:

```yaml
dartvel:
  modules:
    documentation:
      source: { path: modules/documentation }
      mount: /docs
      deployment: federated
      theme: override
      auth: public
      sitemap: include
```

The same module responds at `/products` standalone and `/store/products`
mounted; generated navigation always uses the correct route base, so module code
must not hard-code its mount point.

Per-module modes:

- **shell**: `inherit` | `extend` | `override` | `none`
- **auth**: `inherit` (uses the parent's `DV.Auth`) | `independent` |
  `federated` (securely exchanged identity) | `public`
- **theme**: `inherit` | `extend` | `override` | `isolated`
- **data**: `shared` | `schema-isolated` | `database-isolated` | `remote`

A parent cannot mount a module on a target that cannot satisfy the module's
required capabilities unless a configured fallback exists (see Platform
Compatibility).

## Module globals

Modules receive scoped `DV.global` registries — Dartvel does not add a separate
DI/service-container primitive. Globals are isolated by default between
independently deployed modules; sharing is deliberate.

```dart
DV.global<Cart>(Cart(), 'store');
final cart = DV.global<Cart>(null, 'store');
final same = DV.Modules.store.global<Cart>();  // generated convenience
```

Inside the module the namespace is inferred, so `DV.global<Cart>()` resolves to
the module registry. Exported and inherited globals are declared explicitly:

```yaml
dartvel:
  module:
    globals:
      export: [cart, checkoutState]

dartvel:
  modules:
    store:
      globals:
        inherit: [auth, theme, currentTenant]
```

---

# Generated Model Pages

Every model generates a semantic page for one record: `User.Page()`,
`Post.Page()`, `Product.Page()`. Default composition inspects the model's public
fields in this order:

```text
1. Featured image  2. Title  3. Main text content  4. Remaining text
5. Remaining media  6. Structured fields  7. Relationships  8. Generated actions
```

- **Featured image** — the first public image/media field, else the page begins
  with the title or primary text.
- **Web favicon** — a resized, compressed, content-hashed derivative of the
  featured image, cached, included in SSG output, and generated on demand for
  web-server rendering. Fallbacks: configured model favicon → module favicon →
  application favicon.
- **Main content** — the largest text block, chosen from long-text metadata,
  declaration order, schema type, display priority, and actual non-empty length.
- Sensitive and hidden fields are excluded (see Sensitive Model Fields).

Explicit overrides:

```dart
@DVModel.featuredImage() final DVImage cover;
@DVModel.pageTitle()     final String title;
@DVModel.mainContent()   final String body;
@DVModel.pageOrder(3)    final String author;
@DVModel.hideFromPage()  final String internalReference;
```

Field-scoped model annotations live under the `DVModel` parent, alongside
`@DVModel.sensitiveField()` and `@DVModel.searchableField()`. There are no
standalone `@DVFeaturedImage`, `@DVPageTitle`, `@DVMainContent`, `@DVPageOrder`
or `@DVHideFromPage` annotations.

## Page data modes

```dart
enum DVModelPageDataMode {
  auto, sync, async, reactive, cached, staleWhileRevalidate,
}
```

`auto` (default) picks rendering from the input: an existing model renders
synchronously; an id/route parameter triggers an async query; a signal renders
reactively; a stream renders streaming; a cached record renders immediately then
refreshes.

```dart
User.Page(user)
User.Page.async(getUser(id))
User.Page.signal(user.signal(context))
User.Page.fromId(id)
User.Page.fromId(id, dataMode: DVModelPageDataMode.async)   // per-page override
```

```dart
@DVModel(pageDataMode: DVModelPageDataMode.staleWhileRevalidate)
class _User(...)
```

Model-page SEO derives from model data (title → page title, summary/first
excerpt → meta description, featured image → OG image, type/relationships →
structured data, canonical route → canonical URL); all values can be overridden.

---

# Reversible Transactions

The canonical transaction API is:

```dart
final order = await DV.transaction((DVContext context) async {
  final order = await Order.create(customer: customer, total: cart.total);
  await Inventory.reserve(cart.items);
  await DV.FileStorage.put('orders/${order.id}/receipt.json', receiptBytes);
  return order;
});
```

Operations executed through Dartvel primitives participate automatically in the
active transaction. Dartvel can reverse model create/update/delete, relationship
changes, database writes, file creation/replacement, cache changes,
tenant-scoped mutations, and generated model-sync mutations by recording the
previous state or inverse operation.

- **Database-local** — one transactional database uses its native
  begin/execute/commit, rollback on failure.
- **Distributed** — spanning systems uses a compensation log: execute → record
  inverse → continue; on failure reverse completed operations and run
  compensation functions.

`context.lifecycle.transaction` exposes a `DVSignal<DVTransactionLifecycle>`.
Nested `DV.transaction` calls join the active transaction by default; an
isolated transaction can be requested where supported.

## Irreversible and external effects

Truly irreversible effects (email, SMS, webhooks, settled payments, external API
mutations) run after commit; external effects with an inverse register
compensation:

```dart
await DV.transaction((context) async {
  final order = await Order.create(...);
  context.afterCommit(() async {
    await DV.Notifications.send(customer.id, OrderConfirmed(order));
  });
});

await DV.transaction((context) async {
  final payment = await gateway.charge(amount);
  context.compensate(() async => gateway.refund(payment.id));
  await Order.create(paymentId: payment.id);
});
```

---

# Background and Durable Work

Signals and cron functions remain the primary reactive and scheduled
primitives, and `@DVJob`/`DV.Jobs`/`DVQueues` (see Queues, Jobs, and Signals)
remain the durable background-work layer. To keep common cases ergonomic, a
backend function can opt into background/durable execution, which the generator
compiles down onto the existing jobs/queues system — it does not introduce a
parallel primitive:

```dart
@DVBackendFunction(background: true, durable: true, retries: 5)
Future<void> _generateReport(String reportId) async =>
    Reports.generate(reportId);
```

Workflows are ordinary backend functions composed from other typed backend
functions inside a transaction; durable state is stored in generated models and
resumed by backend cron or durable function execution:

```dart
@DVBackendFunction(durable: true)
Future<Order> _fulfilOrder(Order order) async => fulfilOrderWorkflow(order);

Future<Order> fulfilOrderWorkflow(Order order) async =>
    DV.transaction((context) async {
      await chargeCustomer(order);
      await reserveInventory(order);
      await arrangeDelivery(order);
      return order;
    });
```

This keeps the primitive set small: signals, backend functions, transactions,
cron functions, and models.

---

# Sensitive Model Fields

`@DVModel.sensitiveField()` marks a model field as sensitive. By default such a
field is redacted from logs; excluded from AI context, traces, analytics, public
serialization, search indexing, and Open Graph/structured data; hidden from
generated model pages, tables, and admin views; protected from accidental debug
printing; subject to stricter authorization; and audited when accessed.

```dart
@DVModel()
class _User(
  final String name,
  @DVModel.sensitiveField() final String nationalId,
  @DVModel.sensitiveField(encrypted: true) final String recoveryToken,
  @DVModel.sensitiveField(showInForms: true, showInAdmin: false)
  final String recoveryEmail,
);
```

Explicit policy authorization is required before sensitive fields are sent to
clients. This extends the existing security scope (authentication,
authorization, CSRF, CORS, origin validation, XSS/injection/SSRF protection,
secure file handling, rate limiting, secrets, encryption, audit logging,
dependency validation, tenant isolation, security headers, CSP, webhook
verification, sensitive-data redaction). CSRF applies to state-changing browser
requests using automatically attached credentials, not to database queries
themselves.

---

# Static Web Generation

`dartvel build web` does not ship a single shared `index.html`. Dartvel
generates a route-specific HTML document for every known static page:

```text
build/web/
  index.html
  users/index.html
  about/index.html
  products/index.html
  products/product-1/index.html
  sitemap.xml
  robots.txt
  assets/
  flutter/
```

Every generated page contains a route-specific title, meta description,
canonical URL, Open Graph/social metadata, structured data, a route-specific
favicon, the Flutter bootstrap/loader, preload hints, and a raw-text fallback:

```html
<noscript>Raw semantic text representation of the page.</noscript>
```

The raw text is generated from `DVText`, model-page fields, SEO descriptions,
static page content, and accessible semantic labels. When scripting is enabled
and Flutter is supported, the Flutter application takes over.

## Dynamic routes during SSG

Static routes are always generated. Parameterized routes require a known list of
values:

```dart
@DVModel(generatePublicPages: true)
class _Product(...)
```

That renders one page per published record, which is the common case and needs
nothing else. When the set to generate is a subset, a particular order, or
drawn from somewhere the model does not know about, name a resolver instead:

```dart
@DVModel(publicPathsResolver: productPaths)
class _Product(...)

Future<List<String>> productPaths() async {
  return Product.public().select((product) => product.slug);
}
```

The route is the model's own either way, so it is never written out as a
string — a route repeated in an annotation drifts the moment the page file
moves, which is what file-based routing exists to prevent.

For routes without generated static instances, Dartvel produces a configured
fallback document, a client-rendered fallback, a 404, or a redirect to the
web-server deployment.

## Sitemap

Dartvel has a complete generated route index, so it emits `sitemap.xml`
automatically (static pages, generated model pages, module pages, exported
federated micro-site pages, canonical URLs, last-modified, priorities, change
frequencies, alternate locale URLs). Sensitive, private, and authenticated
routes are excluded by default.

```yaml
dartvel:
  seo:
    sitemap:
      enabled: true
      exclude: [/admin/**, /account/**]
      defaults: { priority: 0.5, changeFrequency: weekly }
```

```dart
@DVPage(
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.daily,
  ),
)
Widget _productsPage(BuildContext context) => Product.List();
```

---

# Web Server Rendering

`dartvel build web-server` creates a Dartvel web server that generates
route-specific HTML on demand:

```text
Request received → Route resolved → Page data resolved →
Auth and visibility checked → SEO + structured data generated →
Favicon selected → Raw semantic text generated → Flutter bootstrap embedded →
HTML response returned
```

`GET /products/123` returns HTML containing the SEO, featured image, favicon,
and text content for product `123`; the Flutter client then activates when
supported. Async page data may be awaited, cached, streamed, rendered
stale-while-revalidate, or deferred to the client.

```yaml
dartvel:
  web:
    server:
      pageDataMode: stale-while-revalidate
      cache: redis
      streaming: true
```

Mounted modules contribute their routes to static generation, server rendering,
sitemap/SEO generation, and asset generation. A federated micro-site may serve
its own HTML while still appearing in the parent route index and sitemap.

---

# Embedded, Television, and Extension Build Targets

Beyond mobile, web, and desktop, Dartvel supports dedicated builds for webOS,
Tizen, Sony's Flutter Embedded Linux ecosystem, and VS Code extensions.

```bash
dartvel build webos
dartvel build tizen
dartvel build sony-elinux
dartvel build sony-elinux-iso
dartvel build sony-elinux-img
dartvel build vscode
```

Each target is driven by the platform's dedicated Flutter embedder or host
extension generator rather than plain `flutter build`:

- **webOS** → `flutter-webos` (LG)
- **Tizen** → `flutter-tizen` (Samsung)
- **Sony eLinux** → `flutter-elinux` (Sony)
- **VS Code** → `flutter_vscode` extension generator and webview helper

Dartvel shells out to these embedders, adapting their invocation behind the
stable `dartvel build` surface. When an embedder is not installed, the target is
skipped with a clear message instead of failing the whole build, and
`dartvel doctor --target <t>` validates that the embedder is present.

## VS Code Extension

`dartvel build vscode` packages a Dartvel app as a VS Code extension using the
Dartvel fork of `flutter_vscode`. This target is not a raw `flutter build web`.
It follows the extension-host flow:

1. Generate Dartvel routes/client/backend artifacts.
2. Run `dart run build_runner build --delete-conflicting-outputs` so annotated
   VS Code controller APIs produce current bindings.
3. Run `dart run flutter_vscode:generate_vscode_extension` so the VS Code
   extension scaffold, webview helper wiring, and typed controller bindings are
   present.
4. Run `flutter pub get`.
5. Run `npm install`.
6. Run `npm run compile` to build the TypeScript extension host package.

Application code uses annotated Dart controller APIs for VS Code commands and
messages, initializes `VSCodeWebViewHelper` in the Flutter webview entry point,
and imports Dartvel through the generated `dartvel_client/dartvel_client.dart`
barrel. Dartvel keeps the fork at
`https://github.com/Danroyal001/dartvel_vscode` and tracks upstream
`SlowGen/flutter_vscode`.

The VS Code target requires Node.js/npm, a project dependency on
`flutter_vscode`, and `build_runner` in `dev_dependencies` so controller
bindings are generated before the extension scaffold compiles. `dartvel build
vscode` validates those dependencies before running the scaffold generator, and
`dartvel doctor --target vscode` reports whether npm is on PATH. After
`npm run compile`, Dartvel validates that a
compiled extension-host JavaScript file exists under `out/` or `dist/`, that
`build/web/flutter_bootstrap.js` exists, and that `build/web/assets/` exists.
Those artifacts must be fresh from the current build invocation, so stale
output from a previous run cannot make the build pass. Verification evidence is
recorded in `docs/build-targets.md`; do not infer future compatibility from
command wiring alone.

## webOS

`dartvel build webos` packages the application for a configured webOS target
(webOS OSE, compatible webOS televisions, and embedded webOS devices), covering
remote-control navigation, television-safe areas, lifecycle integration, media
controls, and fullscreen/kiosk modes.

```yaml
dartvel:
  targets:
    webos:
      profile: television
      architecture: arm64
      fullscreen: true
      input: { remoteControl: true, keyboard: true }
      permissions: [media, network, storage]
```

```text
build/webos/release/
  application.ipk
  manifest.json
  checksums.json
```

## Tizen

`dartvel build tizen` packages the application for the configured Tizen profile
(`television`, `mobile`, `wearable`, `embedded`). Dartvel generates Tizen
manifests, privilege declarations, application identifiers, signing
configuration, remote-control mappings, lifecycle bindings, and native or web
runtime packaging.

```yaml
dartvel:
  targets:
    tizen:
      profile: television
      architecture: arm64
      certificate: environment:TIZEN_CERTIFICATE
      input: { remoteControl: true }
      permissions: [internet, media, filesystem]
```

Output is `build/tizen/release/application.wgt` or `.tpk` depending on the
selected runtime profile.

## Sony Embedded Linux

Sony's Flutter Embedded Linux tooling builds application bundles for embedded
Linux architectures. Dartvel provides three related targets.

**Application bundle** — `dartvel build sony-elinux` builds the app and the Sony
eLinux runner without building an OS image.

```yaml
dartvel:
  targets:
    sony-elinux:
      architecture: arm64        # arm | arm64 | x64
      releaseMode: release
      renderer: egl
      displayBackend: drm
      fullscreen: true
      kiosk: true
      autostart: true
```

```text
build/sony-elinux/arm64/release/bundle/
  dartvel_app  lib/  data/  assets/  manifest.json
```

**Bootable ISO** — `dartvel build sony-elinux-iso` assembles a bootable ISO
(minimal Linux OS, bootloader, kernel, system libraries, Flutter eLinux engine,
Dartvel app, native bindings, device/network configuration, autostart, recovery
and diagnostics) for VMs, development hardware, installation media, and
read-only kiosk installs.

```text
build/sony-elinux/arm64/release/
  dartvel-app.iso  dartvel-app.iso.sha256  build-manifest.json
```

**Flashable disk image** — `dartvel build sony-elinux-img` builds a raw disk
image for SD cards, eMMC, USB drives, and development boards.

```yaml
dartvel:
  targets:
    sony-elinux:
      architecture: arm64
      board: generic-arm64
      image:
        size: 8GB
        filesystem: ext4
        compression: xz
        partitions: { boot: 512MB, root: 3GB, data: remaining }
      application: { autostart: true, restartOnFailure: true, kiosk: true }
```

```text
build/sony-elinux/arm64/release/
  dartvel-app.img  dartvel-app.img.xz  dartvel-app.img.sha256
  partitions.json  build-manifest.json
```

## Build-format relationship

The dedicated commands are equivalent to selecting a format explicitly; the
named commands remain first-class because they are easier to discover and
automate.

```bash
dartvel build sony-elinux            # == dartvel build sony-elinux --format bundle
dartvel build sony-elinux-iso        # == dartvel build sony-elinux --format iso
dartvel build sony-elinux-img        # == dartvel build sony-elinux --format img
```

## Device profiles

Reusable embedded-device profiles capture architecture, board, toolchain,
kernel, display backend, GPU renderer, resolution, orientation, touch/remote
support, network defaults, filesystem, partitions, native capabilities, update
behavior, and startup behavior.

```yaml
dartvel:
  deviceProfiles:
    lobby-display:
      platform: sony-elinux
      architecture: arm64
      display: { width: 1920, height: 1080, orientation: landscape }
      kiosk: true
      input: { touch: true, keyboard: false }
```

```bash
dartvel build sony-elinux-img --device-profile lobby-display
```

## Build validation

Before building, Dartvel validates toolchain availability, architecture and
engine compatibility, platform permissions, native bindings, required system
libraries, signing credentials, device-profile compatibility, and disk-image and
bootloader configuration. Failures are typed and explained:

```text
DV-ELINUX-004
The selected application requires Bluetooth, but the sony-elinux device profile
does not provide a Bluetooth adapter or fallback implementation.
```

Validation is also available through
`dartvel doctor --target webos|tizen|sony-elinux|vscode`.

## Updated build target list

```bash
# Mobile
dartvel build android
dartvel build ios
# Web
dartvel build web
dartvel build web-server
# Desktop
dartvel build windows
dartvel build linux
dartvel build macos
# Television, embedded, and extension platforms
dartvel build webos
dartvel build tizen
dartvel build sony-elinux
dartvel build vscode
# Complete Sony Embedded Linux system images
dartvel build sony-elinux-iso
dartvel build sony-elinux-img
```

---

# Unified Development, Transparency, and Contracts

## Unified development

`dartvel dev` owns the complete development loop, watching pages, models, backend
functions, modules, configuration, native bindings, assets, routes, migrations,
AI tools, and home widgets. Change behavior: UI change → Flutter hot reload;
route change → route regeneration and deferred-bundle refresh; backend-function
change → backend reload; model change → schema diff and migration preview;
module change → affected-module rebuild; configuration change → subsystem
reload; Rust/native change → native binding rebuild. Studio and the DevTools
extension expose the same runtime signals the framework uses.

## Generated-code transparency

Generated behavior is always inspectable. Dartvel may hide generated output
during normal development but never obscures how an application works; generated
code carries source mappings back to models, pages, functions, annotations,
configuration entries, and module manifests.

```bash
dartvel inspect routes
dartvel inspect model User
dartvel inspect function createOrder
dartvel inspect module store
dartvel inspect transaction
dartvel inspect schema
dartvel inspect generated
dartvel explain DV001
```

### The project graph

Every inspector above answers a question about the same thing: what this
application is made of. That is one artifact, not eight — a versioned
**`DartvelProjectGraph`** carrying routes, models and their fields, backend
functions, jobs, modules, static paths, the schema, and capability metadata,
each node keeping the source mapping it was derived from.

The graph is the contract, and `--json` is how it is read:

```bash
dartvel inspect routes --json
dartvel inspect model User --json
dartvel inspect --json            # the whole graph
```

```json
{
  "graphVersion": 1,
  "models": [
    {
      "name": "User",
      "source": "lib/models/user.dart:7",
      "fields": [
        {"name": "email", "type": "String"},
        {"name": "taxId", "type": "String", "sensitive": true}
      ]
    }
  ]
}
```

`graphVersion` is a contract: a consumer that understands version 1 keeps
working, and a breaking change to the shape increments it rather than quietly
reshaping a field.

This ordering is deliberate and is the opposite of how the feature is usually
proposed. `--json` looks like a flag to add to commands that already exist,
but the generators do not share a model of the project — each rediscovers what
it needs from source, so eight inspectors would mean eight partial answers that
disagree at the edges. The graph is the work; `--json` is a serialization of
it. Building it in that order is also what lets the other subsystems stop
re-deriving the same facts: generated span names, stale-flag analysis, image
field discovery and the specification status index are all questions about the
graph.

**Sensitive fields are named, never valued.** `@DVModel.sensitiveField()` is
excluded from logs, AI context, traces, analytics, public serialization,
search, model pages, tables and admin; `--json` output and MCP tool results are
the same kind of surface and are covered by that rule. A sensitive field
appears in the graph as a field that exists, marked `"sensitive": true`, with
no value — the schema is what an agent needs, and the data is what it must not
be handed.

Diagnostics are part of the contract. Every error and warning Dartvel emits
carries a stable code, and `dartvel explain <code>` describes the cause and the
fix. A code is an identifier other tools can match on, so it does not change
meaning between releases.

## Platform compatibility

Every capability carries generated support metadata: `Supported`,
`Supported with limitations`, `Experimental`, `Community supported`,
`Unsupported`. Modules declare required capabilities; a parent cannot mount a
module on a target that cannot satisfy them without a configured fallback.

```bash
dartvel doctor --targets android,ios,web,vscode
```

## Upgrade and compatibility

Dartvel upgrades preserve source, generated-code, protocol, database, module,
plugin, and deployment compatibility. Automated code migrations handle changes
such as `DVStyleModifier → DVModifier`, `.styleModifier() → .modifier()`, and
`DV.BlobStorage → DV.FileStorage`. Module manifests declare compatible Dartvel
versions, validated before compiling or mounting.

```bash
dartvel upgrade --plan
dartvel compatibility-check
dartvel migrate-code
dartvel upgrade
```

## Performance contracts

Dartvel measures application/page startup, web and route bundle size, backend
cold start and request overhead, serialization overhead, signal rebuild counts,
database query counts, model sync latency, memory usage, generated-code size,
module loading, SSG build duration, and server-render duration. Generated
diagnostics include N+1 queries, unbounded collections, excessive signal
rebuilds, route bundles over budget, blocking work in backend functions, module
dependency cycles, uncompressed large model images, and non-deterministic SSG
queries.

```bash
dartvel analyze performance
dartvel build --report
dartvel benchmark
```

## Pluggability and escape hatches

Dartvel is opinionated but every major subsystem is pluggable: any Flutter
widget (`DVBox(ExistingFlutterWidget())`), any Dart package, raw SQL, existing
state-management libraries, custom HTTP behavior, native FFI/JNI/Rust, external
services, custom build hooks, platform-specific projects, custom
serializers/databases/deployment adapters, and custom UI systems. A plugin may
contribute pages, models, backend functions, cron functions, signals, modules,
native bindings, providers, storage/database/auth/deployment adapters, Studio
panels, analyzer rules, and build hooks. Raw HTTP behavior stays on
`@DVBackendFunction`, so no separate raw-route abstraction is required.

---

# Mental Model

```text
Pages define application entry points.
Models define data and generate pages, forms, lists, tables, APIs, storage.
Backend functions define server operations, raw HTTP, background and durable work.
Signals define local, global, model, lifecycle, and cross-module reactivity.
DV.global exposes globally available reactive objects.
Cron functions define scheduled behavior.
DV.transaction coordinates reversible operations.
Modules compose complete apps, micro-sites, micro-apps, and backend domains.
DVBox defines layout, collections, and surfaces; DVText defines text.
Modifiers define styling, interaction, accessibility, and behavior.
The generated route index powers navigation, SSG, server rendering, SEO, sitemaps.
Flutter remains the renderer. Dart remains the language. Dartvel is the platform.
```

The rule for scope: design the contracts for the full vision from the beginning,
then implement them progressively without shrinking the platform's intended
destination.

---

# Specification Status

The scope rule above is why this section exists and why it takes the shape it
does. "Design the contracts for the full vision, then implement progressively"
means a section can be **finished as a contract and unbuilt as code at the same
time** — that is the method working, not a defect. A single ladder ending in
`Implemented` would rank a frozen, fully designed contract below a shipped one
and quietly pressure the spec toward describing only what exists.

So status is **two independent axes**, and every h1 section carries both. An h2
subsection inherits its parent's labels unless it declares its own.

**Stability** — how much the surface can still move:

| Label | Meaning |
|---|---|
| `Draft` | Shape under discussion. APIs are illustrative; names and signatures may change without notice. |
| `Contract` | Frozen surface. A breaking change requires the migration path in [Upgrade and compatibility](#upgrade-and-compatibility), not a spec edit. |

**Status** — how much of it is built:

| Label | Meaning |
|---|---|
| `Designed` | Nothing shipped yet. |
| `Partial` | Some of the contract is shipped; the section says which part, and what is absent. |
| `Shipped` | The contract is implemented and covered by tests. |

The two are genuinely orthogonal. `Contract`/`Designed` is a promise the
platform intends to keep and will not casually reword — the most valuable state
for anyone building against the roadmap. `Draft`/`Partial` is code that exists
while its surface is still being argued about, which is a warning to callers.

## Evidence, not adjectives

A `Partial` or `Shipped` label **must name what proves it** — a test file, a
source path, a CLI command. This borrows the discipline `docs/build-targets.md`
already applies to build targets, where "verified" means the command was run and
the artifact inspected, and for the same reason: a status nobody can check is a
status that drifts.

The machine-readable index is `docs/spec-status.json`, checked into the
repository so that reading it needs no toolchain:

```json
{
  "section": "Secrets and Environments",
  "stability": "Draft",
  "status": "Partial",
  "evidence": [
    "packages/dartvel_core/lib/src/secrets/secrets.dart",
    "packages/dartvel_core/test/secrets_test.dart"
  ],
  "absent": "DV-SECRETS-001 reachability analysis; rotation hooks; deploy-time validation"
}
```

`dart run tool/spec_status_check.dart` fails when a section's claim cannot be
substantiated: an entry naming a section the spec does not contain, a section
the index omits, a `Partial` or `Shipped` entry whose evidence path does not
exist, or a `Partial` entry that does not say what is absent. Running it in CI
is what keeps the labels honest — without it this is another list that ages.

The index is the single source of truth for implementation status. The agent
rule files point at it rather than restating it; a status paragraph copied
across eleven files is exactly the drift this section exists to end.

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
