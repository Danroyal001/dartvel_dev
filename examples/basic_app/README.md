# Basic Dartvel App

A simple example demonstrating the core features of the Dartvel framework.

## Features Demonstrated

- **File-based Routing**: Page in `lib/pages/index.page.dart` auto-routes to `/`
- **Data Loading**: Using `DartvelPage.loadData()` for async data fetching
- **Build Runner Integration**: Automatic code generation with `dart run build_runner build`
- **Web Build**: Production builds with `flutter build web`
- **Preview Server**: Preview builds with `dartvel preview`

## Getting Started

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Generate Router
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Run in Development
```bash
flutter run -d chrome
```

### 4. Build for Production
```bash
flutter build web --release
```

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
