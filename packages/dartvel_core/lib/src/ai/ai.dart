/// Dartvel AI: typed JSON values, the tool registry, the adapter contract, and
/// the concrete provider adapters that talk to real AI services over HTTP.
library dartvel_core.ai;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

typedef DVJsonObject = Map<String, DVJsonValue>;
typedef DVAIToolHandler = FutureOr<DVJsonValue> Function(DVJsonObject input);

sealed class DVJsonValue {
  const DVJsonValue();
}

class DVJsonNull extends DVJsonValue {
  const DVJsonNull();
}

class DVJsonString extends DVJsonValue {
  final String value;
  const DVJsonString(this.value);
}

class DVJsonNumber extends DVJsonValue {
  final num value;
  const DVJsonNumber(this.value);
}

class DVJsonBool extends DVJsonValue {
  final bool value;
  const DVJsonBool(this.value);
}

class DVJsonList extends DVJsonValue {
  final List<DVJsonValue> value;
  const DVJsonList(this.value);
}

class DVJsonMap extends DVJsonValue {
  final DVJsonObject value;
  const DVJsonMap(this.value);
}

/// Converts between Dartvel's typed [DVJsonValue] tree and the plain
/// `Object?` tree that `dart:convert` produces and consumes.
class DVJsonCodec {
  const DVJsonCodec._();

  static Object? toJson(DVJsonValue value) => switch (value) {
        DVJsonNull() => null,
        DVJsonString(value: final text) => text,
        DVJsonNumber(value: final number) => number,
        DVJsonBool(value: final flag) => flag,
        DVJsonList(value: final items) => items.map(toJson).toList(),
        DVJsonMap(value: final entries) => toJsonObject(entries),
      };

  static Map<String, Object?> toJsonObject(DVJsonObject object) =>
      <String, Object?>{
        for (final entry in object.entries) entry.key: toJson(entry.value),
      };

  static DVJsonValue fromJson(Object? value) {
    if (value == null) return const DVJsonNull();
    if (value is String) return DVJsonString(value);
    if (value is bool) return DVJsonBool(value);
    if (value is num) return DVJsonNumber(value);
    if (value is List) {
      return DVJsonList(value.map(fromJson).toList(growable: false));
    }
    if (value is Map) {
      return DVJsonMap(<String, DVJsonValue>{
        for (final entry in value.entries)
          entry.key.toString(): fromJson(entry.value),
      });
    }
    throw ArgumentError.value(
      value,
      'value',
      'Values of type ${value.runtimeType} cannot be represented as DVJsonValue.',
    );
  }

  static DVJsonObject fromJsonObject(Map<String, Object?> object) =>
      <String, DVJsonValue>{
        for (final entry in object.entries) entry.key: fromJson(entry.value),
      };
}

class DVAIToolRegistry {
  static final Map<String, DVAIToolHandler> _handlers = {};

  const DVAIToolRegistry();

  void register(String name, DVAIToolHandler handler) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'AI tool names cannot be empty.');
    }
    _handlers[name] = handler;
  }

  bool contains(String name) => _handlers.containsKey(name);

  List<String> get names => List<String>.unmodifiable(_handlers.keys);

  Future<DVJsonValue> call(String name, [DVJsonObject input = const {}]) async {
    final handler = _handlers[name];
    if (handler == null) {
      throw StateError('No AI tool registered for "$name".');
    }
    return handler(input);
  }

  void clear() {
    _handlers.clear();
  }
}

class DVAITranscript {
  final String text;
  final String language;
  final Duration duration;
  final DVJsonObject metadata;

  const DVAITranscript({
    required this.text,
    this.language = 'und',
    this.duration = Duration.zero,
    this.metadata = const <String, DVJsonValue>{},
  });
}

class DVAIAgentRequest {
  final String goal;
  final DVJsonObject context;
  final List<String> tools;

  const DVAIAgentRequest({
    required this.goal,
    this.context = const <String, DVJsonValue>{},
    this.tools = const <String>[],
  });
}

class DVAIAgentResult {
  final String output;
  final DVJsonObject data;
  final List<String> usedTools;

  const DVAIAgentResult({
    required this.output,
    this.data = const <String, DVJsonValue>{},
    this.usedTools = const <String>[],
  });
}

abstract class DVAIAdapter {
  Future<String> chat(String prompt, {String provider = 'gemini'});
  Future<List<double>> embed(String text);
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  );
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  });
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request);
}

/// Deterministic in-process adapter for development and tests. It never reaches
/// the network, so tests cannot accidentally pass because a provider was
/// unreachable.
class LocalDVAIAdapter implements DVAIAdapter {
  const LocalDVAIAdapter();

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async {
    final normalized = prompt.trim();
    return normalized.isEmpty
        ? ''
        : '[$provider] ${normalized.split(RegExp(r'\s+')).take(120).join(' ')}';
  }

  @override
  Future<List<double>> embed(String text) async {
    final buckets = List<double>.filled(16, 0);
    for (var i = 0; i < text.length; i++) {
      buckets[i % buckets.length] += text.codeUnitAt(i) / 65535;
    }
    return buckets;
  }

  @override
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) async =>
      {
        'prompt': DVJsonString(prompt),
        'schema': DVJsonMap(schema),
        'summary': DVJsonString(await chat(prompt, provider: 'local')),
      };

  @override
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) async {
    final checksum = audioBytes.fold<int>(0, (sum, byte) => sum + byte);
    return DVAITranscript(
      text: 'local transcript ${audioBytes.length} bytes checksum $checksum',
      language: language,
      metadata: <String, DVJsonValue>{
        'mimeType': DVJsonString(mimeType),
        'byteLength': DVJsonNumber(audioBytes.length),
        'checksum': DVJsonNumber(checksum),
      },
    );
  }

  @override
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request) async {
    final usedTools = <String>[];
    final data = <String, DVJsonValue>{};
    for (final toolName in request.tools) {
      if (!const DVAIToolRegistry().contains(toolName)) continue;
      usedTools.add(toolName);
      data[toolName] = await const DVAIToolRegistry().call(
        toolName,
        request.context,
      );
    }
    final summary = await chat(request.goal, provider: 'local-agent');
    return DVAIAgentResult(
      output: summary,
      data: Map<String, DVJsonValue>.unmodifiable(data),
      usedTools: List<String>.unmodifiable(usedTools),
    );
  }
}

// ---------------------------------------------------------------------------
// HTTP transport
// ---------------------------------------------------------------------------

class DVAIHttpRequest {
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final List<int> body;

  const DVAIHttpRequest({
    required this.url,
    this.method = 'POST',
    this.headers = const <String, String>{},
    this.body = const <int>[],
  });
}

class DVAIHttpResponse {
  final int statusCode;
  final String body;

  const DVAIHttpResponse({required this.statusCode, required this.body});

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Transport seam for [DVHttpAIAdapter]. Tests inject a function instead of
/// mocking a client, so provider request/response handling is covered without
/// network access.
typedef DVAIHttpSend = Future<DVAIHttpResponse> Function(
  DVAIHttpRequest request,
);

Future<DVAIHttpResponse> dvSendAIHttpRequest(DVAIHttpRequest request) async {
  final client = http.Client();
  try {
    final outgoing = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.body;
    final streamed = await client.send(outgoing);
    return DVAIHttpResponse(
      statusCode: streamed.statusCode,
      body: await streamed.stream.bytesToString(),
    );
  } finally {
    client.close();
  }
}

/// Thrown when a provider rejects a request or returns a payload Dartvel
/// cannot interpret. Provider failures are never swallowed into empty results.
class DVAIProviderException implements Exception {
  final String provider;
  final int? statusCode;
  final String message;
  final String? responseBody;

  const DVAIProviderException(
    this.provider,
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    final body = responseBody == null || responseBody!.isEmpty
        ? ''
        : '\nResponse: $responseBody';
    return 'DVAIProviderException[$provider]$status: $message$body';
  }
}

// ---------------------------------------------------------------------------
// Shared provider base
// ---------------------------------------------------------------------------

abstract class DVHttpAIAdapter implements DVAIAdapter {
  final Uri baseUrl;
  final String apiKey;
  final String model;
  final String embeddingModel;
  final String transcriptionModel;
  final int maxOutputTokens;
  final DVAIHttpSend send;

  const DVHttpAIAdapter({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.embeddingModel,
    required this.transcriptionModel,
    required this.maxOutputTokens,
    required this.send,
  });

  /// Identifier reported in errors and passed through to generated logs.
  String get providerName;

  /// Headers applied to every JSON request for this provider.
  Map<String, String> get authHeaders;

  /// The `provider` argument on [chat] is a caller hint retained for source
  /// compatibility; the configured adapter decides which service is used.
  @override
  Future<String> chat(String prompt, {String provider = 'gemini'});

  @override
  Future<DVAIAgentResult> runAgent(DVAIAgentRequest request) async {
    const registry = DVAIToolRegistry();
    final usedTools = <String>[];
    final data = <String, DVJsonValue>{};
    for (final toolName in request.tools) {
      if (!registry.contains(toolName)) continue;
      usedTools.add(toolName);
      data[toolName] = await registry.call(toolName, request.context);
    }

    final prompt = StringBuffer(request.goal);
    if (request.context.isNotEmpty) {
      prompt
        ..writeln()
        ..writeln()
        ..writeln('Context:')
        ..writeln(jsonEncode(DVJsonCodec.toJsonObject(request.context)));
    }
    if (data.isNotEmpty) {
      prompt
        ..writeln()
        ..writeln('Tool results:')
        ..writeln(jsonEncode(DVJsonCodec.toJsonObject(data)));
    }

    return DVAIAgentResult(
      output: await chat(prompt.toString(), provider: providerName),
      data: Map<String, DVJsonValue>.unmodifiable(data),
      usedTools: List<String>.unmodifiable(usedTools),
    );
  }

  // --- request helpers ---------------------------------------------------

  Uri endpoint(String path, [Map<String, String> query = const {}]) {
    final basePath = baseUrl.path.endsWith('/')
        ? baseUrl.path.substring(0, baseUrl.path.length - 1)
        : baseUrl.path;
    return baseUrl.replace(
      path: '$basePath$path',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Future<Map<String, Object?>> postJson(
    Uri url,
    Map<String, Object?> body,
  ) async {
    final response = await send(
      DVAIHttpRequest(
        url: url,
        headers: <String, String>{
          'content-type': 'application/json',
          ...authHeaders,
        },
        body: utf8.encode(jsonEncode(body)),
      ),
    );
    return decodeJsonResponse(response);
  }

  Map<String, Object?> decodeJsonResponse(DVAIHttpResponse response) {
    if (!response.isSuccess) {
      throw DVAIProviderException(
        providerName,
        'Request was rejected by the provider.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw DVAIProviderException(
        providerName,
        'Response was not valid JSON: ${error.message}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw DVAIProviderException(
        providerName,
        'Expected a JSON object at the top level of the response.',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    return decoded;
  }

  // --- payload navigation ------------------------------------------------

  Never malformed(String description, [String? body]) =>
      throw DVAIProviderException(
        providerName,
        'Malformed response: $description.',
        responseBody: body,
      );

  Map<String, Object?> readMap(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is Map<String, Object?>) return value;
    malformed('"$key" was not a JSON object');
  }

  List<Object?> readList(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is List<Object?>) return value;
    malformed('"$key" was not a JSON array');
  }

  String readString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is String) return value;
    malformed('"$key" was not a string');
  }

  List<double> readDoubles(List<Object?> source, String description) {
    final values = <double>[];
    for (final entry in source) {
      if (entry is! num) malformed('$description contained a non-numeric entry');
      values.add(entry.toDouble());
    }
    return List<double>.unmodifiable(values);
  }

  /// Providers return structured output as a JSON document inside a text
  /// field; this parses that document into Dartvel's typed value tree.
  DVJsonObject parseStructuredText(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw DVAIProviderException(
        providerName,
        'Structured output was not valid JSON: ${error.message}',
        responseBody: text,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw DVAIProviderException(
        providerName,
        'Structured output must be a JSON object.',
        responseBody: text,
      );
    }
    return DVJsonCodec.fromJsonObject(decoded);
  }

  Never unsupported(String capability) => throw UnsupportedError(
        '$providerName does not provide $capability. Configure a different '
        'DVAIAdapter for that capability.',
      );
}

// ---------------------------------------------------------------------------
// Multipart helper (audio transcription uploads)
// ---------------------------------------------------------------------------

String dvGenerateMultipartBoundary([Random? random]) {
  final source = random ?? Random();
  final suffix = List<int>.generate(16, (_) => source.nextInt(36))
      .map((value) => value.toRadixString(36))
      .join();
  return '----dartvel$suffix';
}

List<int> dvEncodeMultipartBody({
  required String boundary,
  required Map<String, String> fields,
  required String fileField,
  required String fileName,
  required String fileContentType,
  required List<int> fileBytes,
}) {
  final builder = BytesBuilder();
  void writeLine(String text) => builder.add(utf8.encode('$text\r\n'));

  for (final entry in fields.entries) {
    writeLine('--$boundary');
    writeLine(
      'content-disposition: form-data; name="${entry.key}"',
    );
    writeLine('');
    writeLine(entry.value);
  }

  writeLine('--$boundary');
  writeLine(
    'content-disposition: form-data; name="$fileField"; '
    'filename="$fileName"',
  );
  writeLine('content-type: $fileContentType');
  writeLine('');
  builder.add(fileBytes);
  writeLine('');
  writeLine('--$boundary--');

  return builder.takeBytes();
}

String dvAudioFileNameFor(String mimeType) {
  final subtype = mimeType.split('/').last.split(';').first.trim();
  return switch (subtype) {
    'mpeg' || 'mp3' => 'audio.mp3',
    'mp4' || 'm4a' || 'x-m4a' => 'audio.m4a',
    'ogg' || 'opus' => 'audio.ogg',
    'webm' => 'audio.webm',
    'flac' || 'x-flac' => 'audio.flac',
    _ => 'audio.wav',
  };
}

// ---------------------------------------------------------------------------
// Anthropic (Claude)
// ---------------------------------------------------------------------------

/// Talks to the Anthropic Messages API (`POST /v1/messages`).
class AnthropicDVAIAdapter extends DVHttpAIAdapter {
  static const String defaultModel = 'claude-opus-5';
  static const String apiVersion = '2023-06-01';

  final String version;

  AnthropicDVAIAdapter({
    required super.apiKey,
    super.model = defaultModel,
    super.maxOutputTokens = 16000,
    this.version = apiVersion,
    Uri? baseUrl,
    super.send = dvSendAIHttpRequest,
  }) : super(
          baseUrl: baseUrl ?? Uri.https('api.anthropic.com'),
          embeddingModel: '',
          transcriptionModel: '',
        );

  @override
  String get providerName => 'anthropic';

  @override
  Map<String, String> get authHeaders => <String, String>{
        'x-api-key': apiKey,
        'anthropic-version': version,
      };

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async {
    final payload = await postJson(
      endpoint('/v1/messages'),
      _messagesBody(prompt),
    );
    return _firstTextBlock(payload);
  }

  @override
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) async {
    final payload = await postJson(
      endpoint('/v1/messages'),
      <String, Object?>{
        ..._messagesBody(prompt),
        'output_config': <String, Object?>{
          'format': <String, Object?>{
            'type': 'json_schema',
            'schema': DVJsonCodec.toJsonObject(schema),
          },
        },
      },
    );
    return parseStructuredText(_firstTextBlock(payload));
  }

  @override
  Future<List<double>> embed(String text) async =>
      unsupported('an embeddings endpoint');

  @override
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) async =>
      unsupported('an audio transcription endpoint');

  Map<String, Object?> _messagesBody(String prompt) => <String, Object?>{
        'model': model,
        'max_tokens': maxOutputTokens,
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': prompt},
        ],
      };

  String _firstTextBlock(Map<String, Object?> payload) {
    final stopReason = payload['stop_reason'];
    if (stopReason == 'refusal') {
      throw DVAIProviderException(
        providerName,
        'The request was declined by Anthropic safety classifiers.',
        responseBody: jsonEncode(payload),
      );
    }
    for (final block in readList(payload, 'content')) {
      if (block is Map<String, Object?> && block['type'] == 'text') {
        return readString(block, 'text');
      }
    }
    malformed('no text block was present in "content"', jsonEncode(payload));
  }
}

// ---------------------------------------------------------------------------
// OpenAI and OpenAI-compatible services
// ---------------------------------------------------------------------------

/// Talks to the OpenAI REST API. [OpenRouterDVAIAdapter] reuses this wire
/// format against a different host.
class OpenAIDVAIAdapter extends DVHttpAIAdapter {
  static const String defaultModel = 'gpt-4.1';
  static const String defaultEmbeddingModel = 'text-embedding-3-small';
  static const String defaultTranscriptionModel = 'whisper-1';

  final Map<String, String> extraHeaders;

  OpenAIDVAIAdapter({
    required super.apiKey,
    super.model = defaultModel,
    super.embeddingModel = defaultEmbeddingModel,
    super.transcriptionModel = defaultTranscriptionModel,
    super.maxOutputTokens = 4096,
    Uri? baseUrl,
    this.extraHeaders = const <String, String>{},
    super.send = dvSendAIHttpRequest,
  }) : super(baseUrl: baseUrl ?? Uri.https('api.openai.com'));

  @override
  String get providerName => 'openai';

  @override
  Map<String, String> get authHeaders => <String, String>{
        'authorization': 'Bearer $apiKey',
        ...extraHeaders,
      };

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async {
    final payload = await postJson(
      endpoint('/v1/chat/completions'),
      _completionsBody(prompt),
    );
    return _firstChoiceContent(payload);
  }

  @override
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) async {
    final payload = await postJson(
      endpoint('/v1/chat/completions'),
      <String, Object?>{
        ..._completionsBody(prompt),
        'response_format': <String, Object?>{
          'type': 'json_schema',
          'json_schema': <String, Object?>{
            'name': 'dartvel_structured_output',
            'strict': true,
            'schema': DVJsonCodec.toJsonObject(schema),
          },
        },
      },
    );
    return parseStructuredText(_firstChoiceContent(payload));
  }

  @override
  Future<List<double>> embed(String text) async {
    if (embeddingModel.isEmpty) unsupported('an embeddings endpoint');
    final payload = await postJson(
      endpoint('/v1/embeddings'),
      <String, Object?>{'model': embeddingModel, 'input': text},
    );
    final data = readList(payload, 'data');
    if (data.isEmpty) malformed('"data" was empty', jsonEncode(payload));
    final first = data.first;
    if (first is! Map<String, Object?>) {
      malformed('"data[0]" was not a JSON object', jsonEncode(payload));
    }
    return readDoubles(readList(first, 'embedding'), '"data[0].embedding"');
  }

  @override
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) async {
    if (transcriptionModel.isEmpty) unsupported('a transcription endpoint');
    final boundary = dvGenerateMultipartBoundary();
    final response = await send(
      DVAIHttpRequest(
        url: endpoint('/v1/audio/transcriptions'),
        headers: <String, String>{
          'content-type': 'multipart/form-data; boundary=$boundary',
          ...authHeaders,
        },
        body: dvEncodeMultipartBody(
          boundary: boundary,
          fields: <String, String>{
            'model': transcriptionModel,
            if (language != 'und') 'language': language,
          },
          fileField: 'file',
          fileName: dvAudioFileNameFor(mimeType),
          fileContentType: mimeType,
          fileBytes: audioBytes,
        ),
      ),
    );
    final payload = decodeJsonResponse(response);
    return DVAITranscript(
      text: readString(payload, 'text'),
      language: language,
      metadata: <String, DVJsonValue>{
        'model': DVJsonString(transcriptionModel),
        'mimeType': DVJsonString(mimeType),
        'byteLength': DVJsonNumber(audioBytes.length),
      },
    );
  }

  Map<String, Object?> _completionsBody(String prompt) => <String, Object?>{
        'model': model,
        'max_completion_tokens': maxOutputTokens,
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': prompt},
        ],
      };

  String _firstChoiceContent(Map<String, Object?> payload) {
    final choices = readList(payload, 'choices');
    if (choices.isEmpty) malformed('"choices" was empty', jsonEncode(payload));
    final first = choices.first;
    if (first is! Map<String, Object?>) {
      malformed('"choices[0]" was not a JSON object', jsonEncode(payload));
    }
    return readString(readMap(first, 'message'), 'content');
  }
}

/// OpenRouter exposes the OpenAI chat-completions wire format under its own
/// host. It does not serve embeddings or transcription.
class OpenRouterDVAIAdapter extends OpenAIDVAIAdapter {
  OpenRouterDVAIAdapter({
    required super.apiKey,
    super.model = 'anthropic/claude-opus-5',
    super.maxOutputTokens,
    Uri? baseUrl,
    super.extraHeaders,
    super.send,
  }) : super(
          baseUrl: baseUrl ?? Uri.https('openrouter.ai', '/api'),
          embeddingModel: '',
          transcriptionModel: '',
        );

  @override
  String get providerName => 'openrouter';
}

// ---------------------------------------------------------------------------
// Google Gemini
// ---------------------------------------------------------------------------

/// Talks to the Gemini generative-language REST API.
class GeminiDVAIAdapter extends DVHttpAIAdapter {
  static const String defaultModel = 'gemini-2.5-flash';
  static const String defaultEmbeddingModel = 'text-embedding-004';

  final String apiVersion;

  GeminiDVAIAdapter({
    required super.apiKey,
    super.model = defaultModel,
    super.embeddingModel = defaultEmbeddingModel,
    super.transcriptionModel = defaultModel,
    super.maxOutputTokens = 4096,
    this.apiVersion = 'v1beta',
    Uri? baseUrl,
    super.send = dvSendAIHttpRequest,
  }) : super(
          baseUrl: baseUrl ?? Uri.https('generativelanguage.googleapis.com'),
        );

  @override
  String get providerName => 'gemini';

  @override
  Map<String, String> get authHeaders => <String, String>{
        'x-goog-api-key': apiKey,
      };

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async {
    final payload = await postJson(
      _generateContent(model),
      <String, Object?>{
        'contents': _textContents(prompt),
        'generationConfig': <String, Object?>{
          'maxOutputTokens': maxOutputTokens,
        },
      },
    );
    return _firstCandidateText(payload);
  }

  @override
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) async {
    final payload = await postJson(
      _generateContent(model),
      <String, Object?>{
        'contents': _textContents(prompt),
        'generationConfig': <String, Object?>{
          'maxOutputTokens': maxOutputTokens,
          'responseMimeType': 'application/json',
          'responseSchema': DVJsonCodec.toJsonObject(schema),
        },
      },
    );
    return parseStructuredText(_firstCandidateText(payload));
  }

  @override
  Future<List<double>> embed(String text) async {
    final payload = await postJson(
      endpoint('/$apiVersion/models/$embeddingModel:embedContent'),
      <String, Object?>{
        'model': 'models/$embeddingModel',
        'content': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': text},
          ],
        },
      },
    );
    return readDoubles(
      readList(readMap(payload, 'embedding'), 'values'),
      '"embedding.values"',
    );
  }

  @override
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) async {
    final payload = await postJson(
      _generateContent(transcriptionModel),
      <String, Object?>{
        'contents': <Object?>[
          <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{
                'inline_data': <String, Object?>{
                  'mime_type': mimeType,
                  'data': base64Encode(audioBytes),
                },
              },
              <String, Object?>{
                'text': language == 'und'
                    ? 'Transcribe this audio. Reply with the transcript only.'
                    : 'Transcribe this audio in $language. Reply with the '
                        'transcript only.',
              },
            ],
          },
        ],
      },
    );
    return DVAITranscript(
      text: _firstCandidateText(payload),
      language: language,
      metadata: <String, DVJsonValue>{
        'model': DVJsonString(transcriptionModel),
        'mimeType': DVJsonString(mimeType),
        'byteLength': DVJsonNumber(audioBytes.length),
      },
    );
  }

  Uri _generateContent(String target) =>
      endpoint('/$apiVersion/models/$target:generateContent');

  List<Object?> _textContents(String prompt) => <Object?>[
        <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': prompt},
          ],
        },
      ];

  String _firstCandidateText(Map<String, Object?> payload) {
    final candidates = readList(payload, 'candidates');
    if (candidates.isEmpty) {
      malformed('"candidates" was empty', jsonEncode(payload));
    }
    final first = candidates.first;
    if (first is! Map<String, Object?>) {
      malformed('"candidates[0]" was not a JSON object', jsonEncode(payload));
    }
    final parts = readList(readMap(first, 'content'), 'parts');
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map<String, Object?> && part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }
    if (buffer.isEmpty) {
      malformed('no text parts were present in the candidate',
          jsonEncode(payload));
    }
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// Ollama / local Llama runtimes
// ---------------------------------------------------------------------------

/// Talks to a local Ollama runtime. The API key is optional and only sent when
/// the runtime is fronted by an authenticating proxy.
class OllamaDVAIAdapter extends DVHttpAIAdapter {
  static const String defaultModel = 'llama3.2';
  static const String defaultEmbeddingModel = 'nomic-embed-text';

  OllamaDVAIAdapter({
    super.apiKey = '',
    super.model = defaultModel,
    super.embeddingModel = defaultEmbeddingModel,
    super.maxOutputTokens = 4096,
    Uri? baseUrl,
    super.send = dvSendAIHttpRequest,
  }) : super(
          baseUrl: baseUrl ?? Uri.parse('http://localhost:11434'),
          transcriptionModel: '',
        );

  @override
  String get providerName => 'ollama';

  @override
  Map<String, String> get authHeaders => apiKey.isEmpty
      ? const <String, String>{}
      : <String, String>{'authorization': 'Bearer $apiKey'};

  @override
  Future<String> chat(String prompt, {String provider = 'gemini'}) async {
    final payload = await postJson(endpoint('/api/chat'), _chatBody(prompt));
    return readString(readMap(payload, 'message'), 'content');
  }

  @override
  Future<DVJsonObject> structuredOutput(
    String prompt,
    DVJsonObject schema,
  ) async {
    final payload = await postJson(
      endpoint('/api/chat'),
      <String, Object?>{
        ..._chatBody(prompt),
        'format': DVJsonCodec.toJsonObject(schema),
      },
    );
    return parseStructuredText(
      readString(readMap(payload, 'message'), 'content'),
    );
  }

  @override
  Future<List<double>> embed(String text) async {
    final payload = await postJson(
      endpoint('/api/embed'),
      <String, Object?>{'model': embeddingModel, 'input': text},
    );
    final embeddings = readList(payload, 'embeddings');
    if (embeddings.isEmpty) {
      malformed('"embeddings" was empty', jsonEncode(payload));
    }
    final first = embeddings.first;
    if (first is! List<Object?>) {
      malformed('"embeddings[0]" was not a JSON array', jsonEncode(payload));
    }
    return readDoubles(first, '"embeddings[0]"');
  }

  @override
  Future<DVAITranscript> transcribe(
    List<int> audioBytes, {
    String mimeType = 'audio/wav',
    String language = 'und',
  }) async =>
      unsupported('an audio transcription endpoint');

  Map<String, Object?> _chatBody(String prompt) => <String, Object?>{
        'model': model,
        'stream': false,
        'options': <String, Object?>{'num_predict': maxOutputTokens},
        'messages': <Object?>[
          <String, Object?>{'role': 'user', 'content': prompt},
        ],
      };
}
