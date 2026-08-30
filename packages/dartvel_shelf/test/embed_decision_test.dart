// The opt-in decision, tested where it can actually fail.
//
// The hook-level test cannot prove this on a machine without cargo: the hook
// skips for want of a toolchain and the assertion passes for the wrong reason.
// This is the decision itself, which is the part with the behaviour.
import 'package:dartvel_shelf/src/build/embed_decision.dart';
import 'package:test/test.dart';

void main() {
  test('absent means no', () {
    // The default that matters: an application that says nothing gets no
    // server linked into it.
    expect(dvEmbedServerRequested(null), isFalse);
  });

  test('true means yes', () {
    expect(dvEmbedServerRequested(true), isTrue);
  });

  test('false written explicitly means no', () {
    // Turning it off must be possible by setting the value, not only by
    // deleting the line.
    expect(dvEmbedServerRequested(false), isFalse);
  });

  test('a string is accepted, because the command line supplies one', () {
    expect(dvEmbedServerRequested('true'), isTrue);
    expect(dvEmbedServerRequested('TRUE'), isTrue);
    expect(dvEmbedServerRequested(' true '), isTrue);
    expect(dvEmbedServerRequested('1'), isTrue);
    expect(dvEmbedServerRequested('yes'), isTrue);
  });

  test('a string that is not an affirmative means no', () {
    expect(dvEmbedServerRequested('false'), isFalse);
    expect(dvEmbedServerRequested('0'), isFalse);
    expect(dvEmbedServerRequested(''), isFalse);
  });

  test('a malformed value is not a request', () {
    // Linking a server on the strength of a typo is the wrong direction to
    // fail in: the cost of a false negative is a build error the developer
    // sees, and of a false positive a server nobody knows is there.
    expect(dvEmbedServerRequested(1), isFalse);
    expect(dvEmbedServerRequested(<String, Object?>{'enabled': true}), isFalse);
    expect(dvEmbedServerRequested(<Object?>[true]), isFalse);
    expect(dvEmbedServerRequested('yes please'), isFalse);
  });

  test('the define is named once, so the hook and the docs cannot drift', () {
    expect(dvEmbedServerDefine, 'embed_server');
  });
}
