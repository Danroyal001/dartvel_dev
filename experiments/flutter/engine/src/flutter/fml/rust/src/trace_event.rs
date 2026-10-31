// Port of flutter/fml/trace_event.h and flutter/fml/trace_event.cc (the
// non-Fuchsia branches).
//
// fml's tracing does not need the Dart VM: it calls whatever timeline event
// handler was installed with `trace_set_timeline_event_handler` (the Dart VM
// installs one when it starts), for labels the allowlist admits, stamping
// events with the installed micros source (which reports -1 until one is
// set). The Dart API contributes only the event type enum, copied below.
// With no handler installed every event is dropped.
//
// `FLUTTER_TIMELINE_ENABLED` is upstream's switch between that and a build
// where every function is a no-op (`FLUTTER_RELEASE` on platforms other than
// Android and Fuchsia); here it is off when the crate is built with the
// `flutter_release` feature.
//
// The macros are upstream's, in snake case: `TRACE_EVENT0(c, n)` is
// `trace_event0!(c, n)`, and like it ends the event when the enclosing block
// ends. Variadic argument lists are written as upstream writes them:
// `fml_trace_event!(c, n, "k1", v1, "k2", v2)`. Flow ids are slices (upstream
// passes a count and a pointer), and the handler gets slices too.
//
// Upstream's handler and micros source are atomics, as here; its allowlist is
// unsynchronized, and here behind a lock. Argument values are `SmallString`s
// (libc++'s short strings, see small_string.rs), and the argument and flow-id
// lists the handler is given live on the stack.

use std::sync::RwLock;
use std::sync::atomic::{AtomicPtr, AtomicUsize, Ordering};

use crate::ascii_trie::AsciiTrie;
use crate::small_string::SmallString;
use crate::time::time_point::TimePoint;

pub const FLUTTER_TIMELINE_ENABLED: bool = !cfg!(feature = "flutter_release");

/// The Dart VM's `Dart_Timeline_Event_Type` (dart_tools_api.h), values
/// unchanged.
#[allow(non_camel_case_types)]
#[repr(i32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dart_Timeline_Event_Type {
    Dart_Timeline_Event_Begin,          // Phase = 'B'.
    Dart_Timeline_Event_End,            // Phase = 'E'.
    Dart_Timeline_Event_Instant,        // Phase = 'i'.
    Dart_Timeline_Event_Duration,       // Phase = 'X'.
    Dart_Timeline_Event_Async_Begin,    // Phase = 'b'.
    Dart_Timeline_Event_Async_End,      // Phase = 'e'.
    Dart_Timeline_Event_Async_Instant,  // Phase = 'n'.
    Dart_Timeline_Event_Counter,        // Phase = 'C'.
    Dart_Timeline_Event_Flow_Begin,     // Phase = 's'.
    Dart_Timeline_Event_Flow_Step,      // Phase = 't'.
    Dart_Timeline_Event_Flow_End,       // Phase = 'f'.
}

use Dart_Timeline_Event_Type::*;

pub type TraceArg<'a> = &'a str;
pub type TraceIDArg = i64;

/// (label, timestamp0, timestamp1_or_async_id, flow_ids, type,
/// argument_names, argument_values).
pub type TimelineEventHandler =
    fn(&str, i64, i64, &[i64], Dart_Timeline_Event_Type, &[&str], &[&str]);

pub type TimelineMicrosSource = fn() -> i64;

fn default_micros_source() -> i64 {
    -1
}

static G_ALLOWLIST: RwLock<Option<AsciiTrie>> = RwLock::new(None);
// `std::atomic<TimelineEventHandler>` and `std::atomic<TimelineMicrosSource>`:
// function pointers stored as data pointers (null for no handler, and for
// the default micros source).
static G_TIMELINE_EVENT_HANDLER: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());
static G_TIMELINE_MICROS_SOURCE: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());

// A function pointer survives the round trip through `*mut ()`.
const _: () = assert!(size_of::<TimelineEventHandler>() == size_of::<*mut ()>());
const _: () = assert!(size_of::<TimelineMicrosSource>() == size_of::<*mut ()>());

/// `gTimelineEventHandler.load(std::memory_order_relaxed)`.
fn load_handler() -> Option<TimelineEventHandler> {
    let p = G_TIMELINE_EVENT_HANDLER.load(Ordering::Relaxed);
    if p.is_null() {
        return None;
    }
    // SAFETY: the only non-null values ever stored are TimelineEventHandlers
    // cast to `*mut ()` (trace_set_timeline_event_handler), and a function
    // pointer cast to a same-sized data pointer and back is the same
    // function pointer (sizes asserted above).
    Some(unsafe { std::mem::transmute::<*mut (), TimelineEventHandler>(p) })
}

/// `gTimelineMicrosSource.load()()`.
fn micros() -> i64 {
    let p = G_TIMELINE_MICROS_SOURCE.load(Ordering::SeqCst);
    if p.is_null() {
        return default_micros_source();
    }
    // SAFETY: the only non-null values ever stored are TimelineMicrosSources
    // cast to `*mut ()` (trace_set_timeline_micros_source); see load_handler.
    let source = unsafe { std::mem::transmute::<*mut (), TimelineMicrosSource>(p) };
    source()
}

/// Up to this many flow ids or arguments are passed to the handler from the
/// stack; more go through a Vec.
const ON_STACK: usize = 8;

/// Calls `f` with `items` mapped by `map`, collected on the stack when they
/// fit (upstream builds a std::vector).
#[inline]
fn with_mapped<'a, T, U: Copy + Default, R>(
    items: &'a [T],
    map: impl Fn(&'a T) -> U,
    f: impl FnOnce(&[U]) -> R,
) -> R {
    if items.len() <= ON_STACK {
        let mut buf = [U::default(); ON_STACK];
        for (slot, item) in buf.iter_mut().zip(items) {
            *slot = map(item);
        }
        f(&buf[..items.len()])
    } else {
        let mapped: Vec<U> = items.iter().map(map).collect();
        f(&mapped)
    }
}

/// `reinterpret_cast<const int64_t*>(flow_ids)`.
#[inline]
fn with_signed<R>(flow_ids: &[u64], f: impl FnOnce(&[i64]) -> R) -> R {
    with_mapped(flow_ids, |&id| id as i64, f)
}

#[allow(clippy::too_many_arguments)]
fn flutter_timeline_event(
    label: &str,
    timestamp0: i64,
    timestamp1_or_async_id: i64,
    flow_ids: &[i64],
    type_: Dart_Timeline_Event_Type,
    argument_names: &[&str],
    argument_values: &[&str],
) {
    if let Some(handler) = load_handler() {
        let allowed = match &*G_ALLOWLIST.read().unwrap_or_else(|e| e.into_inner()) {
            Some(allowlist) => allowlist.query(label),
            // An empty trie admits everything.
            None => true,
        };
        if allowed {
            handler(
                label,
                timestamp0,
                timestamp1_or_async_id,
                flow_ids,
                type_,
                argument_names,
                argument_values,
            );
        }
    }
}

pub fn trace_set_allowlist(allowlist: &[impl AsRef<[u8]>]) {
    if !FLUTTER_TIMELINE_ENABLED {
        return;
    }
    let mut trie = AsciiTrie::new();
    trie.fill(allowlist);
    *G_ALLOWLIST.write().unwrap_or_else(|e| e.into_inner()) = Some(trie);
}

pub fn trace_set_timeline_event_handler(handler: Option<TimelineEventHandler>) {
    if !FLUTTER_TIMELINE_ENABLED {
        return;
    }
    let p = match handler {
        Some(handler) => handler as *mut (),
        None => std::ptr::null_mut(),
    };
    G_TIMELINE_EVENT_HANDLER.store(p, Ordering::SeqCst);
}

pub fn trace_has_timeline_event_handler() -> bool {
    FLUTTER_TIMELINE_ENABLED && load_handler().is_some()
}

pub fn trace_get_timeline_micros() -> i64 {
    if !FLUTTER_TIMELINE_ENABLED {
        return -1;
    }
    micros()
}

pub fn trace_set_timeline_micros_source(source: TimelineMicrosSource) {
    if !FLUTTER_TIMELINE_ENABLED {
        return;
    }
    G_TIMELINE_MICROS_SOURCE.store(source as *mut (), Ordering::SeqCst);
}

pub fn trace_nonce() -> usize {
    if !FLUTTER_TIMELINE_ENABLED {
        return 0;
    }
    static LAST_ITEM: AtomicUsize = AtomicUsize::new(0);
    LAST_ITEM.fetch_add(1, Ordering::SeqCst).wrapping_add(1)
}

/// `TraceTimelineEvent` with a timestamp.
#[allow(clippy::too_many_arguments)]
pub fn trace_timeline_event_at(
    _category_group: TraceArg,
    name: TraceArg,
    timestamp_micros: i64,
    identifier: TraceIDArg,
    flow_ids: &[u64],
    type_: Dart_Timeline_Event_Type,
    c_names: &[&str],
    values: &[SmallString],
) {
    if !FLUTTER_TIMELINE_ENABLED {
        return;
    }
    let argument_count = c_names.len().min(values.len());

    with_mapped(&values[..argument_count], |v: &SmallString| v.as_str(), |c_values| {
        with_signed(flow_ids, |flow_ids| {
            flutter_timeline_event(
                name,
                timestamp_micros,
                identifier,
                flow_ids,
                type_,
                &c_names[..argument_count],
                c_values,
            )
        })
    });
}

/// `TraceTimelineEvent` stamped with the micros source.
pub fn trace_timeline_event(
    category_group: TraceArg,
    name: TraceArg,
    identifier: TraceIDArg,
    flow_ids: &[u64],
    type_: Dart_Timeline_Event_Type,
    c_names: &[&str],
    values: &[SmallString],
) {
    if !FLUTTER_TIMELINE_ENABLED {
        return;
    }
    trace_timeline_event_at(category_group, name, micros(), identifier, flow_ids, type_, c_names, values);
}

/// What an argument value of a trace event becomes (`TraceToString`):
/// strings as they are, a TimePoint as its nanoseconds since the epoch,
/// numbers as `std::to_string` writes them (floats with "%f", bools as 1 and
/// 0). The text is a `SmallString`, as short as libc++'s.
pub trait TraceToString {
    fn trace_to_string(self) -> SmallString;
}

impl TraceToString for &str {
    fn trace_to_string(self) -> SmallString {
        SmallString::from(self)
    }
}

impl TraceToString for String {
    fn trace_to_string(self) -> SmallString {
        SmallString::from(self)
    }
}

impl TraceToString for &String {
    fn trace_to_string(self) -> SmallString {
        SmallString::from(self.as_str())
    }
}

impl TraceToString for SmallString {
    fn trace_to_string(self) -> SmallString {
        self
    }
}

/// Formats into a stack buffer and keeps the text as a SmallString, without
/// a heap String in between when it fits.
fn formatted(args: std::fmt::Arguments<'_>) -> SmallString {
    struct Buf {
        bytes: [u8; 64],
        len: usize,
    }
    impl std::fmt::Write for Buf {
        fn write_str(&mut self, s: &str) -> std::fmt::Result {
            let end = self.len + s.len();
            if end > self.bytes.len() {
                return Err(std::fmt::Error);
            }
            self.bytes[self.len..end].copy_from_slice(s.as_bytes());
            self.len = end;
            Ok(())
        }
    }
    let mut buf = Buf { bytes: [0; 64], len: 0 };
    if std::fmt::Write::write_fmt(&mut buf, args).is_ok() {
        if let Ok(text) = std::str::from_utf8(&buf.bytes[..buf.len]) {
            return SmallString::from(text);
        }
    }
    SmallString::from(std::fmt::format(args))
}

impl TraceToString for TimePoint {
    fn trace_to_string(self) -> SmallString {
        formatted(format_args!("{}", self.to_epoch_delta().to_nanoseconds()))
    }
}

macro_rules! integer_trace_to_string {
    ($($t:ty),*) => {$(
        impl TraceToString for $t {
            fn trace_to_string(self) -> SmallString {
                formatted(format_args!("{}", self))
            }
        }
    )*};
}
integer_trace_to_string!(i8, i16, i32, i64, isize, u8, u16, u32, u64, usize);

impl TraceToString for bool {
    fn trace_to_string(self) -> SmallString {
        SmallString::from(if self { "1" } else { "0" })
    }
}

/// `std::to_string(double)`: printf's "%f".
fn printf_f(value: f64) -> SmallString {
    if value.is_nan() {
        return SmallString::from(if value.is_sign_negative() { "-nan" } else { "nan" });
    }
    if value.is_infinite() {
        return SmallString::from(if value < 0.0 { "-inf" } else { "inf" });
    }
    formatted(format_args!("{value:.6}"))
}

impl TraceToString for f64 {
    fn trace_to_string(self) -> SmallString {
        printf_f(self)
    }
}

impl TraceToString for f32 {
    fn trace_to_string(self) -> SmallString {
        printf_f(self as f64)
    }
}

/// `SplitArguments(key, value, ...)`: the keys, and the values as strings,
/// in arrays (upstream fills two vectors).
#[macro_export]
macro_rules! trace_split_arguments {
    ($($key:expr, $value:expr),* $(,)?) => {{
        let keys: [&str; $crate::trace_split_arguments!(@count $($key)*)] = [$($key),*];
        let values: [$crate::small_string::SmallString; $crate::trace_split_arguments!(@count $($key)*)] =
            [$($crate::trace_event::TraceToString::trace_to_string($value)),*];
        (keys, values)
    }};
    (@count) => { 0usize };
    (@count $head:tt $($tail:tt)*) => { 1usize + $crate::trace_split_arguments!(@count $($tail)*) };
}

/// `TraceCounter(category, name, identifier, args...)` with the arguments
/// already split.
pub fn trace_counter(
    category: TraceArg,
    name: TraceArg,
    identifier: TraceIDArg,
    keys: &[&str],
    values: &[SmallString],
) {
    if FLUTTER_TIMELINE_ENABLED {
        trace_timeline_event(category, name, identifier, &[], Dart_Timeline_Event_Counter, keys, values);
    }
}

/// `TraceCounterNopHACK`: Fuchsia's counter, which records nothing.
pub fn trace_counter_nop_hack(_category: TraceArg, _name: TraceArg, _identifier: TraceIDArg) {}

/// `TraceEvent(category, name, flow_id_count, flow_ids, args...)` with the
/// arguments already split.
pub fn trace_event(
    category: TraceArg,
    name: TraceArg,
    flow_ids: &[u64],
    keys: &[&str],
    values: &[SmallString],
) {
    if FLUTTER_TIMELINE_ENABLED {
        trace_timeline_event(category, name, 0, flow_ids, Dart_Timeline_Event_Begin, keys, values);
    }
}

pub fn trace_event0(_category_group: TraceArg, name: TraceArg, flow_ids: &[u64]) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), 0, flow_ids, Dart_Timeline_Event_Begin, &[], &[]));
    }
}

pub fn trace_event1(
    _category_group: TraceArg,
    name: TraceArg,
    flow_ids: &[u64],
    arg1_name: TraceArg,
    arg1_val: TraceArg,
) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), 0, flow_ids,
            Dart_Timeline_Event_Begin,
            &[arg1_name],
            &[arg1_val],
        ));
    }
}

#[allow(clippy::too_many_arguments)]
pub fn trace_event2(
    _category_group: TraceArg,
    name: TraceArg,
    flow_ids: &[u64],
    arg1_name: TraceArg,
    arg1_val: TraceArg,
    arg2_name: TraceArg,
    arg2_val: TraceArg,
) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), 0, flow_ids,
            Dart_Timeline_Event_Begin,
            &[arg1_name, arg2_name],
            &[arg1_val, arg2_val],
        ));
    }
}

pub fn trace_event_end(name: TraceArg) {
    if FLUTTER_TIMELINE_ENABLED {
        flutter_timeline_event(name, micros(), 0, &[], Dart_Timeline_Event_End, &[], &[]);
    }
}

/// `TraceEventAsyncComplete(category, name, begin, end, args...)` with the
/// arguments already split: an async begin at `begin` and an async end at
/// `end` (swapped if begin is later), under a fresh nonce.
pub fn trace_event_async_complete(
    category_group: TraceArg,
    name: TraceArg,
    mut begin: TimePoint,
    mut end: TimePoint,
    keys: &[&str],
    values: &[SmallString],
) {
    if !FLUTTER_TIMELINE_ENABLED {
        return;
    }
    let identifier = trace_nonce();

    if begin > end {
        std::mem::swap(&mut begin, &mut end);
    }

    let begin_micros = begin.to_epoch_delta().to_microseconds();
    let end_micros = end.to_epoch_delta().to_microseconds();

    trace_timeline_event_at(
        category_group,
        name,
        begin_micros,
        identifier as i64,
        &[],
        Dart_Timeline_Event_Async_Begin,
        keys,
        values,
    );

    trace_timeline_event_at(
        category_group,
        name,
        end_micros,
        identifier as i64,
        &[],
        Dart_Timeline_Event_Async_End,
        keys,
        values,
    );
}

pub fn trace_event_async_begin0(
    _category_group: TraceArg,
    name: TraceArg,
    id: TraceIDArg,
    flow_ids: &[u64],
) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), id, flow_ids, Dart_Timeline_Event_Async_Begin, &[], &[]));
    }
}

pub fn trace_event_async_end0(_category_group: TraceArg, name: TraceArg, id: TraceIDArg) {
    if FLUTTER_TIMELINE_ENABLED {
        flutter_timeline_event(name, micros(), id, &[], Dart_Timeline_Event_Async_End, &[], &[]);
    }
}

pub fn trace_event_async_begin1(
    _category_group: TraceArg,
    name: TraceArg,
    id: TraceIDArg,
    flow_ids: &[u64],
    arg1_name: TraceArg,
    arg1_val: TraceArg,
) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), id, flow_ids,
            Dart_Timeline_Event_Async_Begin,
            &[arg1_name],
            &[arg1_val],
        ));
    }
}

pub fn trace_event_async_end1(
    _category_group: TraceArg,
    name: TraceArg,
    id: TraceIDArg,
    arg1_name: TraceArg,
    arg1_val: TraceArg,
) {
    if FLUTTER_TIMELINE_ENABLED {
        flutter_timeline_event(name, micros(), id, &[], Dart_Timeline_Event_Async_End, &[arg1_name], &[arg1_val]);
    }
}

pub fn trace_event_instant0(_category_group: TraceArg, name: TraceArg, flow_ids: &[u64]) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), 0, flow_ids, Dart_Timeline_Event_Instant, &[], &[]));
    }
}

pub fn trace_event_instant1(
    _category_group: TraceArg,
    name: TraceArg,
    flow_ids: &[u64],
    arg1_name: TraceArg,
    arg1_val: TraceArg,
) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), 0, flow_ids,
            Dart_Timeline_Event_Instant,
            &[arg1_name],
            &[arg1_val],
        ));
    }
}

#[allow(clippy::too_many_arguments)]
pub fn trace_event_instant2(
    _category_group: TraceArg,
    name: TraceArg,
    flow_ids: &[u64],
    arg1_name: TraceArg,
    arg1_val: TraceArg,
    arg2_name: TraceArg,
    arg2_val: TraceArg,
) {
    if FLUTTER_TIMELINE_ENABLED {
        with_signed(flow_ids, |flow_ids| flutter_timeline_event(name, micros(), 0, flow_ids,
            Dart_Timeline_Event_Instant,
            &[arg1_name, arg2_name],
            &[arg1_val, arg2_val],
        ));
    }
}

pub fn trace_event_flow_begin0(_category_group: TraceArg, name: TraceArg, id: TraceIDArg) {
    if FLUTTER_TIMELINE_ENABLED {
        flutter_timeline_event(name, micros(), id, &[], Dart_Timeline_Event_Flow_Begin, &[], &[]);
    }
}

pub fn trace_event_flow_step0(_category_group: TraceArg, name: TraceArg, id: TraceIDArg) {
    if FLUTTER_TIMELINE_ENABLED {
        flutter_timeline_event(name, micros(), id, &[], Dart_Timeline_Event_Flow_Step, &[], &[]);
    }
}

pub fn trace_event_flow_end0(_category_group: TraceArg, name: TraceArg, id: TraceIDArg) {
    if FLUTTER_TIMELINE_ENABLED {
        flutter_timeline_event(name, micros(), id, &[], Dart_Timeline_Event_Flow_End, &[], &[]);
    }
}

/// Ends the event named `label` when dropped (what the macros leave in the
/// enclosing block).
pub struct ScopedInstantEnd<'a> {
    label_: &'a str,
}

impl<'a> ScopedInstantEnd<'a> {
    pub fn new(str: &'a str) -> ScopedInstantEnd<'a> {
        ScopedInstantEnd { label_: str }
    }
}

impl Drop for ScopedInstantEnd<'_> {
    fn drop(&mut self) {
        trace_event_end(self.label_);
    }
}

/// A flow: begun when made, stepped, and ended explicitly or when dropped.
pub struct TraceFlow<'a> {
    label_: &'a str,
    nonce_: u64,
}

impl<'a> TraceFlow<'a> {
    pub fn new(label: &'a str) -> TraceFlow<'a> {
        let this = TraceFlow { label_: label, nonce_: trace_nonce() as u64 };
        trace_event0("flutter", this.label_, &[this.nonce_]);
        trace_event_flow_begin0("flutter", this.label_, this.nonce_ as i64);
        trace_event_end(this.label_);
        this
    }

    /// The move constructor: takes `other`'s flow, leaving it ended.
    pub fn take(other: &mut TraceFlow<'a>) -> TraceFlow<'a> {
        let this = TraceFlow { label_: other.label_, nonce_: other.nonce_ };
        other.nonce_ = 0;
        this
    }

    pub fn step(&self, label: Option<&str>) {
        let label = label.unwrap_or(self.label_);
        trace_event0("flutter", label, &[self.nonce_]);
        trace_event_flow_step0("flutter", label, self.nonce_ as i64);
        trace_event_end(label);
    }

    pub fn end(&mut self, label: Option<&str>) {
        if self.nonce_ != 0 {
            let label = label.unwrap_or(self.label_);
            trace_event0("flutter", label, &[self.nonce_]);
            trace_event_flow_end0("flutter", label, self.nonce_ as i64);
            trace_event_end(label);
            self.nonce_ = 0;
        }
    }
}

impl Drop for TraceFlow<'_> {
    fn drop(&mut self) {
        let label = self.label_;
        self.end(Some(label));
    }
}

/// `FML_TRACE_COUNTER(category_group, name, counter_id, arg1, ...)`.
#[macro_export]
macro_rules! fml_trace_counter {
    ($category_group:expr, $name:expr, $counter_id:expr, $($args:expr),+ $(,)?) => {{
        let (keys, values) = $crate::trace_split_arguments!($($args),+);
        $crate::trace_event::trace_counter($category_group, $name, $counter_id, &keys, &values);
    }};
}

/// `FML_TRACE_EVENT_WITH_FLOW_IDS(category_group, name, flow_id_count,
/// flow_ids, ...)`.
#[macro_export]
macro_rules! fml_trace_event_with_flow_ids {
    ($category_group:expr, $name:expr, $flow_id_count:expr, $flow_ids:expr, $($args:expr),+ $(,)?) => {
        let (keys, values) = $crate::trace_split_arguments!($($args),+);
        $crate::trace_event::trace_event(
            $category_group,
            $name,
            &$flow_ids[..$flow_id_count],
            &keys,
            &values,
        );
        let _trace_end = $crate::trace_event::ScopedInstantEnd::new($name);
    };
}

/// `FML_TRACE_EVENT(category_group, name, ...)`.
#[macro_export]
macro_rules! fml_trace_event {
    ($category_group:expr, $name:expr, $($args:expr),+ $(,)?) => {
        $crate::fml_trace_event_with_flow_ids!($category_group, $name, 0, [0u64; 0], $($args),+);
    };
}

#[macro_export]
macro_rules! trace_event0_with_flow_ids {
    ($category_group:expr, $name:expr, $flow_id_count:expr, $flow_ids:expr) => {
        $crate::trace_event::trace_event0($category_group, $name, &$flow_ids[..$flow_id_count]);
        let _trace_end = $crate::trace_event::ScopedInstantEnd::new($name);
    };
}

#[macro_export]
macro_rules! trace_event0 {
    ($category_group:expr, $name:expr) => {
        $crate::trace_event0_with_flow_ids!($category_group, $name, 0, [0u64; 0]);
    };
}

#[macro_export]
macro_rules! trace_event1_with_flow_ids {
    ($category_group:expr, $name:expr, $flow_id_count:expr, $flow_ids:expr, $arg1_name:expr, $arg1_val:expr) => {
        $crate::trace_event::trace_event1(
            $category_group,
            $name,
            &$flow_ids[..$flow_id_count],
            $arg1_name,
            $arg1_val,
        );
        let _trace_end = $crate::trace_event::ScopedInstantEnd::new($name);
    };
}

#[macro_export]
macro_rules! trace_event1 {
    ($category_group:expr, $name:expr, $arg1_name:expr, $arg1_val:expr) => {
        $crate::trace_event1_with_flow_ids!($category_group, $name, 0, [0u64; 0], $arg1_name, $arg1_val);
    };
}

#[macro_export]
macro_rules! trace_event2 {
    ($category_group:expr, $name:expr, $arg1_name:expr, $arg1_val:expr, $arg2_name:expr, $arg2_val:expr) => {
        $crate::trace_event::trace_event2(
            $category_group,
            $name,
            &[],
            $arg1_name,
            $arg1_val,
            $arg2_name,
            $arg2_val,
        );
        let _trace_end = $crate::trace_event::ScopedInstantEnd::new($name);
    };
}

#[macro_export]
macro_rules! trace_event_async_begin0_with_flow_ids {
    ($category_group:expr, $name:expr, $id:expr, $flow_id_count:expr, $flow_ids:expr) => {
        $crate::trace_event::trace_event_async_begin0(
            $category_group,
            $name,
            $id,
            &$flow_ids[..$flow_id_count],
        );
    };
}

#[macro_export]
macro_rules! trace_event_async_begin0 {
    ($category_group:expr, $name:expr, $id:expr) => {
        $crate::trace_event::trace_event_async_begin0($category_group, $name, $id, &[]);
    };
}

#[macro_export]
macro_rules! trace_event_async_end0 {
    ($category_group:expr, $name:expr, $id:expr) => {
        $crate::trace_event::trace_event_async_end0($category_group, $name, $id);
    };
}

#[macro_export]
macro_rules! trace_event_async_begin1 {
    ($category_group:expr, $name:expr, $id:expr, $arg1_name:expr, $arg1_val:expr) => {
        $crate::trace_event::trace_event_async_begin1(
            $category_group,
            $name,
            $id,
            &[],
            $arg1_name,
            $arg1_val,
        );
    };
}

/// Upstream's `TRACE_EVENT_ASYNC_END1` passes a flow id count and flow ids
/// that `TraceEventAsyncEnd1` does not take, so it does not compile; this
/// one calls the function with the arguments it takes.
#[macro_export]
macro_rules! trace_event_async_end1 {
    ($category_group:expr, $name:expr, $id:expr, $arg1_name:expr, $arg1_val:expr) => {
        $crate::trace_event::trace_event_async_end1($category_group, $name, $id, $arg1_name, $arg1_val);
    };
}

#[macro_export]
macro_rules! trace_event_instant0 {
    ($category_group:expr, $name:expr) => {
        $crate::trace_event::trace_event_instant0($category_group, $name, &[]);
    };
}

#[macro_export]
macro_rules! trace_event_instant1 {
    ($category_group:expr, $name:expr, $arg1_name:expr, $arg1_val:expr) => {
        $crate::trace_event::trace_event_instant1($category_group, $name, &[], $arg1_name, $arg1_val);
    };
}

#[macro_export]
macro_rules! trace_event_instant2 {
    ($category_group:expr, $name:expr, $arg1_name:expr, $arg1_val:expr, $arg2_name:expr, $arg2_val:expr) => {
        $crate::trace_event::trace_event_instant2(
            $category_group,
            $name,
            &[],
            $arg1_name,
            $arg1_val,
            $arg2_name,
            $arg2_val,
        );
    };
}

#[macro_export]
macro_rules! trace_flow_begin {
    ($category:expr, $name:expr, $id:expr) => {
        $crate::trace_event::trace_event_flow_begin0($category, $name, $id);
    };
}

#[macro_export]
macro_rules! trace_flow_step {
    ($category:expr, $name:expr, $id:expr) => {
        $crate::trace_event::trace_event_flow_step0($category, $name, $id);
    };
}

#[macro_export]
macro_rules! trace_flow_end {
    ($category:expr, $name:expr, $id:expr) => {
        $crate::trace_event::trace_event_flow_end0($category, $name, $id);
    };
}

/// `TRACE_EVENT2_INT`: `trace_event2!` with integer values, as
/// `std::to_string` writes them.
#[macro_export]
macro_rules! trace_event2_int {
    ($category_group:expr, $name:expr, $arg1_name:expr, $arg1_val:expr, $arg2_name:expr, $arg2_val:expr) => {
        let __arg1_val_str = $crate::trace_event::TraceToString::trace_to_string($arg1_val);
        let __arg2_val_str = $crate::trace_event::TraceToString::trace_to_string($arg2_val);
        $crate::trace_event2!(
            $category_group,
            $name,
            $arg1_name,
            __arg1_val_str.as_str(),
            $arg2_name,
            __arg2_val_str.as_str()
        );
    };
}
