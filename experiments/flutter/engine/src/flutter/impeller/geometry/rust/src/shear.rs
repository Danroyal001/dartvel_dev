// flutter/impeller/geometry/shear.h (shear.cc is empty)

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Shear {
    pub xy: f64,
    pub xz: f64,
    pub yz: f64,
}

impl Shear {
    #[inline]
    pub const fn new(xy: f64, xz: f64, yz: f64) -> Shear {
        Shear { xy, xz, yz }
    }

    #[inline]
    /// Upstream's `union { struct { xy, xz, yz }; double e[3]; }`.
    pub const fn e(&self) -> [f64; 3] {
        [self.xy, self.xz, self.yz]
    }
}
