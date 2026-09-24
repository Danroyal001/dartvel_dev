/// The one route that takes writes a device made while nobody was watching.
///
/// Everything about the request is somebody else's input: the model it
/// names, the key, the values, how many of them there are. The generated
/// backend authenticates the route like every other, and the model's own
/// policy decides each mutation through the remote's `authorize`. This is
/// what runs before either, and it decides whether the request is a request
/// at all.
///
/// Not in the barrel an application imports. An application declares
/// `@DVModel(offline:)` and the generated backend serves this; nothing else
/// should be able to hand a table a write from outside.
library;

import 'offline_store.dart';

/// What the route answers.
///
/// Status and message are chosen here, and nothing from the request is ever
/// in the message: an error that echoes its input is how a probe learns what
/// exists.
class DVOfflineReplayResult {
  const DVOfflineReplayResult(this.status, this.message,
      {this.body = const <String, Object?>{}});

  final int status;
  final String message;
  final Map<String, Object?> body;
}

/// Applies a batch of replayed mutations to the models that declared they
/// work offline, and to no others.
class DVOfflineReplay {
  const DVOfflineReplay(this.remotes);

  /// By model name, as the generator wrote it. A name that is not a key here
  /// is a model nobody declared offline, and is refused: a registry that fell
  /// back to looking the table up would be an arbitrary-table write
  /// primitive reachable by anybody with a session.
  final Map<String, DVOfflineRemote> remotes;

  /// The most mutations one request may carry.
  ///
  /// A queue that has been filling for a week is replayed in batches, so the
  /// bound is generous; what it stops is a single request holding a
  /// connection and somebody else's database open for as long as the sender
  /// likes.
  static const int maxMutations = 500;

  Future<DVOfflineReplayResult> handle(Object? body) async {
    if (body is! Map<Object?, Object?>) {
      return const DVOfflineReplayResult(400, 'not a replay request');
    }
    final Object? model = body['model'];
    final Object? mutations = body['mutations'];
    if (model is! String || model.isEmpty || mutations is! List<Object?>) {
      return const DVOfflineReplayResult(400, 'not a replay request');
    }
    if (mutations.length > maxMutations) {
      return const DVOfflineReplayResult(413, 'too many mutations at once');
    }

    final DVOfflineRemote? remote = remotes[model];
    if (remote == null) {
      // The same answer for a model that does not exist and one that exists
      // and is not offline. Telling them apart is telling a caller what this
      // application is made of.
      return const DVOfflineReplayResult(404, 'no such offline model');
    }

    // Decoded before any of it is applied, so a batch with one bad mutation
    // in the middle does not leave the ones before it written and the ones
    // after it not.
    final List<DVMutation> decoded = <DVMutation>[];
    for (final Object? entry in mutations) {
      final DVMutation? mutation = _decode(entry);
      if (mutation == null) {
        return const DVOfflineReplayResult(400, 'not a replay request');
      }
      decoded.add(mutation);
    }

    final List<Object?> outcomes = <Object?>[];
    for (final DVMutation mutation in decoded) {
      final DVRemoteOutcome outcome = await remote.apply(mutation);
      outcomes.add(<String, Object?>{
        'mutationId': mutation.mutationId,
        ...dvOutcomeToJson(outcome, sensitive: remote.sensitiveColumns),
      });
    }
    return DVOfflineReplayResult(200, 'applied',
        body: <String, Object?>{'outcomes': outcomes});
  }

  /// A mutation, or null when what arrived is not one.
  ///
  /// The key must be a scalar. A map or a list would reach the table as
  /// whatever it interpolates to -- a key nobody meant, and one no other
  /// writer will ever match, so the row it makes is invisible to everything
  /// except the device that sent it.
  static DVMutation? _decode(Object? entry) {
    if (entry is! Map<Object?, Object?>) return null;
    final Object? key = entry['key'];
    if (key is! String && key is! num) return null;
    final Object? op = entry['op'];
    if (op != DVMutation.opWrite && op != DVMutation.opDelete) return null;
    try {
      return DVMutation.fromJson(
        entry.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
      );
    } catch (_) {
      // Malformed is refused, not thrown at: a 500 here would report the
      // server as broken for a request that was never well formed.
      return null;
    }
  }
}
