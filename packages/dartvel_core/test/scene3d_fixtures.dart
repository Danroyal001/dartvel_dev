// Builds glTF binaries for the scene tests, so a fixture says in code what
// it contains instead of being an opaque file in the repository.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// A GLB container around [json] and an optional [bin] chunk.
Uint8List glb(
  Map<String, Object?> json, {
  List<int> bin = const <int>[],
  int version = 2,
  int? declaredLength,
  int magic = 0x46546C67,
}) {
  List<int> pad(List<int> bytes, int filler) => <int>[
        ...bytes,
        for (int i = 0; i < (4 - bytes.length % 4) % 4; i++) filler,
      ];
  final List<int> jsonChunk = pad(utf8.encode(jsonEncode(json)), 0x20);
  final List<int> binChunk = bin.isEmpty ? const <int>[] : pad(bin, 0);
  final int length = 12 +
      8 +
      jsonChunk.length +
      (binChunk.isEmpty ? 0 : 8 + binChunk.length);
  final ByteData header = ByteData(12)
    ..setUint32(0, magic, Endian.little)
    ..setUint32(4, version, Endian.little)
    ..setUint32(8, declaredLength ?? length, Endian.little);
  ByteData chunkHeader(int size, int type) => ByteData(8)
    ..setUint32(0, size, Endian.little)
    ..setUint32(4, type, Endian.little);
  return Uint8List.fromList(<int>[
    ...header.buffer.asUint8List(),
    ...chunkHeader(jsonChunk.length, 0x4E4F534A).buffer.asUint8List(),
    ...jsonChunk,
    if (binChunk.isNotEmpty) ...<int>[
      ...chunkHeader(binChunk.length, 0x004E4942).buffer.asUint8List(),
      ...binChunk,
    ],
  ]);
}

/// A model with a body (12 triangles, indexed), a wheel under it (3
/// triangles), a strip (4 triangles), a line primitive (none) and a mesh no
/// node uses.
Map<String, Object?> kartGltf() => <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'scene': 0,
      'scenes': <Object?>[
        <String, Object?>{
          'nodes': <int>[0],
        },
      ],
      'nodes': <Object?>[
        <String, Object?>{
          'name': 'body',
          'mesh': 0,
          'translation': <double>[0, 1, 0],
          'children': <int>[1],
        },
        <String, Object?>{
          'name': 'wheel',
          'mesh': 1,
          'translation': <double>[3, 0, 0],
          'scale': <double>[2, 2, 2],
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 0},
              'indices': 1,
            },
          ],
        },
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 2},
            },
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 3},
              'mode': 5,
            },
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 3},
              'mode': 1,
            },
          ],
        },
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 2},
            },
          ],
        },
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'count': 8,
          'type': 'VEC3',
          'componentType': 5126,
          'min': <double>[-1, -1, -1],
          'max': <double>[1, 1, 1],
        },
        <String, Object?>{'count': 36, 'type': 'SCALAR', 'componentType': 5123},
        <String, Object?>{
          'count': 9,
          'type': 'VEC3',
          'componentType': 5126,
          'min': <double>[0, 0, 0],
          'max': <double>[1, 1, 1],
        },
        <String, Object?>{
          'count': 6,
          'type': 'VEC3',
          'componentType': 5126,
          'min': <double>[0, 0, 0],
          'max': <double>[1, 1, 1],
        },
      ],
      'materials': <Object?>[
        <String, Object?>{'name': 'paint'},
      ],
      'animations': <Object?>[
        <String, Object?>{'name': 'steamLoop', 'channels': <Object?>[], 'samplers': <Object?>[]},
      ],
    };

String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();
