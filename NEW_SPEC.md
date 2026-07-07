# New Spec v2

# Dartvel — The Complete Vision

> **Flutter's Laravel.**
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

Internally powered by Riverpod.

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

Editing

```dart
DVForm<User>(user)
```

Manual

```dart
DVForm<User>.builder(...)
```

Generated controls.

Generated validation.

Generated submit.

---

# Backend

Backend code is ordinary Dart.

```dart
@DVBackendFunction()
Future<User> getUser(...)
```

Call it like

```dart
await getUser(id);
```

No REST.

No controllers.

No routes.

No generated SDKs.

Just typed functions.

Under the hood, Dartvel compiles backend functions into a high-performance Rust runtime built on Axum and Tokio, exposing them through zero-boilerplate, strongly typed APIs. Developers continue writing only Dart. 

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

Automatically translated to efficient streaming endpoints (such as Server-Sent Events) while preserving Dart's native `Stream<T>` API.

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

Firebase-style.

```dart
DV.Auth.currentUser
```

```dart
DV.Auth.signIn()

DV.Auth.signOut()

DV.Auth.signUp()
```

Providers

* Email
* Google
* Apple
* GitHub
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

Dark

Light

System

Dynamic switching

---

# Platform

```dart
DV.Platform
```

Provides

Platform detection

Screen size

Safe areas

Breakpoints

Orientation

Device type

Screen shape

Native APIs

Including

Android

iOS

Windows

Linux

macOS

Web

Fuchsia

Tizen

webOS

Amazon

TVs

Watches

Foldables

---

# Native APIs

Expo-style.

Camera

Media

Files

Location

Bluetooth

NFC

Clipboard

Share

Notifications

Sensors

Biometrics

Deep Links

Haptics

Contacts

Permissions managed centrally through `pubspec.yaml`.

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

RPC

REST

GraphQL

OpenAPI

No manual endpoint creation.

---

# Realtime

Built in.

Model sync

Collections

Presence

Subscriptions

Collaborative editing

Reactive models

---

# Storage

Unified API.

Supports

S3

Cloudflare R2

Azure Blob

Google Cloud Storage

Local

---

# Cache

Unified cache layer.

Memory

Redis

Distributed cache

---

# Multi-tenancy

Shared database

Schema per tenant

Database per tenant

Automatic tenant resolution

Automatic filtering

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

OpenGraph

Twitter

Structured Data

Meta tags

---

# PWA

Enabled by default.

Automatic

* Manifest
* Service Worker
* Offline support
* Install prompts
* Icons

---

# AI

First-class.

Providers

OpenAI

Claude

Gemini

OpenRouter

Ollama

Features

Chat

Embeddings

Agents

MCP

Transcription

Structured outputs

AI-native diagnostics

AI project context

---

# Observability

Inspired by

Laravel Nightwatch

Hasura

Vercel

OpenTelemetry

Built in

Logs

Metrics

Traces

Profiling

Performance analysis

Error reporting

Structured diagnostics

AI-readable logs

---

# Deployment

Monolith

Single native backend binary.

Function mode

Each backend function can be deployed independently.

Targets

AWS Lambda

Cloud Run

Containers

Edge runtimes

Fly.io

Railway

Bare metal

---

# CLI

Project

```
dartvel new
dartvel init
dartvel doctor
```

Development

```
dartvel dev
dartvel watch
dartvel hotreload
```

Database

```
dartvel db migrate
dartvel db push
dartvel db pull
dartvel db seed
```

Generate

```
dartvel generate page
dartvel generate model
dartvel generate backend-function
dartvel generate form
```

Build

```
dartvel build
```

Deploy

```
dartvel deploy
dartvel deploy lambda
dartvel deploy edge
```

Observability

```
dartvel logs
dartvel traces
dartvel metrics
```

AI

```
dartvel ai context
dartvel ai doctor
dartvel ai generate
```

---

# Package Structure

```
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
```

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

while Flutter remains the rendering engine and Dart remains the only language developers write. 
