// How Dart gets hold of the Android application Context.
//
// Everything worth binding on Android is reached through
// Context.getSystemService, and Dart has no Activity to ask. The bindings
// were written against `GetApplicationContext()`, which package:jni declares
// in dartjni.h -- and never defines. Reading a header and not checking there
// was an implementation is how every Android binding shipped dead while the
// capability list claimed them; the emulator said so in the end:
// "undefined symbol: GetApplicationContext".
//
// A ContentProvider is the supported way. Android creates every provider
// before Application.onCreate returns and hands it a Context, which is
// exactly what androidx.startup is built on. No hidden API, no
// ActivityThread, and nothing that depends on an Activity existing yet.
import 'dart:io';

import 'package:dartvel_cli/src/build/android_context_provider.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="example"
        android:name="\${applicationName}">
        <activity android:name=".MainActivity"/>
    </application>
</manifest>
''';

void main() {
  _oneName();
  group('the provider Java', () {
    test('caches the application Context, not the provider\'s own', () {
      final String source = dvAndroidContextProviderSource();

      // getContext() on a provider is the app context already on most
      // versions, but not by contract. Asking for it explicitly is one word
      // and removes the question.
      expect(source, contains('getApplicationContext()'));
      expect(source, contains('extends ContentProvider'));
      expect(source, contains('public static Context context()'));
    });

    test('is in a package that does not depend on the app\'s', () {
      // Dart looks this class up by name at run time, so the name has to be
      // the same in every application. Putting it in the app's own package
      // would make it depend on an applicationId the framework cannot know.
      expect(dvAndroidContextProviderSource(),
          contains('package dev.dartvel.jni;'));
      expect(dvAndroidContextProviderPath,
          'android/app/src/main/java/dev/dartvel/jni/DartvelContext.java');
      expect(dvAndroidContextClass, 'dev/dartvel/jni/DartvelContext');
    });

    test('every abstract method of ContentProvider is implemented', () {
      // A provider that does not compile is a build failure; one that throws
      // on a call nobody makes is fine, but it has to exist.
      final String source = dvAndroidContextProviderSource();
      for (final String method in const <String>[
        'query',
        'getType',
        'insert',
        'delete',
        'update',
      ]) {
        expect(source, contains(' $method('), reason: method);
      }
    });
  });

  group('the manifest', () {
    test('registers the provider inside the application', () {
      final String out = dvAndroidContextProviderManifest(_manifest);

      expect(out, contains('dev.dartvel.jni.DartvelContext'));
      expect(out.indexOf('DartvelContext'), lessThan(out.indexOf('</application>')));
      // Not exported: it exists to hold a Context, and a provider other
      // applications can reach is an attack surface for nothing.
      expect(out, contains('android:exported="false"'));
      // Unique per application, or two Dartvel apps cannot be installed side
      // by side -- Android refuses the second with a conflicting-provider
      // error that names neither of them helpfully.
      expect(out, contains(r'${applicationId}'));
    });

    test('writing it twice leaves one provider', () {
      final String once = dvAndroidContextProviderManifest(_manifest);
      final String twice = dvAndroidContextProviderManifest(once);

      expect(twice, once);
      expect(RegExp('DartvelContext').allMatches(twice).length, 1);
    });

    test('a manifest it cannot place the provider in is returned unchanged',
        () {
      // Better than a manifest with a provider outside <application>, which
      // the packager refuses with an error about the XML rather than about
      // this.
      const String odd = '<manifest></manifest>';
      expect(dvAndroidContextProviderManifest(odd), odd);
    });
  });
}


// Appended: the one name, in two packages.
//
// The CLI writes the class and the Flutter package looks it up by name. They
// cannot share a constant -- dartvel_flutter does not depend on dartvel_cli --
// so nothing but this stops them drifting. If they ever disagree, the build
// writes a provider nothing finds and every Android binding goes quiet again,
// on a device, with a message about a class that is right there in the APK.
void _oneName() {
  test('the CLI writes the class the Flutter package looks up', () {
    final String bindings = File(p.join(
      Directory.current.parent.path,
      'dartvel_flutter',
      'lib',
      'src',
      'platform',
      'android',
      'android_bindings_jni.dart',
    )).readAsStringSync();

    expect(bindings, contains("'$dvAndroidContextClass'"));
    // And the Java the CLI writes really declares that class in that package.
    final String java = dvAndroidContextProviderSource();
    final List<String> parts = dvAndroidContextClass.split('/');
    expect(java, contains('package ${parts.sublist(0, parts.length - 1).join('.')};'));
    expect(java, contains('class ${parts.last} '));
    expect(dvAndroidContextProviderPath, endsWith('${parts.last}.java'));
  });
}
