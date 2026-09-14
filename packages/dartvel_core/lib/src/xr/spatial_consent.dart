/// Consent to keep environment data, read from the application's consent
/// records.
///
/// A world anchor token re-localizes a physical place -- often a room in
/// somebody's home -- so keeping one across launches is agreed to the way any
/// other use of personal data is: through a category the application declares
/// in its consent policy, answered by a person, recorded under the policy
/// version in force. An agreement given under an older version is not
/// agreement to this one, and a withdrawal reaches the tokens already kept,
/// not only the next one.
library dartvel.xr.consent;

import 'dart:async';

import '../analytics/consent.dart';
import '../observability/observability.dart';
import '../privacy/privacy.dart';
import 'spatial_session.dart';

/// [DVSpatialConsent] answered by [DVConsent].
///
/// Keeping a world anchor is agreed to while [category] is granted under the
/// policy version [consent] loaded, and at no other time. Sharing an anchor
/// with another device is never agreed to here: nothing sends one, and it is
/// not what a person agreeing to keep a place on their own device was asked.
///
/// Hand the runtime [anchors] rather than the store this was given. Every
/// token goes through it, so a write that arrives after a withdrawal is
/// refused at the store rather than landing behind the deletion.
final class DVConsentSpatialConsent implements DVSpatialConsent {
  DVConsentSpatialConsent(
    this.consent, {
    required this.category,
    required DVSpatialAnchorStore anchors,
  }) : _tokens = anchors {
    final DVConsentDeclaration? declared = consent.policy.declaration(category);
    if (declared == null) {
      throw ArgumentError.value(category.name, 'category',
          'is not declared in the consent policy ${consent.policy.version}');
    }
    if (declared.required || declared.defaultGranted) {
      // Either is a grant nobody gave. Refused here rather than honoured,
      // because the token it would let through maps somebody's room.
      throw ArgumentError.value(
        category.name,
        'category',
        'is ${declared.required ? 'required' : 'granted by default'}, so it '
            'would be granted without anybody being asked; declare the '
            'category that governs world anchors with default: denied',
      );
    }
    consent.addListener(_onChange);
  }

  /// The consent records this reads, for the install they belong to.
  final DVConsent consent;

  /// The declared category that governs keeping world anchors.
  final DVConsentCategory category;

  final DVSpatialAnchorStore _tokens;

  /// Reads, writes and deletions, one at a time, so a deletion never races a
  /// write it should have followed.
  Future<void> _queue = Future<void>.value();

  /// The anchor store to give the runtime: the one this was constructed with,
  /// refusing a write ([DVSpatialAnchorNotStored]) unless the agreement holds
  /// when the write runs, and deleting rather than returning a token that
  /// outlived its agreement.
  late final DVSpatialAnchorStore anchors = _DVConsentedAnchorStore(this);

  @override
  bool granted(DVSpatialDataUse use) =>
      use == DVSpatialDataUse.persistAnchors && consent.isGranted(category);

  /// Completes once every queued read, write and deletion has run --
  /// including the deletion a withdrawal starts.
  Future<void> get idle async {
    Future<void> seen;
    do {
      seen = _queue;
      await seen;
    } while (!identical(seen, _queue));
  }

  /// Deletes every kept token unless keeping them is agreed to now, and
  /// returns how many went.
  ///
  /// A withdrawal made while this runs is heard as it happens. One made
  /// before it -- in an earlier launch, or a grant that belongs to an older
  /// policy version -- is not a change anybody announces, so an application
  /// calls this once [DVConsent.load] has read the records.
  Future<int> enforce() => _serial(
      () async => granted(DVSpatialDataUse.persistAnchors) ? 0 : _eraseAll());

  /// The Data Compliance adapter for the tokens this governs.
  DVPrivacyAdapter privacyAdapter() => _DVSpatialAnchorPrivacyAdapter(this);

  /// Stops listening to [consent].
  void dispose() => consent.removeListener(_onChange);

  void _onChange(DVConsentChange change) {
    if (!change.withdrawn.contains(category)) return;
    unawaited(_serial(_eraseAll).then<void>(
      (int _) {},
      onError: (Object error) => DVObservability.log(
        'consent to keep world anchors was withdrawn and their tokens could '
        'not all be deleted; they are deleted when next read or enforced',
        level: DVLogLevel.error,
        context: <String, Object?>{
          'category': category.name,
          'error': error.runtimeType.toString(),
        },
      ),
    ));
  }

  Future<T> _serial<T>(Future<T> Function() op) {
    final Future<T> result = _queue.then((_) => op());
    _queue = result.then<void>((T _) {}, onError: (Object _) {});
    return result;
  }

  Future<int> _eraseAll() async {
    final List<String> ids = await _tokens.ids();
    for (final String id in ids) {
      await _tokens.remove(id);
    }
    return ids.length;
  }
}

final class _DVConsentedAnchorStore implements DVSpatialAnchorStore {
  _DVConsentedAnchorStore(this._owner);

  final DVConsentSpatialConsent _owner;

  bool get _agreed => _owner.granted(DVSpatialDataUse.persistAnchors);

  @override
  Future<String?> read(String id) => _owner._serial(() async {
        final String? token = await _owner._tokens.read(id);
        if (token == null || _agreed) return token;
        // Kept under an agreement that no longer holds: it goes, rather than
        // being handed to a session that would re-localize the place with it.
        await _owner._tokens.remove(id);
        return null;
      });

  @override
  Future<void> write(String id, String token) => _owner._serial(() async {
        if (!_agreed) {
          throw DVSpatialAnchorNotStored(
            id,
            'keeping world anchors is not agreed to: consent category '
            '"${_owner.category.name}" is not granted under policy '
            '${_owner.consent.policy.version}',
          );
        }
        await _owner._tokens.write(id, token);
      });

  @override
  Future<void> remove(String id) => _owner._serial(() => _owner._tokens.remove(id));

  @override
  Future<List<String>> ids() => _owner._serial(_owner._tokens.ids);
}

/// Erases and exports the world anchor tokens kept on this install.
///
/// The tokens carry no user id: they belong to the install, as the consent
/// that let them be kept does. A subject is tied to them when it is the
/// install, or a user this install's consent records name. Product
/// Analytics' consent adapter keeps those records under the pseudonym, so it
/// may already have replaced both ids when this runs; records under the
/// subject's pseudonym tie the subject too. On a device the consent records
/// are the install's own, which is what makes that sound -- an adapter reading
/// a consent database shared by many installs would erase this install's
/// tokens for a subject erased on another.
final class _DVSpatialAnchorPrivacyAdapter implements DVPrivacyAdapter {
  _DVSpatialAnchorPrivacyAdapter(this._owner);

  final DVConsentSpatialConsent _owner;

  @override
  String get name => 'xr:anchors';

  Future<bool> _tied(DVPrivacySubjectRef subject) async {
    final String id = '${subject.id}';
    final DVConsent consent = _owner.consent;
    if (id == consent.installId) return true;
    for (final DVConsentRecord r in await consent.records()) {
      if (r.userId == id) return true;
    }
    return (await consent.records(subject: subject.pseudonym)).isNotEmpty;
  }

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async {
    if (!await _tied(subject)) return;
    await _owner._serial(_owner._eraseAll);
  }

  /// The anchors kept, by id, and never their tokens.
  ///
  /// A token is the OS's opaque handle and reads as nothing to a person; what
  /// it can do is re-localize the place for whoever holds it, which an export
  /// archive carried off the device must not be able to. The ids say what is
  /// kept.
  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      <String, Object?>{
        'anchors': await _tied(subject)
            ? ((await _owner._serial(_owner._tokens.ids)).toList()..sort())
            : const <String>[],
      };
}
