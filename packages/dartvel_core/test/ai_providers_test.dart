import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Records every request an adapter makes and replays a scripted response, so
/// provider wire formats are covered without touching the network.
class _RecordingTransport {
  final List<DVAIHttpRequest> requests = <DVAIHttpRequest>[];
  final List<DVAIHttpResponse> _responses;

  _RecordingTransport(List<DVAIHttpResponse> responses)
      : _responses = List<DVAIHttpResponse>.of(responses);

  factory _RecordingTransport.json(Object? payload, {int statusCode = 200}) =>
      _RecordingTransport(<DVAIHttpResponse>[
        DVAIHttpResponse(statusCode: statusCode, body: jsonEncode(payload)),
      ]);

  DVAIHttpRequest get single {
    expect(requests, hasLength(1));
    return requests.single;
  }

  Map<String, Object?> get sentJson =>
      jsonDecode(utf8.decode(single.body)) as Map<String, Object?>;

  Future<DVAIHttpResponse> send(DVAIHttpRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) {
      throw StateError('No scripted response left for ${request.url}.');
    }
    return _responses.removeAt(0);
  }
}

void main() {
  group('DVJsonCodec', () {
    test('round-trips every typed JSON value', () {
      const original = <String, DVJsonValue>{
        'text': DVJsonString('hello'),
        'count': DVJsonNumber(3),
        'flag': DVJsonBool(true),
        'missing': DVJsonNull(),
        'items': DVJsonList(<DVJsonValue>[DVJsonNumber(1), DVJsonString('a')]),
        'nested': DVJsonMap(<String, DVJsonValue>{'inner': DVJsonBool(false)}),
      };

      final encoded = DVJsonCodec.toJsonObject(original);
      expect(encoded, <String, Object?>{
        'text': 'hello',
        'count': 3,
        'flag': true,
        'missing': null,
        'items': <Object?>[1, 'a'],
        'nested': <String, Object?>{'inner': false},
      });

      final decoded = DVJsonCodec.fromJsonObject(
        jsonDecode(jsonEncode(encoded)) as Map<String, Object?>,
      );
      expect(DVJsonCodec.toJsonObject(decoded), encoded);
    });

    test('rejects values with no JSON representation', () {
      expect(() => DVJsonCodec.fromJson(Object()), throwsArgumentError);
    });
  });

  group('AnthropicDVAIAdapter', () {
    test('posts the Messages API shape and reads the first text block',
        () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'stop_reason': 'end_turn',
        'content': <Object?>[
          <String, Object?>{'type': 'thinking', 'thinking': ''},
          <String, Object?>{'type': 'text', 'text': 'Paris.'},
        ],
      });
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: transport.send,
      );

      expect(await adapter.chat('Capital of France?'), 'Paris.');

      final request = transport.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(request.headers['x-api-key'], 'sk-test');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(transport.sentJson['model'], AnthropicDVAIAdapter.defaultModel);
      expect(transport.sentJson['messages'], <Object?>[
        <String, Object?>{'role': 'user', 'content': 'Capital of France?'},
      ]);
    });

    test('sends a json_schema output config and decodes structured output',
        () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': '{"summary":"ok"}'},
        ],
      });
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: transport.send,
      );

      final result = await adapter.structuredOutput(
        'Summarize',
        const <String, DVJsonValue>{'type': DVJsonString('object')},
      );

      expect(result['summary'], isA<DVJsonString>());
      expect((result['summary']! as DVJsonString).value, 'ok');
      final outputConfig =
          transport.sentJson['output_config']! as Map<String, Object?>;
      final format = outputConfig['format']! as Map<String, Object?>;
      expect(format['type'], 'json_schema');
      expect(format['schema'], <String, Object?>{'type': 'object'});
    });

    test('surfaces a refusal instead of returning empty text', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'stop_reason': 'refusal',
        'content': <Object?>[],
      });
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: transport.send,
      );

      await expectLater(
        adapter.chat('...'),
        throwsA(isA<DVAIProviderException>()),
      );
    });

    test('reports provider errors with the status code and body', () async {
      final transport = _RecordingTransport(<DVAIHttpResponse>[
        const DVAIHttpResponse(statusCode: 401, body: '{"error":"bad key"}'),
      ]);
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'nope',
        send: transport.send,
      );

      await expectLater(
        adapter.chat('hi'),
        throwsA(
          isA<DVAIProviderException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having((error) => error.provider, 'provider', 'anthropic')
              .having((error) => error.responseBody, 'responseBody',
                  contains('bad key')),
        ),
      );
    });

    test('fails loudly for capabilities Anthropic does not serve', () async {
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: _RecordingTransport(const <DVAIHttpResponse>[]).send,
      );

      await expectLater(adapter.embed('x'), throwsUnsupportedError);
      await expectLater(
        adapter.transcribe(const <int>[1, 2, 3]),
        throwsUnsupportedError,
      );
    });
  });

  group('OpenAIDVAIAdapter', () {
    test('reads chat completions', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'role': 'assistant', 'content': 'hi'},
          },
        ],
      });
      final adapter = OpenAIDVAIAdapter(apiKey: 'sk-a', send: transport.send);

      expect(await adapter.chat('hello'), 'hi');
      expect(
        transport.single.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(transport.single.headers['authorization'], 'Bearer sk-a');
    });

    test('reads embeddings as doubles', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'embedding': <Object?>[0.5, 1, -0.25],
          },
        ],
      });
      final adapter = OpenAIDVAIAdapter(apiKey: 'sk-a', send: transport.send);

      expect(await adapter.embed('text'), <double>[0.5, 1.0, -0.25]);
      expect(
        transport.single.url.toString(),
        'https://api.openai.com/v1/embeddings',
      );
      expect(
        transport.sentJson['model'],
        OpenAIDVAIAdapter.defaultEmbeddingModel,
      );
    });

    test('uploads audio as multipart form data', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'text': 'transcribed words',
      });
      final adapter = OpenAIDVAIAdapter(apiKey: 'sk-a', send: transport.send);

      final transcript = await adapter.transcribe(
        <int>[1, 2, 3, 4],
        mimeType: 'audio/mpeg',
        language: 'en',
      );

      expect(transcript.text, 'transcribed words');
      expect(transcript.language, 'en');
      final request = transport.single;
      expect(
        request.url.toString(),
        'https://api.openai.com/v1/audio/transcriptions',
      );
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      final body = latin1.decode(request.body);
      expect(body, contains('name="model"'));
      expect(body, contains(OpenAIDVAIAdapter.defaultTranscriptionModel));
      expect(body, contains('name="language"'));
      expect(body, contains('filename="audio.mp3"'));
      expect(body, contains('content-type: audio/mpeg'));
    });

    test('a model that calls no tool returns its answer directly', () async {
      const DVAIToolRegistry().clear();
      const DVAIToolRegistry()
          .register('sumLedger', (_) => const DVJsonNumber(10));
      addTearDown(const DVAIToolRegistry().clear);

      final transport = _RecordingTransport.json(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': 'No lookup needed.'},
          },
        ],
      });
      final adapter = OpenAIDVAIAdapter(apiKey: 'sk-a', send: transport.send);

      final result = await adapter.runAgent(
        const DVAIAgentRequest(
          goal: 'Reconcile the ledger',
          tools: <String>['sumLedger'],
        ),
      );

      expect(result.output, 'No lookup needed.');
      expect(result.usedTools, isEmpty,
          reason: 'the model declined to call the tool');
      expect(transport.requests, hasLength(1));
    });
  });

  group('prompt-based agent fallback', () {
    setUp(() {
      const DVAIToolRegistry().clear();
      const DVAIToolRegistry().register('sumLedger', (input) {
        final left = input['left'];
        final right = input['right'];
        if (left is! DVJsonNumber || right is! DVJsonNumber) {
          throw ArgumentError('sumLedger requires numeric left and right.');
        }
        return DVJsonNumber(left.value + right.value);
      });
    });
    tearDown(const DVAIToolRegistry().clear);

    test('Gemini runs allowed tools up front and puts results in the prompt',
        () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': 'The ledger totals 10.'},
              ],
            },
          },
        ],
      });
      final adapter = GeminiDVAIAdapter(apiKey: 'g-key', send: transport.send);

      final result = await adapter.runAgent(
        const DVAIAgentRequest(
          goal: 'Reconcile the ledger',
          context: <String, DVJsonValue>{
            'left': DVJsonNumber(4),
            'right': DVJsonNumber(6),
          },
          tools: <String>['sumLedger', 'notRegistered'],
        ),
      );

      expect(result.usedTools, <String>['sumLedger']);
      expect((result.data['sumLedger']! as DVJsonNumber).value, 10);
      expect(result.output, 'The ledger totals 10.');

      final contents = transport.sentJson['contents']! as List<Object?>;
      final parts =
          (contents.single as Map<String, Object?>)['parts']! as List<Object?>;
      final prompt = (parts.single as Map<String, Object?>)['text']! as String;
      expect(prompt, startsWith('Reconcile the ledger'));
      expect(prompt, contains('Tool results:'));
      expect(prompt, contains('"sumLedger":10'));
    });
  });

  group('OpenRouterDVAIAdapter', () {
    test('keeps the OpenAI wire format on the OpenRouter host', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': 'routed'},
          },
        ],
      });
      final adapter = OpenRouterDVAIAdapter(
        apiKey: 'or-key',
        send: transport.send,
      );

      expect(await adapter.chat('hello'), 'routed');
      expect(
        transport.single.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      await expectLater(adapter.embed('x'), throwsUnsupportedError);
    });
  });

  group('GeminiDVAIAdapter', () {
    test('reads generated candidate text', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': 'Bonjour'},
              ],
            },
          },
        ],
      });
      final adapter = GeminiDVAIAdapter(apiKey: 'g-key', send: transport.send);

      expect(await adapter.chat('Greet me'), 'Bonjour');
      expect(
        transport.single.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '${GeminiDVAIAdapter.defaultModel}:generateContent',
      );
      expect(transport.single.headers['x-goog-api-key'], 'g-key');
    });

    test('requests a JSON response schema for structured output', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': '{"ok":true}'},
              ],
            },
          },
        ],
      });
      final adapter = GeminiDVAIAdapter(apiKey: 'g-key', send: transport.send);

      final result = await adapter.structuredOutput(
        'Check',
        const <String, DVJsonValue>{'type': DVJsonString('object')},
      );

      expect((result['ok']! as DVJsonBool).value, isTrue);
      final config =
          transport.sentJson['generationConfig']! as Map<String, Object?>;
      expect(config['responseMimeType'], 'application/json');
      expect(config['responseSchema'], <String, Object?>{'type': 'object'});
    });

    test('sends audio inline for transcription', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': 'spoken words'},
              ],
            },
          },
        ],
      });
      final adapter = GeminiDVAIAdapter(apiKey: 'g-key', send: transport.send);

      final transcript = await adapter.transcribe(
        <int>[10, 20, 30],
        mimeType: 'audio/ogg',
      );

      expect(transcript.text, 'spoken words');
      final contents = transport.sentJson['contents']! as List<Object?>;
      final parts =
          (contents.single as Map<String, Object?>)['parts']! as List<Object?>;
      final inline = (parts.first as Map<String, Object?>)['inline_data']!
          as Map<String, Object?>;
      expect(inline['mime_type'], 'audio/ogg');
      expect(inline['data'], base64Encode(<int>[10, 20, 30]));
    });
  });

  group('OllamaDVAIAdapter', () {
    test('reads a non-streaming chat response', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'message': <String, Object?>{'role': 'assistant', 'content': 'local'},
      });
      final adapter = OllamaDVAIAdapter(send: transport.send);

      expect(await adapter.chat('hello'), 'local');
      expect(
        transport.single.url.toString(),
        'http://localhost:11434/api/chat',
      );
      expect(transport.sentJson['stream'], isFalse);
      expect(transport.single.headers.containsKey('authorization'), isFalse);
    });

    test('reads the first embedding vector', () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'embeddings': <Object?>[
          <Object?>[0.1, 0.2],
        ],
      });
      final adapter = OllamaDVAIAdapter(send: transport.send);

      expect(await adapter.embed('text'), <double>[0.1, 0.2]);
    });

    test('rejects malformed payloads instead of returning empty results',
        () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'message': 'not an object',
      });
      final adapter = OllamaDVAIAdapter(send: transport.send);

      await expectLater(
        adapter.chat('hi'),
        throwsA(
          isA<DVAIProviderException>().having(
            (error) => error.message,
            'message',
            contains('"message" was not a JSON object'),
          ),
        ),
      );
    });
  });

  group('native tool calling', () {
    setUp(() {
      const DVAIToolRegistry().clear();
      const DVAIToolRegistry().register(
        'getWeather',
        (input) {
          final city = input['city'];
          if (city is! DVJsonString) {
            throw ArgumentError('getWeather requires a city.');
          }
          return DVJsonString('sunny in ${city.value}');
        },
        description: 'Look up the current weather for a city.',
        parameters: const <String, DVJsonValue>{
          'type': DVJsonString('object'),
          'properties': DVJsonMap(<String, DVJsonValue>{
            'city': DVJsonMap(<String, DVJsonValue>{
              'type': DVJsonString('string'),
            }),
          }),
          'required': DVJsonList(<DVJsonValue>[DVJsonString('city')]),
        },
      );
    });
    tearDown(const DVAIToolRegistry().clear);

    test('the registry keeps each tool description and schema', () {
      final definition = const DVAIToolRegistry().definition('getWeather')!;
      expect(definition.description, startsWith('Look up the current'));
      expect(definition.jsonSchema['type'], 'object');
      expect(definition.jsonSchema['required'], <Object?>['city']);
    });

    test('a tool with no declared parameters still advertises a schema', () {
      const DVAIToolRegistry().register('ping', (_) => const DVJsonNull());
      expect(
        const DVAIToolRegistry().definition('ping')!.jsonSchema,
        <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
      );
    });

    test('Anthropic drives a tool_use round trip and returns the final text',
        () async {
      final transport = _RecordingTransport(<DVAIHttpResponse>[
        DVAIHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'stop_reason': 'tool_use',
            'content': <Object?>[
              <String, Object?>{
                'type': 'tool_use',
                'id': 'toolu_1',
                'name': 'getWeather',
                'input': <String, Object?>{'city': 'Paris'},
              },
            ],
          }),
        ),
        DVAIHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'stop_reason': 'end_turn',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'Paris is sunny.'},
            ],
          }),
        ),
      ]);
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: transport.send,
      );

      final result = await adapter.runAgent(
        const DVAIAgentRequest(
          goal: 'What is the weather in Paris?',
          tools: <String>['getWeather'],
        ),
      );

      expect(result.output, 'Paris is sunny.');
      expect(result.usedTools, <String>['getWeather']);
      expect(
        (result.data['getWeather']! as DVJsonString).value,
        'sunny in Paris',
      );

      // Turn 1 advertises the tool with its description and schema.
      final firstBody = jsonDecode(utf8.decode(transport.requests[0].body))
          as Map<String, Object?>;
      final advertised =
          (firstBody['tools']! as List<Object?>).single as Map<String, Object?>;
      expect(advertised['name'], 'getWeather');
      expect(advertised['description'], startsWith('Look up the current'));
      expect(
        (advertised['input_schema']! as Map<String, Object?>)['type'],
        'object',
      );

      // Turn 2 echoes the assistant turn and answers with a tool_result.
      final secondBody = jsonDecode(utf8.decode(transport.requests[1].body))
          as Map<String, Object?>;
      final messages = secondBody['messages']! as List<Object?>;
      expect(messages, hasLength(3));
      expect((messages[1] as Map<String, Object?>)['role'], 'assistant');
      final toolTurn = messages[2] as Map<String, Object?>;
      expect(toolTurn['role'], 'user');
      final toolResult = (toolTurn['content']! as List<Object?>).single
          as Map<String, Object?>;
      expect(toolResult['type'], 'tool_result');
      expect(toolResult['tool_use_id'], 'toolu_1');
      expect(toolResult['content'], '"sunny in Paris"');
      expect(toolResult.containsKey('is_error'), isFalse);
    });

    test('a throwing tool is reported to the model instead of failing the run',
        () async {
      final transport = _RecordingTransport(<DVAIHttpResponse>[
        DVAIHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'stop_reason': 'tool_use',
            'content': <Object?>[
              <String, Object?>{
                'type': 'tool_use',
                'id': 'toolu_1',
                'name': 'getWeather',
                'input': <String, Object?>{'wrong': 'shape'},
              },
            ],
          }),
        ),
        DVAIHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'stop_reason': 'end_turn',
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'I need a city.'},
            ],
          }),
        ),
      ]);
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: transport.send,
      );

      final result = await adapter.runAgent(
        const DVAIAgentRequest(
          goal: 'Weather?',
          tools: <String>['getWeather'],
        ),
      );

      expect(result.output, 'I need a city.');
      expect(result.usedTools, isEmpty);
      expect(result.data, isEmpty);

      final secondBody = jsonDecode(utf8.decode(transport.requests[1].body))
          as Map<String, Object?>;
      final messages = secondBody['messages']! as List<Object?>;
      final toolResult =
          ((messages[2] as Map<String, Object?>)['content']! as List<Object?>)
              .single as Map<String, Object?>;
      expect(toolResult['is_error'], isTrue);
      expect(toolResult['content'], contains('requires a city'));
    });

    test('OpenAI drives a tool_calls round trip', () async {
      final transport = _RecordingTransport(<DVAIHttpResponse>[
        DVAIHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
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
                        'name': 'getWeather',
                        'arguments': '{"city":"Berlin"}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
        ),
        DVAIHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'content': 'Berlin is sunny.'},
              },
            ],
          }),
        ),
      ]);
      final adapter = OpenAIDVAIAdapter(apiKey: 'sk-a', send: transport.send);

      final result = await adapter.runAgent(
        const DVAIAgentRequest(
          goal: 'Weather in Berlin?',
          tools: <String>['getWeather'],
        ),
      );

      expect(result.output, 'Berlin is sunny.');
      expect(result.usedTools, <String>['getWeather']);
      expect(
        (result.data['getWeather']! as DVJsonString).value,
        'sunny in Berlin',
      );

      final firstBody = jsonDecode(utf8.decode(transport.requests[0].body))
          as Map<String, Object?>;
      final advertised =
          (firstBody['tools']! as List<Object?>).single as Map<String, Object?>;
      expect(advertised['type'], 'function');
      expect(
        (advertised['function']! as Map<String, Object?>)['name'],
        'getWeather',
      );

      final secondBody = jsonDecode(utf8.decode(transport.requests[1].body))
          as Map<String, Object?>;
      final messages = secondBody['messages']! as List<Object?>;
      final toolTurn = messages.last as Map<String, Object?>;
      expect(toolTurn['role'], 'tool');
      expect(toolTurn['tool_call_id'], 'call_1');
      expect(toolTurn['content'], '"sunny in Berlin"');
    });

    test('a runaway tool loop fails instead of spinning forever', () async {
      final toolUse = DVAIHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'stop_reason': 'tool_use',
          'content': <Object?>[
            <String, Object?>{
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'getWeather',
              'input': <String, Object?>{'city': 'Paris'},
            },
          ],
        }),
      );
      final transport = _RecordingTransport(
        List<DVAIHttpResponse>.filled(12, toolUse),
      );
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: transport.send,
      );

      await expectLater(
        adapter.runAgent(
          const DVAIAgentRequest(
            goal: 'loop',
            tools: <String>['getWeather'],
          ),
        ),
        throwsA(
          isA<DVAIProviderException>().having(
            (error) => error.message,
            'message',
            contains('did not finish within'),
          ),
        ),
      );
      expect(transport.requests, hasLength(adapter.maxAgentIterations));
    });

    test('an unregistered tool name falls back to the prompt-based run',
        () async {
      final transport = _RecordingTransport.json(<String, Object?>{
        'stop_reason': 'end_turn',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'no tools needed'},
        ],
      });
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: transport.send,
      );

      final result = await adapter.runAgent(
        const DVAIAgentRequest(goal: 'hi', tools: <String>['notRegistered']),
      );

      expect(result.output, 'no tools needed');
      expect(transport.sentJson.containsKey('tools'), isFalse);
    });
  });

  group('DV.AI wiring', () {
    test('an HTTP adapter satisfies the DVAIAdapter contract', () {
      final adapter = AnthropicDVAIAdapter(
        apiKey: 'sk-test',
        send: _RecordingTransport(const <DVAIHttpResponse>[]).send,
      );
      expect(adapter, isA<DVAIAdapter>());
      expect(adapter, isA<DVHttpAIAdapter>());
    });
  });
}
