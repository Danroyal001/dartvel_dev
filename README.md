# Dartvel

> **Flutter's Laravel.**
>
> A batteries-included, AI-native, full-stack platform for building Flutter applications.

---

## 📖 The Complete Vision

Dartvel simplifies developer workflows. Instead of writing controllers, repositories, DTOs, route maps, or boilerplate state folders, you primarily write:
* **Pages** (`@DVPage()`)
* **Models** (`@DVModel`)
* **Backend Functions** (`@DVBackendFunction()`)
* **UI & Style Modifiers** (`DVBox`, `DVText`, `.modifier()`)
* **Business Logic**

Everything else is automatically compiled, generated, or served by the framework.

---

## 🚀 Key Features

| Feature | Description | Status |
| :--- | :--- | :--- |
| **UI Primitives** | `DVBox`, `DVText`, and fluent styling built on `Mix` | ✅ Implemented |
| **Routing** | File-based pages router with strongly-typed navigation targets | ✅ Implemented |
| **State Management** | Riverpod-powered signals (`context.signal`, reactive models, `DV.global`) | ✅ Implemented |
| **Models & Forms** | `@DVModel` annotation + `DVForm<T>` automatic & manual controls | ✅ Implemented |
| **Backend Runtime** | Axum/Tokio Rust server calling Dart FFI, supporting SSE streams | ✅ Implemented |
| **Platform APIs** | Runtime platform/screen detection; camera, location, haptics, etc. are scaffolded pending native plugins | ⚠️ Partial |
| **Authentication** | API surface and prebuilt pages; provider integrations are not complete | ⚠️ Scaffold |
| **Database & Cache** | API surface plus local primitives; external DB/Redis adapters are not complete | ⚠️ Partial |
| **PWA & SEO** | Automatic PWA manifest/worker & runtime/global SEO injection | ✅ Implemented |
| **AI Integration** | API surface and annotations; provider calls are not complete | ⚠️ Scaffold |

---

## 🛠️ CLI Commands

Manage the full-stack lifecycle directly with the Dartvel CLI:

```bash
# Project initialization
dartvel new [name]
dartvel init
dartvel doctor

# Development
dartvel dev
dartvel watch
hotreload

# Database management
dartvel db migrate
dartvel db push
dartvel db pull
dartvel db seed

# Generators
dartvel generate page
dartvel generate model
dartvel generate backend-function
dartvel generate form
```

---

## 📦 Getting Started

### 1. Project Initialization
```bash
dartvel init my_app
cd my_app
dartvel dev
```

### 2. Declare Reactive Models
Annotated models automatically generate DB schemas, validation, forms, and serializations:
```dart
// lib/models/user.dart
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class User extends DVModel {
  final String name;
  final String email;

  const User({required this.name, required this.email});
}
```

### 3. Build Safe Reactive Forms
Render custom-designed form layouts with auto-generated controls, validation states, and submit triggers:
```dart
// lib/pages/index.page.dart
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:your_app/dartvel_client/models.g.dart';

@DVPage()
@DVFunctionalWidget()
Widget indexPage(BuildContext context) {
  return DVForm<User>.builder(
    (formControls) {
      final userControls = formControls as UserFormControls;
      return Column(
        children: [
          TextFormField(
            initialValue: userControls.name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextFormField(
            initialValue: userControls.email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          ElevatedButton(
            onPressed: userControls.emailIsValid ? () => userControls.submit() : null,
            child: const Text('Save'),
          ),
        ],
      );
    },
    const User(name: 'John Doe', email: 'john@example.com'),
  );
}
```

### 4. Create FFI Backend Functions
Write plain Dart functions that are compiled into a high-performance Rust runtime using Axum and FFI:
```dart
// lib/backend/functions/hello.get.dart
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<User> getUser(String id) async {
  return User(name: 'User $id', email: 'user$id@example.com');
}
```

Call it directly from your frontend code:
```dart
final user = await getUser('101');
```

---

## 🔒 Authentication

Support Clerk-style authentication and native OS login flows out-of-the-box:

```dart
// Core Methods
await DV.Auth.signInWithEmailAndPassword(email: email, password: password);
await DV.Auth.signInWithProvider('google');
await DV.Auth.signInWithPasskey();
await DV.Auth.signInWithWeb3();

// Prebuilt Widgets & Pages
DV.Auth.SignInWithEmailAndPasswordPage();
DV.Auth.SignInWithProviderPage();
DV.Auth.SignInWithPasskeyPage();
```

---

## 📱 Platform Expo-style Native APIs

Access local hardware or OS APIs using a unified static interface:

```dart
final photoBytes = await DV.Platform.camera.takePhoto();
final location = await DV.Platform.location.getCurrentLocation();
await DV.Platform.haptics.impact();
```

All permissions are centrally managed under the `dartvel` block in `pubspec.yaml`.
