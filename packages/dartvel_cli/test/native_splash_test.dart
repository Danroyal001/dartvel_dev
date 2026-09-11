// The splash a Dartvel application shows before its first frame.
//
// Every platform Flutter targets shows something between the process starting
// and the first frame: Android draws the launch theme's window background,
// iOS the launch storyboard, the web whatever the page is before the engine
// has painted -- and the templates `flutter create` writes make every one of
// them white. An application with a dark page therefore opens on a white
// flash on every platform, and on the web, where main.dart.js is megabytes,
// the white page lasts as long as the download.
//
// These tests pin what the build writes and, as much, what it refuses to
// touch: a launch screen somebody designed by hand is theirs, and a build that
// replaced it without being asked would be a worse bug than the white one.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The files `flutter create` writes, verbatim, so "is this still the
// template?" is tested against the real thing rather than a paraphrase.
const String _androidLaunch = '''
<?xml version="1.0" encoding="utf-8"?>
<!-- Modify this file to customize your launch splash screen -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@android:color/white" />

    <!-- You can insert your own image assets here -->
    <!-- <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/launch_image" />
    </item> -->
</layer-list>
''';

const String _androidLaunchV21 = '''
<?xml version="1.0" encoding="utf-8"?>
<!-- Modify this file to customize your launch splash screen -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="?android:colorBackground" />

    <!-- You can insert your own image assets here -->
    <!-- <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/launch_image" />
    </item> -->
</layer-list>
''';

const String _androidStyles = '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
''';

const String _storyboard = '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="12121" systemVersion="16G29" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="12089"/>
    </dependencies>
    <scenes>
        <!--View Controller-->
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <layoutGuides>
                        <viewControllerLayoutGuide type="top" id="Ydg-fD-yQy"/>
                        <viewControllerLayoutGuide type="bottom" id="xbc-2k-c8Z"/>
                    </layoutGuides>
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">
                            </imageView>
                        </subviews>
                        <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                        <constraints>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="1a2-6s-vTC"/>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="4X2-HB-R7a"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
    <resources>
        <image name="LaunchImage" width="168" height="185"/>
    </resources>
</document>
''';

const String _launchImageContents = '''
{
  "images" : [
    {
      "idiom" : "universal",
      "filename" : "LaunchImage.png",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "filename" : "LaunchImage@2x.png",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "filename" : "LaunchImage@3x.png",
      "scale" : "3x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
''';

const String _macosWindow = '''
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
''';

const String _linuxApplication = '''
  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
''';

const String _webIndex = '''
<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <title>app</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

late Directory root;

String _read(String relative) =>
    File(p.join(root.path, relative)).readAsStringSync();

void _write(String relative, String contents) => File(p.join(root.path, relative))
  ..parent.createSync(recursive: true)
  ..writeAsStringSync(contents);

bool _exists(String relative) => File(p.join(root.path, relative)).existsSync();

/// A solid PNG of [width] by [height], written at [relative].
void _png(String relative, int width, int height,
    {int r = 255, int g = 0, int b = 0}) {
  final DVRgbaImage image = DVRgbaImage(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.set(x, y, r: r, g: g, b: b);
    }
  }
  File(p.join(root.path, relative))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(dvPngEncode(image));
}

(int, int) _size(String relative) {
  final DVRgbaImage image =
      dvPngDecode(File(p.join(root.path, relative)).readAsBytesSync());
  return (image.width, image.height);
}

DVSplash _splash(Map<String, Object?> dartvel) =>
    DVSplash.fromConfig(dartvel, root: root.path);

const String _res = 'android/app/src/main/res';

void _androidTemplate() {
  _write('$_res/drawable/launch_background.xml', _androidLaunch);
  _write('$_res/drawable-v21/launch_background.xml', _androidLaunchV21);
  _write('$_res/values/styles.xml', _androidStyles);
}

void _iosTemplate() {
  _write('ios/Runner/Base.lproj/LaunchScreen.storyboard', _storyboard);
  _write('ios/Runner/Assets.xcassets/LaunchImage.imageset/Contents.json',
      _launchImageContents);
  // Flutter's placeholders are a transparent 1x1 each.
  for (final String name in <String>[
    'LaunchImage.png',
    'LaunchImage@2x.png',
    'LaunchImage@3x.png',
  ]) {
    final File file = File(p.join(root.path,
        'ios/Runner/Assets.xcassets/LaunchImage.imageset', name));
    file.writeAsBytesSync(dvPngEncode(DVRgbaImage(1, 1)));
  }
}

void main() {
  setUp(() => root = Directory.systemTemp.createTempSync('dv_splash_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('what the splash is, from what the project already says', () {
    test('with nothing declared it still follows the system dark mode', () {
      // The white flash is worst for someone whose phone is in dark mode, and
      // that is the case a project declaring nothing is most likely to hit.
      final DVSplash splash = _splash(const <String, Object?>{});

      expect(splash.enabled, isTrue);
      expect(splash.color, dvSplashDefaultColor);
      expect(splash.darkColor, dvSplashDefaultDarkColor);
      expect(splash.darkColor, isNot(splash.color));
      expect(splash.problems, isEmpty);
    });

    test('the PWA background colour is used when the splash names none', () {
      // It is the colour the application already says its page is: Chrome
      // paints it behind an installed app's launch, so two splashes that
      // disagreed would be visible one after the other.
      final DVSplash splash = _splash(const <String, Object?>{
        'pwa': <String, Object?>{'backgroundColor': '#0a0d13'},
      });

      expect(splash.color, '#0A0D13');
      // A declared colour is a decision, so it holds in both schemes rather
      // than being swapped for a default dark nobody chose.
      expect(splash.darkColor, '#0A0D13');
    });

    test('and the splash colour wins over it', () {
      final DVSplash splash = _splash(const <String, Object?>{
        'splash': <String, Object?>{'color': '#112233', 'darkColor': '#445566'},
        'pwa': <String, Object?>{'backgroundColor': '#FFFFFF'},
      });

      expect(splash.color, '#112233');
      expect(splash.darkColor, '#445566');
    });

    test('three-digit colours are expanded', () {
      expect(_splash(const <String, Object?>{
        'splash': <String, Object?>{'color': '#abc'},
      }).color, '#AABBCC');
    });

    test('a colour that is not one is reported, not quietly made white', () {
      final DVSplash splash = _splash(const <String, Object?>{
        'splash': <String, Object?>{'color': 'midnight'},
        'pwa': <String, Object?>{'backgroundColor': '#101010'},
      });

      expect(splash.problems.single, contains('dartvel.splash.color'));
      // Falls through to the next thing the project declared.
      expect(splash.color, '#101010');
    });

    test('an image that is not there is reported', () {
      final DVSplash splash = _splash(const <String, Object?>{
        'splash': <String, Object?>{'image': 'assets/nope.png'},
      });

      expect(splash.image, isNull);
      expect(splash.problems.single, contains('assets/nope.png'));
    });

    test('the project icon stands in for an image nobody named', () {
      _png('web/icon.png', 64, 64);
      final DVSplash splash = _splash(const <String, Object?>{});

      expect(splash.image, isNotNull);
      expect(splash.imageIsIcon, isTrue);
    });

    test('enabled: false turns it off', () {
      expect(_splash(const <String, Object?>{
        'splash': <String, Object?>{'enabled': false},
      }).enabled, isFalse);
    });

    test('reads pubspec.yaml', () {
      _write('pubspec.yaml', '''
name: app
dartvel:
  splash:
    color: "#123456"
''');
      expect(DVSplash.of(root.path).color, '#123456');
    });
  });

  group('web', () {
    final DVSplash splash = DVSplash(color: '#112233', darkColor: '#445566');

    test('paints the colour before anything loads, in both schemes', () {
      final String html = dvWebSplashApply(_webIndex, splash);

      expect(html, contains('id="dartvel-splash"'));
      expect(html, contains('#112233'));
      expect(html, contains('prefers-color-scheme:dark'));
      expect(html, contains('#445566'));
    });

    test('goes first in the body, so the Flutter view stacks above it', () {
      // The engine appends <flutter-view> to the end of the body. Placed
      // before it, the splash is underneath the application the moment the
      // application paints anything, whether or not the script that removes
      // it is ever allowed to run.
      final String html = dvWebSplashApply(_webIndex, splash);
      final int body = html.indexOf('<body>');

      expect(html.indexOf('id="dartvel-splash"'), greaterThan(body));
      expect(html.indexOf('id="dartvel-splash"'),
          lessThan(html.indexOf('flutter_bootstrap.js')));
    });

    test('is removed on the first frame', () {
      expect(dvWebSplashApply(_webIndex, splash), contains('flutter-first-frame'));
    });

    test('never covers the page a reader without scripting gets', () {
      // The prerendered text is a noscript block. Without scripting the
      // first-frame event never comes, so a splash left in place would sit
      // over the only content that page has.
      expect(dvWebSplashApply(_webIndex, splash),
          contains('<noscript><style>#dartvel-splash{display:none}</style></noscript>'));
    });

    test('applying twice is applying once, and a new colour replaces the old',
        () {
      final String once = dvWebSplashApply(_webIndex, splash);
      expect(dvWebSplashApply(once, splash), once);

      final String recoloured = dvWebSplashApply(
          once, DVSplash(color: '#AA0000', darkColor: '#AA0000'));
      expect(recoloured, isNot(contains('#112233')));
      expect('id="dartvel-splash"'.allMatches(recoloured), hasLength(1));
    });

    test('an image is centred at its logical width, with a dark variant', () {
      final String html = dvWebSplashApply(_webIndex, splash,
          imageUrl: 'dartvel-splash.png',
          darkImageUrl: 'dartvel-splash-dark.png',
          imageWidth: 120);

      expect(html, contains('src="dartvel-splash.png"'));
      expect(html, contains('srcset="dartvel-splash-dark.png"'));
      expect(html, contains('media="(prefers-color-scheme: dark)"'));
      expect(html, contains('width:120px'));
    });

    test('the writer puts the image beside index.html and links it', () {
      _png('assets/splash.png', 400, 200);
      _write('build/web/index.html', _webIndex);
      final DVSplashResult result = dvWriteWebSplash(
        Directory(p.join(root.path, 'build', 'web')),
        _splash(const <String, Object?>{
          'splash': <String, Object?>{'image': 'assets/splash.png'},
        }),
      );

      expect(result.written, contains('build/web/index.html'));
      // Treated as a 4x image, the way a density-bucketed Android drawable
      // is, and written at 3x for the densest screens a browser has.
      expect(_size('build/web/dartvel-splash.png'), (300, 150));
      expect(_read('build/web/index.html'), contains('width:100px'));
    });

    test('disabled leaves the page alone', () {
      _write('build/web/index.html', _webIndex);
      dvWriteWebSplash(Directory(p.join(root.path, 'build', 'web')),
          _splash(const <String, Object?>{
            'splash': <String, Object?>{'enabled': false},
          }));
      expect(_read('build/web/index.html'), _webIndex);
    });
  });

  group('Android', () {
    test('the template launch background becomes the splash colour', () {
      _androidTemplate();
      dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'color': '#112233', 'darkColor': '#445566'},
      }));

      for (final String dir in <String>['drawable', 'drawable-v21']) {
        final String xml = _read('$_res/$dir/launch_background.xml');
        expect(xml, contains('@color/dartvel_splash_background'));
        expect(xml, isNot(contains('@android:color/white')));
        expect(xml, isNot(contains('?android:colorBackground')));
      }
      expect(_read('$_res/values/dartvel_splash.xml'), contains('#112233'));
      // values-night is how Android picks the dark one: the drawable names a
      // colour and the resource system chooses which.
      expect(_read('$_res/values-night/dartvel_splash.xml'), contains('#445566'));
    });

    test('Android 12 gets its own splash background', () {
      // From API 31 the system draws its own splash and ignores a layer-list
      // window background, so without these every Android 12+ phone opens on
      // the system's white or black whatever launch_background.xml says.
      _androidTemplate();
      dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{}));

      for (final String dir in <String>['values-v31', 'values-night-v31']) {
        final String xml = _read('$_res/$dir/styles.xml');
        expect(xml, contains('name="LaunchTheme"'));
        expect(xml, contains(
            '<item name="android:windowSplashScreenBackground">@color/dartvel_splash_background</item>'));
      }
    });

    test('a launch background somebody designed is left alone', () {
      const String custom = '''
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@drawable/my_gradient" />
</layer-list>
''';
      _androidTemplate();
      _write('$_res/drawable/launch_background.xml', custom);

      final DVSplashResult result =
          dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{}));

      expect(_read('$_res/drawable/launch_background.xml'), custom);
      expect(result.skipped.join('\n'), contains('overwrite'));
    });

    test('unless the project says to overwrite it', () {
      _androidTemplate();
      _write('$_res/drawable/launch_background.xml', '<layer-list/>');

      dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'overwrite': true},
      }));

      expect(_read('$_res/drawable/launch_background.xml'),
          contains('@color/dartvel_splash_background'));
    });

    test('an Android 12 style the project wrote is its own', () {
      _androidTemplate();
      _write('$_res/values-v31/styles.xml', '<resources/>');

      dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{}));

      expect(_read('$_res/values-v31/styles.xml'), '<resources/>');
    });

    test('an image is written per density and centred', () {
      _androidTemplate();
      _png('assets/splash.png', 400, 200);
      _png('assets/splash-dark.png', 400, 200, r: 0, g: 0, b: 255);

      dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{
          'image': 'assets/splash.png',
          'darkImage': 'assets/splash-dark.png',
        },
      }));

      // The source is read as xxxhdpi, 4x, so 400 pixels is 100dp.
      expect(_size('$_res/drawable-mdpi/dartvel_splash_image.png'), (100, 50));
      expect(_size('$_res/drawable-xhdpi/dartvel_splash_image.png'), (200, 100));
      expect(_size('$_res/drawable-xxxhdpi/dartvel_splash_image.png'), (400, 200));
      expect(_exists('$_res/drawable-night-mdpi/dartvel_splash_image.png'), isTrue);
      expect(_read('$_res/drawable/launch_background.xml'),
          contains('@drawable/dartvel_splash_image'));
    });

    test('an Android 12 icon sits inside the circle the system crops to', () {
      _androidTemplate();
      _png('assets/a12.png', 512, 512);

      dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'android12Image': 'assets/a12.png'},
      }));

      // 288dp canvas, the artwork within the middle 192.
      expect(_size('$_res/drawable-mdpi/dartvel_splash_android12.png'), (288, 288));
      final DVRgbaImage icon = dvPngDecode(File(p.join(
              root.path, '$_res/drawable-mdpi/dartvel_splash_android12.png'))
          .readAsBytesSync());
      expect(icon.get(10, 10)[3], 0, reason: 'the corner must be transparent');
      expect(icon.get(144, 144)[0], 255, reason: 'the artwork is in the middle');
      expect(_read('$_res/values-v31/styles.xml'),
          contains('@drawable/dartvel_splash_android12'));
    });

    test('running twice changes nothing the second time', () {
      _androidTemplate();
      final DVSplash splash = _splash(const <String, Object?>{});
      dvWriteAndroidSplash(root.path, splash);
      final String first = _read('$_res/drawable/launch_background.xml');
      final DVSplashResult second = dvWriteAndroidSplash(root.path, splash);

      expect(_read('$_res/drawable/launch_background.xml'), first);
      expect(second.written, isEmpty);
    });

    test('a project with no Android runner is not an error', () {
      expect(dvWriteAndroidSplash(root.path, _splash(const <String, Object?>{})).written,
          isEmpty);
    });
  });

  group('iOS', () {
    test('the template storyboard takes a colour that follows dark mode', () {
      _iosTemplate();
      dvWriteIosSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'color': '#112233', 'darkColor': '#445566'},
      }));

      final String storyboard = _read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
      expect(storyboard, contains('<color key="backgroundColor" name="DartvelSplashBackground"/>'));
      expect(storyboard, isNot(contains('red="1" green="1" blue="1"')));

      final Map<String, Object?> colorset = jsonDecode(_read(
              'ios/Runner/Assets.xcassets/DartvelSplashBackground.colorset/Contents.json'))
          as Map<String, Object?>;
      final String encoded = jsonEncode(colorset);
      expect(encoded, contains('"luminosity"'));
      expect(encoded, contains('"dark"'));
      expect(encoded, contains('"0x44"'));
      expect(encoded, contains('"0x11"'));
    });

    test('a storyboard somebody designed is left alone', () {
      _iosTemplate();
      const String custom = '<document launchScreen="YES"><!-- mine --></document>';
      _write('ios/Runner/Base.lproj/LaunchScreen.storyboard', custom);

      final DVSplashResult result =
          dvWriteIosSplash(root.path, _splash(const <String, Object?>{}));

      expect(_read('ios/Runner/Base.lproj/LaunchScreen.storyboard'), custom);
      expect(result.skipped.join('\n'), contains('overwrite'));
    });

    test('an image fills the LaunchImage set at 1x, 2x and 3x', () {
      _iosTemplate();
      _png('assets/splash.png', 400, 200);

      dvWriteIosSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'image': 'assets/splash.png'},
      }));

      const String set = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
      expect(_size('$set/LaunchImage.png'), (100, 50));
      expect(_size('$set/LaunchImage@2x.png'), (200, 100));
      expect(_size('$set/LaunchImage@3x.png'), (300, 150));
      expect(_read('ios/Runner/Base.lproj/LaunchScreen.storyboard'),
          contains('<image name="LaunchImage" width="100" height="50"/>'));
    });

    test('a LaunchImage somebody supplied is left alone', () {
      _iosTemplate();
      const String set = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
      _png('$set/LaunchImage.png', 50, 50, r: 1);
      _png('assets/splash.png', 400, 200);

      dvWriteIosSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'image': 'assets/splash.png'},
      }));

      expect(_size('$set/LaunchImage.png'), (50, 50));
    });
  });

  group('desktop', () {
    test('the macOS view is given the colour before its first frame', () {
      // The window is visible at launch and FlutterView is black until the
      // first frame, so a light application opens on a black window.
      _write('macos/Runner/MainFlutterWindow.swift', _macosWindow);
      final DVSplash splash = _splash(const <String, Object?>{
        'splash': <String, Object?>{'color': '#112233', 'darkColor': '#445566'},
      });

      dvWriteMacosSplash(root.path, splash);
      final String once = _read('macos/Runner/MainFlutterWindow.swift');
      dvWriteMacosSplash(root.path, splash);

      expect(once, contains('flutterViewController.backgroundColor ='));
      expect(once, contains('darkAqua'));
      expect(_read('macos/Runner/MainFlutterWindow.swift'), once);
      expect('flutterViewController.backgroundColor ='.allMatches(once),
          hasLength(1));
    });

    test('a macOS window with no FlutterViewController line is left alone', () {
      _write('macos/Runner/MainFlutterWindow.swift', 'class MainFlutterWindow {}');
      final DVSplashResult result =
          dvWriteMacosSplash(root.path, _splash(const <String, Object?>{}));
      expect(_read('macos/Runner/MainFlutterWindow.swift'), 'class MainFlutterWindow {}');
      expect(result.skipped, isNotEmpty);
    });

    test('the Linux view background takes the colour, and keeps taking it', () {
      _write('linux/runner/my_application.cc', _linuxApplication);

      dvWriteLinuxSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'color': '#112233'},
      }));
      expect(_read('linux/runner/my_application.cc'),
          contains('gdk_rgba_parse(&background_color, "#112233");'));

      dvWriteLinuxSplash(root.path, _splash(const <String, Object?>{
        'splash': <String, Object?>{'color': '#445566'},
      }));
      expect(_read('linux/runner/my_application.cc'),
          contains('gdk_rgba_parse(&background_color, "#445566");'));
    });

    test('a Linux background somebody chose is left alone', () {
      _write('linux/runner/my_application.cc',
          _linuxApplication.replaceFirst('"#000000"', '"#00000000"'));
      dvWriteLinuxSplash(root.path, _splash(const <String, Object?>{}));
      expect(_read('linux/runner/my_application.cc'), contains('"#00000000"'));
    });

    test('Windows needs nothing, and says why', () {
      final DVSplashResult result =
          dvWriteNativeSplash(root.path, 'windows', _splash(const <String, Object?>{}));
      expect(result.written, isEmpty);
      expect(result.skipped.single, contains('first frame'));
    });
  });

  test('disabled writes nothing anywhere', () {
    _androidTemplate();
    _iosTemplate();
    final DVSplash off = _splash(const <String, Object?>{
      'splash': <String, Object?>{'enabled': false},
    });
    for (final String platform in <String>['android', 'ios', 'macos', 'linux']) {
      expect(dvWriteNativeSplash(root.path, platform, off).written, isEmpty);
    }
    expect(_read('$_res/drawable/launch_background.xml'), _androidLaunch);
  });
}
