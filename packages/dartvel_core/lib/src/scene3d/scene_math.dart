/// The vector, quaternion and matrix types a scene is described in.
///
/// One convention, stated once, because a scene that is right-handed in one
/// file and left-handed in the next renders mirrored with no error: world
/// space is **right-handed, Y up, in metres**, and matrices are column-major,
/// the layout the engine and glTF both use. A document written in another
/// convention says so (see `DV3DSceneDocument.units`, `.upAxis`,
/// `.handedness`) and the scene graph converts it at the root.
///
/// These are small immutable values rather than a dependency on a vector
/// package: the scene document is read by the CLI and the server as well as
/// the application, and none of them should acquire a math library to parse
/// a JSON file.
library dartvel.scene3d.math;

import 'dart:math' as math;
import 'dart:typed_data';

/// A point or a direction in three dimensions.
final class DVVec3 {
  const DVVec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const DVVec3 zero = DVVec3(0, 0, 0);
  static const DVVec3 one = DVVec3(1, 1, 1);
  static const DVVec3 up = DVVec3(0, 1, 0);

  DVVec3 operator +(DVVec3 other) =>
      DVVec3(x + other.x, y + other.y, z + other.z);
  DVVec3 operator -(DVVec3 other) =>
      DVVec3(x - other.x, y - other.y, z - other.z);
  DVVec3 operator -() => DVVec3(-x, -y, -z);
  DVVec3 operator *(double factor) => DVVec3(x * factor, y * factor, z * factor);

  double dot(DVVec3 other) => x * other.x + y * other.y + z * other.z;

  DVVec3 cross(DVVec3 other) => DVVec3(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  double get length => math.sqrt(dot(this));

  /// This direction at unit length; the zero vector stays zero rather than
  /// becoming NaN, which would poison every transform downstream.
  DVVec3 normalized() {
    final double l = length;
    return l == 0 ? this : this * (1 / l);
  }

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  List<double> toList() => <double>[x, y, z];

  @override
  bool operator ==(Object other) =>
      other is DVVec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'DVVec3($x, $y, $z)';
}

/// A rotation, as a unit quaternion.
final class DVQuat {
  const DVQuat(this.x, this.y, this.z, this.w);

  final double x;
  final double y;
  final double z;
  final double w;

  static const DVQuat identity = DVQuat(0, 0, 0, 1);

  /// A rotation of [radians] about [axis], counter-clockwise looking down
  /// the axis toward the origin (the right-hand rule).
  factory DVQuat.axisAngle(DVVec3 axis, double radians) {
    final DVVec3 a = axis.normalized();
    final double s = math.sin(radians / 2);
    return DVQuat(a.x * s, a.y * s, a.z * s, math.cos(radians / 2));
  }

  /// The Hamilton product: this rotation applied after [other].
  DVQuat operator *(DVQuat other) => DVQuat(
        w * other.x + x * other.w + y * other.z - z * other.y,
        w * other.y - x * other.z + y * other.w + z * other.x,
        w * other.z + x * other.y - y * other.x + z * other.w,
        w * other.w - x * other.x - y * other.y - z * other.z,
      );

  double get length => math.sqrt(x * x + y * y + z * z + w * w);

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite && w.isFinite;

  /// [v] rotated by this quaternion.
  DVVec3 rotate(DVVec3 v) {
    final DVVec3 q = DVVec3(x, y, z);
    final DVVec3 t = q.cross(v) * 2;
    return v + t * w + q.cross(t);
  }

  List<double> toList() => <double>[x, y, z, w];

  @override
  bool operator ==(Object other) =>
      other is DVQuat &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.w == w;

  @override
  int get hashCode => Object.hash(x, y, z, w);

  @override
  String toString() => 'DVQuat($x, $y, $z, $w)';
}

/// A 4x4 matrix, column-major: element (row r, column c) is
/// `storage[c * 4 + r]`.
final class DVMat4 {
  DVMat4._(this.storage);

  /// Copies [values] (16 of them, column-major).
  factory DVMat4.fromList(List<double> values) {
    if (values.length != 16) {
      throw ArgumentError.value(values, 'values', 'A DVMat4 needs 16 values.');
    }
    return DVMat4._(Float64List.fromList(values));
  }

  factory DVMat4.identity() => DVMat4._(Float64List(16)
    ..[0] = 1
    ..[5] = 1
    ..[10] = 1
    ..[15] = 1);

  factory DVMat4.translation(DVVec3 t) => DVMat4.identity()
    ..storage[12] = t.x
    ..storage[13] = t.y
    ..storage[14] = t.z;

  factory DVMat4.scaling(DVVec3 s) => DVMat4._(Float64List(16)
    ..[0] = s.x
    ..[5] = s.y
    ..[10] = s.z
    ..[15] = 1);

  /// Translation * rotation * scale, the order glTF and the engine compose a
  /// node's local transform in.
  factory DVMat4.compose(DVVec3 t, DVQuat r, DVVec3 s) {
    final double x2 = r.x + r.x, y2 = r.y + r.y, z2 = r.z + r.z;
    final double xx = r.x * x2, xy = r.x * y2, xz = r.x * z2;
    final double yy = r.y * y2, yz = r.y * z2, zz = r.z * z2;
    final double wx = r.w * x2, wy = r.w * y2, wz = r.w * z2;
    return DVMat4._(Float64List(16)
      ..[0] = (1 - (yy + zz)) * s.x
      ..[1] = (xy + wz) * s.x
      ..[2] = (xz - wy) * s.x
      ..[4] = (xy - wz) * s.y
      ..[5] = (1 - (xx + zz)) * s.y
      ..[6] = (yz + wx) * s.y
      ..[8] = (xz + wy) * s.z
      ..[9] = (yz - wx) * s.z
      ..[10] = (1 - (xx + yy)) * s.z
      ..[12] = t.x
      ..[13] = t.y
      ..[14] = t.z
      ..[15] = 1);
  }

  /// A right-handed perspective projection into OpenGL clip space (NDC z in
  /// -1..1). [fovYRadians] is the full vertical field of view.
  factory DVMat4.perspective(
    double fovYRadians,
    double aspect,
    double near,
    double far,
  ) {
    final double f = 1 / math.tan(fovYRadians / 2);
    final double nf = 1 / (near - far);
    return DVMat4._(Float64List(16)
      ..[0] = f / aspect
      ..[5] = f
      ..[10] = (far + near) * nf
      ..[11] = -1
      ..[14] = 2 * far * near * nf);
  }

  /// A view matrix for an eye at [eye] looking at [target].
  factory DVMat4.lookAt(DVVec3 eye, DVVec3 target, DVVec3 up) {
    final DVVec3 zAxis = (eye - target).normalized();
    DVVec3 xAxis = up.cross(zAxis).normalized();
    if (xAxis == DVVec3.zero) {
      // Looking straight along [up]: any perpendicular will do, and a zero
      // axis would collapse the view to a line.
      xAxis = const DVVec3(1, 0, 0);
    }
    final DVVec3 yAxis = zAxis.cross(xAxis);
    return DVMat4._(Float64List(16)
      ..[0] = xAxis.x
      ..[1] = yAxis.x
      ..[2] = zAxis.x
      ..[4] = xAxis.y
      ..[5] = yAxis.y
      ..[6] = zAxis.y
      ..[8] = xAxis.z
      ..[9] = yAxis.z
      ..[10] = zAxis.z
      ..[12] = -xAxis.dot(eye)
      ..[13] = -yAxis.dot(eye)
      ..[14] = -zAxis.dot(eye)
      ..[15] = 1);
  }

  final Float64List storage;

  DVMat4 operator *(DVMat4 other) {
    final Float64List a = storage, b = other.storage;
    final Float64List out = Float64List(16);
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 4; r++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += a[k * 4 + r] * b[c * 4 + k];
        }
        out[c * 4 + r] = sum;
      }
    }
    return DVMat4._(out);
  }

  /// [p] as a point: translated, and divided by w when this is a projection.
  DVVec3 transformPoint(DVVec3 p) {
    final Float64List m = storage;
    final double x = m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12];
    final double y = m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13];
    final double z = m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14];
    final double w = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15];
    return w == 1 || w == 0 ? DVVec3(x, y, z) : DVVec3(x / w, y / w, z / w);
  }

  /// [d] as a direction: rotated and scaled, never translated.
  DVVec3 transformDirection(DVVec3 d) {
    final Float64List m = storage;
    return DVVec3(
      m[0] * d.x + m[4] * d.y + m[8] * d.z,
      m[1] * d.x + m[5] * d.y + m[9] * d.z,
      m[2] * d.x + m[6] * d.y + m[10] * d.z,
    );
  }

  DVVec3 get translation => DVVec3(storage[12], storage[13], storage[14]);

  /// The determinant of the upper 3x3, whose sign says whether this matrix
  /// mirrors.
  double get determinant3 {
    final Float64List m = storage;
    return m[0] * (m[5] * m[10] - m[9] * m[6]) -
        m[4] * (m[1] * m[10] - m[9] * m[2]) +
        m[8] * (m[1] * m[6] - m[5] * m[2]);
  }

  /// The inverse, or null when this matrix has none.
  DVMat4? inverse() {
    final Float64List a = storage;
    final double a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
    final double a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
    final double a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
    final double a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
    final double b00 = a00 * a11 - a01 * a10;
    final double b01 = a00 * a12 - a02 * a10;
    final double b02 = a00 * a13 - a03 * a10;
    final double b03 = a01 * a12 - a02 * a11;
    final double b04 = a01 * a13 - a03 * a11;
    final double b05 = a02 * a13 - a03 * a12;
    final double b06 = a20 * a31 - a21 * a30;
    final double b07 = a20 * a32 - a22 * a30;
    final double b08 = a20 * a33 - a23 * a30;
    final double b09 = a21 * a32 - a22 * a31;
    final double b10 = a21 * a33 - a23 * a31;
    final double b11 = a22 * a33 - a23 * a32;
    final double det =
        b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    if (det == 0 || !det.isFinite) return null;
    final double inv = 1 / det;
    return DVMat4._(Float64List(16)
      ..[0] = (a11 * b11 - a12 * b10 + a13 * b09) * inv
      ..[1] = (a02 * b10 - a01 * b11 - a03 * b09) * inv
      ..[2] = (a31 * b05 - a32 * b04 + a33 * b03) * inv
      ..[3] = (a22 * b04 - a21 * b05 - a23 * b03) * inv
      ..[4] = (a12 * b08 - a10 * b11 - a13 * b07) * inv
      ..[5] = (a00 * b11 - a02 * b08 + a03 * b07) * inv
      ..[6] = (a32 * b02 - a30 * b05 - a33 * b01) * inv
      ..[7] = (a20 * b05 - a22 * b02 + a23 * b01) * inv
      ..[8] = (a10 * b10 - a11 * b08 + a13 * b06) * inv
      ..[9] = (a01 * b08 - a00 * b10 - a03 * b06) * inv
      ..[10] = (a30 * b04 - a31 * b02 + a33 * b00) * inv
      ..[11] = (a21 * b02 - a20 * b04 - a23 * b00) * inv
      ..[12] = (a11 * b07 - a10 * b09 - a12 * b06) * inv
      ..[13] = (a00 * b09 - a01 * b07 + a02 * b06) * inv
      ..[14] = (a31 * b01 - a30 * b03 - a32 * b00) * inv
      ..[15] = (a20 * b03 - a21 * b01 + a22 * b00) * inv);
  }

  @override
  bool operator ==(Object other) {
    if (other is! DVMat4) return false;
    for (int i = 0; i < 16; i++) {
      if (storage[i] != other.storage[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(storage);

  @override
  String toString() => 'DVMat4(${storage.join(', ')})';
}

/// A node's local transform: translation, rotation and scale.
final class DVTransform {
  DVTransform({
    this.translation = DVVec3.zero,
    this.rotation = DVQuat.identity,
    this.scale = DVVec3.one,
  });

  final DVVec3 translation;
  final DVQuat rotation;
  final DVVec3 scale;

  static final DVTransform identity = DVTransform();

  DVMat4 get matrix => DVMat4.compose(translation, rotation, scale);

  DVTransform copyWith({DVVec3? translation, DVQuat? rotation, DVVec3? scale}) =>
      DVTransform(
        translation: translation ?? this.translation,
        rotation: rotation ?? this.rotation,
        scale: scale ?? this.scale,
      );

  @override
  bool operator ==(Object other) =>
      other is DVTransform &&
      other.translation == translation &&
      other.rotation == rotation &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(translation, rotation, scale);

  @override
  String toString() => 'DVTransform(t: $translation, r: $rotation, s: $scale)';
}

/// A half-line: every point `origin + direction * t` for `t >= 0`.
final class DVRay {
  const DVRay(this.origin, this.direction);

  final DVVec3 origin;
  final DVVec3 direction;

  DVVec3 pointAt(double t) => origin + direction * t;

  @override
  String toString() => 'DVRay($origin -> $direction)';
}

/// An axis-aligned box.
final class DVAabb {
  const DVAabb(this.min, this.max);

  final DVVec3 min;
  final DVVec3 max;

  DVVec3 get center => (min + max) * 0.5;

  /// The eight corners, in a fixed order.
  List<DVVec3> get corners => <DVVec3>[
        for (final double x in <double>[min.x, max.x])
          for (final double y in <double>[min.y, max.y])
            for (final double z in <double>[min.z, max.z]) DVVec3(x, y, z),
      ];

  /// The smallest box containing this one after [matrix] -- conservative
  /// under rotation, which is why picking does not use it.
  DVAabb transformed(DVMat4 matrix) => DVAabb.containing(
      corners.map(matrix.transformPoint).toList(growable: false));

  DVAabb union(DVAabb other) => DVAabb(
        DVVec3(math.min(min.x, other.min.x), math.min(min.y, other.min.y),
            math.min(min.z, other.min.z)),
        DVVec3(math.max(max.x, other.max.x), math.max(max.y, other.max.y),
            math.max(max.z, other.max.z)),
      );

  factory DVAabb.containing(List<DVVec3> points) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'no points to contain');
    }
    double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (final DVVec3 p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      minZ = math.min(minZ, p.z);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
      maxZ = math.max(maxZ, p.z);
    }
    return DVAabb(DVVec3(minX, minY, minZ), DVVec3(maxX, maxY, maxZ));
  }

  /// The ray parameter where [ray] enters this box, 0 when it starts inside,
  /// or null when it misses. The slab method.
  double? intersect(DVRay ray) {
    double tMin = 0;
    double tMax = double.infinity;
    final List<double> o = ray.origin.toList();
    final List<double> d = ray.direction.toList();
    final List<double> lo = min.toList();
    final List<double> hi = max.toList();
    for (int axis = 0; axis < 3; axis++) {
      if (d[axis] == 0) {
        if (o[axis] < lo[axis] || o[axis] > hi[axis]) return null;
        continue;
      }
      double t1 = (lo[axis] - o[axis]) / d[axis];
      double t2 = (hi[axis] - o[axis]) / d[axis];
      if (t1 > t2) {
        final double swap = t1;
        t1 = t2;
        t2 = swap;
      }
      tMin = math.max(tMin, t1);
      tMax = math.min(tMax, t2);
      if (tMin > tMax) return null;
    }
    return tMin;
  }

  @override
  bool operator ==(Object other) =>
      other is DVAabb && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'DVAabb($min, $max)';
}
