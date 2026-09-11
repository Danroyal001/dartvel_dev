# Basic Dartvel App

A simple example demonstrating the core features of the Dartvel framework.

## Features Demonstrated

- **File-based Routing**: Page in `lib/pages/index.page.dart` auto-routes to `/`
- **Data Loading**: Using `DartvelPage.loadData()` for async data fetching
- **Build Runner Integration**: The router and each page's body regenerate with `dart run build_runner build`
- **Web Build**: Production builds with `dartvel build web`
- **Preview Server**: Preview builds with `dartvel preview`

## Getting Started

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Generate the Client
```bash
dart run dartvel_cli:dartvel routes
dart run build_runner build --delete-conflicting-outputs
```

Both, in that order. `dartvel routes` writes the whole client: the barrel
every page imports, the functional widgets (`Button` here), models and
functions. build_runner's builders then regenerate the router and each page's
body over it. On their own they do not write the rest, so from a clean
checkout build_runner alone stops at the first page.

### 3. Run in Development
```bash
flutter run -d chrome
```

### 4. Build for Production
```bash
dart run dartvel_cli:dartvel build web --release
```

`dartvel build web` rather than `flutter build web`: the prerendered pages,
the service worker, the launch splash and the preload hints are Dartvel's,
and a plain Flutter build writes none of them.

### 5. Preview Production Build
```bash
dartvel preview
```

## Project Structure

```
lib/
├── pages/
│   ├── index.page.dart       # Main page (routes to /)
│   ├── index.loading.dart    # Loading state for index
│   └── index.error.dart      # Error state for index
├── backend/
│   └── functions/
│       ├── health.get.dart   # GET /api/health
│       └── contact.dart      # POST /api/contact
└── main.dart                 # App entry point
```

## What's Inside

### Page with Data Loading
The index page demonstrates async data loading:
```dart
@override
Future<Object?> loadData(Map<String, String> params, Map<String, String> query) async {
  await Future.delayed(const Duration(milliseconds: 500));
  return {'timestamp': DateTime.now().toIso8601String()};
}
```

Access the data with:
```dart
final data = DvDataScope.of(context).data as Map?;
```

### API Endpoints
- **Health Check**: `GET /api/health` - Returns server status
- **Contact Form**: `POST /api/contact` - Processes contact submissions

## Learn More

- [Dartvel Documentation](https://dartvel.dev)
- [Flutter Documentation](https://flutter.dev)
