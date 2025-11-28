# Dartvel CLI Doctor Command - Implementation Instructions

## CRITICAL: Doctor Command Requirements

**The `dartvel doctor` command MUST:**

1. ✅ Work from ANY directory (does NOT require pubspec.yaml)
2. ✅ Check system-level dependencies:
   - Dart SDK (required)
   - Flutter SDK (required)
   - Git (recommended)
   - **Shorebird** (optional - for OTA updates)
   - **Codemagic CLI** (optional - for CI/CD)

3. ✅ Run the actual `flutter doctor -v` command at the end
4. ✅ Optionally check project config if in a Dartvel project directory

## Implementation Pattern

```dart
@override
Future<void> run() async {
  Logger.log('🏥 Dartvel Doctor\n');
  
  // Check required tools
  await _checkDartSDK();
  await _checkFlutterSDK();
  await _checkGit();
  
  // Check optional tools
  await _checkShorebird();
  await _checkCodemagic();
  
  // Check project if in one
  if (pubspecExists) {
    await _checkProjectConfig();
  }
  
  // IMPORTANT: Run flutter doctor at the end
  await _runFlutterDoctor();
}
```

## DO NOT:
- ❌ Require pubspec.yaml to exist
- ❌ Exit early if not in a project
- ❌ Skip flutter doctor execution
- ❌ Make Shorebird/Codemagic required

## Expected Output

```
🏥 Dartvel Doctor

✅ Dart SDK: Dart SDK version 3.10.1
✅ Flutter SDK: Flutter 3.38.3
✅ Git: git version 2.x.x
✅ Shorebird: 1.x.x
ℹ️  Codemagic CLI: Not installed (optional for CI/CD)

📦 Not in a Dartvel project

✅ All system checks passed!

🔍 Running Flutter Doctor...

[Full flutter doctor -v output follows]
```

## File Location
`packages/dartvel_cli/lib/src/commands/doctor_command.dart`

**Last Updated:** November 28, 2025
**DO NOT DEVIATE FROM THESE REQUIREMENTS**
