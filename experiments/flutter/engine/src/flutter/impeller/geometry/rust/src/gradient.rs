// flutter/impeller/geometry/gradient.h, gradient.cc

use crate::color::Color;
use crate::scalar::{Scalar, scalar_nearly_equal};

/// The largest texture size the gradient is sampled into.
const kMaxGradientTextureSize: u32 = 1024;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct GradientData {
    pub colors: Vec<Color>,
}

/// Populate GradientData with the interpolated colors for the linear
/// gradient described by colors and stops.
///
/// Upstream indexes past `colors` when the stops do not end at the last
/// color (undefined); the port panics there.
pub fn create_gradient_buffer(colors: &[Color], stops: &[Scalar]) -> GradientData {
    fml::fml_dcheck_at!(
        "flutter/impeller/geometry/gradient.cc",
        19,
        "stops.size() == colors.size()",
        stops.len() == colors.len()
    );

    let texture_size: u32;
    if stops.len() == 2 {
        texture_size = colors.len() as u32;
    } else {
        let mut minimum_delta: f64 = 1.0;
        let minimum_allowable_delta: f64 = 1.0 / (kMaxGradientTextureSize as f64 - 1.0);
        for i in 1..stops.len() {
            let value: Scalar = stops[i] - stops[i - 1];
            // Smaller than kEhCloseEnough
            if (value as f64) <= minimum_allowable_delta {
                minimum_delta = minimum_allowable_delta;
                break;
            }
            if (value as f64) < minimum_delta {
                minimum_delta = value as f64;
            }
        }
        // Avoid creating textures that are absurdly large due to stops that
        // are very close together.
        // TODO(jonahwilliams): this should use a platform specific max
        // texture size.
        texture_size = (1.0 / minimum_delta).round() as u32 + 1;
    }

    let mut result = GradientData::default();
    if texture_size as usize == colors.len() && colors.len() <= kMaxGradientTextureSize as usize {
        // Simple case: the texture is exactly the colors.
        result.colors = colors.to_vec();
    } else {
        result.colors.reserve(texture_size as usize);
        let mut previous_color = colors[0];
        let mut previous_stop: f64 = 0.0;
        let mut previous_color_index: usize = 0;

        result.colors.push(previous_color);

        let mut i: u32 = 1;
        while i < texture_size.wrapping_sub(1) {
            let scaled_i: f64 = i as f64 / (texture_size as f64 - 1.0);
            let next_color = colors[previous_color_index + 1];
            let next_stop: Scalar = stops[previous_color_index + 1];
            // We're at a stop, so this color is the stop color.
            if scalar_nearly_equal(scaled_i as Scalar, next_stop) {
                result.colors.push(next_color);

                previous_color = next_color;
                previous_stop = next_stop as f64;
                previous_color_index += 1;
            } else if scaled_i < next_stop as f64 {
                // We're between stops, so interpolate.
                let t: f64 = (scaled_i - previous_stop) / (next_stop as f64 - previous_stop);
                let mixed_color = Color::lerp(previous_color, next_color, t as Scalar);
                result.colors.push(mixed_color);
            } else {
                // We've passed the next stop: advance and recheck this i.
                previous_color = next_color;
                previous_stop = next_stop as f64;
                previous_color_index += 1;
                i = i.wrapping_sub(1);
            }
            i = i.wrapping_add(1);
        }
        result.colors.push(*colors.last().unwrap());
    }
    result
}
