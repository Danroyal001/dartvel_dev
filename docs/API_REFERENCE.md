# API Reference

## Core Modules

### Authentication (`dartvel_core/auth`)

```dart
// Initialize auth
Auth.initialize(MyAuthProvider());

// Sign in
final user = await Auth.instance.signIn('email@example.com', 'password');
```

### Database (`dartvel_core/database`)

```dart
// Access database
final db = DatabaseManager.instance.db;

// Run transaction
await db.transaction(() async {
  // ...
});
```

### Caching (`dartvel_core/cache`)

```dart
final cache = InMemoryCache();
await cache.set('key', 'value', ttl: Duration(minutes: 5));
```

### Background Tasks (`dartvel_core/tasks`)

```dart
TaskManager.instance.register(MyTask());
await TaskManager.instance.schedule('my_task', {'data': 123});
```

## Flutter Widgets

### SEO (`dartvel_flutter/seo`)

```dart
SeoHead(
  metadata: SeoMetadata(
    title: 'My Page',
    description: 'Description',
  ),
  child: Scaffold(...),
)
```

### i18n (`dartvel_flutter/i18n`)

```dart
Text('hello_world'.tr())
```
