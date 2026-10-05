//! Brotli and Zstandard for the assets a web-server binary carries.
//!
//! The build compresses every asset once, at the highest level, and the
//! binary serves those bytes as they are to a client that accepts the
//! encoding. Decoding is only for a client that does not, and it happens once
//! per asset: the result is kept. Both directions are here so the build and
//! the binary cannot disagree about a format -- the build loads this same
//! library to encode.
//!
//! The caller owns every buffer. Encoding writes into `out` and says how many
//! bytes it wrote, or that the result would not fit, which the build treats as
//! "not worth compressing": an asset whose encoding is no smaller than it is
//! stored as it is.

/// Brotli, `Content-Encoding: br`.
pub const AW_CODEC_BROTLI: i32 = 1;
/// Zstandard, `Content-Encoding: zstd`.
pub const AW_CODEC_ZSTD: i32 = 2;

/// The encoding did not fit in the output buffer.
pub const AW_CODEC_TOO_LARGE: i64 = -2;
/// An unknown codec, a level out of range, or a null buffer.
pub const AW_CODEC_BAD_ARGUMENT: i64 = -3;
/// The input is not a valid stream of the codec, or decodes to a different
/// length than the caller said.
pub const AW_CODEC_CORRUPT: i64 = -4;

/// The largest window a browser's zstd decoder is required to accept for
/// `Content-Encoding: zstd` (RFC 8878, section 3: 8 MiB).
const ZSTD_HTTP_WINDOW_LOG: i32 = 23;

/// A writer into a fixed buffer that reports running out of room rather than
/// growing or truncating.
struct Bounded<'a> {
    out: &'a mut [u8],
    at: usize,
    overflowed: bool,
}

impl std::io::Write for Bounded<'_> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let room = self.out.len() - self.at;
        if buf.len() > room {
            self.overflowed = true;
            return Err(std::io::Error::new(std::io::ErrorKind::WriteZero, "full"));
        }
        self.out[self.at..self.at + buf.len()].copy_from_slice(buf);
        self.at += buf.len();
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn encode(codec: i32, level: i32, input: &[u8], out: &mut [u8]) -> i64 {
    match codec {
        AW_CODEC_BROTLI => {
            if !(0..=11).contains(&level) {
                return AW_CODEC_BAD_ARGUMENT;
            }
            let params = brotli::enc::BrotliEncoderParams {
                quality: level,
                // 16 MiB, the largest window every browser's decoder takes.
                lgwin: 24,
                size_hint: input.len(),
                ..Default::default()
            };
            let mut writer = Bounded { out, at: 0, overflowed: false };
            match brotli::BrotliCompress(&mut &input[..], &mut writer, &params) {
                Ok(_) => writer.at as i64,
                Err(_) if writer.overflowed => AW_CODEC_TOO_LARGE,
                Err(_) => AW_CODEC_CORRUPT,
            }
        }
        AW_CODEC_ZSTD => {
            if !(1..=22).contains(&level) {
                return AW_CODEC_BAD_ARGUMENT;
            }
            let mut compressor = match zstd::bulk::Compressor::new(level) {
                Ok(c) => c,
                Err(_) => return AW_CODEC_BAD_ARGUMENT,
            };
            // Long-distance matching finds repeats far apart, within the
            // window a browser accepts: past it the stream is one no browser
            // decodes.
            if compressor
                .set_parameter(zstd::zstd_safe::CParameter::WindowLog(ZSTD_HTTP_WINDOW_LOG as u32))
                .and_then(|_| {
                    compressor.set_parameter(zstd::zstd_safe::CParameter::EnableLongDistanceMatching(true))
                })
                .and_then(|_| compressor.include_checksum(true))
                .is_err()
            {
                return AW_CODEC_BAD_ARGUMENT;
            }
            match compressor.compress_to_buffer(input, out) {
                Ok(n) => n as i64,
                Err(_) => AW_CODEC_TOO_LARGE,
            }
        }
        _ => AW_CODEC_BAD_ARGUMENT,
    }
}

fn decode(codec: i32, input: &[u8], out: &mut [u8]) -> i64 {
    match codec {
        AW_CODEC_BROTLI => {
            let mut writer = Bounded { out, at: 0, overflowed: false };
            match brotli::BrotliDecompress(&mut &input[..], &mut writer) {
                Ok(()) if writer.at == writer.out.len() => writer.at as i64,
                _ => AW_CODEC_CORRUPT,
            }
        }
        AW_CODEC_ZSTD => {
            let mut decompressor = match zstd::bulk::Decompressor::new() {
                Ok(d) => d,
                Err(_) => return AW_CODEC_CORRUPT,
            };
            if decompressor
                .set_parameter(zstd::zstd_safe::DParameter::WindowLogMax(ZSTD_HTTP_WINDOW_LOG as u32))
                .is_err()
            {
                return AW_CODEC_CORRUPT;
            }
            // One byte of room past the promised length: a stream that fills
            // it decodes to more than it should, which is corruption rather
            // than a fit.
            let mut spare = vec![0u8; out.len() + 1];
            match decompressor.decompress_to_buffer(input, &mut spare) {
                Ok(n) if n == out.len() => {
                    out.copy_from_slice(&spare[..n]);
                    n as i64
                }
                _ => AW_CODEC_CORRUPT,
            }
        }
        _ => AW_CODEC_BAD_ARGUMENT,
    }
}

/// Compresses `input_len` bytes at `input` with `codec` at `level` into the
/// `out_cap` bytes at `out`. Returns the length written, or a negative
/// `AW_CODEC_*`.
///
/// # Safety
/// `input` must be valid for `input_len` bytes and `out` for `out_cap`.
#[no_mangle]
pub unsafe extern "C" fn aw_codec_encode(
    codec: i32,
    level: i32,
    input: *const u8,
    input_len: usize,
    out: *mut u8,
    out_cap: usize,
) -> i64 {
    if input.is_null() || out.is_null() {
        return AW_CODEC_BAD_ARGUMENT;
    }
    let input = std::slice::from_raw_parts(input, input_len);
    let out = std::slice::from_raw_parts_mut(out, out_cap);
    encode(codec, level, input, out)
}

/// Decompresses `input_len` bytes at `input`, encoded with `codec`, into
/// exactly the `out_len` bytes at `out`. Returns `out_len`, or a negative
/// `AW_CODEC_*` -- a stream that decodes to any other length is corrupt.
///
/// # Safety
/// `input` must be valid for `input_len` bytes and `out` for `out_len`.
#[no_mangle]
pub unsafe extern "C" fn aw_codec_decode(
    codec: i32,
    input: *const u8,
    input_len: usize,
    out: *mut u8,
    out_len: usize,
) -> i64 {
    if input.is_null() || (out.is_null() && out_len > 0) {
        return AW_CODEC_BAD_ARGUMENT;
    }
    let input = std::slice::from_raw_parts(input, input_len);
    let out: &mut [u8] = if out_len == 0 {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(out, out_len)
    };
    decode(codec, input, out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Vec<u8> {
        let mut text = Vec::new();
        for i in 0..4000 {
            text.extend_from_slice(format!("<p class=\"line\">line {i} of the page</p>\n").as_bytes());
        }
        text
    }

    fn round_trip(codec: i32, level: i32) {
        let input = sample();
        let mut out = vec![0u8; input.len()];
        let n = unsafe {
            aw_codec_encode(codec, level, input.as_ptr(), input.len(), out.as_mut_ptr(), out.len())
        };
        assert!(n > 0, "encoded to {n}");
        assert!((n as usize) < input.len() / 10, "{n} bytes is barely compressed");
        let mut back = vec![0u8; input.len()];
        let m = unsafe {
            aw_codec_decode(codec, out.as_ptr(), n as usize, back.as_mut_ptr(), back.len())
        };
        assert_eq!(m, input.len() as i64);
        assert_eq!(back, input);
    }

    #[test]
    fn brotli_round_trips_at_the_highest_level() {
        round_trip(AW_CODEC_BROTLI, 11);
    }

    #[test]
    fn zstd_round_trips_at_a_high_level() {
        round_trip(AW_CODEC_ZSTD, 19);
    }

    #[test]
    fn brotli_output_is_what_a_standard_decoder_reads() {
        let input = sample();
        let mut out = vec![0u8; input.len()];
        let n = unsafe {
            aw_codec_encode(AW_CODEC_BROTLI, 11, input.as_ptr(), input.len(), out.as_mut_ptr(), out.len())
        };
        assert!(n > 0);
        let mut decoded = Vec::new();
        brotli::BrotliDecompress(&mut &out[..n as usize], &mut decoded).unwrap();
        assert_eq!(decoded, input);
    }

    #[test]
    fn zstd_output_stays_within_the_window_browsers_accept() {
        let input = sample();
        let mut out = vec![0u8; input.len()];
        let n = unsafe {
            aw_codec_encode(AW_CODEC_ZSTD, 19, input.as_ptr(), input.len(), out.as_mut_ptr(), out.len())
        };
        assert!(n > 0);
        let mut decoder = zstd::bulk::Decompressor::new().unwrap();
        decoder
            .set_parameter(zstd::zstd_safe::DParameter::WindowLogMax(ZSTD_HTTP_WINDOW_LOG as u32))
            .unwrap();
        assert_eq!(decoder.decompress(&out[..n as usize], input.len()).unwrap(), input);
    }

    #[test]
    fn an_encoding_that_does_not_fit_says_so() {
        let input: Vec<u8> = (0..4096u32).map(|i| (i.wrapping_mul(2654435761) >> 13) as u8).collect();
        let mut out = vec![0u8; 16];
        for codec in [AW_CODEC_BROTLI, AW_CODEC_ZSTD] {
            let n = unsafe {
                aw_codec_encode(codec, 11, input.as_ptr(), input.len(), out.as_mut_ptr(), out.len())
            };
            assert_eq!(n, AW_CODEC_TOO_LARGE, "codec {codec}");
        }
    }

    #[test]
    fn a_stream_of_the_wrong_length_is_corrupt() {
        let input = sample();
        let mut out = vec![0u8; input.len()];
        for codec in [AW_CODEC_BROTLI, AW_CODEC_ZSTD] {
            let n = unsafe {
                aw_codec_encode(codec, 9, input.as_ptr(), input.len(), out.as_mut_ptr(), out.len())
            };
            assert!(n > 0);
            let mut short = vec![0u8; input.len() - 1];
            let m = unsafe {
                aw_codec_decode(codec, out.as_ptr(), n as usize, short.as_mut_ptr(), short.len())
            };
            assert_eq!(m, AW_CODEC_CORRUPT, "codec {codec} short");
            let mut long = vec![0u8; input.len() + 1];
            let m = unsafe {
                aw_codec_decode(codec, out.as_ptr(), n as usize, long.as_mut_ptr(), long.len())
            };
            assert_eq!(m, AW_CODEC_CORRUPT, "codec {codec} long");
        }
    }

    #[test]
    fn garbage_is_corrupt_rather_than_a_crash() {
        let garbage = [0xffu8; 64];
        let mut out = vec![0u8; 1024];
        for codec in [AW_CODEC_BROTLI, AW_CODEC_ZSTD] {
            let m = unsafe {
                aw_codec_decode(codec, garbage.as_ptr(), garbage.len(), out.as_mut_ptr(), out.len())
            };
            assert_eq!(m, AW_CODEC_CORRUPT, "codec {codec}");
        }
    }

    #[test]
    fn an_unknown_codec_or_level_is_refused() {
        let input = sample();
        let mut out = vec![0u8; input.len()];
        let refused = |codec, level| unsafe {
            aw_codec_encode(codec, level, input.as_ptr(), input.len(), out.clone().as_mut_ptr(), out.len())
        };
        assert_eq!(refused(0, 5), AW_CODEC_BAD_ARGUMENT);
        assert_eq!(refused(AW_CODEC_BROTLI, 12), AW_CODEC_BAD_ARGUMENT);
        assert_eq!(refused(AW_CODEC_ZSTD, 23), AW_CODEC_BAD_ARGUMENT);
        let _ = &mut out;
    }
}
