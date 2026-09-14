/// Reads what a glTF 2.0 model contains without decoding its geometry.
///
/// Everything an upload is validated against and a scene graph picks by is in
/// the JSON: accessor counts give triangles, POSITION accessors carry their
/// bounds, nodes carry their transforms. So a model can be checked on a
/// server, in the CLI or on a worker with no GPU and no buffer decoding.
library dartvel.scene3d.gltf;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'scene_math.dart';

/// Thrown when bytes are not a glTF 2.0 model this inspector can read.
final class DVGltfFormatException implements Exception {
  const DVGltfFormatException(this.reason);

  final String reason;

  @override
  String toString() => 'DVGltfFormatException: $reason';
}

/// What a model contains.
final class DVGltfSummary {
  const DVGltfSummary({
    required this.triangles,
    required this.bounds,
    required this.nodeNames,
    required this.animations,
    required this.meshes,
    required this.materials,
    required this.isBinary,
    required this.byteLength,
  });

  /// Triangles the default scene draws: each mesh counted once per node that
  /// uses it, strips and fans as the triangles they make, points and lines
  /// as none.
  final int triangles;

  /// The default scene's bounds in the model's own space, or null when it
  /// draws nothing.
  final DVAabb? bounds;

  /// Names of the named nodes, in file order.
  final List<String> nodeNames;

  /// Animation names, in file order; an unnamed one is `animation<index>`.
  final List<String> animations;
  final int meshes;
  final int materials;

  /// Whether this was a GLB container rather than a `.gltf` JSON file.
  final bool isBinary;
  final int byteLength;

  Map<String, Object?> toJson() => <String, Object?>{
        'triangles': triangles,
        'bounds': bounds == null
            ? null
            : <String, Object?>{
                'min': bounds!.min.toList(),
                'max': bounds!.max.toList(),
              },
        'nodeNames': nodeNames,
        'animations': animations,
        'meshes': meshes,
        'materials': materials,
        'isBinary': isBinary,
        'byteLength': byteLength,
      };

  factory DVGltfSummary.fromJson(Map<String, Object?> json) {
    DVVec3 vec(Object? v) {
      final List<Object?> l = v! as List<Object?>;
      return DVVec3((l[0]! as num).toDouble(), (l[1]! as num).toDouble(),
          (l[2]! as num).toDouble());
    }

    final Map<String, Object?>? b = (json['bounds'] as Map?)?.cast<String, Object?>();
    return DVGltfSummary(
      triangles: json['triangles']! as int,
      bounds: b == null ? null : DVAabb(vec(b['min']), vec(b['max'])),
      nodeNames: (json['nodeNames']! as List<Object?>).cast<String>(),
      animations: (json['animations']! as List<Object?>).cast<String>(),
      meshes: json['meshes']! as int,
      materials: json['materials']! as int,
      isBinary: json['isBinary']! as bool,
      byteLength: json['byteLength']! as int,
    );
  }
}

/// The glTF inspector.
abstract final class DVGltf {
  static const int _glbMagic = 0x46546C67;
  static const int _chunkJson = 0x4E4F534A;
  static const int _chunkBin = 0x004E4942;

  /// A cap on node visits, so a file whose nodes share children many times
  /// over cannot make an import job run for hours.
  static const int maxNodeVisits = 1000000;

  /// Summarises [bytes], a GLB container or a `.gltf` JSON file.
  static DVGltfSummary inspect(List<int> bytes) {
    final Uint8List data =
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final ByteData view = ByteData.sublistView(data);
    final bool binary =
        data.length >= 4 && view.getUint32(0, Endian.little) == _glbMagic;
    final Map<String, Object?> json =
        binary ? _readGlb(data, view) : _readJsonFile(data);
    return _summarise(json, binary: binary, byteLength: data.length);
  }

  static Map<String, Object?> _readGlb(Uint8List data, ByteData view) {
    if (data.length < 20) {
      throw const DVGltfFormatException(
          'a GLB is at least 20 bytes; the file is shorter than its header');
    }
    final int version = view.getUint32(4, Endian.little);
    if (version != 2) {
      throw DVGltfFormatException(
          'GLB container version $version; only version 2 is read');
    }
    final int declared = view.getUint32(8, Endian.little);
    if (declared != data.length) {
      throw DVGltfFormatException(
          'the header declares a length of $declared bytes but the file is '
          '${data.length} bytes');
    }
    final int jsonLength = view.getUint32(12, Endian.little);
    if (view.getUint32(16, Endian.little) != _chunkJson) {
      throw const DVGltfFormatException('the first GLB chunk is not JSON');
    }
    if (20 + jsonLength > data.length) {
      throw const DVGltfFormatException(
          'the JSON chunk runs past the declared length');
    }
    int offset = 20 + jsonLength;
    while (offset < data.length) {
      if (offset + 8 > data.length) {
        throw const DVGltfFormatException(
            'a chunk header runs past the declared length');
      }
      final int chunkLength = view.getUint32(offset, Endian.little);
      final int type = view.getUint32(offset + 4, Endian.little);
      if (offset + 8 + chunkLength > data.length) {
        throw DVGltfFormatException(
            'a ${type == _chunkBin ? 'BIN' : 'chunk'} runs past the declared length');
      }
      offset += 8 + chunkLength;
    }
    return _decodeJson(Uint8List.sublistView(data, 20, 20 + jsonLength));
  }

  static Map<String, Object?> _readJsonFile(Uint8List data) {
    int first = 0;
    while (first < data.length &&
        (data[first] == 0x20 || data[first] == 0x0A || data[first] == 0x0D ||
            data[first] == 0x09 || data[first] == 0xEF || data[first] == 0xBB ||
            data[first] == 0xBF)) {
      first++;
    }
    if (first >= data.length || data[first] != 0x7B) {
      throw const DVGltfFormatException('not a glTF or GLB file');
    }
    return _decodeJson(data);
  }

  static Map<String, Object?> _decodeJson(Uint8List bytes) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) return decoded;
    } on FormatException {
      // Reported below.
    }
    throw const DVGltfFormatException('not a glTF file: its JSON does not parse');
  }

  static DVGltfSummary _summarise(
    Map<String, Object?> json, {
    required bool binary,
    required int byteLength,
  }) {
    final Object? asset = json['asset'];
    final Object? version = asset is Map ? asset['version'] : null;
    if (version is! String || !version.startsWith('2.')) {
      throw DVGltfFormatException(
          'asset.version must be 2.x, not ${jsonEncode(version)}');
    }
    final List<Object?> nodes = _list(json, 'nodes');
    final List<Object?> meshes = _list(json, 'meshes');
    final List<Object?> accessors = _list(json, 'accessors');
    final List<Object?> scenes = _list(json, 'scenes');

    Map<String, Object?> accessor(Object? index, String what) {
      if (index is! int || index < 0 || index >= accessors.length) {
        throw DVGltfFormatException(
            '$what refers to accessor $index, which does not exist');
      }
      final Object? a = accessors[index];
      if (a is! Map<String, Object?> || a['count'] is! int || (a['count']! as int) < 0) {
        throw DVGltfFormatException('accessor $index has no valid count');
      }
      return a;
    }

    DVVec3 vec(Object? value, String what) {
      if (value is List && value.length >= 3 && value.take(3).every((Object? v) => v is num && v.isFinite)) {
        return DVVec3((value[0] as num).toDouble(), (value[1] as num).toDouble(),
            (value[2] as num).toDouble());
      }
      throw DVGltfFormatException('$what must be three finite numbers');
    }

    final List<int> meshTriangles = <int>[];
    final List<DVAabb?> meshBounds = <DVAabb?>[];
    for (int m = 0; m < meshes.length; m++) {
      final Object? mesh = meshes[m];
      final Object? primitives = mesh is Map ? mesh['primitives'] : null;
      if (primitives is! List || primitives.isEmpty) {
        throw DVGltfFormatException('mesh $m has no primitives');
      }
      int triangles = 0;
      DVAabb? bounds;
      for (int p = 0; p < primitives.length; p++) {
        final Object? primitive = primitives[p];
        if (primitive is! Map) {
          throw DVGltfFormatException('mesh $m primitive $p is not an object');
        }
        final Object? attributes = primitive['attributes'];
        if (attributes is! Map || attributes['POSITION'] == null) {
          throw DVGltfFormatException(
              'mesh $m primitive $p has no POSITION attribute');
        }
        final Object? mode = primitive['mode'] ?? 4;
        if (mode is! int || mode < 0 || mode > 6) {
          throw DVGltfFormatException('mesh $m primitive $p has mode $mode');
        }
        final Map<String, Object?> position =
            accessor(attributes['POSITION'], 'mesh $m primitive $p POSITION');
        final Object? indices = primitive['indices'];
        final int count = indices == null
            ? position['count']! as int
            : accessor(indices, 'mesh $m primitive $p indices')['count']! as int;
        triangles += switch (mode) {
          4 => count ~/ 3,
          5 || 6 => math.max(0, count - 2),
          _ => 0,
        };
        final int positionIndex = attributes['POSITION'] as int;
        if (position['min'] == null || position['max'] == null) {
          throw DVGltfFormatException(
              'accessor $positionIndex (POSITION) must declare min and max');
        }
        final DVAabb box = DVAabb(
          vec(position['min'], 'accessor $positionIndex min'),
          vec(position['max'], 'accessor $positionIndex max'),
        );
        bounds = bounds == null ? box : bounds.union(box);
      }
      meshTriangles.add(triangles);
      meshBounds.add(bounds);
    }

    DVMat4 localMatrix(int n, Map<String, Object?> node) {
      final Object? matrix = node['matrix'];
      if (matrix != null) {
        if (matrix is! List || matrix.length != 16 ||
            !matrix.every((Object? v) => v is num && v.isFinite)) {
          throw DVGltfFormatException('node $n matrix must be 16 finite numbers');
        }
        return DVMat4.fromList(<double>[
          for (final Object? v in matrix) (v! as num).toDouble(),
        ]);
      }
      final Object? r = node['rotation'];
      DVQuat rotation = DVQuat.identity;
      if (r != null) {
        if (r is! List || r.length != 4 || !r.every((Object? v) => v is num && v.isFinite)) {
          throw DVGltfFormatException('node $n rotation must be four finite numbers');
        }
        rotation = DVQuat((r[0] as num).toDouble(), (r[1] as num).toDouble(),
            (r[2] as num).toDouble(), (r[3] as num).toDouble());
      }
      return DVMat4.compose(
        node['translation'] == null
            ? DVVec3.zero
            : vec(node['translation'], 'node $n translation'),
        rotation,
        node['scale'] == null ? DVVec3.one : vec(node['scale'], 'node $n scale'),
      );
    }

    final Set<int> childIndices = <int>{};
    for (int n = 0; n < nodes.length; n++) {
      final Object? node = nodes[n];
      if (node is! Map<String, Object?>) {
        throw DVGltfFormatException('node $n is not an object');
      }
      final Object? mesh = node['mesh'];
      if (mesh != null && (mesh is! int || mesh < 0 || mesh >= meshes.length)) {
        throw DVGltfFormatException(
            'node $n refers to mesh $mesh, which does not exist');
      }
      final Object? children = node['children'];
      if (children != null) {
        if (children is! List) {
          throw DVGltfFormatException('node $n children must be a list');
        }
        for (final Object? child in children) {
          if (child is! int || child < 0 || child >= nodes.length) {
            throw DVGltfFormatException(
                'node $n refers to child node $child, which does not exist');
          }
          childIndices.add(child);
        }
      }
    }

    List<int> roots;
    if (scenes.isNotEmpty) {
      final Object? sceneIndex = json['scene'] ?? 0;
      if (sceneIndex is! int || sceneIndex < 0 || sceneIndex >= scenes.length) {
        throw DVGltfFormatException('scene $sceneIndex does not exist');
      }
      final Object? scene = scenes[sceneIndex];
      final Object? sceneNodes = scene is Map ? scene['nodes'] : null;
      roots = <int>[
        for (final Object? n in (sceneNodes as List?) ?? const <Object?>[])
          if (n is int && n >= 0 && n < nodes.length)
            n
          else
            throw DVGltfFormatException(
                'scene $sceneIndex refers to node $n, which does not exist'),
      ];
    } else {
      roots = <int>[
        for (int n = 0; n < nodes.length; n++)
          if (!childIndices.contains(n)) n,
      ];
    }

    int triangles = 0;
    int visits = 0;
    DVAabb? bounds;
    final Set<int> onPath = <int>{};
    void visit(int n, DVMat4 parent) {
      if (!onPath.add(n)) {
        throw DVGltfFormatException('the node hierarchy has a cycle at node $n');
      }
      if (++visits > maxNodeVisits) {
        throw const DVGltfFormatException(
            'the node hierarchy expands to more than $maxNodeVisits nodes');
      }
      final Map<String, Object?> node = nodes[n]! as Map<String, Object?>;
      final DVMat4 world = parent * localMatrix(n, node);
      final Object? mesh = node['mesh'];
      if (mesh is int) {
        triangles += meshTriangles[mesh];
        final DVAabb? local = meshBounds[mesh];
        if (local != null) {
          final DVAabb placed = local.transformed(world);
          bounds = bounds == null ? placed : bounds!.union(placed);
        }
      }
      for (final Object? child in (node['children'] as List?) ?? const <Object?>[]) {
        visit(child! as int, world);
      }
      onPath.remove(n);
    }

    for (final int root in roots) {
      visit(root, DVMat4.identity());
    }

    final List<Object?> animations = _list(json, 'animations');
    return DVGltfSummary(
      triangles: triangles,
      bounds: bounds,
      nodeNames: <String>[
        for (final Object? node in nodes)
          if (node is Map && node['name'] is String) node['name'] as String,
      ],
      animations: <String>[
        for (int i = 0; i < animations.length; i++)
          (animations[i] is Map && (animations[i]! as Map)['name'] is String)
              ? (animations[i]! as Map)['name'] as String
              : 'animation$i',
      ],
      meshes: meshes.length,
      materials: _list(json, 'materials').length,
      isBinary: binary,
      byteLength: byteLength,
    );
  }

  static List<Object?> _list(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) return const <Object?>[];
    if (value is List<Object?>) return value;
    throw DVGltfFormatException('$key must be a list');
  }
}
