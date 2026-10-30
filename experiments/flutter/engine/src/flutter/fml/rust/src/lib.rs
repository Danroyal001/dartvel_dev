// Not an upstream file: the crate root of the Rust port of flutter/fml.
//
// Each module ports the flutter/fml file at the same path and names it in
// its first line; `*_unittest(s)` modules port the upstream gtest files of
// the same name. See README.md.

pub mod ascii_trie;
pub mod backtrace;
pub mod base32;
pub mod closure;
pub mod command_line;
pub mod concurrent_message_loop;
pub mod container;
pub mod cpu_affinity;
pub mod delayed_task;
pub mod eintr_wrapper;
pub mod endianness;
pub mod file;
pub mod hash_combine;
pub mod hex_codec;
pub mod log_level;
pub mod log_settings;
pub mod logging;
pub mod make_copyable;
pub mod mapping;
pub mod math;
pub mod memory;
pub mod message_loop;
pub mod message_loop_impl;
pub mod message_loop_task_queues;
pub mod native_library;
pub mod paths;
pub mod platform;
pub mod posix_wrappers;
pub mod process;
pub mod raster_thread_merger;
pub mod safe_math;
pub mod shared_thread_merger;
pub mod string_conversion;
pub mod synchronization;
pub mod task_queue_id;
pub mod task_runner;
pub mod task_runner_util;
pub mod task_source;
pub mod task_source_grade;
pub mod thread;
pub mod time;
pub mod trace_event;
pub mod unique_fd;
pub mod unique_object;
pub mod wakeable;

#[cfg(test)]
mod ascii_trie_unittests;
#[cfg(test)]
mod base32_unittest;
#[cfg(test)]
mod closure_unittests;
#[cfg(test)]
mod endianness_unittests;
#[cfg(test)]
mod hash_combine_unittests;
#[cfg(test)]
mod hex_codec_unittest;
#[cfg(test)]
mod logging_unittests;
#[cfg(test)]
mod math_unittests;
#[cfg(test)]
mod message_loop_unittests;
#[cfg(test)]
mod message_loop_task_queues_merge_unmerge_unittests;
#[cfg(test)]
mod message_loop_task_queues_unittests;
#[cfg(test)]
mod raster_thread_merger_unittests;
#[cfg(test)]
mod string_conversion_unittests;
#[cfg(test)]
mod task_runner_util_unittests;
#[cfg(test)]
mod task_source_unittests;
#[cfg(test)]
mod thread_unittests;
