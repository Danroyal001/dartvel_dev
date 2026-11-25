// `dartvel: web: lazyBackfill: true` reaches the app as the
// DARTVEL_LAZY_BACKFILL define (dartvel_flutter's lists/backfill.dart).
//
// The idle backfill builds every row a lazy list holds back while the page is
// idle. It is off by default since 3.47.9 (on long lists it cost heap and
// frames), so an application that wants it says so, and the build must hand
// that over; a value that is not true or false fails the build rather than
// leaving the app silently off.
import 'package:dartvel_cli/src/build/lazy_backfill_setting.dart';
import 'package:test/test.dart';

void main() {
  test('nothing declared, nothing passed: the backfill stays off', () {
    expect(dvLazyBackfillDefines(null), isEmpty);
    expect(dvLazyBackfillDefines(<String, Object?>{}), isEmpty);
    expect(dvLazyBackfillDefines({'web': {'ssrFirst': true}}), isEmpty);
    expect(dvLazyBackfillDefines({'web': true}), isEmpty);
  });

  test('lazyBackfill: true opts in', () {
    expect(dvLazyBackfillDefines({'web': {'lazyBackfill': true}}), ['--dart-define=DARTVEL_LAZY_BACKFILL=true']);
  });

  test('lazyBackfill: false passes nothing', () {
    expect(dvLazyBackfillDefines({'web': {'lazyBackfill': false}}), isEmpty);
  });

  test('anything else fails the build', () {
    expect(() => dvLazyBackfillDefines({'web': {'lazyBackfill': 'yes'}}), throwsFormatException);
  });
}
