// DVStepUp: a generated call refused for a missing second factor presents
// the challenge and is sent again.
//
// The specification's shape: an unsatisfied requirement is not an error
// page; it suspends the call, presents the generated challenge and resumes.
// The silent failures:
//  * any 401 treated as a step-up, so a revoked session is asked for a code
//    instead of being signed out;
//  * a retry loop when the server still refuses after the challenge;
//  * five calls refused at once presenting five challenges;
//  * a challenge that was dismissed or failed sending the call again anyway.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVHttpResponse _stepUp({int? maxAge}) => DVHttpResponse(
      statusCode: 401,
      body: jsonEncode(<String, Object?>{
        'error': 'mfa_required',
        'code': 'DV-SESSION-001',
        if (maxAge != null) 'maxAge': maxAge,
      }),
    );

const DVHttpResponse _ok = DVHttpResponse(statusCode: 200, body: '"done"');

void main() {
  tearDown(() => DVStepUp.challenge = null);

  test('an answer that is not a step-up is returned as it is, and nothing is '
      'presented', () async {
    int challenged = 0;
    DVStepUp.challenge = (DVStepUpRequest _) async {
      challenged++;
      return true;
    };
    const DVHttpResponse revoked = DVHttpResponse(
        statusCode: 401, body: 'Unauthorized');
    int sent = 0;
    final DVHttpResponse answer = await DVStepUp.send(() async {
      sent++;
      return revoked;
    });
    expect(answer, same(revoked));
    expect(sent, 1);
    expect(challenged, 0);
    expect(DVStepUp.isRequired(revoked), isFalse);
    expect(DVStepUp.isRequired(_stepUp()), isTrue);
  });

  test('a presented challenge sends the call again once', () async {
    DVStepUpRequest? asked;
    DVStepUp.challenge = (DVStepUpRequest request) async {
      asked = request;
      return true;
    };
    int sent = 0;
    final DVHttpResponse answer = await DVStepUp.send(() async {
      sent++;
      return sent == 1 ? _stepUp(maxAge: 900) : _ok;
    });
    expect(answer, same(_ok));
    expect(sent, 2);
    expect(asked!.maxAge, const Duration(seconds: 900));
  });

  test('a dismissed or failed challenge returns the refusal without sending '
      'again', () async {
    for (final Future<bool> Function(DVStepUpRequest) challenge
        in <Future<bool> Function(DVStepUpRequest)>[
      (DVStepUpRequest _) async => false,
      (DVStepUpRequest _) async => throw StateError('no navigator'),
    ]) {
      DVStepUp.challenge = challenge;
      int sent = 0;
      final DVHttpResponse answer = await DVStepUp.send(() async {
        sent++;
        return _stepUp();
      });
      expect(DVStepUp.isRequired(answer), isTrue);
      expect(sent, 1);
    }
  });

  test('with no challenge installed the refusal is returned', () async {
    int sent = 0;
    final DVHttpResponse answer = await DVStepUp.send(() async {
      sent++;
      return _stepUp();
    });
    expect(DVStepUp.isRequired(answer), isTrue);
    expect(sent, 1);
  });

  test('a server that still refuses after the challenge is not asked a third '
      'time', () async {
    int challenged = 0;
    DVStepUp.challenge = (DVStepUpRequest _) async {
      challenged++;
      return true;
    };
    int sent = 0;
    final DVHttpResponse answer = await DVStepUp.send(() async {
      sent++;
      return _stepUp();
    });
    expect(DVStepUp.isRequired(answer), isTrue);
    expect(sent, 2);
    expect(challenged, 1);
  });

  test('calls refused together share one challenge', () async {
    int challenged = 0;
    final Completer<bool> presented = Completer<bool>();
    DVStepUp.challenge = (DVStepUpRequest _) {
      challenged++;
      return presented.future;
    };
    final Map<int, int> sent = <int, int>{};
    final List<Future<DVHttpResponse>> calls = <Future<DVHttpResponse>>[
      for (int i = 0; i < 5; i++)
        DVStepUp.send(() async {
          sent[i] = (sent[i] ?? 0) + 1;
          return sent[i] == 1 ? _stepUp() : _ok;
        }),
    ];
    await Future<void>.delayed(Duration.zero);
    presented.complete(true);
    final List<DVHttpResponse> answers = await Future.wait(calls);
    expect(challenged, 1);
    expect(answers.every((DVHttpResponse a) => a.statusCode == 200), isTrue);
  });
}
