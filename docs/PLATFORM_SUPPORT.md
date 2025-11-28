# Platform Support Guide

Dartvel supports a wide range of platforms, enabling you to build truly universal applications.

## Supported Platforms

| Platform | Support Level | Build Command |
| :--- | :--- | :--- |
| **Android** | ✅ Stable | `flutter build apk` |
| **iOS** | ✅ Stable | `flutter build ios` |
| **Windows** | ✅ Stable | `flutter build windows` |
| **macOS** | ✅ Stable | `flutter build macos` |
| **Linux** | ✅ Stable | `flutter build linux` |
| **Web** | ✅ Stable | `flutter build web` |
| **Android TV** | ⚠️ Beta | `flutter build apk --target-platform android-arm64` |
| **Apple TV** | ⚠️ Beta | `flutter build ios --config-only` |
| **Tizen OS** | ⚠️ Beta | `flutter-tizen build tpk` |
| **webOS** | ⚠️ Beta | Custom tooling required |
| **Embedded Linux** | ⚠️ Beta | `flutter build linux --target-platform linux-arm64` |

## Platform-Specific Configuration

### Android

Update `android/app/build.gradle` to set the correct SDK versions.

### iOS

Ensure you have a valid Apple Developer account and configured signing in Xcode.

### Desktop (Windows, macOS, Linux)

Desktop support requires the relevant build tools (Visual Studio, Xcode, CMake/Ninja).

### Smart TVs (Tizen, webOS)

Requires specific SDKs (Tizen Studio, webOS CLI) to be installed and configured.
