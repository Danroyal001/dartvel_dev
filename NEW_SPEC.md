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


No controllers.

No repositories.

No DTOs.

No route maps.

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

```dart
DVBox(...)
DVText(...)
```


Everything else is built from them.

Images ( .backgroundImage() modifier on DVBox )

Cards ( .card() modifier on DVBox )

Rows

Columns

Buttons ( .onTap() or .onPressed() alias modifier on DVBox or DVText )

Containers

Layouts

Forms ( DVForm does exist )

Lists

Grids

Navigation

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

No `.wrap()`.

Wrapping is automatically handled by dartvel where necessary.

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
@DVFunctionalWidget()
Widget usersPage(
    BuildContext context
) {}
```

DVPage handles routing, transitions, scaffolding, e.t.c

---

# Routing

Pages Router.

```
pages/index.dart
```

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

Global

Register

```dart
DV.global<Cart>(Cart());
```

Retrieve

```dart
DV.global<Cart>();
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

Internally powered by Riverpod, so in works in flutter and in pure dart.

---

# Models

```dart
@DVModel()
class User(
    String name,
    String email,
);
```

Automatically generates

* Database schema
* CRUD
* Validation
* Serialization
* Equality
* Forms
* APIs
* Queries

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
```

Or alias

```dart
// The instantiated object
user.Form()
```

Manual

```dart
DVForm<User>.builder((formControls) {})
```

Editing

```dart
// Accepts the model as a positional Arg. The Arg type is DVModel, base class for all the models
DVForm<User>.builder((formControls) {}, user)
```

Generated controls ( formControls.email, e.t.c ).

Generated validation ( formControls.emailIsValid, e.t.c ).

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

Automatically translated to efficient streaming endpoints (such as Server-Sent Events or websockets with automatic fallback to polling) while preserving Dart's native `Stream<T>` API.

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

# Authentication

Like firebase and Clerk.

```dart
DV.Auth.currentUser
```

```dart
DV.Auth.signInWithEmailAndPassword()

DV.Auth.signInWithProvider() // google, facebook, e.t.c

DV.Auth.signInWithRawOAuth()

DV.Auth.signInWithPasskey() // Triggers the passkey flow for the OS or browser, with safe fallback

DV.Auth.signInWithWeb3()

DV.Auth.signOut()

DV.Auth.signUp()

// e.t.c
// We'll also have prebuilt pages for each one. Just Make the first letter uppercase for the class name, and add `Page`, e.g `DV.Auth.SignInWithEmailAndPasswordPage()`
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
DV.Platform
```

Provides:
- Platform detection (DV.Platform.currentPlatform (enum))
- Screen size (DV.Platform.screen.size)
- Safe areas (DV.Platform.screen.safeAreaBounds)
- Breakpoints (DV.Platform.screen.breakPoints)
- Orientation (DV.Platform.deviceOrientation)
- Window (DV.Platform.Window) - Window bounds, properties and functionalities for the app/site. Supports almost everything in the window object on web, no-op on other platforms.
- Device type (DV.Platform.type (enum, e.g mobile, desktop, laptop, desktopOrLaptop, tablet, embeddedDisplay, watch, circularWatch, squareWatch, embeddedWithoutDisplay))
- Screen shape (DV.Platform.screen.shape (enum e.g square, rectangle, verticalRectangle, horizontalRectangle, custom))

Native APIs, including:
- Android (DV.Platform.*)
- iOS (DV.Platform.*)
- Windows (DV.Platform.*)
- Linux (DV.Platform.*)
- macOS (DV.Platform.*)
- Web (DV.Platform.*)
- Fuchsia (DV.Platform.*)
- Tizen (DV.Platform.*)
- webOS (DV.Platform.*)
- Amazon (DV.Platform.*)
- TVs (DV.Platform.*)
- Watches (DV.Platform.*)
- Foldables (DV.Platform.*)
- Native APIs: (DV.Platform.*)
- Expo-style. (DV.Platform.*)
- Camera (DV.Platform.*)
- Media (DV.Platform.*)
- Files (DV.Platform.*)
- Location (DV.Platform.*)
- Bluetooth (DV.Platform.*)
- NFC (DV.Platform.*)
- Clipboard (DV.Platform.*)
- Share (DV.Platform.*)
- Notifications (DV.Platform.*)
- Sensors (DV.Platform.*)
- Biometrics (DV.Platform.*)
- Deep Links (DV.Platform.*)
- Haptics (DV.Platform.*)
- Contacts (DV.Platform.*)
- Permissions, managed centrally through `pubspec.yaml`. (DV.Platform.*)

All under DV.Platform.*

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

---

# APIs

Generated automatically.

- RPC
- REST
- GraphQL
- OpenAPI

No manual endpoint creation, but available if needed.

---

# Realtime

- Built in
- Model sync
- Collections
- Presence
- Subscriptions
- Collaborative editing
- Reactive models

---

# Storage

Unified API, supports:

- S3 (And s3 compatible, e.g MiniIO)
- Cloudflare R2
- Azure Blob
- Google Cloud Storage
- Local
- In-memory blobs (zram if supported, or raw blobs)

---

# Cache

Unified cache layer.

- In-Memory
- Memcache
- Redis (Or Valkey)
- Distributed cache

---

# Multi-tenancy

- Enabled by default
- Shared database or
- Schema per tenant or
- Database per tenant or
- Automatic tenant resolution
- Automatic filtering

```dart
DV.currentTenant
```

---

# SEO

Global defaults

```yaml
dartvel:
  seo:
```

Per page

```dart
DVSeo(...)
```

Passed to @DVPage

```dart
@DVPage(seo: DVSeo(...))
@DVFunctionalWidget()
Widget usersPage(
    BuildContext context
) {}
```

Supports:
- OpenGraph
- Twitter
- Structured Data (Content schema, e.t.c)
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

---

# AI

First-class.

Providers:
- OpenAI
- Claude
- Gemini
- OpenRouter
- Ollama

Features
- Chat
- Embeddings
- Agents
- MCP
- Transcription
- Structured outputs
- AI-native diagnostics
- AI project context
- Function and tool calling (@DVAITool(description: 'Optional, used as the KDoc for android appfunctions, or the equivilent for the platform. Also used in context for dartvel-native ai') annotation can be used on functions e.g can be translated to @AppFunction in android, e.t.c based on platform equivilent while remaining exposed to the built-in ai in dartvel even if the platform doesn't have the concept natively, also gets exposed as WebMCP functions)

---

# Observability

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
- Structured diagnostics
- Structured, AI-readable logs

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

Project

```bash
dartvel new
dartvel init
dartvel doctor
# e.t.c
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

All dartvel code is valid on all platforms. It just no-op and raise a warning by default, but this can be tailored.

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

Allows building home-screen and lock screen widgets on supported platforms (e.g Jetpack glance or remote compose on android, e.t.c), using the @DVHomeWidget annotation on any widget, whether flutter-native, DVClassWidget or DVFunctionalWIdget.These widgets just becomes no-op and/or gets excluded from the compiled binary/artifact when unsupported (can be configured).

```dart
@DVHomeWidget()
@DVFunctionalWidget()
Widget StepCounterWidget(
    BuildContext context
) {}
```

Home widgets will act like DVPage, and support all supported properties. it will be possible to navigate launch and navigat to pages within the app, and vise versa (a page will be auto-generated with the widget as its centered content)

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
* Realtime
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
