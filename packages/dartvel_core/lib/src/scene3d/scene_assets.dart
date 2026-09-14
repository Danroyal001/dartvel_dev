/// Scene assets: which references may be fetched, and how a load ended.
///
/// Every check that can be made from the reference alone is made before any
/// request: a host nobody allowed, a storage key under another tenant, a key
/// that climbs out of its prefix, a stored or network asset with no digest,
/// a declared size over the ceiling. Then the bytes are checked against the
/// digest and, for a model, read by the glTF inspector. A load ends in one
/// typed state -- ready, refused, missing, digest mismatch, too large, corrupt
/// or failed -- so a renderer is never handed bytes nobody verified and a
/// viewport can say exactly why it shows a poster.
library dartvel.scene3d.assets;

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../compute/worker_types.dart';
import '../compute/workers.dart';
import '../storage/adapters.dart';
import '../tenancy/tenants.dart';
import 'gltf.dart';
import 'scene_document.dart';

/// Why an asset reference was refused before it was fetched.
final class DVSceneAssetRefusal {
  const DVSceneAssetRefusal(this.reason);

  final String reason;

  @override
  String toString() => 'DVSceneAssetRefusal: $reason';
}

/// What an application allows its scenes to load.
final class DVSceneAssetPolicy {
  const DVSceneAssetPolicy({
    this.allowedHosts = const <String>{},
    this.sharedStoragePrefixes = const <String>{},
    this.requireDigest = true,
    this.maxBytes,
  });

  /// Hosts a network asset may come from, matched exactly and without case.
  /// Empty allows no network assets at all.
  final Set<String> allowedHosts;

  /// Storage prefixes every tenant may read, such as a shared model library.
  ///
  /// Every other stored asset must sit under `tenants/<tenant>/`, the
  /// current tenant's own prefix. A storage adapter is one bucket for every
  /// tenant, so a key is the only thing standing between one tenant's scene
  /// and another tenant's upload.
  final Set<String> sharedStoragePrefixes;

  /// Whether a stored or network asset needs a SHA-256. A bundled asset never
  /// does: the build imported it and the bundle is signed as a whole.
  final bool requireDigest;

  /// The largest asset, in bytes, a scene may load.
  final int? maxBytes;

  static const String tenantPrefix = 'tenants/';

  /// The refusal for [asset] under [tenant], or null when it may be fetched.
  DVSceneAssetRefusal? check(DVSceneAsset asset, {required String tenant}) {
    final String ref = asset.reference;
    if (ref.isEmpty || ref.contains('\\') || ref.codeUnits.any((int c) => c < 0x20)) {
      return const DVSceneAssetRefusal(
          'the reference is empty or contains a backslash or control character');
    }
    final int? ceiling = maxBytes;
    if (ceiling != null && asset.byteLength != null && asset.byteLength! > ceiling) {
      return DVSceneAssetRefusal(
          'the asset declares ${asset.byteLength} bytes, over the $ceiling-byte ceiling');
    }
    switch (asset.source) {
      case DVSceneAssetSource.bundled:
        if (ref.contains(':') || ref.startsWith('/') || _climbs(ref)) {
          return DVSceneAssetRefusal(
              "'$ref' is not a relative bundle key");
        }
        return null;
      case DVSceneAssetSource.stored:
        if (ref.startsWith('/') || _climbs(ref)) {
          return DVSceneAssetRefusal("'$ref' climbs out of its storage prefix");
        }
        if (requireDigest && asset.sha256 == null) {
          return DVSceneAssetRefusal(
              "the stored asset '$ref' has no sha256, so its bytes cannot be verified");
        }
        if (ref.startsWith(tenantPrefix)) {
          final String owner = ref.substring(tenantPrefix.length).split('/').first;
          if (owner != tenant) {
            return DVSceneAssetRefusal(
                "'$ref' belongs to tenant '$owner', not to the current tenant '$tenant'");
          }
          return null;
        }
        if (sharedStoragePrefixes.any(ref.startsWith)) return null;
        return DVSceneAssetRefusal(
            "'$ref' is outside $tenantPrefix$tenant/ and no shared prefix covers it");
      case DVSceneAssetSource.network:
        final Uri? uri = Uri.tryParse(ref);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
          return DVSceneAssetRefusal("'$ref' is not an https URL");
        }
        if (uri.userInfo.isNotEmpty) {
          return DVSceneAssetRefusal("'$ref' carries credentials in the URL");
        }
        final String host = uri.host.toLowerCase();
        if (!allowedHosts.any((String h) => h.toLowerCase() == host)) {
          return DVSceneAssetRefusal(
              "the host '$host' is not in the scene asset policy's allowed hosts");
        }
        if (requireDigest && asset.sha256 == null) {
          return DVSceneAssetRefusal(
              "the network asset '$ref' has no sha256, so its bytes cannot be verified");
        }
        return null;
    }
  }

  static bool _climbs(String ref) =>
      ref.split('/').any((String segment) => segment == '..' || segment == '.');
}

/// Where a load is.
enum DVSceneAssetStatus { pending, loading, ready, failed }

/// How a load failed.
enum DVSceneAssetFailure {
  /// The policy refused the reference; nothing was requested.
  refused,

  /// Nothing is behind the reference.
  missing,

  /// The bytes are not the bytes the reference names.
  digestMismatch,

  /// The bytes are over the policy's ceiling.
  tooLarge,

  /// The bytes are not a model this runtime can read.
  corrupt,

  /// Anything else: no fetcher for the source, a network error, a worker
  /// that died.
  failed,
}

/// The state of one asset.
final class DVSceneAssetState {
  const DVSceneAssetState._(
    this.status, {
    this.bytes,
    this.model,
  })  : failure = null,
        reason = null;

  static const DVSceneAssetState pending =
      DVSceneAssetState._(DVSceneAssetStatus.pending);
  static const DVSceneAssetState loading =
      DVSceneAssetState._(DVSceneAssetStatus.loading);

  DVSceneAssetState.failed(DVSceneAssetFailure this.failure, String this.reason)
      : status = DVSceneAssetStatus.failed,
        bytes = null,
        model = null;

  /// A ready state, for renderer tests that do not go through a loader.
  DVSceneAssetState.debugReady(List<int> bytes, [this.model])
      : status = DVSceneAssetStatus.ready,
        failure = null,
        reason = null,
        bytes = Uint8List.fromList(bytes);

  final DVSceneAssetStatus status;
  final DVSceneAssetFailure? failure;
  final String? reason;

  /// The verified bytes, only when [status] is ready.
  final Uint8List? bytes;

  /// What the inspector found, for a model.
  final DVGltfSummary? model;

  bool get isReady => status == DVSceneAssetStatus.ready;

  @override
  String toString() => failure == null
      ? 'DVSceneAssetState(${status.name})'
      : 'DVSceneAssetState(${failure!.name}: $reason)';
}

/// One asset's state changing.
final class DVSceneAssetChange {
  const DVSceneAssetChange(this.key, this.state);

  final String key;
  final DVSceneAssetState state;
}

/// Fetches an asset's bytes, or null when nothing is there.
typedef DVSceneAssetFetch = Future<List<int>?> Function(DVSceneAsset asset);

/// Reads a model's bytes into a summary.
typedef DVSceneAssetDecode = Future<DVGltfSummary> Function(Uint8List bytes);

/// Loads scene assets under a policy.
final class DVSceneAssetLoader {
  DVSceneAssetLoader({
    this.policy = const DVSceneAssetPolicy(),
    required Map<DVSceneAssetSource, DVSceneAssetFetch> fetchers,
    String Function()? tenant,
    DVSceneAssetDecode? decode,
  })  : _fetchers = Map<DVSceneAssetSource, DVSceneAssetFetch>.of(fetchers),
        _tenant = tenant ?? (() => const DVTenants().currentTenant),
        _decode = decode ?? ((Uint8List bytes) async => DVGltf.inspect(bytes));

  final DVSceneAssetPolicy policy;
  final Map<DVSceneAssetSource, DVSceneAssetFetch> _fetchers;
  final String Function() _tenant;
  final DVSceneAssetDecode _decode;

  final Map<String, DVSceneAssetState> _states = <String, DVSceneAssetState>{};
  final Map<String, DVSceneAsset> _assets = <String, DVSceneAsset>{};
  final Map<String, _Flight> _inFlight = <String, _Flight>{};
  final StreamController<DVSceneAssetChange> _changes =
      StreamController<DVSceneAssetChange>.broadcast();

  Stream<DVSceneAssetChange> get changes => _changes.stream;

  DVSceneAssetState stateOf(String key) => _states[key] ?? DVSceneAssetState.pending;

  /// Decodes models on [workers], off the calling isolate.
  static DVSceneAssetDecode decodeOn(DVWorkers workers) =>
      (Uint8List bytes) async {
        final DVWorkerResult<Map<String, Object?>> result =
            await workers.run<Uint8List, Map<String, Object?>>(
          _inspectOnWorker,
          input: bytes,
        );
        if (!result.isCompleted) {
          throw StateError('the model could not be read on a worker: '
              '${result.outcome.name} ${result.error ?? ''}');
        }
        final Map<String, Object?> json = result.value;
        final Object? error = json['error'];
        if (error is String) throw DVGltfFormatException(error);
        return DVGltfSummary.fromJson(json);
      };

  /// Loads [asset] as [key]. A second call for the same key and asset shares
  /// the first load; a different asset under the key starts a new one.
  Future<DVSceneAssetState> load(String key, DVSceneAsset asset) async {
    // Everything up to the first await runs synchronously, so a second
    // caller in the same turn finds the first caller's load in flight.
    if (_assets[key] == asset) {
      final _Flight? running = _inFlight[key];
      if (running != null) return running.future;
      final DVSceneAssetState? known = _states[key];
      if (known != null) return known;
    }
    _assets[key] = asset;
    final _Flight flight = _Flight(_load(key, asset));
    _inFlight[key] = flight;
    try {
      return await flight.future;
    } finally {
      if (identical(_inFlight[key], flight)) _inFlight.remove(key);
    }
  }

  /// Forgets [key], so the next load fetches again.
  void forget(String key) {
    _states.remove(key);
    _assets.remove(key);
    _inFlight.remove(key);
  }

  void _set(String key, DVSceneAsset asset, DVSceneAssetState state) {
    // A load superseded by a newer asset under the same key does not report.
    if (_assets[key] != asset) return;
    _states[key] = state;
    _changes.add(DVSceneAssetChange(key, state));
  }

  Future<DVSceneAssetState> _load(String key, DVSceneAsset asset) async {
    _set(key, asset, DVSceneAssetState.loading);
    DVSceneAssetState end(DVSceneAssetState state) {
      _set(key, asset, state);
      return state;
    }

    final DVSceneAssetRefusal? refusal = policy.check(asset, tenant: _tenant());
    if (refusal != null) {
      return end(DVSceneAssetState.failed(DVSceneAssetFailure.refused, refusal.reason));
    }
    final DVSceneAssetFetch? fetch = _fetchers[asset.source];
    if (fetch == null) {
      return end(DVSceneAssetState.failed(DVSceneAssetFailure.failed,
          'no fetcher is configured for ${asset.source.name} assets'));
    }
    final List<int>? fetched;
    try {
      fetched = await fetch(asset);
    } on DVFileStorageException catch (error) {
      return end(error.isNotFound
          ? DVSceneAssetState.failed(
              DVSceneAssetFailure.missing, "nothing is stored at '${asset.reference}'")
          : DVSceneAssetState.failed(DVSceneAssetFailure.failed, error.toString()));
    } on Object catch (error) {
      return end(DVSceneAssetState.failed(DVSceneAssetFailure.failed, error.toString()));
    }
    if (fetched == null) {
      return end(DVSceneAssetState.failed(
          DVSceneAssetFailure.missing, "nothing is at '${asset.reference}'"));
    }
    final Uint8List bytes =
        fetched is Uint8List ? fetched : Uint8List.fromList(fetched);
    final int? ceiling = policy.maxBytes;
    if (ceiling != null && bytes.length > ceiling) {
      return end(DVSceneAssetState.failed(DVSceneAssetFailure.tooLarge,
          '${bytes.length} bytes is over the $ceiling-byte ceiling'));
    }
    if (asset.byteLength != null && asset.byteLength != bytes.length) {
      return end(DVSceneAssetState.failed(DVSceneAssetFailure.digestMismatch,
          'the reference declares ${asset.byteLength} bytes and ${bytes.length} arrived'));
    }
    if (asset.sha256 != null) {
      final String actual = crypto.sha256.convert(bytes).toString();
      if (actual != asset.sha256) {
        return end(DVSceneAssetState.failed(DVSceneAssetFailure.digestMismatch,
            'the bytes at \'${asset.reference}\' hash to $actual, not ${asset.sha256}'));
      }
    }
    DVGltfSummary? model;
    if (asset.kind == DVSceneAssetKind.model) {
      try {
        model = await _decode(bytes);
      } on DVGltfFormatException catch (error) {
        return end(DVSceneAssetState.failed(DVSceneAssetFailure.corrupt, error.reason));
      } on Object catch (error) {
        return end(DVSceneAssetState.failed(DVSceneAssetFailure.failed, error.toString()));
      }
    }
    return end(DVSceneAssetState._(DVSceneAssetStatus.ready, bytes: bytes, model: model));
  }
}

/// A load in progress. Held in a wrapper so removing it from the in-flight
/// table does not hand back a bare future nobody awaits.
final class _Flight {
  _Flight(this.future);

  final Future<DVSceneAssetState> future;
}

Map<String, Object?> _inspectOnWorker(Uint8List bytes, DVWorkerReporter reporter) {
  try {
    return DVGltf.inspect(bytes).toJson();
  } on DVGltfFormatException catch (error) {
    return <String, Object?>{'error': error.reason};
  }
}
