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

    test('runAgent executes registered tools and feeds results to the model',
        () async {
      const DVAIToolRegistry().clear();
      const DVAIToolRegistry().register('sumLedger', (input) {
        final left = input['left'];
        final right = input['right'];
        if (left is! DVJsonNumber || right is! DVJsonNumber) {
          throw ArgumentError('sumLedger requires numeric left and right.');
        }
        return DVJsonNumber(left.value + right.value);
      });
      addTearDown(const DVAIToolRegistry().clear);

      final transport = _RecordingTransport.json(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': 'The ledger totals 10.'},
          },
        ],
      });
      final adapter = OpenAIDVAIAdapter(apiKey: 'sk-a', send: transport.send);

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

      final messages = transport.sentJson['messages']! as List<Object?>;
      final prompt =
          (messages.single as Map<String, Object?>)['content']! as String;
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
      final parts = (contents.single as Map<String, Object?>)['parts']!
          as List<Object?>;
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
