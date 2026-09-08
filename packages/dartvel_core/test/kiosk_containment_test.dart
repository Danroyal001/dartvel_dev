// Two of the five kiosk containment keys the specification describes and
// nothing implemented.
//
// They were read straight past: the parser pulled three named children out of
// input and the rest fell through, so `clipboard: disabled` in a kiosk policy
// changed nothing and said nothing. That was reported as a problem rather
// than left silent, which was the right first step and not the feature --
// somebody who writes the clipboard rule into a kiosk has decided the
// clipboard is locked.
//
// These two are the ones Dartvel can honour on its own, in Dart, with no
// platform binding: what a page lets you select, and what the framework's own
// clipboard API will do. The three that remain -- routes.external,
// display.hideCursor and screenDim -- still need something underneath them
// and still report.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy _policy(Map<String, Object?> input) => DVKioskPolicy.parse(
      <String, Object?>{
        'kiosk': <String, Object?>{'enabled': true, 'input': input},
      },
    );

void main() {
  group('the two keys are read', () {
    test('clipboard: disabled blocks the clipboard', () {
      final DVKioskPolicy policy =
          _policy(<String, Object?>{'clipboard': 'disabled'});

      expect(policy.blockClipboard, isTrue);
      expect(policy.problems, isEmpty);
    });

    test('textSelection: disabled blocks selection', () {
      final DVKioskPolicy policy =
          _policy(<String, Object?>{'textSelection': 'disabled'});

      expect(policy.blockTextSelection, isTrue);
      expect(policy.problems, isEmpty);
    });

    test('neither is blocked unless the policy says so', () {
      // A kiosk is not automatically a device where nothing can be copied.
      // An order screen that shows a reference number is more useful if the
      // number can be copied, and the specification makes both explicit
      // keys rather than consequences of kiosk mode.
      final DVKioskPolicy policy = _policy(const <String, Object?>{});

      expect(policy.blockClipboard, isFalse);
      expect(policy.blockTextSelection, isFalse);
    });

    test('they are no longer reported as unread', () {
      // The report was the honest answer while nothing implemented them.
      // Leaving it in place now would say a key does nothing while it does.
      final DVKioskPolicy policy = _policy(<String, Object?>{
        'clipboard': 'disabled',
        'textSelection': 'disabled',
      });

      expect(
        policy.problems.where((String p) => p.contains('clipboard')),
        isEmpty,
      );
      expect(
        policy.problems.where((String p) => p.contains('textSelection')),
        isEmpty,
      );
    });

    test('the three that are still unbuilt still say so', () {
      // Naming two of five as done would be worse than naming none: the
      // remaining three look implemented by association.
      final DVKioskPolicy policy = DVKioskPolicy.parse(<String, Object?>{
        'kiosk': <String, Object?>{
          'enabled': true,
          'routes': <String, Object?>{'external': 'block'},
          'display': <String, Object?>{'hideCursor': true, 'screenDim': '30s'},
        },
      });

      expect(
        policy.problems.join(' '),
        allOf(
          contains('external'),
          contains('hideCursor'),
          contains('screenDim'),
        ),
      );
    });
  });

  group('a blocked clipboard refuses', () {
    tearDown(dvResetKioskContainment);

    test('a copy under a blocking policy is refused by name', () async {
      dvApplyKioskContainment(
        _policy(<String, Object?>{'clipboard': 'disabled'}),
      );

      expect(dvKioskBlocksClipboard, isTrue);
      expect(
        () => dvRefuseIfClipboardBlocked('copy'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('kiosk'), contains('clipboard')),
          ),
        ),
      );
    });

    test('with no kiosk running the clipboard is nobody else\'s business',
        () {
      expect(dvKioskBlocksClipboard, isFalse);
      expect(() => dvRefuseIfClipboardBlocked('copy'), returnsNormally);
    });

    test('a policy that does not block leaves it alone', () {
      dvApplyKioskContainment(_policy(const <String, Object?>{}));

      expect(dvKioskBlocksClipboard, isFalse);
    });
  });

  group('containment follows the kiosk state, not the process', () {
    tearDown(dvResetKioskContainment);

    test('resuming a locking kiosk locks it', () async {
      final DVKioskRuntime kiosk = DVKioskRuntime(
        _policy(<String, Object?>{
          'clipboard': 'disabled',
          'textSelection': 'disabled',
        }),
      );
      addTearDown(kiosk.stop);

      await kiosk.resume();

      expect(dvKioskBlocksClipboard, isTrue);
      expect(dvKioskBlocksTextSelection, isTrue);
    });

    test('staff mode lifts it, through the real way in', () async {
      // Somebody standing at the machine with the exit method has been
      // trusted with more than the person in the queue, and an engineer who
      // cannot copy the error code off the screen reads it down a phone.
      //
      // Through exit() with the declared method rather than by setting the
      // state, because the question is whether the transition that actually
      // happens carries this with it.
      final DVKioskRuntime kiosk = DVKioskRuntime(
        DVKioskPolicy.parse(<String, Object?>{
          'kiosk': <String, Object?>{
            'enabled': true,
            'input': <String, Object?>{'clipboard': 'disabled'},
            'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:KIOSK_PIN'},
          },
        }),
        readSecret: (String name) async => name == 'KIOSK_PIN' ? '4821' : null,
      );
      addTearDown(kiosk.stop);

      await kiosk.resume();
      expect(dvKioskBlocksClipboard, isTrue);

      final DVKioskExitResult result =
          await kiosk.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isTrue);
      expect(dvKioskBlocksClipboard, isFalse);
    });

    test('a refused exit leaves it locked', () async {
      // The failure worth checking: an attempt that did not succeed must not
      // relax anything, or the way past a locked clipboard is to guess once.
      final DVKioskRuntime kiosk = DVKioskRuntime(
        DVKioskPolicy.parse(<String, Object?>{
          'kiosk': <String, Object?>{
            'enabled': true,
            'input': <String, Object?>{'clipboard': 'disabled'},
            'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:KIOSK_PIN'},
          },
        }),
        readSecret: (String name) async => '4821',
      );
      addTearDown(kiosk.stop);

      await kiosk.resume();
      final DVKioskExitResult result =
          await kiosk.exit(const DVKioskExitRequest.pin('0000'));

      expect(result.granted, isFalse);
      expect(dvKioskBlocksClipboard, isTrue);
    });
  });
}
