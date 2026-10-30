// flutter/impeller/geometry/color.h, color.cc

use std::fmt;
use std::ops::{Add, Div, Mul, Sub};

use crate::constants::kEhCloseEnough;
use crate::cxx::{self, Num};
use crate::scalar::{Scalar, scalar_nearly_equal};
use crate::vector::{Vector3, Vector4};

/// `IMPELLER_FOR_EACH_BLEND_MODE`, applied to a macro taking the names.
#[macro_export]
macro_rules! impeller_for_each_blend_mode {
    ($v:ident) => {
        $v!(
            Clear, Src, Dst, SrcOver, DstOver, SrcIn, DstIn, SrcOut, DstOut, SrcATop, DstATop, Xor,
            Plus, Modulate, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight,
            SoftLight, Difference, Exclusion, Multiply, Hue, Saturation, Color, Luminosity
        );
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum YUVColorSpace {
    kBT601LimitedRange,
    kBT601FullRange,
}

/// All blend modes assume that both the source (fragment output) and
/// destination (first color attachment) have colors with premultiplied alpha.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(u8)]
pub enum BlendMode {
    kClear = 0,
    kSrc,
    kDst,
    kSrcOver,
    kDstOver,
    kSrcIn,
    kDstIn,
    kSrcOut,
    kDstOut,
    kSrcATop,
    kDstATop,
    kXor,
    kPlus,
    kModulate,
    kScreen,
    kOverlay,
    kDarken,
    kLighten,
    kColorDodge,
    kColorBurn,
    kHardLight,
    kSoftLight,
    kDifference,
    kExclusion,
    kMultiply,
    kHue,
    kSaturation,
    kColor,
    kLuminosity,
}

impl BlendMode {
    pub const kLastMode: BlendMode = BlendMode::kLuminosity;
    pub const kDefaultMode: BlendMode = BlendMode::kSrcOver;

    /// The mode with the given underlying value, if there is one.
    pub fn from_u8(v: u8) -> Option<BlendMode> {
        if v <= BlendMode::kLastMode as u8 { Some(kBlendModes[v as usize]) } else { None }
    }
}

macro_rules! blend_mode_tables {
    ($($name:ident),*) => {
        static kBlendModeNames: &[&str] = &[$(stringify!($name)),*];
        static kBlendModes: &[BlendMode] = &[$(paste_mode!($name)),*];
    };
}
macro_rules! paste_mode {
    (Clear) => { BlendMode::kClear };
    (Src) => { BlendMode::kSrc };
    (Dst) => { BlendMode::kDst };
    (SrcOver) => { BlendMode::kSrcOver };
    (DstOver) => { BlendMode::kDstOver };
    (SrcIn) => { BlendMode::kSrcIn };
    (DstIn) => { BlendMode::kDstIn };
    (SrcOut) => { BlendMode::kSrcOut };
    (DstOut) => { BlendMode::kDstOut };
    (SrcATop) => { BlendMode::kSrcATop };
    (DstATop) => { BlendMode::kDstATop };
    (Xor) => { BlendMode::kXor };
    (Plus) => { BlendMode::kPlus };
    (Modulate) => { BlendMode::kModulate };
    (Screen) => { BlendMode::kScreen };
    (Overlay) => { BlendMode::kOverlay };
    (Darken) => { BlendMode::kDarken };
    (Lighten) => { BlendMode::kLighten };
    (ColorDodge) => { BlendMode::kColorDodge };
    (ColorBurn) => { BlendMode::kColorBurn };
    (HardLight) => { BlendMode::kHardLight };
    (SoftLight) => { BlendMode::kSoftLight };
    (Difference) => { BlendMode::kDifference };
    (Exclusion) => { BlendMode::kExclusion };
    (Multiply) => { BlendMode::kMultiply };
    (Hue) => { BlendMode::kHue };
    (Saturation) => { BlendMode::kSaturation };
    (Color) => { BlendMode::kColor };
    (Luminosity) => { BlendMode::kLuminosity };
}
impeller_for_each_blend_mode!(blend_mode_tables);

// ValidateBlendModes: the list and the enum agree, in order.
const _: () = {
    assert!(BlendMode::kLastMode as usize == 28);
};

pub fn blend_mode_to_string(blend_mode: BlendMode) -> &'static str {
    kBlendModeNames[blend_mode as usize]
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ColorMatrix {
    pub array: [Scalar; 20],
}

/// Represents a RGBA color
#[derive(Clone, Copy, Debug, Default)]
#[repr(C)]
pub struct Color {
    /// The red color component (0 to 1)
    pub red: Scalar,
    /// The green color component (0 to 1)
    pub green: Scalar,
    /// The blue color component (0 to 1)
    pub blue: Scalar,
    /// The alpha component of the color (0 to 1)
    pub alpha: Scalar,
}

const _: () = assert!(std::mem::size_of::<Color>() == 4 * std::mem::size_of::<Scalar>());

/// `explicit Color(const Vector4& value)`.
impl From<Vector4> for Color {
    fn from(value: Vector4) -> Color {
        Color { red: value.x, green: value.y, blue: value.z, alpha: value.w }
    }
}

/// Upstream's `operator==` compares within kEhCloseEnough.
impl PartialEq for Color {
    fn eq(&self, c: &Color) -> bool {
        scalar_nearly_equal(self.red, c.red)
            && scalar_nearly_equal(self.green, c.green)
            && scalar_nearly_equal(self.blue, c.blue)
            && scalar_nearly_equal(self.alpha, c.alpha)
    }
}

impl Color {
    pub const fn new(r: Scalar, g: Scalar, b: Scalar, a: Scalar) -> Color {
        Color { red: r, green: g, blue: b, alpha: a }
    }

    pub fn make_rgba8(r: u8, g: u8, b: u8, a: u8) -> Color {
        Color::new(r as Scalar / 255.0, g as Scalar / 255.0, b as Scalar / 255.0, a as Scalar / 255.0)
    }

    /// Convert this color to a 32-bit representation.
    pub fn to_i_color(color: Color) -> u32 {
        (((cxx::lround(color.alpha * 255.0) & 0xff) << 24)
            | ((cxx::lround(color.red * 255.0) & 0xff) << 16)
            | ((cxx::lround(color.green * 255.0) & 0xff) << 8)
            | (cxx::lround(color.blue * 255.0) & 0xff)) as u64 as u32
    }

    pub fn premultiply(&self) -> Color {
        Color::new(self.red * self.alpha, self.green * self.alpha, self.blue * self.alpha, self.alpha)
    }

    pub fn unpremultiply(&self) -> Color {
        if scalar_nearly_equal(self.alpha, 0.0) {
            return Color::black_transparent();
        }
        Color::new(self.red / self.alpha, self.green / self.alpha, self.blue / self.alpha, self.alpha)
    }

    /// Returns true if any of the color components lies outside [0, 1].
    pub fn is_wide_gamut(&self) -> bool {
        self.red < -kEhCloseEnough
            || self.red > 1.0 + kEhCloseEnough
            || self.green < -kEhCloseEnough
            || self.green > 1.0 + kEhCloseEnough
            || self.blue < -kEhCloseEnough
            || self.blue > 1.0 + kEhCloseEnough
    }

    /// Return a color that is linearly interpolated between colors a and b,
    /// according to the value of t.
    pub fn lerp(a: Color, b: Color, t: Scalar) -> Color {
        a + (b - a) * t
    }

    pub fn clamp01(&self) -> Color {
        Color::new(
            cxx::clamp(self.red, 0.0, 1.0),
            cxx::clamp(self.green, 0.0, 1.0),
            cxx::clamp(self.blue, 0.0, 1.0),
            cxx::clamp(self.alpha, 0.0, 1.0),
        )
    }

    /// Convert to R8G8B8A8 representation. Upstream converts the rounded
    /// float to `uint8_t` implicitly, which is undefined outside [0, 255];
    /// the port saturates.
    pub fn to_r8g8b8a8(&self) -> [u8; 4] {
        let r = (self.red * 255.0).round() as u8;
        let g = (self.green * 255.0).round() as u8;
        let b = (self.blue * 255.0).round() as u8;
        let a = (self.alpha * 255.0).round() as u8;
        [r, g, b, a]
    }

    /// Convert to ARGB 32 bit color.
    pub fn to_argb(&self) -> u32 {
        let result = self.to_r8g8b8a8();
        (result[3] as u32) << 24 | (result[0] as u32) << 16 | (result[1] as u32) << 8 | result[2] as u32
    }

    pub const fn white() -> Color {
        Color::new(1.0, 1.0, 1.0, 1.0)
    }
    pub const fn black() -> Color {
        Color::new(0.0, 0.0, 0.0, 1.0)
    }
    pub const fn white_transparent() -> Color {
        Color::new(1.0, 1.0, 1.0, 0.0)
    }
    pub const fn black_transparent() -> Color {
        Color::new(0.0, 0.0, 0.0, 0.0)
    }
    pub const fn red() -> Color {
        Color::new(1.0, 0.0, 0.0, 1.0)
    }
    pub const fn green() -> Color {
        Color::new(0.0, 1.0, 0.0, 1.0)
    }
    pub const fn blue() -> Color {
        Color::new(0.0, 0.0, 1.0, 1.0)
    }

    pub const fn with_alpha(&self, new_alpha: Scalar) -> Color {
        Color::new(self.red, self.green, self.blue, new_alpha)
    }

    pub const fn alice_blue() -> Color {
        Color::new(240.0 / 255.0, 248.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn antique_white() -> Color {
        Color::new(250.0 / 255.0, 235.0 / 255.0, 215.0 / 255.0, 1.0)
    }
    pub const fn aqua() -> Color {
        Color::new(0.0 / 255.0, 255.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn aqua_marine() -> Color {
        Color::new(127.0 / 255.0, 255.0 / 255.0, 212.0 / 255.0, 1.0)
    }
    pub const fn azure() -> Color {
        Color::new(240.0 / 255.0, 255.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn beige() -> Color {
        Color::new(245.0 / 255.0, 245.0 / 255.0, 220.0 / 255.0, 1.0)
    }
    pub const fn bisque() -> Color {
        Color::new(255.0 / 255.0, 228.0 / 255.0, 196.0 / 255.0, 1.0)
    }
    pub const fn blanched_almond() -> Color {
        Color::new(255.0 / 255.0, 235.0 / 255.0, 205.0 / 255.0, 1.0)
    }
    pub const fn blue_violet() -> Color {
        Color::new(138.0 / 255.0, 43.0 / 255.0, 226.0 / 255.0, 1.0)
    }
    pub const fn brown() -> Color {
        Color::new(165.0 / 255.0, 42.0 / 255.0, 42.0 / 255.0, 1.0)
    }
    pub const fn burly_wood() -> Color {
        Color::new(222.0 / 255.0, 184.0 / 255.0, 135.0 / 255.0, 1.0)
    }
    pub const fn cadet_blue() -> Color {
        Color::new(95.0 / 255.0, 158.0 / 255.0, 160.0 / 255.0, 1.0)
    }
    pub const fn chartreuse() -> Color {
        Color::new(127.0 / 255.0, 255.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn chocolate() -> Color {
        Color::new(210.0 / 255.0, 105.0 / 255.0, 30.0 / 255.0, 1.0)
    }
    pub const fn coral() -> Color {
        Color::new(255.0 / 255.0, 127.0 / 255.0, 80.0 / 255.0, 1.0)
    }
    pub const fn cornflower_blue() -> Color {
        Color::new(100.0 / 255.0, 149.0 / 255.0, 237.0 / 255.0, 1.0)
    }
    pub const fn cornsilk() -> Color {
        Color::new(255.0 / 255.0, 248.0 / 255.0, 220.0 / 255.0, 1.0)
    }
    pub const fn crimson() -> Color {
        Color::new(220.0 / 255.0, 20.0 / 255.0, 60.0 / 255.0, 1.0)
    }
    pub const fn cyan() -> Color {
        Color::new(0.0 / 255.0, 255.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn dark_blue() -> Color {
        Color::new(0.0 / 255.0, 0.0 / 255.0, 139.0 / 255.0, 1.0)
    }
    pub const fn dark_cyan() -> Color {
        Color::new(0.0 / 255.0, 139.0 / 255.0, 139.0 / 255.0, 1.0)
    }
    pub const fn dark_goldenrod() -> Color {
        Color::new(184.0 / 255.0, 134.0 / 255.0, 11.0 / 255.0, 1.0)
    }
    pub const fn dark_gray() -> Color {
        Color::new(169.0 / 255.0, 169.0 / 255.0, 169.0 / 255.0, 1.0)
    }
    pub const fn dark_green() -> Color {
        Color::new(0.0 / 255.0, 100.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn dark_grey() -> Color {
        Color::new(169.0 / 255.0, 169.0 / 255.0, 169.0 / 255.0, 1.0)
    }
    pub const fn dark_khaki() -> Color {
        Color::new(189.0 / 255.0, 183.0 / 255.0, 107.0 / 255.0, 1.0)
    }
    pub const fn dark_magenta() -> Color {
        Color::new(139.0 / 255.0, 0.0 / 255.0, 139.0 / 255.0, 1.0)
    }
    pub const fn dark_olive_green() -> Color {
        Color::new(85.0 / 255.0, 107.0 / 255.0, 47.0 / 255.0, 1.0)
    }
    pub const fn dark_orange() -> Color {
        Color::new(255.0 / 255.0, 140.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn dark_orchid() -> Color {
        Color::new(153.0 / 255.0, 50.0 / 255.0, 204.0 / 255.0, 1.0)
    }
    pub const fn dark_red() -> Color {
        Color::new(139.0 / 255.0, 0.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn dark_salmon() -> Color {
        Color::new(233.0 / 255.0, 150.0 / 255.0, 122.0 / 255.0, 1.0)
    }
    pub const fn dark_seagreen() -> Color {
        Color::new(143.0 / 255.0, 188.0 / 255.0, 143.0 / 255.0, 1.0)
    }
    pub const fn dark_slate_blue() -> Color {
        Color::new(72.0 / 255.0, 61.0 / 255.0, 139.0 / 255.0, 1.0)
    }
    pub const fn dark_slate_gray() -> Color {
        Color::new(47.0 / 255.0, 79.0 / 255.0, 79.0 / 255.0, 1.0)
    }
    pub const fn dark_slate_grey() -> Color {
        Color::new(47.0 / 255.0, 79.0 / 255.0, 79.0 / 255.0, 1.0)
    }
    pub const fn dark_turquoise() -> Color {
        Color::new(0.0 / 255.0, 206.0 / 255.0, 209.0 / 255.0, 1.0)
    }
    pub const fn dark_violet() -> Color {
        Color::new(148.0 / 255.0, 0.0 / 255.0, 211.0 / 255.0, 1.0)
    }
    pub const fn deep_pink() -> Color {
        Color::new(255.0 / 255.0, 20.0 / 255.0, 147.0 / 255.0, 1.0)
    }
    pub const fn deep_sky_blue() -> Color {
        Color::new(0.0 / 255.0, 191.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn dim_gray() -> Color {
        Color::new(105.0 / 255.0, 105.0 / 255.0, 105.0 / 255.0, 1.0)
    }
    pub const fn dim_grey() -> Color {
        Color::new(105.0 / 255.0, 105.0 / 255.0, 105.0 / 255.0, 1.0)
    }
    pub const fn dodger_blue() -> Color {
        Color::new(30.0 / 255.0, 144.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn firebrick() -> Color {
        Color::new(178.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0, 1.0)
    }
    pub const fn floral_white() -> Color {
        Color::new(255.0 / 255.0, 250.0 / 255.0, 240.0 / 255.0, 1.0)
    }
    pub const fn forest_green() -> Color {
        Color::new(34.0 / 255.0, 139.0 / 255.0, 34.0 / 255.0, 1.0)
    }
    pub const fn fuchsia() -> Color {
        Color::new(255.0 / 255.0, 0.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn gainsboro() -> Color {
        Color::new(220.0 / 255.0, 220.0 / 255.0, 220.0 / 255.0, 1.0)
    }
    pub const fn ghostwhite() -> Color {
        Color::new(248.0 / 255.0, 248.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn gold() -> Color {
        Color::new(255.0 / 255.0, 215.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn goldenrod() -> Color {
        Color::new(218.0 / 255.0, 165.0 / 255.0, 32.0 / 255.0, 1.0)
    }
    pub const fn gray() -> Color {
        Color::new(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)
    }
    pub const fn green_yellow() -> Color {
        Color::new(173.0 / 255.0, 255.0 / 255.0, 47.0 / 255.0, 1.0)
    }
    pub const fn grey() -> Color {
        Color::new(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)
    }
    pub const fn honeydew() -> Color {
        Color::new(240.0 / 255.0, 255.0 / 255.0, 240.0 / 255.0, 1.0)
    }
    pub const fn hot_pink() -> Color {
        Color::new(255.0 / 255.0, 105.0 / 255.0, 180.0 / 255.0, 1.0)
    }
    pub const fn indian_red() -> Color {
        Color::new(205.0 / 255.0, 92.0 / 255.0, 92.0 / 255.0, 1.0)
    }
    pub const fn indigo() -> Color {
        Color::new(75.0 / 255.0, 0.0 / 255.0, 130.0 / 255.0, 1.0)
    }
    pub const fn ivory() -> Color {
        Color::new(255.0 / 255.0, 255.0 / 255.0, 240.0 / 255.0, 1.0)
    }
    pub const fn khaki() -> Color {
        Color::new(240.0 / 255.0, 230.0 / 255.0, 140.0 / 255.0, 1.0)
    }
    pub const fn lavender() -> Color {
        Color::new(230.0 / 255.0, 230.0 / 255.0, 250.0 / 255.0, 1.0)
    }
    pub const fn lavender_blush() -> Color {
        Color::new(255.0 / 255.0, 240.0 / 255.0, 245.0 / 255.0, 1.0)
    }
    pub const fn lawn_green() -> Color {
        Color::new(124.0 / 255.0, 252.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn lemon_chiffon() -> Color {
        Color::new(255.0 / 255.0, 250.0 / 255.0, 205.0 / 255.0, 1.0)
    }
    pub const fn light_blue() -> Color {
        Color::new(173.0 / 255.0, 216.0 / 255.0, 230.0 / 255.0, 1.0)
    }
    pub const fn light_coral() -> Color {
        Color::new(240.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)
    }
    pub const fn light_cyan() -> Color {
        Color::new(224.0 / 255.0, 255.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn light_goldenrod_yellow() -> Color {
        Color::new(50.0 / 255.0, 250.0 / 255.0, 210.0 / 255.0, 1.0)
    }
    pub const fn light_gray() -> Color {
        Color::new(211.0 / 255.0, 211.0 / 255.0, 211.0 / 255.0, 1.0)
    }
    pub const fn light_green() -> Color {
        Color::new(144.0 / 255.0, 238.0 / 255.0, 144.0 / 255.0, 1.0)
    }
    pub const fn light_grey() -> Color {
        Color::new(211.0 / 255.0, 211.0 / 255.0, 211.0 / 255.0, 1.0)
    }
    pub const fn light_pink() -> Color {
        Color::new(255.0 / 255.0, 182.0 / 255.0, 193.0 / 255.0, 1.0)
    }
    pub const fn light_salmon() -> Color {
        Color::new(255.0 / 255.0, 160.0 / 255.0, 122.0 / 255.0, 1.0)
    }
    pub const fn light_sea_green() -> Color {
        Color::new(32.0 / 255.0, 178.0 / 255.0, 170.0 / 255.0, 1.0)
    }
    pub const fn light_sky_blue() -> Color {
        Color::new(135.0 / 255.0, 206.0 / 255.0, 250.0 / 255.0, 1.0)
    }
    pub const fn light_slate_gray() -> Color {
        Color::new(119.0 / 255.0, 136.0 / 255.0, 153.0 / 255.0, 1.0)
    }
    pub const fn light_slate_grey() -> Color {
        Color::new(119.0 / 255.0, 136.0 / 255.0, 153.0 / 255.0, 1.0)
    }
    pub const fn light_steel_blue() -> Color {
        Color::new(176.0 / 255.0, 196.0 / 255.0, 222.0 / 255.0, 1.0)
    }
    pub const fn light_yellow() -> Color {
        Color::new(255.0 / 255.0, 255.0 / 255.0, 224.0 / 255.0, 1.0)
    }
    pub const fn lime() -> Color {
        Color::new(0.0 / 255.0, 255.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn lime_green() -> Color {
        Color::new(50.0 / 255.0, 205.0 / 255.0, 50.0 / 255.0, 1.0)
    }
    pub const fn linen() -> Color {
        Color::new(250.0 / 255.0, 240.0 / 255.0, 230.0 / 255.0, 1.0)
    }
    pub const fn magenta() -> Color {
        Color::new(255.0 / 255.0, 0.0 / 255.0, 255.0 / 255.0, 1.0)
    }
    pub const fn maroon() -> Color {
        Color::new(128.0 / 255.0, 0.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn medium_aquamarine() -> Color {
        Color::new(102.0 / 255.0, 205.0 / 255.0, 170.0 / 255.0, 1.0)
    }
    pub const fn medium_blue() -> Color {
        Color::new(0.0 / 255.0, 0.0 / 255.0, 205.0 / 255.0, 1.0)
    }
    pub const fn medium_orchid() -> Color {
        Color::new(186.0 / 255.0, 85.0 / 255.0, 211.0 / 255.0, 1.0)
    }
    pub const fn medium_purple() -> Color {
        Color::new(147.0 / 255.0, 112.0 / 255.0, 219.0 / 255.0, 1.0)
    }
    pub const fn medium_seagreen() -> Color {
        Color::new(60.0 / 255.0, 179.0 / 255.0, 113.0 / 255.0, 1.0)
    }
    pub const fn medium_slate_blue() -> Color {
        Color::new(123.0 / 255.0, 104.0 / 255.0, 238.0 / 255.0, 1.0)
    }
    pub const fn medium_spring_green() -> Color {
        Color::new(0.0 / 255.0, 250.0 / 255.0, 154.0 / 255.0, 1.0)
    }
    pub const fn medium_turquoise() -> Color {
        Color::new(72.0 / 255.0, 209.0 / 255.0, 204.0 / 255.0, 1.0)
    }
    pub const fn medium_violet_red() -> Color {
        Color::new(199.0 / 255.0, 21.0 / 255.0, 133.0 / 255.0, 1.0)
    }
    pub const fn midnight_blue() -> Color {
        Color::new(25.0 / 255.0, 25.0 / 255.0, 112.0 / 255.0, 1.0)
    }
    pub const fn mint_cream() -> Color {
        Color::new(245.0 / 255.0, 255.0 / 255.0, 250.0 / 255.0, 1.0)
    }
    pub const fn misty_rose() -> Color {
        Color::new(255.0 / 255.0, 228.0 / 255.0, 225.0 / 255.0, 1.0)
    }
    pub const fn moccasin() -> Color {
        Color::new(255.0 / 255.0, 228.0 / 255.0, 181.0 / 255.0, 1.0)
    }
    pub const fn navajo_white() -> Color {
        Color::new(255.0 / 255.0, 222.0 / 255.0, 173.0 / 255.0, 1.0)
    }
    pub const fn navy() -> Color {
        Color::new(0.0 / 255.0, 0.0 / 255.0, 128.0 / 255.0, 1.0)
    }
    pub const fn old_lace() -> Color {
        Color::new(253.0 / 255.0, 245.0 / 255.0, 230.0 / 255.0, 1.0)
    }
    pub const fn olive() -> Color {
        Color::new(128.0 / 255.0, 128.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn olive_drab() -> Color {
        Color::new(107.0 / 255.0, 142.0 / 255.0, 35.0 / 255.0, 1.0)
    }
    pub const fn orange() -> Color {
        Color::new(255.0 / 255.0, 165.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn orange_red() -> Color {
        Color::new(255.0 / 255.0, 69.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn orchid() -> Color {
        Color::new(218.0 / 255.0, 112.0 / 255.0, 214.0 / 255.0, 1.0)
    }
    pub const fn pale_goldenrod() -> Color {
        Color::new(238.0 / 255.0, 232.0 / 255.0, 170.0 / 255.0, 1.0)
    }
    pub const fn pale_green() -> Color {
        Color::new(152.0 / 255.0, 251.0 / 255.0, 152.0 / 255.0, 1.0)
    }
    pub const fn pale_turquoise() -> Color {
        Color::new(175.0 / 255.0, 238.0 / 255.0, 238.0 / 255.0, 1.0)
    }
    pub const fn pale_violet_red() -> Color {
        Color::new(219.0 / 255.0, 112.0 / 255.0, 147.0 / 255.0, 1.0)
    }
    pub const fn papaya_whip() -> Color {
        Color::new(255.0 / 255.0, 239.0 / 255.0, 213.0 / 255.0, 1.0)
    }
    pub const fn peachpuff() -> Color {
        Color::new(255.0 / 255.0, 218.0 / 255.0, 185.0 / 255.0, 1.0)
    }
    pub const fn peru() -> Color {
        Color::new(205.0 / 255.0, 133.0 / 255.0, 63.0 / 255.0, 1.0)
    }
    pub const fn pink() -> Color {
        Color::new(255.0 / 255.0, 192.0 / 255.0, 203.0 / 255.0, 1.0)
    }
    pub const fn plum() -> Color {
        Color::new(221.0 / 255.0, 160.0 / 255.0, 221.0 / 255.0, 1.0)
    }
    pub const fn powder_blue() -> Color {
        Color::new(176.0 / 255.0, 224.0 / 255.0, 230.0 / 255.0, 1.0)
    }
    pub const fn purple() -> Color {
        Color::new(128.0 / 255.0, 0.0 / 255.0, 128.0 / 255.0, 1.0)
    }
    pub const fn rosy_brown() -> Color {
        Color::new(188.0 / 255.0, 143.0 / 255.0, 143.0 / 255.0, 1.0)
    }
    pub const fn royal_blue() -> Color {
        Color::new(65.0 / 255.0, 105.0 / 255.0, 225.0 / 255.0, 1.0)
    }
    pub const fn saddle_brown() -> Color {
        Color::new(139.0 / 255.0, 69.0 / 255.0, 19.0 / 255.0, 1.0)
    }
    pub const fn salmon() -> Color {
        Color::new(250.0 / 255.0, 128.0 / 255.0, 114.0 / 255.0, 1.0)
    }
    pub const fn sandy_brown() -> Color {
        Color::new(244.0 / 255.0, 164.0 / 255.0, 96.0 / 255.0, 1.0)
    }
    pub const fn seagreen() -> Color {
        Color::new(46.0 / 255.0, 139.0 / 255.0, 87.0 / 255.0, 1.0)
    }
    pub const fn seashell() -> Color {
        Color::new(255.0 / 255.0, 245.0 / 255.0, 238.0 / 255.0, 1.0)
    }
    pub const fn sienna() -> Color {
        Color::new(160.0 / 255.0, 82.0 / 255.0, 45.0 / 255.0, 1.0)
    }
    pub const fn silver() -> Color {
        Color::new(192.0 / 255.0, 192.0 / 255.0, 192.0 / 255.0, 1.0)
    }
    pub const fn sky_blue() -> Color {
        Color::new(135.0 / 255.0, 206.0 / 255.0, 235.0 / 255.0, 1.0)
    }
    pub const fn slate_blue() -> Color {
        Color::new(106.0 / 255.0, 90.0 / 255.0, 205.0 / 255.0, 1.0)
    }
    pub const fn slate_gray() -> Color {
        Color::new(112.0 / 255.0, 128.0 / 255.0, 144.0 / 255.0, 1.0)
    }
    pub const fn slate_grey() -> Color {
        Color::new(112.0 / 255.0, 128.0 / 255.0, 144.0 / 255.0, 1.0)
    }
    pub const fn snow() -> Color {
        Color::new(255.0 / 255.0, 250.0 / 255.0, 250.0 / 255.0, 1.0)
    }
    pub const fn spring_green() -> Color {
        Color::new(0.0 / 255.0, 255.0 / 255.0, 127.0 / 255.0, 1.0)
    }
    pub const fn steel_blue() -> Color {
        Color::new(70.0 / 255.0, 130.0 / 255.0, 180.0 / 255.0, 1.0)
    }
    pub const fn tan() -> Color {
        Color::new(210.0 / 255.0, 180.0 / 255.0, 140.0 / 255.0, 1.0)
    }
    pub const fn teal() -> Color {
        Color::new(0.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0, 1.0)
    }
    pub const fn thistle() -> Color {
        Color::new(216.0 / 255.0, 191.0 / 255.0, 216.0 / 255.0, 1.0)
    }
    pub const fn tomato() -> Color {
        Color::new(255.0 / 255.0, 99.0 / 255.0, 71.0 / 255.0, 1.0)
    }
    pub const fn turquoise() -> Color {
        Color::new(64.0 / 255.0, 224.0 / 255.0, 208.0 / 255.0, 1.0)
    }
    pub const fn violet() -> Color {
        Color::new(238.0 / 255.0, 130.0 / 255.0, 238.0 / 255.0, 1.0)
    }
    pub const fn wheat() -> Color {
        Color::new(245.0 / 255.0, 222.0 / 255.0, 179.0 / 255.0, 1.0)
    }
    pub const fn whitesmoke() -> Color {
        Color::new(245.0 / 255.0, 245.0 / 255.0, 245.0 / 255.0, 1.0)
    }
    pub const fn yellow() -> Color {
        Color::new(255.0 / 255.0, 255.0 / 255.0, 0.0 / 255.0, 1.0)
    }
    pub const fn yellow_green() -> Color {
        Color::new(154.0 / 255.0, 205.0 / 255.0, 50.0 / 255.0, 1.0)
    }
    /// Upstream draws from `std::rand()`; the port draws from its own
    /// per-thread xorshift, so the colors differ (as two libcs' would).
    pub fn random() -> Color {
        use std::cell::Cell;
        thread_local!(static STATE: Cell<u32> = const { Cell::new(0x2545_f491) });
        let next = || {
            STATE.with(|s| {
                let mut x = s.get();
                x ^= x << 13;
                x ^= x >> 17;
                x ^= x << 5;
                s.set(x);
                (x >> 1) as i32
            })
        };
        Color::new(
            (next() % 255) as Scalar / 255.0,
            (next() % 255) as Scalar / 255.0,
            (next() % 255) as Scalar / 255.0,
            1.0,
        )
    }

    pub fn blend(&self, src: Color, blend_mode: BlendMode) -> Color {
        let dst = *self;
        match blend_mode {
            BlendMode::kClear => Color::black_transparent(),
            BlendMode::kSrc => src,
            BlendMode::kDst => dst,
            BlendMode::kSrcOver => {
                (src.premultiply() + dst.premultiply() * (1.0 - src.alpha)).unpremultiply()
            }
            BlendMode::kDstOver => {
                (dst.premultiply() + src.premultiply() * (1.0 - dst.alpha)).unpremultiply()
            }
            BlendMode::kSrcIn => (src.premultiply() * dst.alpha).unpremultiply(),
            BlendMode::kDstIn => (dst.premultiply() * src.alpha).unpremultiply(),
            BlendMode::kSrcOut => (src.premultiply() * (1.0 - dst.alpha)).unpremultiply(),
            BlendMode::kDstOut => (dst.premultiply() * (1.0 - src.alpha)).unpremultiply(),
            BlendMode::kSrcATop => (src.premultiply() * dst.alpha
                + dst.premultiply() * (1.0 - src.alpha))
                .unpremultiply(),
            BlendMode::kDstATop => (dst.premultiply() * src.alpha
                + src.premultiply() * (1.0 - dst.alpha))
                .unpremultiply(),
            BlendMode::kXor => (src.premultiply() * (1.0 - dst.alpha)
                + dst.premultiply() * (1.0 - src.alpha))
                .unpremultiply(),
            BlendMode::kPlus => min(src.premultiply() + dst.premultiply(), 1.0).unpremultiply(),
            BlendMode::kModulate => (src.premultiply() * dst.premultiply()).unpremultiply(),
            BlendMode::kScreen => do_color_blend(dst, src, &|d, s| s + d - s * d),
            BlendMode::kOverlay => do_color_blend(dst, src, &|d, s| {
                // The same as HardLight, but with the source and destination
                // reversed.
                let screen_src = 2.0f64 * d - 1.0;
                let screen = screen_src + s - screen_src * s;
                component_choose(s * (2.0f64 * d), screen, d, 0.5)
            }),
            BlendMode::kDarken => do_color_blend(dst, src, &|d, s| d.min(&s)),
            BlendMode::kLighten => do_color_blend(dst, src, &|d, s| d.max(&s)),
            BlendMode::kColorDodge => do_color_blend_components(dst, src, &|d, s| {
                if d < kEhCloseEnough {
                    return 0.0;
                }
                if 1.0 - (s as f64) < (kEhCloseEnough as f64) {
                    return 1.0;
                }
                cxx::min(1.0, d / (1.0 - s))
            }),
            BlendMode::kColorBurn => do_color_blend_components(dst, src, &|d, s| {
                if 1.0 - (d as f64) < (kEhCloseEnough as f64) {
                    return 1.0;
                }
                if s < kEhCloseEnough {
                    return 0.0;
                }
                1.0 - cxx::min(1.0, (1.0 - d) / s)
            }),
            BlendMode::kHardLight => do_color_blend(dst, src, &|d, s| {
                let screen_src = 2.0f64 * s - 1.0;
                let screen = screen_src + d - screen_src * d;
                component_choose(d * (2.0f64 * s), screen, s, 0.5)
            }),
            BlendMode::kSoftLight => do_color_blend(dst, src, &|d, s| {
                let D = component_choose(
                    ((16.0f64 * d - 12.0) * d + 4.0) * d,
                    Vector3::new(d.x.sqrt(), d.y.sqrt(), d.z.sqrt()),
                    d,
                    0.25,
                );
                component_choose(
                    d - (1.0f64 - 2.0f64 * s) * d * (1.0f64 - d),
                    d + (2.0f64 * s - 1.0) * (D - d),
                    s,
                    0.5,
                )
            }),
            BlendMode::kDifference => do_color_blend(dst, src, &|d, s| (d - s).abs()),
            BlendMode::kExclusion => do_color_blend(dst, src, &|d, s| d + s - 2.0f32 * d * s),
            BlendMode::kMultiply => do_color_blend(dst, src, &|d, s| d * s),
            BlendMode::kHue => do_color_blend(dst, src, &|d, s| {
                set_luminosity(set_saturation(s, saturation(d)), luminosity(d))
            }),
            BlendMode::kSaturation => do_color_blend(dst, src, &|d, s| {
                set_luminosity(set_saturation(d, saturation(s)), luminosity(d))
            }),
            BlendMode::kColor => {
                do_color_blend(dst, src, &|d, s| set_luminosity(s, luminosity(d)))
            }
            BlendMode::kLuminosity => {
                do_color_blend(dst, src, &|d, s| set_luminosity(d, luminosity(s)))
            }
        }
    }

    /// A color filter that transforms colors through a 4x5 color matrix.
    pub fn apply_color_matrix(&self, color_matrix: &ColorMatrix) -> Color {
        let c = &color_matrix.array;
        let (red, green, blue, alpha) = (self.red, self.green, self.blue, self.alpha);
        Color::new(
            c[0] * red + c[1] * green + c[2] * blue + c[3] * alpha + c[4],
            c[5] * red + c[6] * green + c[7] * blue + c[8] * alpha + c[9],
            c[10] * red + c[11] * green + c[12] * blue + c[13] * alpha + c[14],
            c[15] * red + c[16] * green + c[17] * blue + c[18] * alpha + c[19],
        )
        .clamp01()
    }

    /// Convert the color from linear space to sRGB space. The conversion is
    /// computed in double and narrowed.
    pub fn linear_to_srgb(&self) -> Color {
        let conversion = |component: Scalar| -> f64 {
            let c = component as f64;
            if c <= 0.0031308 {
                return c * 12.92;
            }
            1.055 * c.powf(1.0 / 2.4) - 0.055
        };
        Color::new(
            conversion(self.red) as Scalar,
            conversion(self.green) as Scalar,
            conversion(self.blue) as Scalar,
            self.alpha,
        )
    }

    /// Convert the color from sRGB space to linear space.
    pub fn srgb_to_linear(&self) -> Color {
        let conversion = |component: Scalar| -> f64 {
            let c = component as f64;
            if c <= 0.04045 {
                return c / 12.92;
            }
            ((c + 0.055) / 1.055).powf(2.4)
        };
        Color::new(
            conversion(self.red) as Scalar,
            conversion(self.green) as Scalar,
            conversion(self.blue) as Scalar,
            self.alpha,
        )
    }

    pub fn is_transparent(&self) -> bool {
        self.alpha == 0.0
    }

    pub fn is_opaque(&self) -> bool {
        self.alpha == 1.0
    }
}

impl Add<Color> for Color {
    type Output = Color;
    fn add(self, c: Color) -> Color {
        Color::new(self.red + c.red, self.green + c.green, self.blue + c.blue, self.alpha + c.alpha)
    }
}

impl<T: Num> Add<T> for Color {
    type Output = Color;
    fn add(self, value: T) -> Color {
        let v = value.to_f32();
        Color::new(self.red + v, self.green + v, self.blue + v, self.alpha + v)
    }
}

impl Sub<Color> for Color {
    type Output = Color;
    fn sub(self, c: Color) -> Color {
        Color::new(self.red - c.red, self.green - c.green, self.blue - c.blue, self.alpha - c.alpha)
    }
}

impl<T: Num> Sub<T> for Color {
    type Output = Color;
    fn sub(self, value: T) -> Color {
        let v = value.to_f32();
        Color::new(self.red - v, self.green - v, self.blue - v, self.alpha - v)
    }
}

impl Mul<Color> for Color {
    type Output = Color;
    fn mul(self, c: Color) -> Color {
        Color::new(self.red * c.red, self.green * c.green, self.blue * c.blue, self.alpha * c.alpha)
    }
}

impl<T: Num> Mul<T> for Color {
    type Output = Color;
    fn mul(self, value: T) -> Color {
        let v = value.to_f32();
        Color::new(self.red * v, self.green * v, self.blue * v, self.alpha * v)
    }
}

/// Upstream's `operator/(const Color&)` multiplies (kept).
impl Div<Color> for Color {
    type Output = Color;
    fn div(self, c: Color) -> Color {
        Color::new(self.red * c.red, self.green * c.green, self.blue * c.blue, self.alpha * c.alpha)
    }
}

impl<T: Num> Div<T> for Color {
    type Output = Color;
    fn div(self, value: T) -> Color {
        let v = value.to_f32();
        Color::new(self.red / v, self.green / v, self.blue / v, self.alpha / v)
    }
}

macro_rules! color_lhs {
    ($($t:ty),*) => {$(
        impl Add<Color> for $t {
            type Output = Color;
            fn add(self, c: Color) -> Color {
                c + self as Scalar
            }
        }
        impl Sub<Color> for $t {
            type Output = Color;
            fn sub(self, c: Color) -> Color {
                let v = self as Scalar;
                Color::new(v - c.red, v - c.green, v - c.blue, v - c.alpha)
            }
        }
        impl Mul<Color> for $t {
            type Output = Color;
            fn mul(self, c: Color) -> Color {
                c * self as Scalar
            }
        }
        impl Div<Color> for $t {
            type Output = Color;
            fn div(self, c: Color) -> Color {
                let v = self as Scalar;
                Color::new(v / c.red, v / c.green, v / c.blue, v / c.alpha)
            }
        }
    )*};
}
color_lhs!(f32, f64, i32, i64);

// ------------------------------------------------------------ color.cc ----

#[inline]
fn min(c: Color, threshold: f32) -> Color {
    Color::new(
        cxx::min(c.red, threshold),
        cxx::min(c.green, threshold),
        cxx::min(c.blue, threshold),
        cxx::min(c.alpha, threshold),
    )
}

// The following HSV utilities correspond to the following source:
// https://github.com/google/skia/blob/master/src/gpu/ganesh/glsl/GrGLSLBlend.cpp

#[inline]
fn luminosity(color: Vector3) -> Scalar {
    color.x * 0.3 + color.y * 0.59 + color.z * 0.11
}

#[inline]
fn clip_color(mut color: Vector3) -> Vector3 {
    let lum = luminosity(color);
    let mn = cxx::min(cxx::min(color.x, color.y), color.z);
    let mx = cxx::max(cxx::max(color.x, color.y), color.z);
    // `lum - mn` and `mx - lum` will always be >= 0 in the following
    // conditions, so adding a tiny value is enough to make these divisions
    // safe.
    if mn < 0.0 {
        color = lum + (((color - lum) * lum) / (lum - mn + kEhCloseEnough));
    }
    if mx as f64 > 1.0 {
        color = lum + (((color - lum) * (1.0f32 - lum)) / (mx - lum + kEhCloseEnough));
    }
    color
}

#[inline]
fn set_luminosity(color: Vector3, luminosity_: Scalar) -> Vector3 {
    let relative_lum = luminosity_ - luminosity(color);
    clip_color(color + relative_lum)
}

#[inline]
fn saturation(color: Vector3) -> Scalar {
    cxx::max(cxx::max(color.x, color.y), color.z) - cxx::min(cxx::min(color.x, color.y), color.z)
}

#[inline]
fn set_saturation(color: Vector3, saturation: Scalar) -> Vector3 {
    let mn = cxx::min(cxx::min(color.x, color.y), color.z);
    let mx = cxx::max(cxx::max(color.x, color.y), color.z);
    if mn < mx { ((color - mn) * saturation) / (mx - mn) } else { Vector3::default() }
}

#[inline]
fn component_choose(a: Vector3, b: Vector3, value: Vector3, cutoff: Scalar) -> Vector3 {
    Vector3::new(
        if value.x > cutoff { b.x } else { a.x },
        if value.y > cutoff { b.y } else { a.y },
        if value.z > cutoff { b.z } else { a.z },
    )
}

#[inline]
fn to_rgb(color: Color) -> Vector3 {
    Vector3::new(color.red, color.green, color.blue)
}

#[inline]
fn from_rgb(color: Vector3, alpha: Scalar) -> Color {
    Color::new(color.x, color.y, color.z, alpha)
}

/// Composite a blended color onto the destination.
/// All three parameters are unpremultiplied. Returns a premultiplied result.
///
/// This routine is the same as `IPApplyBlendedColor` in the Impeller shader
/// library.
#[inline]
fn apply_blended_color(mut dst: Color, mut src: Color, blend_result: Vector3) -> Color {
    dst = dst.premultiply();
    src =
        // Use the blended color for areas where the source and destination
        // colors overlap.
        from_rgb(blend_result, src.alpha * dst.alpha).premultiply() +
        // Use the original source color for any remaining non-overlapping
        // areas.
        src.premultiply() * (1.0f32 - dst.alpha);

    // Source-over composite the blended source color atop the destination.
    src + dst * (1.0f32 - src.alpha)
}

#[inline]
fn do_color_blend(dst: Color, src: Color, blend_rgb_func: &dyn Fn(Vector3, Vector3) -> Vector3) -> Color {
    let blend_result = blend_rgb_func(to_rgb(dst), to_rgb(src));
    apply_blended_color(dst, src, blend_result).unpremultiply()
}

#[inline]
fn do_color_blend_components(
    dst: Color,
    src: Color,
    blend_func: &dyn Fn(Scalar, Scalar) -> Scalar,
) -> Color {
    let blend_result = Vector3::new(
        blend_func(dst.red, src.red),
        blend_func(dst.green, src.green),
        blend_func(dst.blue, src.blue),
    );
    apply_blended_color(dst, src, blend_result).unpremultiply()
}

impl fmt::Display for Color {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        use crate::print::g;
        write!(f, "({}, {}, {}, {})", g(self.red), g(self.green), g(self.blue), g(self.alpha))
    }
}

impl fmt::Display for BlendMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "BlendMode::k{}", blend_mode_to_string(*self))
    }
}
