// How a dual-mode application decides where to start. `NEW_SPEC.md`
// § Terminal Rendering, "How a dual-mode application starts".
//
// Pure decision, no IO: the prompt is an *outcome* this returns, not something
// it performs. That keeps every branch testable without a TTY, and keeps the
// policy in one readable place instead of spread through a main().
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('launch negotiation', () {
    group('an application with only one backend has no decision to make', () {
      test('a GUI-only build starts the GUI, display or not', () {
        // It fails to find a display exactly as it does today. No prompt, no
        // flag, no branch — an app that opted into nothing gains nothing.
        expect(
          resolveLaunchSurface(
            linked: const <DVRenderSurface>{DVRenderSurface.gui},
            arguments: const <String>[],
            displayAvailable: false,
          ),
          DVLaunchOutcome.gui,
        );
      });

      test('a terminal-only build starts the terminal, and ignores --tui', () {
        // --tui is redundant rather than wrong when there is nothing else.
        expect(
          resolveLaunchSurface(
            linked: const <DVRenderSurface>{DVRenderSurface.terminal},
            arguments: const <String>['--tui'],
            displayAvailable: true,
          ),
          DVLaunchOutcome.terminal,
        );
      });
    });

    group('a dual-mode application', () {
      const both = <DVRenderSurface>{
        DVRenderSurface.gui,
        DVRenderSurface.terminal,
      };

      test('starts the GUI by default', () {
        // A terminal is where the command was typed, not necessarily where the
        // application belongs.
        expect(
          resolveLaunchSurface(
            linked: both,
            arguments: const <String>[],
            displayAvailable: true,
          ),
          DVLaunchOutcome.gui,
        );
      });

      test('--tui starts the terminal directly', () {
        // The explicit path, and the one to reach for over SSH.
        expect(
          resolveLaunchSurface(
            linked: both,
            arguments: const <String>['--tui'],
            displayAvailable: true,
          ),
          DVLaunchOutcome.terminal,
        );
      });

      test('--tui wins even when a display exists', () {
        expect(
          resolveLaunchSurface(
            linked: both,
            arguments: const <String>['--verbose', '--tui'],
            displayAvailable: true,
          ),
          DVLaunchOutcome.terminal,
        );
      });

      test('asks when there is no display', () {
        // Both silent answers are wrong. Quietly redrawing as text is
        // indistinguishable from a bug at the moment it happens, and failing
        // outright wastes a capability the app was built with.
        expect(
          resolveLaunchSurface(
            linked: both,
            arguments: const <String>[],
            displayAvailable: false,
          ),
          DVLaunchOutcome.askToUseTerminal,
        );
      });

      test('does not ask when --tui already answered the question', () {
        expect(
          resolveLaunchSurface(
            linked: both,
            arguments: const <String>['--tui'],
            displayAvailable: false,
          ),
          DVLaunchOutcome.terminal,
        );
      });

      test('does not ask when nobody can answer', () {
        // A prompt with no human at the other end is a hang. Non-interactive
        // means take the terminal, which is the only surface that can work.
        expect(
          resolveLaunchSurface(
            linked: both,
            arguments: const <String>[],
            displayAvailable: false,
            interactive: false,
          ),
          DVLaunchOutcome.terminal,
        );
      });
    });

    test('a build with no backend at all is a build error, not a runtime one',
        () {
      expect(
        () => resolveLaunchSurface(
          linked: const <DVRenderSurface>{},
          arguments: const <String>[],
          displayAvailable: true,
        ),
        throwsArgumentError,
      );
    });

    test('the prompt says what it is offering and what declining means', () {
      // The wording is part of the feature: a prompt nobody understands is a
      // worse outcome than either silent answer.
      expect(dvTerminalFallbackPrompt, contains('No display'));
      expect(dvTerminalFallbackPrompt, contains('terminal'));
      expect(dvTerminalFallbackPrompt, contains('[Y/n]'));
    });
  });
}
