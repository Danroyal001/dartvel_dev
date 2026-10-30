// Port of flutter/fml/safe_math.h and flutter/fml/safe_math.cc.
//
// abseil's uint128 is Rust's u128.

/// Multiplies sizes, remembering whether any product overflowed.
#[derive(Clone, Copy, Debug, Default)]
pub struct SafeMath {
    overflow_detected_: bool,
}

impl SafeMath {
    pub fn new() -> SafeMath {
        SafeMath::default()
    }

    pub fn overflow_detected(&self) -> bool {
        self.overflow_detected_
    }

    pub fn mul(&mut self, x: usize, y: usize) -> usize {
        if std::mem::size_of::<usize>() == std::mem::size_of::<u64>() {
            self.mul64(x as u64, y as u64) as usize
        } else {
            self.mul32(x as u32, y as u32) as usize
        }
    }

    fn mul32(&mut self, x: u32, y: u32) -> u32 {
        let big_x = x as u64;
        let big_y = y as u64;
        let result = big_x * big_y;
        if result >> 32 != 0 {
            self.overflow_detected_ = true;
        }
        result as u32
    }

    fn mul64(&mut self, x: u64, y: u64) -> u64 {
        if x <= u32::MAX as u64 && y <= u32::MAX as u64 {
            return x * y;
        }

        let big_x = x as u128;
        let big_y = y as u128;
        let result = big_x * big_y;
        if (result >> 64) as u64 != 0 {
            self.overflow_detected_ = true;
        }
        result as u64
    }
}
