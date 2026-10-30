// flutter/impeller/geometry/matrix_decomposition.h (matrix_decomposition.cc
// is empty; GetComponentsMask is defined in matrix.cc and ported here)

use crate::quaternion::Quaternion;
use crate::shear::Shear;
use crate::vector::{Vector3, Vector4};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct MatrixDecomposition {
    pub translation: Vector3,
    pub scale: Vector3,
    pub shear: Shear,
    pub perspective: Vector4,
    pub rotation: Quaternion,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u64)]
pub enum Component {
    kTranslation = 1 << 0,
    kScale = 1 << 1,
    kShear = 1 << 2,
    kPerspective = 1 << 3,
    kRotation = 1 << 4,
}

impl MatrixDecomposition {
    #[inline]
    pub fn get_components_mask(&self) -> u64 {
        let mut mask: u64 = 0;

        let noRotation = Quaternion::new(0.0, 0.0, 0.0, 1.0);
        if self.rotation != noRotation {
            mask |= Component::kRotation as u64;
        }

        let defaultPerspective = Vector4::new(0.0, 0.0, 0.0, 1.0);
        if self.perspective != defaultPerspective {
            mask |= Component::kPerspective as u64;
        }

        let noShear = Shear::new(0.0, 0.0, 0.0);
        if self.shear != noShear {
            mask |= Component::kShear as u64;
        }

        let defaultScale = Vector3::new(1.0, 1.0, 1.0);
        if self.scale != defaultScale {
            mask |= Component::kScale as u64;
        }

        let defaultTranslation = Vector3::new(0.0, 0.0, 0.0);
        if self.translation != defaultTranslation {
            mask |= Component::kTranslation as u64;
        }

        mask
    }
}
