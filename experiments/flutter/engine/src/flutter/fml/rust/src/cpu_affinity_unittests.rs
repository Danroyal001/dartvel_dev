// Port of flutter/fml/cpu_affinity_unittests.cc.

use super::cpu_affinity::*;
use super::file::{ScopedTemporaryDirectory, open_file_read_only, write_atomically};
use super::mapping::DataMapping;

fn speeds(list: &[(usize, i64)]) -> Vec<CpuIndexAndSpeed> {
    list.iter().map(|&(index, speed)| CpuIndexAndSpeed { index, speed }).collect()
}

#[test]
fn non_android_platform_defaults() {
    assert!(efficiency_core_count().is_none());
    assert!(request_affinity(CpuAffinity::kEfficiency));
}

#[test]
fn normal_slow_med_fast_cores() {
    let tracker = CPUSpeedTracker::new(speeds(&[(0, 1), (1, 2), (2, 3)]));

    assert!(tracker.is_valid());
    assert_eq!(tracker.get_indices(CpuAffinity::kEfficiency)[0], 0);
    assert_eq!(tracker.get_indices(CpuAffinity::kPerformance)[0], 2);
    assert_eq!(tracker.get_indices(CpuAffinity::kNotPerformance).len(), 2);
    assert_eq!(tracker.get_indices(CpuAffinity::kNotPerformance)[0], 0);
    assert_eq!(tracker.get_indices(CpuAffinity::kNotPerformance)[1], 1);
    assert_eq!(tracker.get_indices(CpuAffinity::kNotEfficiency).len(), 2);
    assert_eq!(tracker.get_indices(CpuAffinity::kNotEfficiency)[0], 1);
    assert_eq!(tracker.get_indices(CpuAffinity::kNotEfficiency)[1], 2);
}

#[test]
fn no_cpu_data() {
    let tracker = CPUSpeedTracker::new(Vec::new());

    assert!(!tracker.is_valid());
}

#[test]
fn all_same_speed() {
    let tracker = CPUSpeedTracker::new(speeds(&[(0, 1), (1, 1), (2, 1)]));

    assert!(!tracker.is_valid());
}

#[test]
fn single_core() {
    let tracker = CPUSpeedTracker::new(speeds(&[(0, 1)]));

    assert!(!tracker.is_valid());
}

#[test]
fn file_parsing() {
    let base_dir = ScopedTemporaryDirectory::new();
    assert!(base_dir.fd().is_valid());

    // Generate a fake CPU speed file
    let test_data = DataMapping::from_string("12345");
    assert!(write_atomically(base_dir.fd(), "test_file", &test_data));

    let file = open_file_read_only(base_dir.fd(), "test_file");
    assert!(file.is_valid());

    // Open file and parse speed.
    let result = read_int_from_file(format!("{}/test_file", base_dir.path()));
    assert!(result.is_some());
    assert_eq!(result.unwrap_or(0), 12345);
}

#[test]
fn file_parsing_with_non_number() {
    let base_dir = ScopedTemporaryDirectory::new();
    assert!(base_dir.fd().is_valid());

    // Generate a fake CPU speed file
    let test_data = DataMapping::from_string("whoa this isnt a number");
    assert!(write_atomically(base_dir.fd(), "test_file", &test_data));

    let file = open_file_read_only(base_dir.fd(), "test_file");
    assert!(file.is_valid());

    // Open file and parse speed.
    let result = read_int_from_file(format!("{}/test_file", base_dir.path()));
    assert!(result.is_none());
}

#[test]
fn missing_file_parsing() {
    let result = read_int_from_file("/does_not_exist");
    assert!(result.is_none());
}
