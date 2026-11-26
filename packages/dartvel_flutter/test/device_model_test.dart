// A model kept on the visitor's device, as generated: the framework's own
// DVVoiceSettings and DVAccessibilitySettings go through the same emitter as
// an application's @DVModel(storage: DVModelStorage.device).
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/accessibility/accessibility_settings.g.dart' as framework;
import 'package:dartvel_flutter/src/accessibility/voice_settings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DVMemoryPreferenceStore store;
  setUp(() {
    store = DVMemoryPreferenceStore();
    DVPreferenceStore.instance = store;
    DVVoiceSettings.forget();
  });
  tearDown(DVPreferenceStore.reset);

  test('a value: equal when its fields are, copyWith replaces only what it names', () {
    expect(const DVVoiceSettings(), DVVoiceSettings.defaults);
    expect(const DVVoiceSettings(language: 'yo'), const DVVoiceSettings(language: 'yo'));
    expect(const DVVoiceSettings(language: 'yo').hashCode, const DVVoiceSettings(language: 'yo').hashCode);
    expect(const DVVoiceSettings(language: 'yo'), isNot(const DVVoiceSettings()));
    final DVVoiceSettings centred = const DVVoiceSettings(language: 'ha').copyWith(position: DVVoicePosition.centre);
    expect(centred.position, DVVoicePosition.centre);
    expect(centred.language, 'ha');
  });

  test('keep() stores it and makes it kept; a fresh read finds it; forget() goes back to defaults', () {
    expect(DVVoiceSettings.isKept, isFalse);
    expect(DVVoiceSettings.kept, DVVoiceSettings.defaults);
    const DVVoiceSettings(position: DVVoicePosition.centre, language: 'ig').keep();
    expect(DVVoiceSettings.kept.language, 'ig');
    expect(DVVoiceSettings.isKept, isTrue);
    expect(store.read('dartvel.voice'), '{"position":"centre","language":"ig"}');
    expect(DVVoiceSettings.decode(store.read('dartvel.voice')), const DVVoiceSettings(position: DVVoicePosition.centre, language: 'ig'));
    DVVoiceSettings.forget();
    expect(DVVoiceSettings.kept, DVVoiceSettings.defaults);
    expect(store.read('dartvel.voice'), isNull);
  });

  test('reading back is tolerant: broken, missing and wrong-typed values are the defaults', () {
    expect(DVVoiceSettings.decode(null), DVVoiceSettings.defaults);
    expect(DVVoiceSettings.decode('not json'), DVVoiceSettings.defaults);
    expect(DVVoiceSettings.decode('[1,2]'), DVVoiceSettings.defaults);
    expect(DVVoiceSettings.decode('{"position":"sideways","language":7}'), DVVoiceSettings.defaults);
    // An older value under the same key, with fields this model does not have.
    expect(DVVoiceSettings.decode('{"v":2,"zone":"top","position":"centre","largeText":true}').position, DVVoicePosition.centre);
  });

  test('accessibility settings keep the wire format the SSR-first head reads, and read the 3.47.16 value', () {
    const framework.DVAccessibilitySettings chosen = framework.DVAccessibilitySettings(textScale: 1.35, highContrast: true);
    expect(chosen.encode(), '{"textScale":1.35,"highContrast":true,"reducedMotion":false}');
    final framework.DVAccessibilitySettings old =
        framework.DVAccessibilitySettings.decode('{"v":1,"textScale":2,"highContrast":false,"reducedMotion":true}');
    expect(old.textScale, 2.0);
    expect(old.reducedMotion, isTrue);
  });

  testWidgets('a widget reading context.global rebuilds when the value is kept', (WidgetTester tester) async {
    DVVoiceSettings.kept;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (BuildContext context) => Text(context.global<DVVoiceSettings>().language)),
    ));
    expect(find.text('en'), findsOneWidget);
    const DVVoiceSettings(language: 'pcm').keep();
    await tester.pump();
    expect(find.text('pcm'), findsOneWidget);
  });
}
