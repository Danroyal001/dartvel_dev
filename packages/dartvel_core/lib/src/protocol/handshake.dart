/// The handshake: a client states the protocol it speaks on every request,
/// and the backend decides what it serves.
///
/// It rides the existing request as a header rather than a second transport
/// or envelope, and the client never pins a version: it says what it is.
library dartvel_core.protocol.handshake;

import 'dart:collection';

import '../lifecycle/lifecycle.dart';
import 'compatibility.dart';

/// What the backend decided for one request.
class DVProtocolDecision {
  const DVProtocolDecision._({
    required this.server,
    this.client,
    this.result,
    this.adapter,
  });

  /// The backend's protocol version.
  final int server;

  /// The version the client stated, or null when it stated none.
  final int? client;

  /// Null only when the client is ahead of the backend; see [backendBehind].
  final DVProtocolResult? result;

  /// The adapters a degraded client's responses go through.
  final DVProtocolAdapterSet? adapter;

  /// The caller stated no protocol: a raw route, a webhook consumer, curl.
  /// Passed through, because refusing it would turn every non-generated caller
  /// into an upgrade prompt -- and marked, so it is not mistaken for a client
  /// that was checked.
  bool get unversioned => client == null;

  /// The client speaks a protocol newer than this backend: an instance that
  /// has not rolled forward yet. Upgrading the client would not help, so it
  /// is never told to.
  bool get backendBehind => client != null && result == null;

  /// The status to refuse the request with, or null to serve it: `426 Upgrade
  /// Required` outside the window, `503` when this backend is behind the
  /// client and another instance may not be.
  int? get refusalStatus => result == DVProtocolResult.upgradeRequired
      ? 426
      : backendBehind
      ? 503
      : null;
}

/// The backend half.
class DVProtocolServer {
  DVProtocolServer({
    required this.plan,
    this.sessionMemory = 10000,
    void Function(String code, String message)? onDiagnostic,
  }) : _diagnose = onDiagnostic ?? dvLogProtocolDiagnostic;

  /// The request header a client states its protocol in.
  static const String header = 'x-dartvel-protocol';

  /// The response header a backend states its decision in.
  static const String resultHeader = 'x-dartvel-protocol-result';

  final DVProtocolPlan plan;

  /// How many sessions `DV-PROTO-002` remembers having reported. Bounded, so
  /// a flood of stale clients costs a fixed amount of memory.
  final int sessionMemory;

  final void Function(String code, String message) _diagnose;
  final LinkedHashSet<String> _reported = LinkedHashSet<String>();

  /// Decides what a request carrying [header] is served.
  ///
  /// [session] scopes `DV-PROTO-002`, which the specification reports once per
  /// session. A request with no session is scoped to its protocol version, so
  /// a stale client without one is still not reported on every call.
  ///
  /// Throws [FormatException] for a header that is present but not a protocol
  /// version: that is a broken client, not an unversioned one.
  DVProtocolDecision decide(String? header, {String? session}) {
    final int? client = _parse(header);
    if (client == null) {
      return DVProtocolDecision._(
        server: plan.current,
        result: DVProtocolResult.compatible,
      );
    }
    final DVProtocolResult? result = plan.resultFor(client);
    if (result == DVProtocolResult.upgradeRequired &&
        _reported.add(session ?? 'protocol:$client')) {
      while (_reported.length > sessionMemory) {
        _reported.remove(_reported.first);
      }
      _diagnose(
        'DV-PROTO-002',
        'a client outside the window called; upgrade required: protocol '
            '$client called a backend on protocol ${plan.current}',
      );
    }
    return DVProtocolDecision._(
      server: plan.current,
      client: client,
      result: result,
      adapter: result == DVProtocolResult.degraded
          ? plan.adapterFor(client)
          : null,
    );
  }

  /// The body a handshake request is answered with.
  Map<String, Object?> handshake(String? header, {String? session}) {
    final DVProtocolDecision decision = decide(header, session: session);
    return <String, Object?>{
      'protocol': decision.server,
      if (decision.client != null) 'client': decision.client,
      if (decision.backendBehind)
        'backendBehind': true
      else
        'result': decision.result!.name,
    };
  }

  static int? _parse(String? header) {
    if (header == null) return null;
    final String value = header.trim();
    if (!RegExp(r'^\d{1,9}$').hasMatch(value)) {
      throw FormatException(
        '${DVProtocolServer.header} must be a protocol version, got "$header"',
      );
    }
    return int.parse(value);
  }
}

/// The client is on a newer protocol than the backend that answered.
class DVProtocolBackendBehind implements Exception {
  const DVProtocolBackendBehind(this.server, this.client);

  final int server;
  final int client;

  @override
  String toString() =>
      'DVProtocolBackendBehind: the backend is on protocol '
      '$server and this client is on $client';
}

/// The client half.
///
/// [fetch] sends the handshake request with the given headers over the
/// generated client's existing transport and returns the decoded body.
class DVProtocolClient {
  DVProtocolClient({
    required this.protocol,
    required Future<Map<String, Object?>> Function(Map<String, String> headers)
    fetch,
  }) : _fetch = fetch;

  /// The protocol version this build embeds.
  final int protocol;

  final Future<Map<String, Object?>> Function(Map<String, String> headers)
  _fetch;
  final DVMutableLifecycleSignal<DVProtocolResult?> _state =
      DVMutableLifecycleSignal<DVProtocolResult?>(null);
  Future<DVProtocolResult>? _handshake;

  /// The latest result, null until a handshake has answered. A signal, so a
  /// page can show what it means rather than discovering it through a failure;
  /// read-only, because the backend decides it.
  DVLifecycleSignal<DVProtocolResult?> get state => _state;

  /// The headers every request carries.
  Map<String, String> get headers => <String, String>{
    DVProtocolServer.header: '$protocol',
  };

  /// This build's protocol, as `DVCrashContext.protocolVersion` records it.
  String get protocolVersion => '$protocol';

  /// Runs the handshake once. Calls that arrive while it is in flight wait on
  /// the same request, and a handshake that fails is forgotten so the next
  /// call tries again -- an offline launch must not be remembered as a
  /// verdict.
  Future<DVProtocolResult> handshake() => _handshake ??= _run().then(
    (DVProtocolResult result) => result,
    onError: (Object error, StackTrace stack) {
      _handshake = null;
      Error.throwWithStackTrace(error, stack);
    },
  );

  Future<DVProtocolResult> _run() async {
    final Map<String, Object?> body = await _fetch(headers);
    final Object? server = body['protocol'];
    if (server is! int) {
      throw FormatException('handshake answered without a protocol: $body');
    }
    if (body['backendBehind'] == true) {
      throw DVProtocolBackendBehind(server, protocol);
    }
    final DVProtocolResult? result = _result(body['result']);
    if (result == null) {
      throw FormatException(
        'handshake answered with a result this client does not know: '
        '${body['result']}',
      );
    }
    _state.set(result);
    return result;
  }

  /// Takes what a later response says about the protocol: a `426` means the
  /// window has moved past this client since the handshake, and a result
  /// header is the backend's current decision.
  void observe(int status, Map<String, String> headers) {
    if (status == 426) {
      _state.set(DVProtocolResult.upgradeRequired);
      return;
    }
    String? stated;
    headers.forEach((String key, String value) {
      if (key.toLowerCase() == DVProtocolServer.resultHeader) stated = value;
    });
    final DVProtocolResult? result = _result(stated);
    if (result != null) _state.set(result);
  }

  static DVProtocolResult? _result(Object? name) {
    for (final DVProtocolResult r in DVProtocolResult.values) {
      if (r.name == name) return r;
    }
    return null;
  }
}
