// The first-frame picture is gone (7 Nov 2026): a page shows the splash, its
// loading line and its loading bar until the real app has drawn its first
// frame. A project that still names `dartvel.web.firstFrame` keeps building;
// the build says once that the key does nothing and can be deleted.
import 'package:dartvel_cli/src/build/removed_web_options.dart';
import 'package:test/test.dart';

void main() {
  group('dartvel.web.firstFrame', () {
    for (final Object? value in <Object?>[
      true,
      false,
      <String, Object?>{'widths': <Object?>[390, 1366]},
      <String, Object?>{'enabled': false},
      null,
    ]) {
      test('set to $value: one warning that the feature was removed', () {
        final List<String> warnings = dvRemovedWebOptionWarnings(<Object?, Object?>{
          'web': <Object?, Object?>{'firstFrame': value},
        });
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('dartvel.web.firstFrame'));
        expect(warnings.single, contains('removed'));
        expect(warnings.single, contains('delete'));
        expect(warnings.single.contains('\n'), isFalse, reason: 'one line');
      });
    }

    test('absent: nothing to say', () {
      expect(dvRemovedWebOptionWarnings(const <Object?, Object?>{}), isEmpty);
      expect(
          dvRemovedWebOptionWarnings(<Object?, Object?>{
            'web': <Object?, Object?>{'fonts': false},
          }),
          isEmpty);
      // A web section that is not a map is someone else's error to report.
      expect(dvRemovedWebOptionWarnings(<Object?, Object?>{'web': true}), isEmpty);
    });
  });
}
