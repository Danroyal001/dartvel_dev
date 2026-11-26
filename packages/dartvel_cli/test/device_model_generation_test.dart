// Models kept on the visitor's device: @DVModel(storage: DVModelStorage.device).
// A settings object (a text size, a voice language) is a DVModel like any
// other: the generator writes its value class, equality, copyWith and JSON,
// and keeps it in DVPreferenceStore. It has no table, page, admin or sync, so
// it is declared outside lib/models, which every database scanner reads.
import 'dart:io';

import 'package:dartvel_cli/src/generators/device_model_generator.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _voice = '''
// ignore_for_file: unused_element
import 'package:dartvel_core/dartvel.dart';

/// Where voice mode sits.
enum Position { top, centre }

/// The reader's voice settings.
@DVModel(storage: DVModelStorage.device, storageKey: 'shop.voice')
class const _VoiceSettings({
  final Position position = .top,
  final String language = 'en',
  final double rate = 1.0,
  final int repeats = 0,
  final bool slow = false,
  final num? volume,
  final DateTime? since,
});
''';

late Directory root;

Future<String> _generateApp(Map<String, String> files) async {
  for (final MapEntry<String, String> file in files.entries) {
    File(p.join(root.path, file.key))
      ..createSync(recursive: true)
      ..writeAsStringSync(file.value);
  }
  await DeviceModelGenerator.generate(root: root.path, pkgName: 'shop');
  return File(p.join(root.path, 'lib/dartvel_client/device_models.g.dart')).readAsStringSync();
}

void main() {
  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_device_models_');
    Directory(p.join(root.path, 'lib/dartvel_client')).createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a device model outside lib/models generates a typed value class that keeps its defaults', () async {
    final String out = await _generateApp(<String, String>{'lib/settings/voice.dart': _voice});
    expect(out, contains('enum Position { top, centre }'));
    expect(out, contains('class const VoiceSettings({'));
    expect(out, contains('final Position position = .top,'));
    expect(out, contains("final String language = 'en',"));
    expect(out, contains('final num? volume,'));
    expect(out, contains("static const String storageKey = 'shop.voice';"));
    expect(out, contains('static const VoiceSettings defaults = VoiceSettings();'));
    expect(out, contains('bool operator ==(Object other)'));
    expect(out, contains('int get hashCode'));
    expect(out, contains('VoiceSettings copyWith({'));
    expect(out, contains('static VoiceSettings get kept'));
    expect(out, contains('VoiceSettings keep()'));
    expect(out, contains('static void forget()'));
    expect(out, contains('static bool get isKept'));
    expect(out, contains('static VoiceSettings decode(String? stored)'));
    expect(out, contains('String encode()'));
    expect(out, contains('class VoiceSettingsParser'));
    expect(out, isNot(contains('Map<Object?, Object?>')));
    expect(out, isNot(contains('dynamic')));
  });

  test('JSON: an enum leaves by name, a DateTime as ISO text, and reading back is tolerant', () async {
    final String out = await _generateApp(<String, String>{'lib/settings/voice.dart': _voice});
    expect(out, contains("'position': position.name"));
    expect(out, contains("'since': since?.toIso8601String()"));
    // Missing or wrong-typed: the field's default, never a throw.
    expect(out, contains('Position.values.asNameMap()'));
    expect(out, contains('defaults.position'));
    expect(out, contains('is num ? '));
  });

  test('the runtime registers every device model before the first frame', () async {
    final String out = await _generateApp(<String, String>{'lib/settings/voice.dart': _voice});
    expect(out, contains('void registerDartvelDeviceModels() {'));
    expect(out, contains('VoiceSettings.kept;'));
  });

  test('without storageKey the key is <package>.<Model>', () async {
    final String out = await _generateApp(<String, String>{
      'lib/settings/voice.dart': _voice.replaceFirst(", storageKey: 'shop.voice'", ''),
    });
    expect(out, contains("static const String storageKey = 'shop.VoiceSettings';"));
  });

  test('an app with no device model still gets the registration function', () async {
    final String out = await _generateApp(<String, String>{'lib/main.dart': 'void main() {}\n'});
    expect(out, contains('void registerDartvelDeviceModels() {}'));
  });

  test('a database model elsewhere under lib is not a device model', () async {
    final String out = await _generateApp(<String, String>{
      'lib/settings/other.dart': "@DVModel()\nclass const _Other({required final String id});\n",
    });
    expect(out, isNot(contains('class const Other(')));
  });

  test('a non-nullable field with no default is refused, naming it', () {
    expect(
      () => dvDeviceModelLibrary(
        "@DVModel(storage: DVModelStorage.device)\nclass const _S({required final String name});\n",
        defaultKeyPrefix: 'shop',
        header: '',
      ),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', allOf(contains('S.name'), contains('default')))),
    );
  });

  test('a type a device model cannot keep is refused, naming the field and type', () {
    expect(
      () => dvDeviceModelLibrary(
        "@DVModel(storage: DVModelStorage.device)\nclass const _S({final List<String> tags = const <String>[]});\n",
        defaultKeyPrefix: 'shop',
        header: '',
      ),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', allOf(contains('S.tags'), contains('List<String>')))),
    );
  });

  test('a device model in lib/models is refused with the file and where to move it', () async {
    Directory(p.join(root.path, 'lib/models')).createSync(recursive: true);
    File(p.join(root.path, 'lib/models/voice.dart')).writeAsStringSync(_voice);
    await expectLater(
      ModelGenerator.generate(root: root.path, pkgName: 'shop'),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message', allOf(contains('lib/models/voice.dart'), contains('outside lib/models')))),
    );
  });

  test('the framework eats its own cooking: every checked-in framework device model matches the generator', () {
    final Directory repo = _repoRoot();
    for (final DVFrameworkDeviceModel model in dvFrameworkDeviceModels) {
      final File input = File(p.join(repo.path, model.input));
      final File output = File(p.join(repo.path, model.output));
      expect(input.existsSync(), isTrue, reason: model.input);
      expect(output.readAsStringSync(), dvFrameworkDeviceModelSource(model, input.readAsStringSync()),
          reason: '${model.output} is out of date: run dart run tool/generate_framework_models.dart');
    }
  });
}

Directory _repoRoot() {
  Directory dir = Directory.current;
  while (!File(p.join(dir.path, 'NEW_SPEC.md')).existsSync()) {
    dir = dir.parent;
  }
  return dir;
}
