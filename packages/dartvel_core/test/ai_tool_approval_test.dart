// A tool that spends money asks first.
//
// A tool declared with DVToolApproval.required does not run because a model
// asked for it. The agent loop stops and hands back a typed pause carrying the
// tool, its arguments and the reason; the tool runs only when something
// approves that pause, and then with exactly the arguments that were shown.
// Anything that reaches the tool another way -- the registry, an MCP client,
// a provider with no native tool calling that runs tools up front -- is
// refused with DV-AI-010, because asking at that point would be asking after
// the decision was made.
//
// The silent failure is the one that matters: a refund issued because a
// model said so, with a successful result and nothing anywhere saying that
// nobody approved it. So every path asserts the handler never ran.
import 'dart:async';
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

Map<String, Object?> _anthropicToolUse(
  List<(String, Map<String, Object?>)> calls,
) => <String, Object?>{
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

Map<String, Object?> _openAIToolCall(
  String name,
  String arguments,
) => <String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{
        'role': 'assistant',
        'content': null,
        'tool_calls': <Object?>[
          <String, Object?>{
            'id': 'call_1',
            'type': 'function',
            'function': <String, Object?>{'name': name, 'arguments': arguments},
          },
        ],
      },
    },
  ],
};

void main() {
  const DVAIToolRegistry registry = DVAIToolRegistry();
  late List<DVJsonObject> refunds;
  late List<DVJsonObject> lookups;

  setUp(() {
    refunds = <DVJsonObject>[];
    lookups = <DVJsonObject>[];
    registry.register(
      'issueRefund',
      (DVJsonObject input) {
        refunds.add(input);
        return const DVJsonString('refunded');
      },
      description: 'Issue a refund',
      approval: DVToolApproval.required,
    );
    registry.register('lookupOrder', (DVJsonObject input) {
      lookups.add(input);
      return const DVJsonString('order 7');
    }, description: 'Look up an order');
  });

  tearDown(registry.clear);

  test(
    'a tool declares whether it needs approval, and none is the default',
    () {
      expect(
        registry.definition('issueRefund')!.approval,
        DVToolApproval.required,
      );
      expect(registry.definition('lookupOrder')!.approval, DVToolApproval.none);
    },
  );

  test('calling a tool that needs approval directly is DV-AI-010', () async {
    await expectLater(
      registry.call('issueRefund', const <String, DVJsonValue>{
        'amount': DVJsonNumber(40),
      }),
      throwsA(
        isA<DVAIToolApprovalRequired>()
            .having((DVAIToolApprovalRequired e) => e.code, 'code', 'DV-AI-010')
            .having(
              (DVAIToolApprovalRequired e) => e.tool,
              'tool',
              'issueRefund',
            ),
      ),
    );
    expect(refunds, isEmpty);
  });

  test('DV-AI-010 is the registered error', () {
    final DVDiagnostic? diagnostic = DVDiagnostics.find('DV-AI-010');
    expect(diagnostic?.level, 'error');
  });

  group('Anthropic loop', () {
    test(
      'stops at the tool and hands back a pause, without running it',
      () async {
        final _Transport transport = _Transport(<Object?>[
          _anthropicToolUse(<(String, Map<String, Object?>)>[
            ('issueRefund', <String, Object?>{'amount': 40}),
          ]),
        ]);
        final DVAIAgentResult result =
            await AnthropicDVAIAdapter(
              apiKey: 'sk-test',
              send: transport.send,
            ).runAgent(
              const DVAIAgentRequest(
                goal: 'Refund order 7',
                tools: <String>['issueRefund'],
              ),
            );

        expect(refunds, isEmpty);
        // One model turn: the loop did not carry on as if the tool had run.
        expect(transport.sent, hasLength(1));
        final DVAIToolPause pause = result.pause!;
        expect(pause.tool, 'issueRefund');
        expect(DVJsonCodec.toJsonObject(pause.arguments), <String, Object?>{
          'amount': 40,
        });
        expect(pause.reason, contains('issueRefund'));
        expect(result.usedTools, isEmpty);
      },
    );

    test(
      'approving the pause runs the tool with the arguments shown',
      () async {
        final _Transport transport = _Transport(<Object?>[
          _anthropicToolUse(<(String, Map<String, Object?>)>[
            ('issueRefund', <String, Object?>{'amount': 40}),
          ]),
        ]);
        final DVAIAgentResult result =
            await AnthropicDVAIAdapter(
              apiKey: 'sk-test',
              send: transport.send,
            ).runAgent(
              const DVAIAgentRequest(
                goal: 'Refund order 7',
                tools: <String>['issueRefund'],
              ),
            );

        final DVJsonValue value = await result.pause!.approve();
        expect((value as DVJsonString).value, 'refunded');
        expect(refunds.map(DVJsonCodec.toJsonObject), <Object?>[
          <String, Object?>{'amount': 40},
        ]);
      },
    );

    test('a pause approves once', () async {
      final _Transport transport = _Transport(<Object?>[
        _anthropicToolUse(<(String, Map<String, Object?>)>[
          ('issueRefund', <String, Object?>{'amount': 40}),
        ]),
      ]);
      final DVAIAgentResult result =
          await AnthropicDVAIAdapter(
            apiKey: 'sk-test',
            send: transport.send,
          ).runAgent(
            const DVAIAgentRequest(
              goal: 'Refund order 7',
              tools: <String>['issueRefund'],
            ),
          );
      await result.pause!.approve();
      await expectLater(result.pause!.approve(), throwsStateError);
      expect(refunds, hasLength(1));
    });

    test('a turn asking for that tool and another runs neither', () async {
      final _Transport transport = _Transport(<Object?>[
        _anthropicToolUse(<(String, Map<String, Object?>)>[
          ('lookupOrder', <String, Object?>{'id': 7}),
          ('issueRefund', <String, Object?>{'amount': 40}),
        ]),
      ]);
      final DVAIAgentResult result =
          await AnthropicDVAIAdapter(
            apiKey: 'sk-test',
            send: transport.send,
          ).runAgent(
            const DVAIAgentRequest(
              goal: 'Refund order 7',
              tools: <String>['lookupOrder', 'issueRefund'],
            ),
          );
      expect(result.pause?.tool, 'issueRefund');
      expect(refunds, isEmpty);
      expect(lookups, isEmpty);
    });

    test('a tool that needs no approval still runs and finishes', () async {
      final _Transport transport = _Transport(<Object?>[
        _anthropicToolUse(<(String, Map<String, Object?>)>[
          ('lookupOrder', <String, Object?>{'id': 7}),
        ]),
        <String, Object?>{
          'stop_reason': 'end_turn',
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'Order 7 found.'},
          ],
        },
      ]);
      final DVAIAgentResult result =
          await AnthropicDVAIAdapter(
            apiKey: 'sk-test',
            send: transport.send,
          ).runAgent(
            const DVAIAgentRequest(
              goal: 'Find order 7',
              tools: <String>['lookupOrder'],
            ),
          );
      expect(result.pause, isNull);
      expect(result.output, 'Order 7 found.');
      expect(lookups, hasLength(1));
    });
  });

  test('the OpenAI loop stops at the tool too', () async {
    final _Transport transport = _Transport(<Object?>[
      _openAIToolCall('issueRefund', '{"amount":40}'),
    ]);
    final DVAIAgentResult result =
        await OpenAIDVAIAdapter(apiKey: 'sk-a', send: transport.send).runAgent(
          const DVAIAgentRequest(
            goal: 'Refund order 7',
            tools: <String>['issueRefund'],
          ),
        );
    expect(refunds, isEmpty);
    expect(transport.sent, hasLength(1));
    expect(result.pause?.tool, 'issueRefund');
    expect(DVJsonCodec.toJsonObject(result.pause!.arguments), <String, Object?>{
      'amount': 40,
    });
  });

  test('a provider that runs tools up front pauses instead', () async {
    // Gemini has no native loop here: the fallback runs the allowed tools
    // with the request context before asking the model anything.
    final _Transport transport = _Transport(<Object?>[]);
    final DVAIAgentResult result =
        await GeminiDVAIAdapter(apiKey: 'g', send: transport.send).runAgent(
          const DVAIAgentRequest(
            goal: 'Refund order 7',
            context: <String, DVJsonValue>{'amount': DVJsonNumber(40)},
            tools: <String>['lookupOrder', 'issueRefund'],
          ),
        );
    expect(refunds, isEmpty);
    expect(lookups, isEmpty);
    expect(transport.sent, isEmpty);
    expect(result.pause?.tool, 'issueRefund');
  });

  test('the local adapter pauses as well', () async {
    final DVAIAgentResult result = await const LocalDVAIAdapter().runAgent(
      const DVAIAgentRequest(
        goal: 'Refund order 7',
        context: <String, DVJsonValue>{'amount': DVJsonNumber(40)},
        tools: <String>['issueRefund'],
      ),
    );
    expect(refunds, isEmpty);
    expect(result.pause?.tool, 'issueRefund');
  });

  test('an MCP client calling the tool is refused with DV-AI-010', () async {
    final toServer = StreamController<List<int>>.broadcast();
    final toClient = StreamController<List<int>>.broadcast();
    Future<void> teardown() async {
      if (!toServer.isClosed) await toServer.close();
      if (!toClient.isClosed) await toClient.close();
    }

    final DVMcpServer server = DVMcpServer(
      DVMcpStreamTransport(
        input: toServer.stream,
        write: (List<int> bytes) {
          if (!toClient.isClosed) toClient.add(bytes);
        },
        onClose: teardown,
      ),
    );
    unawaited(server.serve());
    final DVMcpClient client = DVMcpClient(
      DVMcpStreamTransport(
        input: toClient.stream,
        write: (List<int> bytes) {
          if (!toServer.isClosed) toServer.add(bytes);
        },
        onClose: teardown,
      ),
    );
    addTearDown(() async {
      await client.close();
      await server.stop();
    });
    await client.initialize();

    await expectLater(
      client.callTool('issueRefund', const <String, DVJsonValue>{
        'amount': DVJsonNumber(40),
      }),
      throwsA(
        isA<DVMcpException>().having(
          (DVMcpException e) => e.message,
          'message',
          contains('DV-AI-010'),
        ),
      ),
    );
    expect(refunds, isEmpty);
  });
}
