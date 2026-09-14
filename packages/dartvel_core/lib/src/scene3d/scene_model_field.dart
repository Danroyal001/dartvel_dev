/// What a `@DVModel.model3dField()` accepts, and the value it stores.
library dartvel.scene3d.model_field;

import 'package:crypto/crypto.dart' as crypto;

import 'gltf.dart';
import 'scene_document.dart';

/// Why an upload was refused.
enum DVModel3DProblemKind {
  /// Not a glTF 2.0 model this runtime can read.
  format,

  /// Over the field's size ceiling.
  size,

  /// Draws more triangles than the field's budget.
  triangles,
}

/// One reason an upload was refused.
final class DVModel3DProblem {
  const DVModel3DProblem(this.kind, this.message);

  final DVModel3DProblemKind kind;
  final String message;

  @override
  String toString() => '${kind.name}: $message';
}

/// The outcome of checking an upload against a field's policy.
final class DVModel3DValidation {
  const DVModel3DValidation._(this.problems, this.summary);

  final List<DVModel3DProblem> problems;

  /// What the model contains, when it could be read.
  final DVGltfSummary? summary;

  bool get isValid => problems.isEmpty;
}

/// Thrown by [DVModel3DFieldPolicy.accept] for an upload that is not valid.
final class DVModel3DRejected implements Exception {
  const DVModel3DRejected(this.validation);

  final DVModel3DValidation validation;

  @override
  String toString() =>
      'DVModel3DRejected: ${validation.problems.join('; ')}';
}

/// The upload limits of one 3D model field, as the generator writes them into
/// `Model.model3dFields`.
final class DVModel3DFieldPolicy {
  const DVModel3DFieldPolicy({
    this.poster = true,
    this.maxBytes,
    this.maxTriangles,
  });

  /// [maxSizeMb] mebibytes, the unit the annotation is written in.
  const DVModel3DFieldPolicy.megabytes(
    int maxSizeMb, {
    this.poster = true,
    this.maxTriangles,
  }) : maxBytes = maxSizeMb * 1024 * 1024;

  /// Whether the field asks for a still of the model for where 3D cannot
  /// render.
  final bool poster;
  final int? maxBytes;
  final int? maxTriangles;

  /// Checks [bytes]. Size first, without reading the file, so an oversized
  /// upload costs nothing to refuse.
  DVModel3DValidation validate(List<int> bytes) {
    final int? ceiling = maxBytes;
    if (ceiling != null && bytes.length > ceiling) {
      return DVModel3DValidation._(<DVModel3DProblem>[
        DVModel3DProblem(DVModel3DProblemKind.size,
            'the upload is ${bytes.length} bytes, over the $ceiling-byte limit'),
      ], null);
    }
    final DVGltfSummary summary;
    try {
      summary = DVGltf.inspect(bytes);
    } on DVGltfFormatException catch (error) {
      return DVModel3DValidation._(<DVModel3DProblem>[
        DVModel3DProblem(DVModel3DProblemKind.format, error.reason),
      ], null);
    }
    final int? budget = maxTriangles;
    return DVModel3DValidation._(<DVModel3DProblem>[
      if (budget != null && summary.triangles > budget)
        DVModel3DProblem(DVModel3DProblemKind.triangles,
            'the model draws ${summary.triangles} triangles, over the budget of $budget'),
    ], summary);
  }

  /// The field value for a valid upload stored at [storageKey], pinned to
  /// these exact bytes by their digest. Throws [DVModel3DRejected] otherwise.
  DVSceneAsset accept(List<int> bytes, {required String storageKey}) {
    if (storageKey.isEmpty) {
      throw ArgumentError.value(storageKey, 'storageKey', 'must not be empty');
    }
    final DVModel3DValidation validation = validate(bytes);
    if (!validation.isValid) throw DVModel3DRejected(validation);
    return DVSceneAsset(
      kind: DVSceneAssetKind.model,
      source: DVSceneAssetSource.stored,
      reference: storageKey,
      sha256: crypto.sha256.convert(bytes).toString(),
      byteLength: bytes.length,
      triangles: validation.summary!.triangles,
    );
  }
}
