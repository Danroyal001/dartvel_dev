# reproduction_app

A new Dartvel project.

## Getting Started

### Prerequisites

- Flutter SDK >= 3.4.0
- Dart SDK >= 3.4.0

### Installation

```bash
flutter pub get
```

### Development

```bash
dartvel dev
```

This will:
- Start the backend server on http://localhost:3000
- Run your Flutter app with hot reload

### Project Structure

```
lib/
├── pages/              # Page components (file-based routing)
├── backend/
│   └── functions/      # API endpoints
└── main.dart

.env                    # Environment variables (gitignored)
pubspec.yaml           # Dependencies and Dartvel config
```

### Adding Pages

Create a new file in `lib/pages/`:

```dart
// lib/pages/about.page.dart
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class AboutPage extends DartvelPage {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(child: Text('About page')),
    );
  }
}
```

Route is automatically available at `/about`.

### Adding API Endpoints

Create a new file in `lib/backend/functions/`:

```dart
// lib/backend/functions/hello.get.dart
Map<String, dynamic> handler() {
  return {'message': 'Hello World!'};
}
```

Endpoint is automatically available at `GET /api/hello`.

### Building for Production

```bash
dartvel build
```

## Learn More

- [Dartvel Documentation](https://dartvel.dev)
- [Flutter Documentation](https://flutter.dev)

## License

MIT
