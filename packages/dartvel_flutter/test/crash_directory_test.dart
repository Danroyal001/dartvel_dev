// Where a crash record is written, per platform.
//
// A record the next launch cannot find is a crash nobody hears about, and it
// fails quietly in both directions: a directory that is wiped between runs
// (the temp directory) looks like it works until the reboot, and a relative
// path written from a process whose working directory is `/` fails on the
// device and never in a test.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a read-only or full disk throws, without needing dart:io here.
class FileSystemLikeError implements Exception {
  const FileSystemLikeError();
}

void main() {
  test('DARTVEL_CRASH_DIR wins on every platform', () {
    for (final String os in <String>['linux', 'macos', 'windows', 'ios']) {
      expect(
        dvCrashDirectoryFor(
          appId: 'shop',
          os: os,
          environment: const <String, String>{
            'DARTVEL_CRASH_DIR': '/srv/crashes',
            'HOME': '/home/ada',
          },
        ),
        '/srv/crashes',
      );
    }
  });

  test('linux: XDG_DATA_HOME, else ~/.local/share, per application', () {
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'linux',
        environment: const <String, String>{
          'XDG_DATA_HOME': '/data',
          'HOME': '/home/ada',
        },
      ),
      '/data/shop/dartvel-crashes',
    );
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'linux',
        environment: const <String, String>{'HOME': '/home/ada'},
      ),
      '/home/ada/.local/share/shop/dartvel-crashes',
    );
  });

  test('macOS and iOS: Application Support under HOME', () {
    // HOME is the sandbox container on iOS and on a sandboxed Mac, and the
    // person's home otherwise; Library/Application Support is right in both.
    for (final String os in <String>['macos', 'ios']) {
      expect(
        dvCrashDirectoryFor(
          appId: 'shop',
          os: os,
          environment: const <String, String>{'HOME': '/Users/ada'},
        ),
        '/Users/ada/Library/Application Support/shop/dartvel-crashes',
      );
    }
  });

  test('windows: LOCALAPPDATA, else APPDATA', () {
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'windows',
        environment: const <String, String>{
          'LOCALAPPDATA': r'C:\Users\ada\AppData\Local',
          'APPDATA': r'C:\Users\ada\AppData\Roaming',
        },
      ),
      r'C:\Users\ada\AppData\Local\shop\dartvel-crashes',
    );
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'windows',
        environment: const <String, String>{
          'APPDATA': r'C:\Users\ada\AppData\Roaming',
        },
      ),
      r'C:\Users\ada\AppData\Roaming\shop\dartvel-crashes',
    );
  });

  test('android: beside the device state directory in the files directory',
      () {
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'android',
        environment: const <String, String>{},
        androidStateDirectory: '/data/user/0/com.shop/files/dartvel-device',
      ),
      '/data/user/0/com.shop/files/dartvel-crashes',
    );
  });

  group('the install id', () {
    // Generated once per install and read back after that. One made per
    // launch would count every launch as a person in crash-free users.
    test('is generated and stored when there is none', () {
      final List<String> written = <String>[];
      final String id = dvInstallIdFrom(
        read: () => null,
        write: written.add,
      );
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(written, <String>[id]);
    });

    test('is the stored one afterwards, and nothing is rewritten', () {
      final List<String> written = <String>[];
      const String stored = '0123456789abcdef0123456789abcdef';
      expect(
        dvInstallIdFrom(read: () => '$stored\n', write: written.add),
        stored,
      );
      expect(written, isEmpty);
    });

    test('a stored value that is not an id is replaced, not trusted', () {
      // A record cut short, or somebody's user id written there by hand:
      // either would ride along on every report.
      final List<String> written = <String>[];
      final String id = dvInstallIdFrom(
        read: () => 'ada@example.com',
        write: written.add,
      );
      expect(id, isNot('ada@example.com'));
      expect(written, <String>[id]);
    });

    test('storage that cannot be written still yields an id', () {
      final String id = dvInstallIdFrom(
        read: () => throw const FileSystemLikeError(),
        write: (String _) => throw const FileSystemLikeError(),
      );
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  test('no usable base is null, never a relative or root path', () {
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'android',
        environment: const <String, String>{'HOME': '/'},
      ),
      isNull,
    );
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'linux',
        environment: const <String, String>{'HOME': ''},
      ),
      isNull,
    );
    expect(
      dvCrashDirectoryFor(
        appId: 'shop',
        os: 'windows',
        environment: const <String, String>{},
      ),
      isNull,
    );
  });
}
