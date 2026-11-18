// Port of flutter/fml/cpu_affinity.h and flutter/fml/cpu_affinity.cc (the
// non-Android branch).
//
// Android's EfficiencyCoreCount and RequestAffinity
// (platform/android/cpu_affinity.cc) read
// /sys/devices/system/cpu/cpu<N>/cpufreq/cpuinfo_max_freq and call
// sched_setaffinity; they are not ported. Elsewhere upstream answers "no
// count" and "granted" without touching the system, as this does.

#[allow(non_camel_case_types)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CpuAffinity {
    /// Request CPU affinity for the performance cores.
    ///
    /// Generally speaking, only the UI and Raster thread should use this
    /// option.
    kPerformance,

    /// Request CPU affinity for the efficiency cores.
    kEfficiency,

    /// Request affinity for all non-performance cores.
    kNotPerformance,

    /// Request affinity for all non-efficiency cores.
    kNotEfficiency,
}

pub fn efficiency_core_count() -> Option<usize> {
    None
}

pub fn request_affinity(_affinity: CpuAffinity) -> bool {
    true
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CpuIndexAndSpeed {
    /// The index of the given CPU.
    pub index: usize,
    /// CPU speed in kHZ
    pub speed: i64,
}

pub struct CPUSpeedTracker {
    valid_: bool,
    cpu_speeds_: Vec<CpuIndexAndSpeed>,
    efficiency_: Vec<usize>,
    performance_: Vec<usize>,
    not_performance_: Vec<usize>,
    not_efficiency_: Vec<usize>,
}

impl CPUSpeedTracker {
    pub fn new(data: Vec<CpuIndexAndSpeed>) -> CPUSpeedTracker {
        let mut this = CPUSpeedTracker {
            valid_: false,
            cpu_speeds_: data,
            efficiency_: Vec::new(),
            performance_: Vec::new(),
            not_performance_: Vec::new(),
            not_efficiency_: Vec::new(),
        };
        let mut max_speed: Option<i64> = None;
        let mut min_speed: Option<i64> = None;
        for data in &this.cpu_speeds_ {
            if max_speed.is_none() || data.speed > max_speed.unwrap() {
                max_speed = Some(data.speed);
            }
            if min_speed.is_none() || data.speed < min_speed.unwrap() {
                min_speed = Some(data.speed);
            }
        }
        let (Some(max_speed_value), Some(min_speed_value)) = (max_speed, min_speed) else {
            return this;
        };
        if min_speed_value == max_speed_value {
            return this;
        }

        for data in &this.cpu_speeds_ {
            if data.speed == max_speed_value {
                this.performance_.push(data.index);
            } else {
                this.not_performance_.push(data.index);
            }
            if data.speed == min_speed_value {
                this.efficiency_.push(data.index);
            } else {
                this.not_efficiency_.push(data.index);
            }
        }

        this.valid_ = true;
        this
    }

    /// The class is valid if it has more than one CPU index and a distinct
    /// set of efficiency or performance CPUs.
    ///
    /// If all CPUs are the same speed this returns false, and all requests
    /// to set affinity are ignored.
    pub fn is_valid(&self) -> bool {
        self.valid_
    }

    /// Return the set of CPU indices for the requested CPU affinity.
    ///
    /// If the tracker is valid, this will always return a non-empty set.
    pub fn get_indices(&self, affinity: CpuAffinity) -> &Vec<usize> {
        match affinity {
            CpuAffinity::kPerformance => &self.performance_,
            CpuAffinity::kEfficiency => &self.efficiency_,
            CpuAffinity::kNotPerformance => &self.not_performance_,
            CpuAffinity::kNotEfficiency => &self.not_efficiency_,
        }
    }
}

/// `std::ifstream >> int64_t` as libc++ reads it: skip C-locale white
/// space; take an optional sign and then decimal digits, stopping at the
/// first other byte; convert with strtoll. No digits (or nothing to read)
/// leaves 0; a value past the range of int64_t saturates to its maximum or
/// minimum (libc++ sets failbit and stores the limit).
fn libcxx_extract_i64(bytes: &[u8]) -> i64 {
    let mut i = 0;
    while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\n' | 0x0b | 0x0c | b'\r') {
        i += 1;
    }
    let mut negative = false;
    if i < bytes.len() && (bytes[i] == b'+' || bytes[i] == b'-') {
        negative = bytes[i] == b'-';
        i += 1;
    }
    let digits_start = i;
    let mut magnitude: u128 = 0;
    let mut saturated = false;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        if !saturated {
            magnitude = magnitude * 10 + (bytes[i] - b'0') as u128;
            if magnitude > (i64::MAX as u128) + 1 {
                saturated = true;
            }
        }
        i += 1;
    }
    if i == digits_start {
        return 0;
    }
    if negative {
        if saturated || magnitude > (i64::MAX as u128) + 1 {
            i64::MIN
        } else {
            (magnitude as i128).wrapping_neg() as i64
        }
    } else if saturated || magnitude > i64::MAX as u128 {
        i64::MAX
    } else {
        magnitude as i64
    }
}

pub fn read_int_from_file(path: impl AsRef<std::path::Path>) -> Option<i64> {
    // A file that cannot be opened or read (a missing file, a directory)
    // reads as nothing, leaving the value 0.
    let contents = std::fs::read(path).unwrap_or_default();

    // Dont use stoi because if this data isnt a parseable number then it
    // will abort, as we compile with exceptions disabled.
    let speed = libcxx_extract_i64(&contents);
    if speed > 0 {
        return Some(speed);
    }
    None
}
