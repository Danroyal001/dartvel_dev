// A paused agent run carries on once the pause is resolved.
//
// Approving runs the tool with the arguments that were shown and sends its
// result back to the model; declining tells the model the call did not run.
// Either way the run continues where it stopped, rather than leaving the
// application holding a tool result the model never sees.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final class _Transport {
  _Transport(this._responses);

  final List<Object?> _responses;
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];

  Future<DVAIHttpResponse> send(DVAIHttpRequest request) async {
    sent.add(jsonDecode(utf8.decode(request.body)) as Map<String, Object?>);
    if (_responses.isEmpty) throw StateError('no scripted response left');
    return DVAIHttpResponse(
      statusCode: 200,
      body: jsonEncode(_responses.removeAt(0)),
    );
  }
}

Map<String, Object?> _toolUse(List<(String, Map<String, Object?>)> calls) =>
    <String, Object?>{
      'stop_reason': 'tool_use',
      'content': <Object?>[
        for (final (String name, Map<String, Object?> input) in calls)
          <String, Object?>{
            'type': 'tool_use',
            'id': 'toolu_$name',
            'name': name,
            'input': input,
          },
      ],
    };

Map<String, Object?> _endTurn(String text) => <String, Object?>{
      'stop_reason': 'end_turn',
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
    };

/// The tool_result blocks of the last request, by tool_use id.
Map<String, Map<String, Object?>> _results(Map<String, Object?> body) {
  final List<Object?> messages = body['messages']! as List<Object?>;
  final Map<String, Object?> last = messages.last! as Map<String, Object?>;
  return <String, Map<String, Object?>>{
    for (final Object? block in last['content']! as List<Object?>)
      ((block! as Map<String, Object?>)['tool_use_id']! as String):
          block as Map<String, Object?>,
  };
}

void main() {
  const DVAIToolRegistry registry = DVAIToolRegistry();
  late List<String> ran;

  setUp(() {
    ran = <String>[];
    for (final String name in <String>['issueRefund', 'cancelOrder']) {
      registry.register(
        name,
        (DVJsonObject input) {
          ran.add('$name ${jsonEncode(DVJsonCodec.toJsonObject(input))}');
          return DVJsonString('$name done');
        },
        approval: DVToolApproval.required,
      );
    }
    registry.register('lookupOrder', (DVJsonObject input) {
      ran.add('lookupOrder');
      return const DVJsonString('order 7');
    });
  });

  tearDown(registry.clear);

  AnthropicDVAIAdapter anthropic(_Transport t) =>
      AnthropicDVAIAdapter(apiKey: 'sk-test', send: t.send);

  const DVAIAgentRequest request = DVAIAgentRequest(
    goal: 'Refund order 7',
    tools: <String>['issueRefund', 'cancelOrder', 'lookupOrder'],
  );

  test('approved, the tool runs and its result goes back to the model',
      () async {
    final _Transport t = _Transport(<Object?>[
      _toolUse(<(String, Map<String, Object?>)>[
        ('issueRefund', <String, Object?>{'amount': 40}),
      ]),
      _endTurn('Refunded 40.'),
    ]);
    final DVAIAgentResult paused = await anthropic(t).runAgent(request);
    expect(ran, isEmpty);

    final DVAIAgentResult done = await paused.pause!.resume(approved: true);

    expect(ran, <String>['issueRefund {"amount":40}']);
    expect(done.pause, isNull);
    expect(done.output, 'Refunded 40.');
    expect(done.usedTools, <String>['issueRefund']);
    expect(t.sent, hasLength(2));
    final Map<String, Object?> result = _results(t.sent[1])['toolu_issueRefund']!;
    expect(result['content'], '"issueRefund done"');
    expect(result.containsKey('is_error'), isFalse);
  });

  test('declined, the tool never runs and the model is told so', () async {
    final _Transport t = _Transport(<Object?>[
      _toolUse(<(String, Map<String, Object?>)>[
        ('issueRefund', <String, Object?>{'amount': 40}),
      ]),
      _endTurn('I did not refund it.'),
    ]);
    final DVAIAgentResult paused = await anthropic(t).runAgent(request);

    final DVAIAgentResult done = await paused.pause!.resume(approved: false);

    expect(ran, isEmpty);
    expect(done.output, 'I did not refund it.');
    expect(done.usedTools, isEmpty);
    final Map<String, Object?> result = _results(t.sent[1])['toolu_issueRefund']!;
    expect(result['is_error'], isTrue);
    expect('${result['content']}', contains('declined'));
  });

  test('the rest of the turn runs once the pause is resolved', () async {
    final _Transport t = _Transport(<Object?>[
      _toolUse(<(String, Map<String, Object?>)>[
        ('lookupOrder', <String, Object?>{'id': 7}),
        ('issueRefund', <String, Object?>{'amount': 40}),
      ]),
      _endTurn('Done.'),
    ]);
    final DVAIAgentResult paused = await anthropic(t).runAgent(request);
    expect(ran, isEmpty);

    await paused.pause!.resume(approved: true);

    expect(ran, <String>['lookupOrder', 'issueRefund {"amount":40}']);
    expect(_results(t.sent[1]).keys,
        <String>['toolu_lookupOrder', 'toolu_issueRefund']);
  });

  test('a second tool needing approval in the same turn pauses again',
      () async {
    final _Transport t = _Transport(<Object?>[
      _toolUse(<(String, Map<String, Object?>)>[
        ('issueRefund', <String, Object?>{'amount': 40}),
        ('cancelOrder', <String, Object?>{'id': 7}),
      ]),
      _endTurn('Both done.'),
    ]);
    final DVAIAgentResult first = await anthropic(t).runAgent(request);
    expect(first.pause!.tool, 'issueRefund');

    final DVAIAgentResult second = await first.pause!.resume(approved: true);
    expect(second.pause!.tool, 'cancelOrder');
    // Nothing ran yet: the turn runs once every call in it is decided.
    expect(ran, isEmpty);
    expect(t.sent, hasLength(1));

    final DVAIAgentResult done = await second.pause!.resume(approved: true);
    expect(done.output, 'Both done.');
    expect(ran, <String>[
      'issueRefund {"amount":40}',
      'cancelOrder {"id":7}',
    ]);
  });

  test('a pause is resolved once', () async {
    final _Transport t = _Transport(<Object?>[
      _toolUse(<(String, Map<String, Object?>)>[
        ('issueRefund', <String, Object?>{'amount': 40}),
      ]),
      _endTurn('ok'),
    ]);
    final DVAIAgentResult paused = await anthropic(t).runAgent(request);
    await paused.pause!.resume(approved: true);
    await expectLater(paused.pause!.resume(approved: true), throwsStateError);
    await expectLater(paused.pause!.approve(), throwsStateError);
    expect(ran, hasLength(1));
  });

  test('the OpenAI loop resumes too', () async {
    final _Transport t = _Transport(<Object?>[
      <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'role': 'assistant',
              'content': null,
              'tool_calls': <Object?>[
                <String, Object?>{
                  'id': 'call_1',
                  'type': 'function',
                  'function': <String, Object?>{
                    'name': 'issueRefund',
                    'arguments': '{"amount":40}',
                  },
                },
              ],
            },
          },
        ],
      },
      <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': 'Refunded.'},
          },
        ],
      },
    ]);
    final DVAIAgentResult paused =
        await OpenAIDVAIAdapter(apiKey: 'sk-a', send: t.send)
            .runAgent(request);
    final DVAIAgentResult done = await paused.pause!.resume(approved: true);

    expect(done.output, 'Refunded.');
    expect(ran, <String>['issueRefund {"amount":40}']);
    final List<Object?> messages = t.sent[1]['messages']! as List<Object?>;
    final Map<String, Object?> tool = messages.last! as Map<String, Object?>;
    expect(tool['role'], 'tool');
    expect(tool['tool_call_id'], 'call_1');
    expect(tool['content'], '"issueRefund done"');
  });

  test('a run that ran its tools up front resumes with the decision',
      () async {
    final DVAIAgentResult paused = await const LocalDVAIAdapter().runAgent(
      const DVAIAgentRequest(
        goal: 'Refund order 7',
        context: <String, DVJsonValue>{'amount': DVJsonNumber(40)},
        tools: <String>['lookupOrder', 'issueRefund'],
      ),
    );
    expect(ran, isEmpty);

    final DVAIAgentResult declined =
        await paused.pause!.resume(approved: false);
    expect(declined.pause, isNull);
    expect(ran, <String>['lookupOrder']);
    expect(declined.usedTools, <String>['lookupOrder']);
  });

  test('approved up front, the tool runs with the request context', () async {
    final DVAIAgentResult paused = await const LocalDVAIAdapter().runAgent(
      const DVAIAgentRequest(
        goal: 'Refund order 7',
        context: <String, DVJsonValue>{'amount': DVJsonNumber(40)},
        tools: <String>['issueRefund'],
      ),
    );
    final DVAIAgentResult done = await paused.pause!.resume(approved: true);
    expect(ran, <String>['issueRefund {"amount":40}']);
    expect(done.usedTools, <String>['issueRefund']);
    expect((done.data['issueRefund']! as DVJsonString).value,
        'issueRefund done');
  });
}
