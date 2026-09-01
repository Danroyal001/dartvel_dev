// `dartvel explain <code>`.
//
// The specification publishes the DV-WINDOW and DV-KIOSK codes as a contract
// and says this command reads them. It did not exist, so a developer who found
// DV-WINDOW-004 in a log had to search a 4,000-line document for it.
import 'package:dartvel_cli/src/commands/explain_command.dart';
import 'package:test/test.dart';

void main() {
  group('explaining a code', () {
    test('a known code is explained with its level and reason', () {
      final String out = dvExplain(<String>['DV-WINDOW-004']);

      expect(out, contains('DV-WINDOW-004'));
      expect(out, contains('warning'));
      expect(out, contains('platform refused'));
    });

    test('a pasted code still resolves', () {
      // It arrives out of a log, so case and stray whitespace are the normal
      // case rather than the exception.
      expect(dvExplain(<String>['  dv-window-004 ']), contains('DV-WINDOW-004'));
    });

    test('an unknown code says so and suggests the family', () {
      // Rather than printing nothing, which reads like the command failed.
      final String out = dvExplain(<String>['DV-WINDOW-999']);

      expect(out, contains('DV-WINDOW-999'));
      expect(out.toLowerCase(), contains('not a known'));
      expect(out, contains('DV-WINDOW-001'),
          reason: 'the family it looks like it belongs to is worth listing');
    });

    test('a family name lists the whole family', () {
      final String out = dvExplain(<String>['DV-KIOSK']);

      expect(out, contains('DV-KIOSK-001'));
      expect(out, contains('DV-KIOSK-010'));
      // Numeric order: as text '010' sorts before '002' only by accident of
      // padding, and an unpadded family would read out of order.
      expect(out.indexOf('DV-KIOSK-002'), lessThan(out.indexOf('DV-KIOSK-010')));
    });

    test('with no argument it lists the families rather than everything', () {
      final String out = dvExplain(<String>[]);

      expect(out, contains('DV-WINDOW'));
      expect(out, contains('DV-KIOSK'));
      expect(out, isNot(contains('platform refused')),
          reason: 'a bare invocation should orient, not dump every code');
    });

    test('an empty or nonsense argument does not throw', () {
      expect(() => dvExplain(<String>['']), returnsNormally);
      expect(() => dvExplain(<String>['nonsense']), returnsNormally);
    });
  });
}
