// The Android half of a home widget.
//
// @DVHomeWidget generates the page and the route; that is the Dart half and
// it was all there was. A widget nobody can put on a home screen is a page at
// /widgets/<id> and a promise -- the annotation says "home widget" and
// Android is never told the application has one.
//
// What Android needs is an AppWidgetProvider, the metadata that describes the
// widget to the launcher, a layout to draw, and a receiver in the manifest.
// None of them can be added at run time, so all four are the build's.
import 'package:dartvel_cli/src/build/android_home_widget.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="dartvel_example"
        android:name="\${applicationName}">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''';

const List<DVHomeWidgetSpec> _widgets = <DVHomeWidgetSpec>[
  DVHomeWidgetSpec(
    id: 'step-counter',
    name: 'StepCounterWidget',
    route: '/widgets/step-counter',
  ),
];

void main() {
  test('the launcher is told the application has one', () {
    final String out = dvAndroidHomeWidgetManifest(_manifest, _widgets);

    expect(out, contains('android.appwidget.action.APPWIDGET_UPDATE'));
    expect(out, contains('StepCounterWidgetProvider'));
    expect(out, contains('@xml/dartvel_widget_step_counter'));
  });

  test('an application with no home widgets is left exactly as it was', () {
    expect(
      dvAndroidHomeWidgetManifest(_manifest, const <DVHomeWidgetSpec>[]),
      _manifest,
    );
  });

  test('building twice does not add the receiver twice', () {
    // Two providers under one name is a manifest the packager refuses, from
    // a build that succeeded.
    final String once = dvAndroidHomeWidgetManifest(_manifest, _widgets);
    expect(dvAndroidHomeWidgetManifest(once, _widgets), once);
  });

  test('the provider opens the page the widget was generated for', () {
    // "Home widgets can launch and navigate to pages within the app" is the
    // specification's own sentence, and this is the whole of it on Android:
    // a tap is a deep link to the route Dartvel generated.
    final String source =
        dvAndroidHomeWidgetProviderSource('com.example.app', _widgets.single);

    expect(source, contains('class StepCounterWidgetProvider'));
    expect(source, contains('package com.example.app;'));
    expect(source, contains('/widgets/step-counter'));
    expect(source, contains('PendingIntent'));
  });

  test('the metadata names a layout that exists', () {
    // A provider whose metadata points at a missing layout is installed and
    // then crashes the launcher when somebody places it -- in their home
    // screen, not in the build.
    final String meta = dvAndroidHomeWidgetMetadata(_widgets.single);

    expect(meta, contains('<appwidget-provider'));
    expect(meta, contains('@layout/dartvel_widget_step_counter'));
    expect(dvAndroidHomeWidgetLayout(_widgets.single), contains('android:id'));
  });

  test('the resource names are the identifier, made legal', () {
    // Android resource names take no hyphens. "step-counter" as a file name
    // is an aapt error at the end of a build; silently different names in
    // the manifest and on disk is worse.
    expect(dvAndroidWidgetResource('step-counter'), 'dartvel_widget_step_counter');
    expect(dvAndroidWidgetResource('nav.bar'), 'dartvel_widget_nav_bar');
  });

  test('two widgets are two providers', () {
    final String out = dvAndroidHomeWidgetManifest(_manifest, const <DVHomeWidgetSpec>[
      DVHomeWidgetSpec(id: 'a', name: 'AWidget', route: '/widgets/a'),
      DVHomeWidgetSpec(id: 'b', name: 'BWidget', route: '/widgets/b'),
    ]);

    expect(out, contains('AWidgetProvider'));
    expect(out, contains('BWidgetProvider'));
  });

  test('the launcher offers the widget by its title', () {
    // The identifier is a route segment. A widget picker listing
    // "step-counter" between two applications' widgets looks like a defect
    // in whichever application it came from, and nothing about it is
    // reported anywhere -- the build is green, the widget works, and it is
    // named after a URL.
    const DVHomeWidgetSpec titled = DVHomeWidgetSpec(
      id: 'step-counter',
      name: 'StepCounterWidget',
      route: '/widgets/step-counter',
      title: 'Steps today',
    );

    expect(dvAndroidHomeWidgetMetadata(titled), contains('Steps today'));
    expect(
      dvAndroidHomeWidgetProviderSource('com.example.app', titled),
      contains('Steps today'),
    );
  });

  group('the data the application leaves it', () {
    test('is what the provider draws, with the title as the fallback', () {
      // The provider drew a constant, so a home widget showed the same line
      // for ever: it looked like a working widget, which is why nothing
      // about it would ever be reported.
      final String source =
          dvAndroidHomeWidgetProviderSource('com.example.app', _widgets.single);

      expect(source, contains(dvHomeWidgetAndroidStore));
      expect(source, contains(dvHomeWidgetDataKey('step-counter')));
    });

    test('is committed before the launcher is asked to redraw', () {
      // apply() writes on another thread. The broadcast would reach the
      // provider first and the provider would read what was there before --
      // a redraw showing the previous value, which reads as a publish that
      // did nothing rather than as a race.
      final String java =
          dvAndroidWidgetPublisherSource('com.example.app', _widgets);

      expect(java, contains('.commit()'));
      expect(java, isNot(contains('.apply()')));
    });

    test('reaches every provider, not the first one', () {
      // The redraw is per component: AppWidgetManager is asked for the ids
      // placed for each provider by name. A widget missing from the list is
      // one that keeps showing yesterday's value while its neighbour on the
      // same home screen updates.
      final String java =
          dvAndroidWidgetPublisherSource('com.example.app', const <DVHomeWidgetSpec>[
        DVHomeWidgetSpec(id: 'a', name: 'AWidget', route: '/widgets/a'),
        DVHomeWidgetSpec(id: 'b', name: 'BWidget', route: '/widgets/b'),
      ]);

      expect(java, contains('com.example.app.AWidgetProvider'));
      expect(java, contains('com.example.app.BWidgetProvider'));
      expect(java, contains('EXTRA_APPWIDGET_IDS'));
    });

    test('is published through the class the runtime looks up by name', () {
      // Dart finds this class by a fixed name, because the application's
      // package is an applicationId the framework is compiled without. A
      // class in the application's own package would be a lookup that fails
      // on every device, and the publish answers false for that.
      final String java =
          dvAndroidWidgetPublisherSource('com.example.app', _widgets);

      expect(java, contains('package $dvAndroidWidgetPublisherPackage;'));
      expect('$dvAndroidWidgetPublisherPackage.DartvelWidgets'.replaceAll('.', '/'),
          dvHomeWidgetAndroidClass);
    });
  });

  test('a widget with no title is offered by its identifier', () {
    // The fallback is the identifier rather than an empty label: a widget
    // with no name in the picker cannot be picked.
    expect(dvAndroidHomeWidgetMetadata(_widgets.single), contains('step-counter'));
  });
}
