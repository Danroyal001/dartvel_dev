// Not an upstream file: the port's side of the oracle (see oracle/fml_dump.cc,
// which this mirrors suite by suite and line by line).
//
//   fml_dump <suite> <seed> <cases>     suite: time strings codec hash endian
//                                              trie queues loop merger thread
//                                              logging file mapping paths
//                                              cmdline misc affinity native
//                                              trace backtrace all
//   fml_dump bench <name> <iterations>  name: queues time strings hash
//                                              dispatch loop thread concurrent
//                                              merger file mapping paths
//                                              cmdline trace
//   fml_dump fatal <seed> 0             (internal) the logging suite's child
//   fml_dump crash <signal> 0           (internal) the backtrace suite's child

use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use fml::ascii_trie::AsciiTrie;
use fml::base32::{base32_decode, base32_encode};
use fml::endianness::{big_endian_to_arch, byte_swap, little_endian_to_arch};
use fml::hash_combine::ByteString;
use fml::hex_codec::hex_encode;
use fml::string_conversion::{join, path_to_utf8, try_utf16_to_utf8, try_utf8_to_utf16};
use fml::message_loop_task_queues::MessageLoopTaskQueues;
use fml::synchronization::count_down_latch::CountDownLatch;
use fml::task_queue_id::TaskQueueId;
use fml::task_source_grade::TaskSourceGrade;
use fml::wakeable::Wakeable;
use fml::{hash_combine, hash_combine_seed};
use std::collections::BTreeMap;
use std::sync::atomic::AtomicBool;
use std::sync::atomic::AtomicI64;
use std::sync::atomic::AtomicUsize;
use std::sync::atomic::Ordering::{Relaxed, SeqCst};
use std::sync::{Arc, Condvar, Mutex, Weak};

use fml::closure::closure;
use fml::concurrent_message_loop::ConcurrentMessageLoop;
use fml::log_level::{LogSeverity, kLogFatal};
use fml::log_settings::{
    LogSettings, ScopedSetLogSettings, get_log_settings, get_min_log_level, set_log_settings,
};
use fml::logging::testing::LogCapture;
use fml::logging::{LogMessage, get_vlog_verbosity, should_create_log_message};
use fml::memory::ref_ptr::RefPtr;
use fml::memory::task_runner_checker::TaskRunnerChecker;
use fml::message_loop::MessageLoop;
use fml::raster_thread_merger::RasterThreadMerger;
use fml::synchronization::waitable_event::AutoResetWaitableEvent;
use fml::task_runner::{BasicTaskRunner, TaskRunner};
use fml::task_runner_util::{ConditionalBasicTaskRunner, WrapperBasicTaskRunner};
use fml::thread::{Thread, ThreadConfig, ThreadPriority};

use fml::time::time_delta::{
    TimeDelta, kDefaultFrameBudget, refresh_rate_to_frame_budget, timespec,
};
use fml::time::time_point::TimePoint;

// ---------------------------------------------------------------- rng ------

struct Rng {
    s: u64,
}

impl Rng {
    fn next(&mut self) -> u64 {
        self.s = self.s.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.s;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    fn chance(&mut self, one_in: u64) -> bool {
        self.below(one_in) == 0
    }
}

fn edge_i64(r: &mut Rng) -> i64 {
    match r.below(12) {
        0 => 0,
        1 => 1,
        2 => -1,
        3 => i64::MIN,
        4 => i64::MAX,
        5 => i64::MIN + 1,
        6 => i64::MAX - 1,
        7 => 1000000000,
        8 => r.below(2001) as i64 - 1000,
        9 => r.below(20000000001) as i64 - 10000000000,
        10 => i64::MAX / 1000 + r.below(3) as i64 - 1,
        _ => r.next() as i64,
    }
}

fn bounded_f64(r: &mut Rng, bound: f64) -> f64 {
    match r.below(8) {
        0 => 0.0,
        1 => -0.0,
        2 => 0.5,
        3 => -1e-9,
        _ => {
            let unit = (r.next() >> 11) as f64 / 9007199254740992.0;
            let v = unit * bound;
            if r.chance(2) { -v } else { v }
        }
    }
}

fn cmp<T: Ord>(a: T, b: T) -> i32 {
    match a.cmp(&b) {
        std::cmp::Ordering::Less => -1,
        std::cmp::Ordering::Equal => 0,
        std::cmp::Ordering::Greater => 1,
    }
}

// Everything goes through one buffer, as C++ stdio does, so output printed
// from inside a task closure lands in order.
static OUT: std::sync::Mutex<Vec<u8>> = std::sync::Mutex::new(Vec::new());
// Set in bench mode, where output is formatted and dropped, as the C++ driver
// formats it into /dev/null.
static DISCARD: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

fn discard_if_benching(out: &mut Vec<u8>) {
    if out.len() > 4096 && DISCARD.load(std::sync::atomic::Ordering::Relaxed) {
        out.clear();
    }
}

macro_rules! w {
    ($($arg:tt)*) => {{
        let mut out = OUT.lock().unwrap();
        write!(out, $($arg)*).unwrap();
        discard_if_benching(&mut out);
    }};
}
macro_rules! p {
    ($($arg:tt)*) => {{
        let mut out = OUT.lock().unwrap();
        writeln!(out, $($arg)*).unwrap();
        discard_if_benching(&mut out);
    }};
}

fn hex(s: &[u8]) {
    if s.is_empty() {
        w!("-");
        return;
    }
    for c in s {
        w!("{c:02x}");
    }
}

fn hex16(s: &[u16]) {
    if s.is_empty() {
        w!("-");
        return;
    }
    for c in s {
        w!("{c:04x}");
    }
}

// --------------------------------------------------------------- time ------

fn suite_time(r: &mut Rng, cases: i32) {
    p!("frame_budget {:016x}", kDefaultFrameBudget.count().to_bits());
    for i in 0..cases {
        let a = edge_i64(r);
        let b = edge_i64(r);
        p!("case {i} a={a} b={b}");
        p!("from {} {} {} {}",
            TimeDelta::from_nanoseconds(a).to_nanoseconds(),
            TimeDelta::from_microseconds(a).to_nanoseconds(),
            TimeDelta::from_milliseconds(a).to_nanoseconds(),
            TimeDelta::from_seconds(a).to_nanoseconds()
        );
        let da = TimeDelta::from_nanoseconds(a);
        let db = TimeDelta::from_nanoseconds(b);
        p!("to {} {} {}", da.to_microseconds(), da.to_milliseconds(), da.to_seconds());
        p!("tof {:016x} {:016x} {:016x} {:016x}",
            da.to_nanoseconds_f().to_bits(),
            da.to_microseconds_f().to_bits(),
            da.to_milliseconds_f().to_bits(),
            da.to_seconds_f().to_bits()
        );
        p!("add {} sub {} mul {}",
            (da + db).to_nanoseconds(),
            (da - db).to_nanoseconds(),
            (da * b).to_nanoseconds()
        );
        if b != 0 && !(a == i64::MIN && b == -1) {
            p!("div {} divd {} mod {}",
                (da / b).to_nanoseconds(),
                da / db,
                (da % db).to_nanoseconds()
            );
        } else {
            p!("div skip");
        }
        p!("cmp {} {} {} {}",
            cmp(da, db),
            (da == db) as i32,
            (da < db) as i32,
            (da >= db) as i32
        );
        let ts = timespec { tv_sec: a, tv_nsec: (b % 1000000000) as std::os::raw::c_long };
        p!("fromts {}", TimeDelta::from_timespec(ts).to_nanoseconds());
        let out = da.to_timespec();
        p!("tots {} {}", out.tv_sec, out.tv_nsec);
        let pa = TimePoint::from_ticks(a);
        let pb = TimePoint::from_epoch_delta(db);
        p!("tp {} {} {} {}",
            (pa - pb).to_nanoseconds(),
            (pa + db).to_epoch_delta().to_nanoseconds(),
            (pa - db).to_epoch_delta().to_nanoseconds(),
            cmp(pa, pb)
        );
        let s = bounded_f64(r, 9.0e9);
        let m = bounded_f64(r, 9.0e12);
        p!("fromf {} {}",
            TimeDelta::from_seconds_f(s).to_nanoseconds(),
            TimeDelta::from_milliseconds_f(m).to_nanoseconds()
        );
        let hz = r.below(240) as i64 + 1;
        let hzf = bounded_f64(r, 240.0);
        p!("budget {:016x} {:016x}",
            refresh_rate_to_frame_budget(hz).count().to_bits(),
            refresh_rate_to_frame_budget(hzf).count().to_bits()
        );
    }
    p!("minmax {} {} {} {}",
        TimeDelta::min().to_nanoseconds(),
        TimeDelta::max().to_nanoseconds(),
        TimePoint::min().to_epoch_delta().to_nanoseconds(),
        TimePoint::max().to_epoch_delta().to_nanoseconds()
    );
}

// ------------------------------------------------------------ strings ------

fn gen_utf16(r: &mut Rng) -> Vec<u16> {
    let mut s = Vec::new();
    let n = r.below(13) as i32;
    for _ in 0..n {
        match r.below(10) {
            0 => s.push((1 + r.below(127)) as u16),
            1 => s.push((0x80 + r.below(0xD800 - 0x80)) as u16),
            2 => s.push((0xE000 + r.below(0x2000)) as u16),
            3 => {
                let mut cp = 0x10000 + r.below(0x100000) as u32;
                cp -= 0x10000;
                s.push((0xD800 + (cp >> 10)) as u16);
                s.push((0xDC00 + (cp & 0x3FF)) as u16);
            }
            4 => {
                if r.chance(4) {
                    s.push((0xD800 + r.below(0x400)) as u16)
                }
            }
            5 => {
                if r.chance(4) {
                    s.push((0xDC00 + r.below(0x400)) as u16)
                }
            }
            6 => {
                if r.chance(6) {
                    s.push(0)
                }
            }
            7 => {
                const K_SPECIAL: [u16; 7] = [0xFFFE, 0xFFFF, 0xFEFF, 0x7FF, 0x800, 0xD7FF, 0xE000];
                s.push(K_SPECIAL[r.below(7) as usize]);
            }
            _ => s.push((b'a' as u64 + r.below(26)) as u16),
        }
    }
    s
}

fn push_utf8(s: &mut Vec<u8>, cp: u32) {
    if cp < 0x80 {
        s.push(cp as u8);
    } else if cp < 0x800 {
        s.push((0xC0 | (cp >> 6)) as u8);
        s.push((0x80 | (cp & 0x3F)) as u8);
    } else if cp < 0x10000 {
        s.push((0xE0 | (cp >> 12)) as u8);
        s.push((0x80 | ((cp >> 6) & 0x3F)) as u8);
        s.push((0x80 | (cp & 0x3F)) as u8);
    } else {
        s.push((0xF0 | (cp >> 18)) as u8);
        s.push((0x80 | ((cp >> 12) & 0x3F)) as u8);
        s.push((0x80 | ((cp >> 6) & 0x3F)) as u8);
        s.push((0x80 | (cp & 0x3F)) as u8);
    }
}

fn gen_utf8(r: &mut Rng) -> Vec<u8> {
    let mut s = Vec::new();
    let n = r.below(10) as i32;
    for _ in 0..n {
        match r.below(14) {
            0 => push_utf8(&mut s, 1 + r.below(127) as u32),
            1 => push_utf8(&mut s, 0x80 + r.below(0x780) as u32),
            2 => push_utf8(&mut s, 0x800 + r.below(0xD000) as u32),
            3 => push_utf8(&mut s, 0xE000 + r.below(0x2000) as u32),
            4 => push_utf8(&mut s, 0x10000 + r.below(0x100000) as u32),
            5 => {
                if r.chance(3) {
                    s.push(r.below(256) as u8)
                }
            }
            6 => {
                if r.chance(3) {
                    let cp = 0xD800 + r.below(0x800) as u32;
                    push_utf8(&mut s, cp);
                }
            }
            7 => {
                if r.chance(3) {
                    const K_OVERLONG: [&[u8]; 6] = [
                        b"\xC0\x80",
                        b"\xC1\xBF",
                        b"\xE0\x80\x80",
                        b"\xE0\x9F\xBF",
                        b"\xF0\x80\x80\x80",
                        b"\xF0\x8F\xBF\xBF",
                    ];
                    s.extend_from_slice(K_OVERLONG[r.below(6) as usize]);
                }
            }
            8 => {
                if r.chance(3) {
                    const K_BEYOND: [&[u8]; 6] = [
                        b"\xF4\x90\x80\x80",
                        b"\xF5\x80\x80\x80",
                        b"\xF7\xBF\xBF\xBF",
                        b"\xF8\x88\x80\x80\x80",
                        b"\xFF",
                        b"\xFE",
                    ];
                    s.extend_from_slice(K_BEYOND[r.below(6) as usize]);
                }
            }
            9 => {
                if r.chance(3) {
                    let mut full = Vec::new();
                    push_utf8(&mut full, 0x80 + r.below(0x10FF80) as u32);
                    let keep = 1 + r.below(full.len() as u64 - 1) as usize;
                    s.extend_from_slice(&full[..keep]);
                }
            }
            10 => {
                if r.chance(6) {
                    s.push(0)
                }
            }
            11 => s.extend_from_slice(b"\xEF\xBB\xBF"),
            _ => s.push(b'a' + r.below(26) as u8),
        }
    }
    s
}

fn gen_bytes(r: &mut Rng, max_len: i32) -> Vec<u8> {
    let n = r.below(max_len as u64 + 1) as i32;
    (0..n).map(|_| r.below(256) as u8).collect()
}

fn suite_strings(r: &mut Rng, cases: i32) {
    for i in 0..cases {
        p!("case {i}");
        let u16s = gen_utf16(r);
        w!("u16 ");
        hex16(&u16s);
        w!(" -> ");
        match try_utf16_to_utf8(&u16s) {
            Ok(s) => hex(s.as_bytes()),
            Err(_) => w!("ERR"),
        }
        w!("\n");

        let u8s = gen_utf8(r);
        w!("u8 ");
        hex(&u8s);
        w!(" -> ");
        match try_utf8_to_utf16(&u8s) {
            Ok(s) => hex16(&s),
            Err(_) => w!("ERR"),
        }
        w!("\n");

        let mut parts = Vec::new();
        let n = r.below(5) as i32;
        for _ in 0..n {
            let mut part = String::new();
            let len = r.below(4) as i32;
            for _ in 0..len {
                part.push((b'a' + r.below(26) as u8) as char);
            }
            parts.push(part);
        }
        const K_DELIMS: [&str; 4] = [",", ", ", "", "--"];
        let delim = K_DELIMS[r.below(4) as usize];
        w!("join ");
        hex(join(&parts, delim).as_bytes());
        w!("\n");

        let path_bytes = gen_bytes(r, 8);
        w!("path ");
        hex(&path_to_utf8(Path::new(std::ffi::OsStr::from_bytes(&path_bytes))));
        w!("\n");
    }
}

// -------------------------------------------------------------- codec ------

fn gen_base32_text(r: &mut Rng) -> Vec<u8> {
    const K_ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    const K_INVALID: [u8; 12] = [b'=', b'a', b'1', b'8', b'0', b'9', b':', b'@', b'[', b' ', 0x80, 0xff];
    let mut s = Vec::new();
    let n = r.below(17) as i32;
    for _ in 0..n {
        if r.chance(25) {
            s.push(K_INVALID[r.below(K_INVALID.len() as u64) as usize]);
        } else {
            s.push(K_ALPHABET[r.below(32) as usize]);
        }
    }
    s
}

fn suite_codec(r: &mut Rng, cases: i32) {
    for i in 0..cases {
        p!("case {i}");
        let bytes = gen_bytes(r, 20);
        let enc = base32_encode(&bytes);
        w!("b32e ");
        hex(&bytes);
        w!(" -> {} ", enc.0 as i32);
        hex(enc.1.as_bytes());
        let round = base32_decode(&enc.1);
        w!(" rt {} ", round.0 as i32);
        hex(&round.1);
        w!("\n");

        let text = gen_base32_text(r);
        let dec = base32_decode(&text);
        w!("b32d ");
        hex(&text);
        w!(" -> {} ", dec.0 as i32);
        hex(&dec.1);
        w!("\n");

        w!("hex ");
        hex(hex_encode(&bytes).as_bytes());
        w!("\n");
    }
}

// --------------------------------------------------------------- hash ------

fn gen_hash_string(r: &mut Rng) -> String {
    let mut s = Vec::new();
    let n = match r.below(4) {
        0 => r.below(17) as i32,
        1 => 17 + r.below(16) as i32,
        2 => 33 + r.below(32) as i32,
        _ => 65 + r.below(200) as i32,
    };
    for _ in 0..n {
        if r.chance(8) {
            push_utf8(&mut s, 0x80 + r.below(0x700) as u32);
        } else {
            s.push(b' ' + r.below(95) as u8);
        }
    }
    String::from_utf8(s).unwrap()
}

fn gen_f32(r: &mut Rng) -> f32 {
    match r.below(4) {
        0 => 0.0,
        1 => -0.0,
        _ => f32::from_bits(r.next() as u32),
    }
}

fn gen_f64(r: &mut Rng) -> f64 {
    match r.below(4) {
        0 => 0.0,
        1 => -0.0,
        _ => f64::from_bits(r.next()),
    }
}

fn suite_hash(r: &mut Rng, cases: i32) {
    p!("empty {:016x}", hash_combine!());
    for i in 0..cases {
        p!("case {i}");
        let a = r.next() as i32;
        let b = edge_i64(r);
        let c = r.next() as u32;
        let d = r.chance(2);
        let s = gen_hash_string(r);
        let t = gen_bytes(r, 80);
        let t = ByteString(&t);
        let f = gen_f32(r);
        let g = gen_f64(r);
        let grade = grade_of(r.below(3));
        let u8v = r.next() as u8;
        let i16v = r.next() as i16;
        let ch = r.next() as i8;
        let u64v = r.next();
        let mut seed = r.next() as usize;
        p!("h1 {:016x}", hash_combine!(a));
        p!("h2 {:016x}", hash_combine!(b, c, d));
        p!("h3 {:016x}", hash_combine!(s));
        p!("h4 {:016x}", hash_combine!(t));
        p!("h5 {:016x}", hash_combine!(s, a, f, g));
        p!("h6 {:016x}", hash_combine!(grade, u8v, i16v, ch, u64v));
        hash_combine_seed!(&mut seed, a, s);
        p!("h7 {:016x}", seed);
    }
}

// ------------------------------------------------------------- endian ------

fn suite_endian(r: &mut Rng, cases: i32) {
    for _ in 0..cases {
        let x = r.next();
        p!(
            "x {:016x} {:02x} {:04x} {:08x} {:016x}",
            x,
            byte_swap(x as u8),
            byte_swap(x as u16),
            byte_swap(x as u32),
            byte_swap(x)
        );
        p!("s {} {} {}", byte_swap(x as i16), byte_swap(x as i32), byte_swap(x as i64));
        p!(
            "be {:08x} {:016x} le {:08x} {:016x}",
            big_endian_to_arch(x as u32),
            big_endian_to_arch(x),
            little_endian_to_arch(x as u32),
            little_endian_to_arch(x)
        );
    }
}

// --------------------------------------------------------------- trie ------

fn gen_trie_word(r: &mut Rng, alphabet: &[u8], max_len: i32) -> String {
    let n = r.below(max_len as u64 + 1) as i32;
    (0..n).map(|_| alphabet[r.below(alphabet.len() as u64) as usize] as char).collect()
}

fn suite_trie(r: &mut Rng, cases: i32) {
    for i in 0..cases {
        p!("case {i}");
        let mut trie = AsciiTrie::new();
        if !r.chance(8) {
            let mut entries = Vec::new();
            let n = r.below(6) as i32;
            for _ in 0..n {
                entries.push(gen_trie_word(r, b"abc", 4));
            }
            w!("fill");
            for e in &entries {
                w!(" '{e}'");
            }
            w!("\n");
            trie.fill(&entries);
        }
        for _ in 0..8 {
            let q = gen_trie_word(r, b"abcd", 5);
            p!("q '{q}' {}", trie.query(&q) as i32);
        }
    }
}

// ------------------------------------------------------------- queues ------

fn grade_of(n: u64) -> TaskSourceGrade {
    match n {
        0 => TaskSourceGrade::kUserInteraction,
        1 => TaskSourceGrade::kDartEventLoop,
        _ => TaskSourceGrade::kUnspecified,
    }
}

struct Recorder {
    queue_: usize,
}

impl Wakeable for Recorder {
    fn wake_up(&self, time_point: TimePoint) {
        p!("  wake {} {}", self.queue_, time_point.to_epoch_delta().to_nanoseconds());
    }
}

fn gen_target(r: &mut Rng) -> TimePoint {
    match r.below(16) {
        0 => TimePoint::max(),
        1 => TimePoint::min(),
        _ => TimePoint::from_ticks(r.below(100) as i64),
    }
}

fn suite_queues(r: &mut Rng, cases: i32) {
    let queues = MessageLoopTaskQueues::get_instance();
    let mut task_counter = 0;
    for i in 0..cases {
        p!("case {i}");
        let mut recorders: Vec<Arc<Recorder>> = Vec::new();
        let mut live: Vec<TaskQueueId> = Vec::new();
        let mut subsumed_by: BTreeMap<TaskQueueId, TaskQueueId> = BTreeMap::new();
        let mut pauses: BTreeMap<TaskQueueId, i32> = BTreeMap::new();
        let pick = |r: &mut Rng, live: &Vec<TaskQueueId>| live[r.below(live.len() as u64) as usize];
        let ops = 10 + r.below(60) as i32;
        for _ in 0..ops {
            let kind = if live.is_empty() { 0 } else { r.below(20) };
            match kind {
                0 | 1 => {
                    if live.len() >= 6 {
                        continue;
                    }
                    let q = queues.create_task_queue();
                    live.push(q);
                    p!("create {q}");
                    if r.chance(2) {
                        recorders.push(Arc::new(Recorder { queue_: q.value() }));
                        p!("wakeable {q}");
                        let weak: Weak<dyn Wakeable> =
                            Arc::downgrade(recorders.last().unwrap()) as Weak<dyn Wakeable>;
                        queues.set_wakeable(q, weak);
                    }
                }
                2..=6 => {
                    let q = pick(r, &live);
                    let t = gen_target(r);
                    let grade = grade_of(r.below(3));
                    let id = task_counter;
                    task_counter += 1;
                    p!("reg {q} task{id} {} {}", t.to_epoch_delta().to_nanoseconds(), grade as i32);
                    queues.register_task(q, Arc::new(move || p!("  run task{id}")), t, grade);
                }
                7..=9 => {
                    let q = pick(r, &live);
                    let from = if r.chance(8) {
                        TimePoint::max()
                    } else {
                        TimePoint::from_ticks(r.below(120) as i64)
                    };
                    p!("next {q} {}", from.to_epoch_delta().to_nanoseconds());
                    match queues.get_next_task_to_run(q, from) {
                        Some(task) => {
                            task();
                            let grade = MessageLoopTaskQueues::get_current_task_source_grade();
                            p!("  grade {}", grade as i32);
                        }
                        None => p!("  none"),
                    }
                }
                10 => {
                    let q = pick(r, &live);
                    let has = queues.has_pending_tasks(q) as i32;
                    let num = queues.get_num_pending_tasks(q);
                    p!("pending {q} {has} {num}");
                }
                11 => {
                    let a = pick(r, &live);
                    let b = pick(r, &live);
                    p!("merge {a} {b}");
                    let ok = queues.merge(a, b);
                    p!("  -> {}", ok as i32);
                    if ok && a != b {
                        subsumed_by.insert(b, a);
                    }
                }
                12 => {
                    let a = pick(r, &live);
                    let b = pick(r, &live);
                    p!("unmerge {a} {b}");
                    let ok = queues.unmerge(a, b);
                    p!("  -> {}", ok as i32);
                    if ok {
                        subsumed_by.remove(&b);
                    }
                }
                13 => {
                    let a = pick(r, &live);
                    let b = pick(r, &live);
                    let owns = queues.owns(a, b) as i32;
                    let set = queues.get_subsumed_task_queue_id(a);
                    w!("owns {a} {b} {owns} [");
                    for s in set {
                        w!(" {s}");
                    }
                    p!(" ]");
                }
                14 => {
                    let q = pick(r, &live);
                    let pause = *pauses.entry(q).or_insert(0) == 0 || r.chance(2);
                    p!("{} {q}", if pause { "pause" } else { "resume" });
                    if pause {
                        *pauses.get_mut(&q).unwrap() += 1;
                        queues.pause_secondary_source(q);
                    } else {
                        *pauses.get_mut(&q).unwrap() -= 1;
                        queues.resume_secondary_source(q);
                    }
                }
                15 => {
                    let q = pick(r, &live);
                    let key = r.below(5) as isize - 1;
                    let qv = q.value();
                    p!("observe {qv} {key}");
                    queues.add_task_observer(q, key, Arc::new(move || p!("  obs {qv} {key}")));
                }
                16 => {
                    let q = pick(r, &live);
                    let key = r.below(5) as isize - 1;
                    p!("unobserve {q} {key}");
                    queues.remove_task_observer(q, key);
                }
                17 => {
                    let q = pick(r, &live);
                    p!("notify {q}");
                    for observer in queues.get_observers_to_notify(q) {
                        observer();
                    }
                }
                18 => {
                    let q = pick(r, &live);
                    if subsumed_by.contains_key(&q) {
                        continue;
                    }
                    p!("dispose_tasks {q}");
                    queues.dispose_tasks(q);
                }
                _ => {
                    let q = pick(r, &live);
                    if subsumed_by.contains_key(&q) {
                        continue;
                    }
                    p!("dispose {q}");
                    queues.dispose(q);
                    let mut kept = Vec::new();
                    for &l in &live {
                        let gone = l == q || subsumed_by.get(&l) == Some(&q);
                        if gone {
                            subsumed_by.remove(&l);
                        } else {
                            kept.push(l);
                        }
                    }
                    live = kept;
                }
            }
        }
        for &q in &live {
            if !subsumed_by.contains_key(&q) {
                queues.dispose(q);
            }
        }
        drop(recorders);
    }
}

// -------------------------------------------------------------- bench ------

// flutter/fml/message_loop_task_queues_benchmark.cc, BM_RegisterAndGetTasks,
// one iteration of its loop body.
fn bench_register_and_get_tasks() {
    let task_queue = MessageLoopTaskQueues::get_instance();
    const NUM_TASK_QUEUES: usize = 10;
    const NUM_TASKS_PER_QUEUE: i32 = 100;
    let past = TimePoint::now();
    for _ in 0..NUM_TASK_QUEUES {
        task_queue.create_task_queue();
    }
    let tasks_registered = CountDownLatch::new(NUM_TASK_QUEUES);
    let tasks_done = CountDownLatch::new(NUM_TASK_QUEUES);
    std::thread::scope(|s| {
        for i in 0..NUM_TASK_QUEUES {
            let (tasks_registered, tasks_done) = (&tasks_registered, &tasks_done);
            s.spawn(move || {
                let task_runner_id = i;
                for _ in 0..NUM_TASKS_PER_QUEUE {
                    task_queue.register_task(
                        TaskQueueId::new(task_runner_id),
                        Arc::new(|| {}),
                        past,
                        TaskSourceGrade::kUnspecified,
                    );
                }
                tasks_registered.count_down();
                tasks_registered.wait();
                let now = TimePoint::now();
                let mut num_invocations = 0;
                loop {
                    let invocation =
                        task_queue.get_next_task_to_run(TaskQueueId::new(task_runner_id), now);
                    if invocation.is_none() {
                        break;
                    }
                    num_invocations += 1;
                }
                if num_invocations != NUM_TASKS_PER_QUEUE {
                    std::process::abort();
                }
                tasks_done.count_down();
            });
        }
        tasks_done.wait();
    });
}

fn peak_rss_kib() -> i64 {
    let Ok(status) = std::fs::read_to_string("/proc/self/status") else {
        return -1;
    };
    status
        .lines()
        .find_map(|l| l.strip_prefix("VmHWM:"))
        .and_then(|v| v.trim().trim_end_matches("kB").trim().parse().ok())
        .unwrap_or(-1)
}

fn bench(name: &str, iterations: i32) {
    DISCARD.store(true, std::sync::atomic::Ordering::Relaxed);
    let mut rounds = Vec::new();
    for i in 0..iterations {
        let start = std::time::Instant::now();
        if name == "queues" {
            bench_register_and_get_tasks();
        } else if name == "loop" {
            bench_loop();
        } else if name == "thread" {
            bench_thread();
        } else if name == "concurrent" {
            bench_concurrent();
        } else {
            let mut r = Rng { s: i as u64 };
            match name {
                "time" => suite_time(&mut r, 20000),
                "strings" => suite_strings(&mut r, 20000),
                "hash" => suite_hash(&mut r, 20000),
                "dispatch" => suite_queues(&mut r, 2000),
                "merger" => suite_merger(&mut r, 200),
                "file" => suite_file(&mut r, 250),
                "mapping" => suite_mapping(&mut r, 2000),
                "paths" => suite_paths(&mut r, 20000),
                "cmdline" => suite_cmdline(&mut r, 20000),
                "trace" => suite_trace(&mut r, 20000),
                _ => {
                    eprintln!("unknown bench {name}");
                    std::process::exit(2);
                }
            }
            // Output goes to /dev/null in the C++ driver; drop it here.
            OUT.lock().unwrap().clear();
        }
        rounds.push(start.elapsed().as_secs_f64() * 1e6);
    }
    rounds.sort_by(|a, b| a.partial_cmp(b).unwrap());
    eprintln!(
        "bench {name} fastest {:.1} us median {:.1} us peak_rss {} KiB",
        rounds[0],
        rounds[rounds.len() / 2],
        peak_rss_kib()
    );
}

// -------------------------------------------------------------- clock ------

// A controllable clock for TimePoint::set_clock_source: every now() returns
// the current fake time and then advances it by a step. The trace reads the
// clock with peek_now(), which does not advance it.
static G_FAKE_NOW: AtomicI64 = AtomicI64::new(0);
static G_FAKE_STEP: AtomicI64 = AtomicI64::new(1);

fn fake_now() -> TimePoint {
    TimePoint::from_ticks(G_FAKE_NOW.fetch_add(G_FAKE_STEP.load(SeqCst), SeqCst))
}

fn peek_now() -> i64 {
    G_FAKE_NOW.load(SeqCst)
}

// The clock starts at 100 or later and no task is posted more than 15 ticks
// in its past, so no target time is negative (see the C++ driver).
fn set_fake_clock(now: i64, step: i64) {
    G_FAKE_NOW.store(now, SeqCst);
    G_FAKE_STEP.store(step, SeqCst);
    TimePoint::set_clock_source(Some(fake_now));
}

fn current_runner() -> RefPtr<TaskRunner> {
    MessageLoop::get_current().get_task_runner()
}

// --------------------------------------------------------------- loop ------

struct LoopState {
    r: Rng,
    next_id: i32,
    budget: i32,
}

struct LoopCtx {
    st: Mutex<LoopState>,
}

impl LoopCtx {
    fn below(&self, n: u64) -> u64 {
        self.st.lock().unwrap().r.below(n)
    }
    fn chance(&self, n: u64) -> bool {
        self.st.lock().unwrap().r.chance(n)
    }
}

fn post_loop_task(c: &Arc<LoopCtx>, indent: &str) {
    let id = {
        let mut st = c.st.lock().unwrap();
        if st.budget <= 0 {
            return;
        }
        st.budget -= 1;
        let id = st.next_id;
        st.next_id += 1;
        id
    };
    let runner = current_runner();
    match c.below(7) {
        0 | 1 => {
            p!("{indent}post t{id}");
            runner.post_task(make_loop_task(c, id));
        }
        2 => {
            let d = c.below(40) as i64 - 8;
            p!("{indent}delay t{id} {d}");
            runner.post_delayed_task(make_loop_task(c, id), TimeDelta::from_nanoseconds(d));
        }
        3 => {
            let t = if c.chance(12) {
                TimePoint::max()
            } else {
                TimePoint::from_ticks(peek_now() + c.below(60) as i64 - 15)
            };
            p!("{indent}at t{id} {}", t.to_epoch_delta().to_nanoseconds());
            runner.post_task_for_time(make_loop_task(c, id), t);
        }
        4 => {
            p!("{indent}now-or-post t{id}");
            TaskRunner::run_now_or_post_task(&runner, make_loop_task(c, id));
        }
        5 => {
            p!("{indent}now-and-flush t{id}");
            TaskRunner::run_now_and_flush_messages(&runner, make_loop_task(c, id));
        }
        _ => {
            p!("{indent}post-queues t{id}");
            let task = make_loop_task(c, id);
            let target = TimePoint::from_ticks(peek_now());
            let grade = grade_of(c.below(3));
            MessageLoopTaskQueues::get_instance().register_task(
                MessageLoop::get_current_task_queue_id(),
                task,
                target,
                grade,
            );
        }
    }
}


fn add_loop_observer(c: &LoopCtx, indent: &str) {
    let key = c.below(4) as isize;
    if c.chance(3) {
        p!("{indent}unobserve {key}");
        MessageLoop::get_current().remove_task_observer(key);
    } else {
        p!("{indent}observe {key}");
        MessageLoop::get_current().add_task_observer(key, Arc::new(move || p!("    obs {key}")));
    }
}

fn make_loop_task(c: &Arc<LoopCtx>, id: i32) -> closure {
    let c = c.clone();
    Arc::new(move || {
        let runner = current_runner();
        p!("  run t{id} @{} on {}", peek_now(), runner.runs_tasks_on_current_thread() as i32);
        match c.below(12) {
            0..=2 => post_loop_task(&c, "   "),
            3 => {
                post_loop_task(&c, "   ");
                post_loop_task(&c, "   ");
            }
            4 => add_loop_observer(&c, "   "),
            5 => {
                let jump = c.below(25) as i64;
                p!("   jump {jump}");
                G_FAKE_NOW.fetch_add(jump, SeqCst);
            }
            6 => {
                if c.chance(4) {
                    p!("   nested flush");
                    MessageLoop::get_current().run_expired_tasks_now();
                    p!("   nested done");
                }
            }
            7 => {
                if c.chance(6) {
                    p!("   terminate");
                    MessageLoop::get_current().terminate();
                }
            }
            8 => {
                p!(
                    "   pending {}",
                    MessageLoopTaskQueues::get_instance()
                        .get_num_pending_tasks(runner.get_task_queue_id())
                );
            }
            _ => {}
        }
    })
}

fn loop_case(c: &Arc<LoopCtx>, i: i32) {
    let now = 100 + c.below(50) as i64;
    let step = 1 + c.below(4) as i64;
    set_fake_clock(now, step);
    let budget = 10 + c.below(40) as i32;
    c.st.lock().unwrap().budget = budget;
    p!("case {i} now {} step {} budget {budget}", peek_now(), G_FAKE_STEP.load(SeqCst));
    MessageLoop::ensure_initialized_for_current_thread();
    let loop_ = MessageLoop::get_current();
    let runner = loop_.get_task_runner();
    p!(
        "init {} {}",
        MessageLoop::is_initialized_for_current_thread() as i32,
        runner.runs_tasks_on_current_thread() as i32
    );
    let setup = 1 + c.below(8) as i32;
    for _ in 0..setup {
        match c.below(6) {
            0 => add_loop_observer(c, ""),
            1 => {
                p!("poll @{}", peek_now());
                loop_.run_expired_tasks_now();
            }
            _ => post_loop_task(c, ""),
        }
    }
    let end = peek_now() + 20 + c.below(150) as i64;
    p!("end at {end}");
    runner.post_task_for_time(
        Arc::new(|| {
            p!("  end @{}", peek_now());
            MessageLoop::get_current().terminate();
        }),
        TimePoint::from_ticks(end),
    );
    loop_.run();
    let queues = MessageLoopTaskQueues::get_instance();
    p!("ran @{} pending {}", peek_now(), queues.get_num_pending_tasks(runner.get_task_queue_id()));
    runner.post_task(Arc::new(|| p!("  never")));
    p!("after terminate pending {}", queues.get_num_pending_tasks(runner.get_task_queue_id()));
    loop_.run_expired_tasks_now();
}

fn suite_loop(r: &mut Rng, cases: i32) {
    for i in 0..cases {
        let c = Arc::new(LoopCtx { st: Mutex::new(LoopState { r: Rng { s: r.s }, next_id: 0, budget: 0 }) });
        let cc = c.clone();
        std::thread::spawn(move || loop_case(&cc, i)).join().unwrap();
        r.s = c.st.lock().unwrap().r.s;
    }
    TimePoint::set_clock_source(None);
}

// ------------------------------------------------------------- merger ------

/// A thread that initializes its message loop, hands it out and waits until
/// it is dropped, never running the loop.
struct ParkedLoop {
    loop_: MessageLoop,
    term: Arc<AutoResetWaitableEvent>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl ParkedLoop {
    fn new() -> Self {
        let slot: Arc<Mutex<Option<MessageLoop>>> = Arc::new(Mutex::new(None));
        let ready = Arc::new(AutoResetWaitableEvent::new());
        let term = Arc::new(AutoResetWaitableEvent::new());
        let thread = {
            let (slot, ready, term) = (slot.clone(), ready.clone(), term.clone());
            std::thread::spawn(move || {
                MessageLoop::ensure_initialized_for_current_thread();
                *slot.lock().unwrap() = Some(MessageLoop::get_current());
                ready.signal();
                term.wait();
            })
        };
        ready.wait();
        let loop_ = slot.lock().unwrap().take().unwrap();
        ParkedLoop { loop_, term, thread: Some(thread) }
    }
}

impl Drop for ParkedLoop {
    fn drop(&mut self) {
        self.term.signal();
        self.thread.take().unwrap().join().unwrap();
    }
}

struct SharedModel {
    enabled: bool,
    leases: BTreeMap<i32, usize>,
}

impl SharedModel {
    fn merged(&self) -> bool {
        self.leases.values().any(|&lease| lease != 0)
    }
}

struct MergerEntry {
    pair: i32,
    shared: usize,
    merger: RefPtr<RasterThreadMerger>,
}

struct MergerState {
    r: Rng,
    flushing: usize,
    next_id: i32,
    budget: i32,
    mergers: Vec<MergerEntry>,
    shared: Vec<SharedModel>,
    queue_merged: [bool; 3],
}

struct MergerCtx {
    loops: [MessageLoop; 3],
    ids: [TaskQueueId; 3],
    st: Mutex<MergerState>,
}

const K_LOOP_NAMES: [&str; 4] = ["P", "R1", "R2", "-"];

fn raster_of(pair: i32) -> usize {
    match pair {
        0 => 1,
        1 => 2,
        _ => 0,
    }
}

fn create_merger(c: &MergerCtx, st: &mut MergerState, indent: &str) {
    let mut pair = st.r.below(5) as i32;
    pair = if pair >= 3 { st.r.below(2) as i32 } else { pair };
    let parent: i32 = if st.mergers.is_empty() || st.r.chance(3) {
        -1
    } else {
        st.r.below(st.mergers.len() as u64) as i32
    };
    let parent_merger =
        if parent >= 0 { st.mergers[parent as usize].merger.clone() } else { RefPtr::null() };
    let index = st.mergers.len();
    let merger = RasterThreadMerger::create_or_share_thread_merger(
        &parent_merger,
        c.ids[0],
        c.ids[raster_of(pair)],
    );
    let shared = if parent >= 0 && st.mergers[parent as usize].pair == pair {
        st.mergers[parent as usize].shared
    } else {
        st.shared.push(SharedModel { enabled: true, leases: BTreeMap::new() });
        st.shared.len() - 1
    };
    let shares = parent >= 0
        && *merger.get_shared_raster_thread_merger()
            == *parent_merger.get_shared_raster_thread_merger();
    p!("{indent}create m{index} pair {pair} parent {parent} shares {}", shares as i32);
    if st.r.chance(2) {
        merger.set_merge_unmerge_callback(Arc::new(move || p!("    callback m{index}")));
    }
    st.mergers.push(MergerEntry { pair, shared, merger });
}

fn merger_op(c: &MergerCtx, indent: &str) {
    let mut guard = c.st.lock().unwrap();
    let st = &mut *guard;
    if st.mergers.is_empty() || st.r.chance(10) {
        create_merger(c, st, indent);
        return;
    }
    let m = st.r.below(st.mergers.len() as u64) as usize;
    let pair = st.mergers[m].pair;
    let si = st.mergers[m].shared;
    let merger = st.mergers[m].merger.clone();
    let same = pair == 2;
    let raster = raster_of(pair);
    let mi = m as i32;
    match st.r.below(9) {
        0 | 1 => {
            let lease = 1 + st.r.below(4) as usize;
            p!("{indent}merge m{m} {lease}");
            merger.merge_with_lease(lease);
            let s = &mut st.shared[si];
            if !same && s.enabled && !s.merged() {
                st.queue_merged[raster] = true;
                st.shared[si].leases.insert(mi, lease);
            }
        }
        2 | 3 => {
            let s = &mut st.shared[si];
            if !same && s.merged() && s.enabled {
                let exists = s.leases.contains_key(&mi);
                if exists {
                    if s.leases[&mi] == 0 {
                        return; // FML_CHECK(lease_term_ref > 0) would abort.
                    }
                    *s.leases.get_mut(&mi).unwrap() -= 1;
                }
                if !s.merged() {
                    if !st.queue_merged[raster] {
                        if exists {
                            *st.shared[si].leases.get_mut(&mi).unwrap() += 1;
                        }
                        return; // Unmerge would fail: FML_CHECK aborts.
                    }
                    st.queue_merged[raster] = false;
                }
            }
            p!("{indent}decrement m{m}");
            let status = merger.decrement_lease();
            p!("{indent}  -> {}", status as i32);
        }
        4 => {
            let lease = 1 + st.r.below(4) as usize;
            let s = &st.shared[si];
            if !same && s.enabled && !s.merged() {
                return; // FML_DCHECK(IsMergedUnSafe()) in debug builds.
            }
            p!("{indent}extend m{m} {lease}");
            merger.extend_lease_to(lease);
            let s = &mut st.shared[si];
            if !same && s.enabled {
                s.leases.insert(mi, lease);
            }
        }
        5 => {
            let s = &mut st.shared[si];
            if !same && s.enabled {
                let old = s.leases.clone();
                s.leases.remove(&mi);
                if s.leases.is_empty() || !s.merged() {
                    if !st.queue_merged[raster] {
                        st.shared[si].leases = old;
                        return; // Unmerge would fail: FML_CHECK aborts.
                    }
                    st.queue_merged[raster] = false;
                }
            }
            p!("{indent}unmerge m{m}");
            merger.un_merge_now_if_last_one();
        }
        6 => {
            let enable = st.r.chance(2);
            p!("{indent}{} m{m}", if enable { "enable" } else { "disable" });
            if enable {
                merger.enable();
            } else {
                merger.disable();
            }
            st.shared[si].enabled = enable;
        }
        7 => {
            let merged = merger.is_merged();
            p!(
                "{indent}query m{m} merged {} enabled {} raster {} platform {}",
                merged as i32,
                merger.is_enabled() as i32,
                merger.is_on_rasterizing_thread() as i32,
                merger.is_on_platform_thread() as i32
            );
            if merged {
                merger.wait_until_merged();
                p!("{indent}  waited");
            }
        }
        _ => create_merger(c, st, indent),
    }
}

fn post_merger_task(c: &Arc<MergerCtx>, indent: &str) {
    let (id, q, kind) = {
        let mut st = c.st.lock().unwrap();
        if st.budget <= 0 {
            return;
        }
        st.budget -= 1;
        let id = st.next_id;
        st.next_id += 1;
        let q = st.r.below(3) as usize;
        let kind = st.r.below(5);
        (id, q, kind)
    };
    let runner = c.loops[q].get_task_runner();
    let name = K_LOOP_NAMES[q];
    match kind {
        0 | 1 => {
            p!("{indent}post t{id} to {name}");
            runner.post_task(make_merger_task(c, id, q));
        }
        2 => {
            let t = {
                let mut st = c.st.lock().unwrap();
                if st.r.chance(10) {
                    TimePoint::max()
                } else {
                    TimePoint::from_ticks(peek_now() + st.r.below(30) as i64 - 10)
                }
            };
            p!("{indent}at t{id} to {name} {}", t.to_epoch_delta().to_nanoseconds());
            runner.post_task_for_time(make_merger_task(c, id, q), t);
        }
        3 => {
            let d = c.st.lock().unwrap().r.below(20) as i64 - 5;
            p!("{indent}delay t{id} to {name} {d}");
            runner.post_delayed_task(make_merger_task(c, id, q), TimeDelta::from_nanoseconds(d));
        }
        _ => {
            p!("{indent}now-or-post t{id} to {name}");
            TaskRunner::run_now_or_post_task(&runner, make_merger_task(c, id, q));
        }
    }
}

fn make_merger_task(c: &Arc<MergerCtx>, id: i32, queue: usize) -> closure {
    let c = c.clone();
    Arc::new(move || {
        let flushing = c.st.lock().unwrap().flushing;
        p!(
            "  run t{id} of {} flushing {} @{}",
            K_LOOP_NAMES[queue],
            K_LOOP_NAMES[flushing],
            peek_now()
        );
        let action = c.st.lock().unwrap().r.below(6);
        match action {
            0 | 1 => merger_op(&c, "   "),
            2 | 3 => post_merger_task(&c, "   "),
            _ => {}
        }
    })
}

fn merger_case(r: &mut Rng, i: i32) {
    set_fake_clock(100 + r.below(50) as i64, 1 + r.below(3) as i64);
    MessageLoop::ensure_initialized_for_current_thread();
    let r1 = ParkedLoop::new();
    let r2 = ParkedLoop::new();
    let loops = [MessageLoop::get_current(), r1.loop_.clone(), r2.loop_.clone()];
    let ids = [
        loops[0].get_task_runner().get_task_queue_id(),
        loops[1].get_task_runner().get_task_queue_id(),
        loops[2].get_task_runner().get_task_queue_id(),
    ];
    let budget = 10 + r.below(40) as i32;
    let c = Arc::new(MergerCtx {
        loops,
        ids,
        st: Mutex::new(MergerState {
            r: Rng { s: r.s },
            flushing: 3,
            next_id: 0,
            budget,
            mergers: Vec::new(),
            shared: Vec::new(),
            queue_merged: [false; 3],
        }),
    });
    p!("case {i} now {} budget {budget}", peek_now());
    let queues = MessageLoopTaskQueues::get_instance();
    let below = |n: u64| c.st.lock().unwrap().r.below(n);
    let ops = 10 + below(50) as i32;
    for _ in 0..ops {
        match below(12) {
            0..=2 => post_merger_task(&c, ""),
            3..=5 => {
                let q = below(3) as usize;
                c.st.lock().unwrap().flushing = q;
                p!("flush {} @{}", K_LOOP_NAMES[q], peek_now());
                c.loops[q].run_expired_tasks_now();
                c.st.lock().unwrap().flushing = 3;
            }
            6 | 7 => merger_op(&c, ""),
            8 => {
                let q = below(3) as usize;
                let key = below(3) as isize;
                if c.st.lock().unwrap().r.chance(3) {
                    p!("unobserve {} {key}", K_LOOP_NAMES[q]);
                    queues.remove_task_observer(c.ids[q], key);
                } else {
                    p!("observe {} {key}", K_LOOP_NAMES[q]);
                    queues.add_task_observer(
                        c.ids[q],
                        key,
                        Arc::new(move || p!("    obs {} {key}", K_LOOP_NAMES[q])),
                    );
                }
            }
            9 => {
                w!("state");
                for q in 0..3 {
                    w!(
                        " {}:{}/{}/{}",
                        K_LOOP_NAMES[q],
                        queues.has_pending_tasks(c.ids[q]) as i32,
                        queues.get_num_pending_tasks(c.ids[q]),
                        c.loops[q].get_task_runner().runs_tasks_on_current_thread() as i32
                    );
                }
                p!(
                    " owns {} {} same {} {}",
                    queues.owns(c.ids[0], c.ids[1]) as i32,
                    queues.owns(c.ids[0], c.ids[2]) as i32,
                    TaskRunnerChecker::runs_on_the_same_thread(c.ids[1], c.ids[0]) as i32,
                    TaskRunnerChecker::runs_on_the_same_thread(c.ids[2], c.ids[1]) as i32
                );
            }
            10 => {
                let checker = TaskRunnerChecker::new();
                p!("checker {}", checker.runs_on_creation_task_runner() as i32);
            }
            _ => {
                let jump = below(15) as i64;
                p!("jump {jump}");
                G_FAKE_NOW.fetch_add(jump, SeqCst);
            }
        }
    }
    let queue_merged = c.st.lock().unwrap().queue_merged;
    for q in 1..3 {
        if queue_merged[q] {
            p!("final unmerge {} {}", K_LOOP_NAMES[q], queues.unmerge(c.ids[0], c.ids[q]) as i32);
        }
    }
    p!(
        "final pending {} {} {}",
        queues.get_num_pending_tasks(c.ids[0]),
        queues.get_num_pending_tasks(c.ids[1]),
        queues.get_num_pending_tasks(c.ids[2])
    );
    for q in 0..3 {
        queues.dispose_tasks(c.ids[q]);
    }
    let mut st = c.st.lock().unwrap();
    st.mergers.clear();
    r.s = st.r.s;
    drop(st);
    drop(c);
    drop(r2);
    drop(r1);
}

fn suite_merger(r: &mut Rng, cases: i32) {
    for i in 0..cases {
        let mut rr = Rng { s: r.s };
        let rr = std::thread::spawn(move || {
            merger_case(&mut rr, i);
            rr
        })
        .join()
        .unwrap();
        r.s = rr.s;
    }
    TimePoint::set_clock_source(None);
}

// ------------------------------------------------------------- thread ------

fn current_thread_name() -> String {
    let name = std::fs::read_to_string("/proc/thread-self/comm").unwrap_or_default();
    name.trim_end_matches('\n').to_string()
}

#[derive(Default)]
struct Pending {
    count: Mutex<i32>,
    cv: Condvar,
}

impl Pending {
    fn add(&self) {
        *self.count.lock().unwrap() += 1;
    }
    fn done(&self) {
        let mut count = self.count.lock().unwrap();
        *count -= 1;
        if *count == 0 {
            self.cv.notify_all();
        }
    }
    fn wait(&self) {
        let count = self.count.lock().unwrap();
        let _unused = self.cv.wait_while(count, |c| *c != 0).unwrap();
    }
}

struct ThreadCtx {
    runners: Vec<RefPtr<TaskRunner>>,
    traces: Mutex<BTreeMap<i32, Vec<String>>>,
    pending: Pending,
}

fn thread_index_of(c: &ThreadCtx) -> i32 {
    for (i, runner) in c.runners.iter().enumerate() {
        if runner.runs_tasks_on_current_thread() {
            return i as i32;
        }
    }
    -1
}

fn make_thread_task(c: &Arc<ThreadCtx>, id: i32, child_action: i32) -> closure {
    let c = c.clone();
    Arc::new(move || {
        let at = thread_index_of(&c);
        let mut line = format!("t{id} runs");
        for runner in &c.runners {
            line += if runner.runs_tasks_on_current_thread() { " 1" } else { " 0" };
        }
        if child_action != 0 {
            let own = c.runners[at as usize].clone();
            let child = id * 10 + child_action;
            c.pending.add();
            match child_action {
                1 => {
                    line += " post";
                    own.post_task(make_thread_task(&c, child, 0));
                }
                2 => {
                    line += " now";
                    TaskRunner::run_now_or_post_task(&own, make_thread_task(&c, child, 0));
                }
                _ => {
                    line += " flush";
                    TaskRunner::run_now_and_flush_messages(&own, make_thread_task(&c, child, 0));
                }
            }
        }
        c.traces.lock().unwrap().entry(at).or_default().push(line);
        c.pending.done();
    })
}

fn thread_name_config_setter(config: &ThreadConfig) {
    p!("  setter {} {}", config.name, config.priority as i32);
    Thread::set_current_thread_name(config);
}

fn random_thread_name(r: &mut Rng) -> String {
    const K_NAMES: [&str; 6] =
        ["ui", "raster", "io", "platform", "VeryLongThreadNameTest", "a.b.c.d.e.f.g.h.i"];
    let mut name = K_NAMES[r.below(6) as usize].to_string();
    name += &r.below(100).to_string();
    name
}

fn priority_of(n: u64) -> ThreadPriority {
    match n {
        0 => ThreadPriority::kBackground,
        1 => ThreadPriority::kNormal,
        2 => ThreadPriority::kDisplay,
        _ => ThreadPriority::kRaster,
    }
}

fn concurrent_case(r: &mut Rng) {
    let workers = r.below(5) as usize;
    let loop_ = ConcurrentMessageLoop::create(workers);
    let count = loop_.get_worker_count();
    p!("concurrent {workers} -> {count}");
    let runner = loop_.get_task_runner();
    let tasks = r.below(30) as usize;
    let latch = Arc::new(CountDownLatch::new(tasks));
    let state = Arc::new(Mutex::new((0usize, true)));
    let weak = Arc::downgrade(&loop_);
    for _ in 0..tasks {
        let (latch, state, weak) = (latch.clone(), state.clone(), weak.clone());
        runner.post_task(Arc::new(move || {
            let name = current_thread_name();
            let on = weak.upgrade().unwrap().runs_tasks_on_current_thread();
            {
                let mut s = state.lock().unwrap();
                s.0 += on as usize;
                let index = name.strip_prefix("io.worker.").and_then(|n| n.parse::<usize>().ok());
                s.1 = s.1 && index.is_some_and(|n| n >= 1 && n <= count);
            }
            latch.count_down();
        }));
    }
    latch.wait();
    let (inside, names_ok) = *state.lock().unwrap();
    p!(
        "  ran {tasks} inside {inside} names {} outside {}",
        names_ok as i32,
        loop_.runs_tasks_on_current_thread() as i32
    );
    let all = Arc::new(CountDownLatch::new(count));
    let names = Arc::new(Mutex::new(Vec::<String>::new()));
    {
        let (all, names) = (all.clone(), names.clone());
        loop_.post_task_to_all_workers(Arc::new(move || {
            names.lock().unwrap().push(current_thread_name());
            all.count_down();
        }));
    }
    all.wait();
    let mut names = names.lock().unwrap().clone();
    names.sort();
    w!("  all");
    for name in &names {
        w!(" {name}");
    }
    p!("");
    if r.chance(2) {
        loop_.terminate();
        let where_ = Arc::new(Mutex::new(String::new()));
        let wc = where_.clone();
        runner.post_task(Arc::new(move || *wc.lock().unwrap() = current_thread_name()));
        p!(
            "  after terminate caller {}",
            (*where_.lock().unwrap() == current_thread_name()) as i32
        );
    }
    drop(loop_);
    let ran = Arc::new(AtomicBool::new(false));
    let rc = ran.clone();
    runner.post_task(Arc::new(move || rc.store(true, SeqCst)));
    p!("  after death ran {}", ran.load(SeqCst) as i32);
}

fn thread_case(r: &mut Rng, i: i32) {
    let n = 1 + r.below(3) as i32;
    p!("case {i} threads {n}");
    let mut kinds = Vec::new();
    let mut threads: Vec<Thread> = Vec::new();
    let mut runners = Vec::new();
    for t in 0..n {
        kinds.push(r.below(3) as i32);
        match kinds.last().unwrap() {
            0 => {
                p!("thread {t} default");
                threads.push(Thread::default());
            }
            1 => {
                let name = random_thread_name(r);
                p!("thread {t} named {name}");
                threads.push(Thread::new(&name));
            }
            _ => {
                let name = random_thread_name(r);
                let priority = priority_of(r.below(4));
                p!("thread {t} config {name} {}", priority as i32);
                threads.push(Thread::with_setter(
                    Arc::new(thread_name_config_setter),
                    ThreadConfig::new(&name, priority),
                ));
            }
        }
        runners.push(threads.last().unwrap().get_task_runner());
    }
    let c = Arc::new(ThreadCtx {
        runners,
        traces: Mutex::new(BTreeMap::new()),
        pending: Pending::default(),
    });
    for t in 0..n as usize {
        if kinds[t] == 0 {
            // Unnamed: inherits the creating thread's name, the executable's.
            continue;
        }
        let latch = Arc::new(AutoResetWaitableEvent::new());
        let name = Arc::new(Mutex::new(String::new()));
        {
            let (latch, name) = (latch.clone(), name.clone());
            c.runners[t].post_task(Arc::new(move || {
                *name.lock().unwrap() = current_thread_name();
                latch.signal();
            }));
        }
        latch.wait();
        p!("name {t} {}", name.lock().unwrap());
    }
    let rounds = 1 + r.below(4) as i32;
    let mut next_id = 0;
    for _ in 0..rounds {
        // Hold every thread while the batch is posted.
        let mut gates = Vec::new();
        for t in 0..n as usize {
            let gate = Arc::new(AutoResetWaitableEvent::new());
            let g = gate.clone();
            c.runners[t].post_task(Arc::new(move || g.wait()));
            gates.push(gate);
        }
        let mut conditionals: Vec<ConditionalBasicTaskRunner> = Vec::new();
        let k = r.below(20) as i32;
        for _ in 0..k {
            let t = r.below(n as u64) as usize;
            let id = next_id;
            next_id += 1;
            let child = if r.chance(3) { 1 + r.below(3) as i32 } else { 0 };
            let task = make_thread_task(&c, id, child);
            match r.below(6) {
                0 => {
                    p!("post t{id} to {t}");
                    c.pending.add();
                    c.runners[t].post_task(task);
                }
                1 => {
                    p!("now-or-post t{id} to {t}");
                    c.pending.add();
                    TaskRunner::run_now_or_post_task(&c.runners[t], task);
                }
                2 => {
                    p!("wrapper t{id} to {t}");
                    c.pending.add();
                    let wrapper = WrapperBasicTaskRunner::new(c.runners[t].clone());
                    wrapper.post_task(task);
                }
                3 => {
                    let usable = r.chance(2);
                    p!("conditional t{id} to {t} {}", usable as i32);
                    // Kept alive until the round ends.
                    conditionals
                        .push(ConditionalBasicTaskRunner::new(c.runners[t].clone(), move || usable));
                    if usable {
                        c.pending.add();
                    }
                    conditionals.last().unwrap().post_task(task);
                }
                4 => {
                    // The runner dies before the gated thread gets to the task.
                    p!("conditional-dead t{id} to {t}");
                    let conditional =
                        ConditionalBasicTaskRunner::new(c.runners[t].clone(), || true);
                    conditional.post_task(task);
                }
                _ => {
                    p!("for-time t{id} to {t}");
                    c.pending.add();
                    c.runners[t].post_task_for_time(task, TimePoint::now());
                }
            }
        }
        for gate in &gates {
            gate.signal();
        }
        c.pending.wait();
        for t in 0..n as usize {
            let latch = Arc::new(AutoResetWaitableEvent::new());
            let l = latch.clone();
            c.runners[t].post_task(Arc::new(move || l.signal()));
            latch.wait();
        }
        let mut traces = c.traces.lock().unwrap();
        for (t, lines) in traces.iter() {
            for line in lines {
                p!("  {t}: {line}");
            }
        }
        traces.clear();
        drop(traces);
        w!("main runs");
        for runner in &c.runners {
            w!(" {}", runner.runs_tasks_on_current_thread() as i32);
        }
        p!("");
        drop(conditionals);
    }
    for t in 0..n as usize {
        if r.chance(2) {
            p!("join {t}");
            threads[t].join();
            if r.chance(2) {
                threads[t].join();
            }
            c.runners[t].post_task(Arc::new(|| p!("never")));
            p!(
                "  pending {}",
                MessageLoopTaskQueues::get_instance()
                    .get_num_pending_tasks(c.runners[t].get_task_queue_id())
            );
        }
    }
    threads.clear();
    if r.chance(3) {
        concurrent_case(r);
    }
}

fn suite_thread(r: &mut Rng, cases: i32) {
    p!("default stack {}", Thread::get_default_stack_size());
    for i in 0..cases {
        thread_case(r, i);
    }
}

// ------------------------------------------------------------ logging ------

const K_LOG_FILES: [&str; 7] =
    ["flutter/fml/logging.cc", "../../flutter/shell/x.cc", "../a.cc", "./b.cc", "..", "", "../../../"];

fn random_log_text(r: &mut Rng) -> String {
    const K_WORDS: [&str; 8] = ["Hello!", "frame", "raster", "42", "-", "a b", "\t", "ok."];
    let mut text = String::new();
    let words = r.below(5);
    for _ in 0..words {
        text += K_WORDS[r.below(8) as usize];
        if r.chance(2) {
            text += " ";
        }
    }
    text
}

fn escaped(s: &str) -> String {
    s.replace('\n', "\\n").replace('\t', "\\t")
}

fn emit_log(r: &mut Rng, severity: LogSeverity, capture: bool) {
    let file = K_LOG_FILES[r.below(7) as usize];
    let line = r.below(500) as i32;
    let condition = r.chance(3);
    let text = random_log_text(r);
    p!("  emit {severity} {file} {line} {} {}", condition as i32, capture as i32);
    let log_capture_slot = LogCapture::new();
    if !capture {
        LogMessage::capture_next_log(None);
    }
    {
        let mut message =
            LogMessage::new(severity, file, line, if condition { Some("x != nullptr") } else { None });
        message.stream().push_str(&text);
    }
    if capture {
        p!("  captured {}", escaped(&log_capture_slot.str()));
    }
}

fn fatal_child(seed: u64) {
    let mut r = Rng { s: seed };
    let severity = 4 + r.below(3) as i32;
    let capture = r.chance(3);
    emit_log(&mut r, severity, capture);
    p!("survived");
}

fn run_fatal_child(seed: u64) {
    use std::os::unix::process::ExitStatusExt;
    let out = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["fatal", &seed.to_string(), "0"])
        .stdout(std::process::Stdio::null())
        .output()
        .unwrap();
    let (kind, code) = match out.status.signal() {
        Some(signal) => ("signal", signal),
        None => ("exit", out.status.code().unwrap_or(-1)),
    };
    p!("  child {kind} {code} stderr {}", escaped(&String::from_utf8_lossy(&out.stderr)));
}

fn suite_logging(r: &mut Rng, cases: i32) {
    for i in 0..cases {
        p!("case {i}");
        match r.below(8) {
            0 | 1 => {
                let settings = LogSettings { min_log_level: r.below(10) as i32 - 3 };
                set_log_settings(&settings);
                p!(
                    "  set {} -> {} min {} vlog {}",
                    settings.min_log_level,
                    get_log_settings().min_log_level,
                    get_min_log_level(),
                    get_vlog_verbosity()
                );
            }
            2 => {
                let settings = LogSettings { min_log_level: r.below(10) as i32 - 3 };
                let before = get_min_log_level();
                {
                    let _scoped = ScopedSetLogSettings::new(&settings);
                    p!(
                        "  scoped {} -> min {} vlog {}",
                        settings.min_log_level,
                        get_min_log_level(),
                        get_vlog_verbosity()
                    );
                }
                p!("  restored {before} {}", get_min_log_level());
            }
            3..=5 => {
                let vlog = r.chance(3);
                let level = r.below(4) as i32;
                let severity = if vlog { -level } else { level };
                let on = if vlog {
                    level <= get_vlog_verbosity()
                } else {
                    should_create_log_message(severity)
                };
                p!("  {} {level} on {}", if vlog { "vlog" } else { "log" }, on as i32);
                if on {
                    let capture = r.chance(2);
                    emit_log(r, severity, capture);
                }
            }
            6 => {
                let severity =
                    if r.chance(2) { 5 + r.below(3) as i32 } else { -(r.below(12) as i32) };
                if severity >= kLogFatal {
                    p!("  fatal");
                    run_fatal_child(r.next());
                } else {
                    let capture = r.chance(2);
                    emit_log(r, severity, capture);
                }
            }
            _ => {
                if r.chance(4) {
                    p!("  fatal");
                    run_fatal_child(r.next());
                }
            }
        }
    }
    set_log_settings(&LogSettings::default());
}

// -------------------------------------------------------- loop benches -----

fn bench_loop() {
    std::thread::spawn(|| {
        MessageLoop::ensure_initialized_for_current_thread();
        let loop_ = MessageLoop::get_current();
        const COUNT: usize = 10000;
        let current = Arc::new(AtomicUsize::new(0));
        for i in 0..COUNT {
            let current = current.clone();
            loop_.get_task_runner().post_task(Arc::new(move || {
                current.fetch_add(1, Relaxed);
                if i + 1 == COUNT {
                    MessageLoop::get_current().terminate();
                }
            }));
        }
        loop_.run();
        if current.load(Relaxed) != COUNT {
            std::process::abort();
        }
    })
    .join()
    .unwrap();
}

fn bench_thread() {
    let thread = Thread::new("bench");
    let ran = Arc::new(AtomicUsize::new(0));
    for _ in 0..10000 {
        let ran = ran.clone();
        thread.get_task_runner().post_task(Arc::new(move || {
            ran.fetch_add(1, Relaxed);
        }));
    }
    thread.join();
    if ran.load(Relaxed) != 10000 {
        std::process::abort();
    }
}

fn bench_concurrent() {
    let loop_ = ConcurrentMessageLoop::create(4);
    let runner = loop_.get_task_runner();
    let latch = Arc::new(CountDownLatch::new(10000));
    for _ in 0..10000 {
        let latch = latch.clone();
        runner.post_task(Arc::new(move || latch.count_down()));
    }
    latch.wait();
}

// -------------------------------------------------------------- main -------

fn run_suite(suite: &str, r: &mut Rng, cases: i32) -> bool {
    let all = suite == "all";
    let mut known = false;
    if all || suite == "time" {
        known = true;
        suite_time(r, cases);
    }
    if all || suite == "strings" {
        known = true;
        suite_strings(r, cases);
    }
    if all || suite == "codec" {
        known = true;
        suite_codec(r, cases);
    }
    if all || suite == "hash" {
        known = true;
        suite_hash(r, cases);
    }
    if all || suite == "endian" {
        known = true;
        suite_endian(r, cases);
    }
    if all || suite == "trie" {
        known = true;
        suite_trie(r, cases);
    }
    if all || suite == "queues" {
        known = true;
        suite_queues(r, cases);
    }
    if all || suite == "loop" {
        known = true;
        suite_loop(r, cases);
    }
    if all || suite == "merger" {
        known = true;
        suite_merger(r, cases);
    }
    if all || suite == "thread" {
        known = true;
        suite_thread(r, cases);
    }
    if all || suite == "logging" {
        known = true;
        suite_logging(r, cases);
    }
    let new_suites: [(&str, fn(&mut Rng, i32)); 9] = [
        ("file", suite_file),
        ("mapping", suite_mapping),
        ("paths", suite_paths),
        ("cmdline", suite_cmdline),
        ("misc", suite_misc),
        ("affinity", suite_affinity),
        ("native", suite_native),
        ("trace", suite_trace),
        ("backtrace", suite_backtrace),
    ];
    for (name, run) in new_suites {
        if all || suite == name {
            known = true;
            run(r, cases);
        }
    }
    known
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: fml_dump <suite> <seed> <cases> | bench <name> <n>");
        std::process::exit(2);
    }
    let suite = args[1].as_str();
    if suite == "bench" {
        bench(&args[2], args[3].parse().unwrap_or(1));
        return;
    }
    if suite == "fatal" {
        fatal_child(args[2].parse().unwrap_or(0));
        std::io::stdout().write_all(&OUT.lock().unwrap()).unwrap();
        return;
    }
    if suite == "crash" {
        crash_child(args[2].parse().unwrap_or(0));
        std::io::stdout().write_all(&OUT.lock().unwrap()).unwrap();
        return;
    }
    let mut r = Rng { s: args[2].parse().unwrap_or(0) };
    let cases: i32 = args[3].parse().unwrap_or(0);
    if !run_suite(suite, &mut r, cases) {
        eprintln!("unknown suite {suite}");
        std::process::exit(2);
    }
    std::io::stdout().write_all(&OUT.lock().unwrap()).unwrap();
}

// ------------------------------------------------------- file system ------
//
// See oracle/fml_dump.cc: the file, mapping, paths, affinity and native
// suites work in a ScopedTemporaryDirectory made fresh per run.

use fml::file::{FilePermission, ScopedTemporaryDirectory};
use fml::mapping::{DataMapping, FileMapping, MallocMapping, Mapping, NonOwnedMapping, Protection};
use fml::unique_fd::UniqueFD;

unsafe extern "C" {
    fn __errno_location() -> *mut i32;
    fn dlopen(filename: *const std::os::raw::c_char, flags: i32) -> *mut std::ffi::c_void;
    fn dlclose(handle: *mut std::ffi::c_void) -> i32;
    #[link_name = "raise"]
    fn c_raise(sig: i32) -> i32;
}

/// `errno = value`, as the C++ driver clears it before a call.
fn set_errno(value: i32) {
    // SAFETY: __errno_location returns this thread's errno, valid for the
    // thread's lifetime.
    unsafe { *__errno_location() = value };
}

fn errno() -> i32 {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

fn quoted(s: &[u8]) -> String {
    let mut out = String::from("\"");
    for &c in s {
        if !(0x20..=0x7e).contains(&c) || c == b'"' || c == b'\\' {
            out.push_str(&format!("\\x{c:02x}"));
        } else {
            out.push(c as char);
        }
    }
    out.push('"');
    out
}

fn fnv1a(data: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in data {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

/// The bytes a mapping points at.
fn mapped(m: &dyn Mapping) -> &[u8] {
    if m.get_mapping().is_null() {
        return &[];
    }
    // SAFETY: by the Mapping contract the pointer covers get_size() bytes
    // while `m` is borrowed; callers only ask for mappings mapped readable,
    // as the C++ driver reads them.
    unsafe { std::slice::from_raw_parts(m.get_mapping(), m.get_size()) }
}

fn gen_data(r: &mut Rng, max_len: u64) -> Vec<u8> {
    let n = r.below(max_len + 1) as usize;
    (0..n).map(|_| r.next() as u8).collect()
}

const K_FILE_NAMES: [&[u8]; 12] = [
    b"a",
    b"b",
    b"c.txt",
    b"d",
    b"\xc3\xa4\xe3\x83\x86",
    b"sp ace",
    b"x\xff",
    b".",
    b"..x",
    b"",
    b"nl\nx",
    b"a.temp",
];

fn gen_rel_path(r: &mut Rng) -> Vec<u8> {
    match r.below(12) {
        0 => vec![b'n'; 256],
        1 | 2 => {
            let mut p = Vec::new();
            let n = 2 + r.below(2);
            for i in 0..n {
                if i != 0 {
                    p.push(b'/');
                }
                p.extend_from_slice(K_FILE_NAMES[r.below(4) as usize]);
            }
            p
        }
        3 => b"a/./b".to_vec(),
        _ => K_FILE_NAMES[r.below(12) as usize].to_vec(),
    }
}

fn perm(p: u64) -> FilePermission {
    match p {
        0 => FilePermission::kRead,
        1 => FilePermission::kWrite,
        _ => FilePermission::kReadWrite,
    }
}

// Fields drop in order: the slots close before the directory is removed,
// as the C++ context's members are destroyed in reverse.
struct FileCtx {
    slots: [UniqueFD; 4],
    invalid: UniqueFD,
    dir: ScopedTemporaryDirectory,
}

const K_BASE_NAMES: [&str; 6] = ["root", "s0", "s1", "s2", "s3", "bad"];

fn gen_base(r: &mut Rng) -> usize {
    if r.chance(2) { 0 } else { r.below(6) as usize }
}

fn base(c: &FileCtx, b: usize) -> &UniqueFD {
    match b {
        0 => c.dir.fd(),
        5 => &c.invalid,
        _ => &c.slots[b - 1],
    }
}

fn abs_path(c: &FileCtx, rel: &[u8]) -> Vec<u8> {
    let mut p = c.dir.path().as_bytes().to_vec();
    p.push(b'/');
    p.extend_from_slice(rel);
    p
}

fn printing_visit(dir: &UniqueFD, recursive: bool, stop: bool, stop_at: &[u8]) -> bool {
    let mut visitor = |_d: &UniqueFD, filename: &[u8]| {
        w!(" {}", quoted(filename));
        !(stop && filename == stop_at)
    };
    if recursive {
        fml::file::visit_files_recursively(dir, &mut visitor)
    } else {
        fml::file::visit_files(dir, &mut visitor)
    }
}

fn os_path(p: &[u8]) -> &std::path::Path {
    use std::os::unix::ffi::OsStrExt;
    std::path::Path::new(std::ffi::OsStr::from_bytes(p))
}

/// `::chmod(path, mode)`: the return code and errno.
fn chmod(path: &[u8], mode: u32) -> (i32, i32) {
    use std::os::unix::fs::PermissionsExt;
    let end = path.iter().position(|&b| b == 0).unwrap_or(path.len());
    match std::fs::set_permissions(os_path(&path[..end]), std::fs::Permissions::from_mode(mode)) {
        Ok(()) => (0, errno()),
        Err(e) => (-1, e.raw_os_error().unwrap_or(0)),
    }
}

fn file_op(c: &mut FileCtx, r: &mut Rng, depth: i32) {
    match r.below(16) {
        0..=3 => {
            let directory = r.below(4) == 0;
            let abs = r.chance(6);
            let b = gen_base(r);
            let path = gen_rel_path(r);
            let create = r.chance(2);
            let p = r.below(3);
            let slot = r.below(4) as usize;
            let read_only = r.chance(4);
            set_errno(0);
            let fd = if read_only {
                if directory {
                    fml::file::open_directory_read_only(base(c, b), &path)
                } else {
                    fml::file::open_file_read_only(base(c, b), &path)
                }
            } else if abs {
                if directory {
                    fml::file::open_directory(abs_path(c, &path), create, perm(p))
                } else {
                    fml::file::open_file(abs_path(c, &path), create, perm(p))
                }
            } else if directory {
                fml::file::open_directory_at(base(c, b), &path, create, perm(p))
            } else {
                fml::file::open_file_at(base(c, b), &path, create, perm(p))
            };
            let e = errno();
            p!(
                "  {} {} {} c{} p{} -> s{} {} errno {}",
                if directory { "opendir" } else { "open" },
                if read_only { "ro" } else if abs { "abs" } else { K_BASE_NAMES[b] },
                quoted(&path),
                create as i32,
                p,
                slot,
                fd.is_valid() as i32,
                e
            );
            c.slots[slot] = fd;
        }
        4 => {
            let b = gen_base(r);
            let n = r.below(4);
            let components: Vec<&[u8]> = (0..n).map(|_| K_FILE_NAMES[r.below(7) as usize]).collect();
            let p = r.below(3);
            let slot = r.below(4) as usize;
            set_errno(0);
            let fd = fml::file::create_directory(base(c, b), &components, perm(p));
            let e = errno();
            w!("  mkdirs {}", K_BASE_NAMES[b]);
            for component in &components {
                w!(" {}", quoted(component));
            }
            p!(" p{} -> s{} {} errno {}", p, slot, fd.is_valid() as i32, e);
            c.slots[slot] = fd;
        }
        5 => {
            let b = gen_base(r);
            let path = gen_rel_path(r);
            let slot = r.below(4) as usize;
            let is_dir_fd = fml::file::is_directory(&c.slots[slot]);
            let is_dir = fml::file::is_directory_at(base(c, b), &path);
            let exists = fml::file::file_exists(base(c, b), &path);
            let exists_abs = fml::file::file_exists(c.dir.fd(), abs_path(c, &path));
            let is_file = fml::file::is_file(abs_path(c, &path));
            p!(
                "  query {} {} s{} dir {} {} exists {} {} file {}",
                K_BASE_NAMES[b],
                quoted(&path),
                slot,
                is_dir_fd as i32,
                is_dir as i32,
                exists as i32,
                exists_abs as i32,
                is_file as i32
            );
        }
        6 => {
            let slot = r.below(4) as usize;
            let size = r.below(5000) as usize;
            set_errno(0);
            let ok = fml::file::truncate_file(&c.slots[slot], size);
            let e = errno();
            p!("  truncate s{slot} {size} -> {} errno {e}", ok as i32);
        }
        7 | 8 => {
            let directory = r.chance(2);
            let abs = r.chance(6);
            let b = gen_base(r);
            let path = gen_rel_path(r);
            set_errno(0);
            let ok = match (directory, abs) {
                (true, true) => fml::file::unlink_directory(abs_path(c, &path)),
                (true, false) => fml::file::unlink_directory_at(base(c, b), &path),
                (false, true) => fml::file::unlink_file(abs_path(c, &path)),
                (false, false) => fml::file::unlink_file_at(base(c, b), &path),
            };
            let e = errno();
            p!(
                "  {} {} {} -> {} errno {}",
                if directory { "rmdir" } else { "unlink" },
                if abs { "abs" } else { K_BASE_NAMES[b] },
                quoted(&path),
                ok as i32,
                e
            );
        }
        9 => {
            let abs = r.chance(6);
            let b = gen_base(r);
            let path = gen_rel_path(r);
            let data = gen_data(r, 300);
            let mapping = DataMapping::new(data.clone());
            set_errno(0);
            let ok = if abs {
                fml::file::write_atomically(c.dir.fd(), abs_path(c, &path), &mapping)
            } else {
                fml::file::write_atomically(base(c, b), &path, &mapping)
            };
            let e = errno();
            p!(
                "  write {} {} {} {:016x} -> {} errno {}",
                if abs { "abs" } else { K_BASE_NAMES[b] },
                quoted(&path),
                data.len(),
                fnv1a(&data),
                ok as i32,
                e
            );
        }
        10 | 11 => {
            let recursive = r.chance(2);
            let b = gen_base(r);
            let stop = r.chance(3);
            let stop_at = K_FILE_NAMES[r.below(12) as usize];
            w!("  visit{} {}", if recursive { "-r" } else { "" }, K_BASE_NAMES[b]);
            let ok = printing_visit(base(c, b), recursive, stop, stop_at);
            p!(" -> {}", ok as i32);
        }
        12 => {
            let whole = r.chance(2);
            let b = gen_base(r);
            let path = gen_rel_path(r);
            set_errno(0);
            let ok = if whole {
                fml::file::remove_directory_recursively(base(c, b), &path)
            } else {
                fml::file::remove_files_in_directory(base(c, b))
            };
            let e = errno();
            p!(
                "  {} {} {} -> {} errno {}",
                if whole { "rmtree" } else { "empty" },
                K_BASE_NAMES[b],
                quoted(if whole { &path } else { b"" }),
                ok as i32,
                e
            );
        }
        13 => {
            let from = r.below(4) as usize;
            let to = r.below(4) as usize;
            set_errno(0);
            let fd = fml::file::duplicate(c.slots[from].get());
            let e = errno();
            p!(
                "  dup s{from} -> s{to} {} errno {e} dir {}",
                fd.is_valid() as i32,
                fml::file::is_directory(&fd) as i32
            );
            c.slots[to] = fd;
        }
        14 => {
            let slot = r.below(4) as usize;
            set_errno(0);
            let mapping = FileMapping::new_read_only(&c.slots[slot]);
            let e = errno();
            p!(
                "  map s{slot} valid {} size {} null {} errno {e} fnv {:016x}",
                mapping.is_valid() as i32,
                mapping.get_size(),
                mapping.get_mapping().is_null() as i32,
                fnv1a(mapped(&mapping))
            );
        }
        _ => {
            const K_MODES: [u32; 8] = [0, 0o400, 0o200, 0o600, 0o700, 0o500, 0o300, 0o644];
            let path = gen_rel_path(r);
            let mode = K_MODES[r.below(8) as usize];
            let abs = abs_path(c, &path);
            set_errno(0);
            let (rc, e) = chmod(&abs, mode);
            let dir = rc == 0 && std::fs::metadata(os_path(&abs)).map(|m| m.is_dir()).unwrap_or(false);
            p!("  chmod {} {:o} -> {} errno {} dir {}", quoted(&path), mode, rc, e, dir as i32);
            if dir {
                if depth == 0 {
                    file_op(c, r, 1);
                }
                chmod(&abs, 0o700);
            }
        }
    }
}

fn make_tree_writable(dir: &UniqueFD) {
    let mut visitor = |directory: &UniqueFD, filename: &[u8]| {
        if fml::file::is_directory_at(directory, filename) {
            let mut proc = format!("/proc/self/fd/{}/", directory.get()).into_bytes();
            proc.extend_from_slice(filename);
            chmod(&proc, 0o700);
        }
        true
    };
    fml::file::visit_files_recursively(dir, &mut visitor);
}

fn suite_file(r: &mut Rng, cases: i32) {
    let mut c = Box::new(FileCtx {
        slots: Default::default(),
        invalid: UniqueFD::default(),
        dir: ScopedTemporaryDirectory::new(),
    });
    let root = c.dir.path().clone();
    p!(
        "root {} {} {} valid {}",
        root,
        root.starts_with("/tmp/flutter_") as i32,
        root.len(),
        c.dir.fd().is_valid() as i32
    );
    for i in 0..cases {
        p!("case {i}");
        file_op(&mut c, r, 0);
    }
    w!("tree");
    printing_visit(c.dir.fd(), true, false, b"");
    p!("");
    make_tree_writable(c.dir.fd());
    drop(c);
    p!("removed {}", !std::path::Path::new(&root).exists() as i32);
}

// ----------------------------------------------------------- mapping ------

static STATIC_BYTES: [u8; 64] = {
    let mut bytes = [0u8; 64];
    let mut i = 0;
    while i < 64 {
        bytes[i] = (i * 7 + 3) as u8;
        i += 1;
    }
    bytes
};

fn mapping_text(m: &dyn Mapping) -> String {
    format!(
        " size {} null {} dontneed {} fnv {:016x}",
        m.get_size(),
        m.get_mapping().is_null() as i32,
        m.is_dont_need_safe() as i32,
        fnv1a(mapped(m))
    )
}

/// The driver's copy of mapping_posix.cc's ToPosixProtectionFlags.
fn protection_flags(protection: &[Protection]) -> i32 {
    let mut flags = 0;
    for p in protection {
        match p {
            Protection::kRead => flags |= 1,
            Protection::kWrite => flags |= 2,
            Protection::kExecute => return 1 | 4,
        }
    }
    flags
}

fn suite_mapping(r: &mut Rng, cases: i32) {
    let dir = ScopedTemporaryDirectory::new();
    p!("root {}", dir.path());
    let bytes: &'static [u8; 64] = &STATIC_BYTES;
    for i in 0..cases {
        p!("case {i}");
        match r.below(10) {
            0 => {
                let data = gen_data(r, 64);
                let from_string = r.chance(2);
                let m = if from_string { DataMapping::from_string(&data) } else { DataMapping::new(data) };
                p!("  data {}{}", from_string as i32, mapping_text(&m));
            }
            1 => {
                let offset = r.below(64);
                let size = r.below(65 - offset);
                let null = r.chance(8);
                let release = r.chance(2);
                let dontneed = r.chance(2);
                let data = if null { std::ptr::null() } else { bytes[offset as usize..].as_ptr() };
                let base = bytes.as_ptr() as usize;
                let proc: Option<fml::mapping::ReleaseProc> = if release {
                    Some(Box::new(move |d: *const u8, s: usize| {
                        p!("  release {} {}", if d.is_null() { -1 } else { (d as usize - base) as i64 }, s);
                    }))
                } else {
                    None
                };
                // SAFETY: `data` is null or points into STATIC_BYTES, with
                // `size` bytes left there, for the whole program.
                let m = unsafe { NonOwnedMapping::new(data, size as usize, proc, dontneed) };
                w!("  nonowned {} {} same {}", null as i32, offset, (m.get_mapping() == data) as i32);
                if null {
                    p!(" size {} dontneed {}", m.get_size(), m.is_dont_need_safe() as i32);
                } else {
                    p!("{}", mapping_text(&m));
                }
            }
            2 => {
                let kind = r.below(4);
                let data = gen_data(r, 64);
                if kind == 0 {
                    let m = MallocMapping::new();
                    p!("  malloc empty{}", mapping_text(&m));
                    continue;
                }
                let mut m = MallocMapping::copy(&data);
                p!("  malloc copy{}", mapping_text(&m));
                if kind == 2 {
                    let released = m.release();
                    p!(
                        "  released {} fnv {:016x} now{}",
                        released.is_none() as i32,
                        fnv1a(released.as_deref().unwrap_or(&[])),
                        mapping_text(&m)
                    );
                } else if kind == 3 {
                    let moved = MallocMapping::take(&mut m);
                    p!("  moved{} from{}", mapping_text(&moved), mapping_text(&m));
                }
            }
            3..=7 => {
                let name = format!("f{}", r.below(4));
                let rewrite = !r.chance(3);
                let data = gen_data(r, 9000);
                let pm = r.below(3);
                let n = r.below(4);
                let protection: Vec<Protection> = (0..n)
                    .map(|_| match r.below(3) {
                        0 => Protection::kRead,
                        1 => Protection::kWrite,
                        _ => Protection::kExecute,
                    })
                    .collect();
                if rewrite {
                    if data.is_empty() {
                        let fd = fml::file::open_file_at(dir.fd(), &name, true, FilePermission::kReadWrite);
                        fml::file::truncate_file(&fd, 0);
                    } else {
                        let contents = DataMapping::new(data.clone());
                        fml::file::write_atomically(dir.fd(), &name, &contents);
                    }
                }
                let fd = fml::file::open_file_at(dir.fd(), &name, false, perm(pm));
                set_errno(0);
                let mut m = Some(Box::new(FileMapping::new(&fd, &protection)));
                let e = errno();
                let flags = protection_flags(&protection);
                let mm = m.as_ref().unwrap();
                w!("  file {} {} {} p{} prot", name, rewrite as i32, data.len(), pm);
                for p in &protection {
                    w!("{}", *p as i32);
                }
                w!(
                    " valid {} size {} null {} mutable-null {} dontneed {} errno {}",
                    mm.is_valid() as i32,
                    mm.get_size(),
                    mm.get_mapping().is_null() as i32,
                    mm.get_mutable_mapping().is_null() as i32,
                    mm.is_dont_need_safe() as i32,
                    e
                );
                if !mm.get_mapping().is_null() && flags & 1 != 0 {
                    w!(" fnv {:016x}", fnv1a(mapped(&**mm)));
                }
                p!("");
                let size = mm.get_size() as u64;
                let offset = r.below(size + 1);
                let length = (r.below(16) + 1).min(size - offset);
                let fill = r.next() as u8;
                if !mm.get_mutable_mapping().is_null() && flags & 2 != 0 && length > 0 {
                    // SAFETY: the mapping is writable (PROT_WRITE, shared) and
                    // [offset, offset + length) lies within its size.
                    unsafe {
                        std::ptr::write_bytes(
                            mm.get_mutable_mapping().add(offset as usize),
                            fill,
                            length as usize,
                        )
                    };
                    m = None;
                    let check = FileMapping::create_read_only_at(dir.fd(), &name);
                    p!(
                        "  wrote {} {} reread {} fnv {:016x}",
                        offset,
                        length,
                        check.is_some() as i32,
                        check.as_ref().map(|c| fnv1a(mapped(&**c))).unwrap_or(0)
                    );
                }
                drop(m);
            }
            8 => {
                let kind = r.below(6);
                const K_NAMES: [&str; 6] = ["f0", "f1", "f2", "f3", "missing", ""];
                let name = K_NAMES[r.below(6) as usize];
                set_errno(0);
                let full = format!("{}/{}", dir.path(), name);
                let m = match kind {
                    0 => FileMapping::create_read_only(&full),
                    1 => FileMapping::create_read_only_at(dir.fd(), name),
                    2 => FileMapping::create_read_only_at(
                        &fml::file::open_file_at(dir.fd(), name, false, FilePermission::kRead),
                        "",
                    ),
                    3 => FileMapping::create_read_execute(&full),
                    4 => FileMapping::create_read_execute_at(dir.fd(), name),
                    _ => FileMapping::create_read_execute_at(
                        &fml::file::open_file_at(dir.fd(), name, false, FilePermission::kRead),
                        "",
                    ),
                };
                let e = errno();
                w!("  factory {} {} -> {} errno {}", kind, quoted(name.as_bytes()), m.is_some() as i32, e);
                if let Some(m) = &m {
                    w!(" valid {}{}", m.is_valid() as i32, mapping_text(&**m));
                }
                p!("");
            }
            _ => {
                let directory = r.chance(2);
                let invalid = UniqueFD::default();
                set_errno(0);
                let m = FileMapping::new_read_only(if directory { dir.fd() } else { &invalid });
                let e = errno();
                p!(
                    "  file {} valid {} size {} null {} errno {}",
                    if directory { "dir" } else { "invalid" },
                    m.is_valid() as i32,
                    m.get_size(),
                    m.get_mapping().is_null() as i32,
                    e
                );
            }
        }
    }
}

// ------------------------------------------------------------- paths ------

fn gen_path_text(r: &mut Rng) -> Vec<u8> {
    const K_CHARS: [u8; 14] = [b'a', b'b', b'/', b'%', b'.', b':', b'f', b'F', b'0', b'9', b' ', 0xff, 0x80, 0];
    let n = r.below(12);
    (0..n).map(|_| K_CHARS[r.below(14) as usize]).collect()
}

fn gen_uri_text(r: &mut Rng) -> Vec<u8> {
    const K_HEX: &[u8] = b"0123456789abcdefABCDEF";
    let mut s = Vec::new();
    let n = r.below(16);
    for _ in 0..n {
        let k = r.below(11);
        if k == 10 {
            s.extend_from_slice(b"%00");
        } else if k < 3 {
            s.push(b'%');
        } else if k < 7 {
            s.push(K_HEX[r.below(22) as usize]);
        } else if k == 7 {
            s.push(b'g');
        } else if k == 8 {
            s.push(b'/');
        } else {
            s.extend(gen_path_text(r));
        }
    }
    s
}

fn suite_paths(r: &mut Rng, cases: i32) {
    use fml::paths;
    let dir = ScopedTemporaryDirectory::new();
    let original = std::env::current_dir().unwrap();
    // AbsolutePath prefixes the working directory, so work in the scratch
    // directory, whose name the harness masks.
    std::env::set_current_dir(dir.path()).unwrap();
    for i in 0..cases {
        p!("case {i}");
        match r.below(6) {
            0 => {
                let n = r.below(5);
                let c: Vec<Vec<u8>> = (0..n).map(|_| gen_path_text(r)).collect();
                let joined = paths::join_paths(&c);
                w!("  join");
                for s in &c {
                    w!(" {}", quoted(s));
                }
                p!(" -> {}", quoted(&joined));
            }
            1 => {
                let path = gen_path_text(r);
                p!("  dirname {} -> {}", quoted(&path), quoted(&paths::get_directory_name(&path)));
            }
            2 => {
                let text = gen_uri_text(r);
                p!(
                    "  sanitize {} -> {}",
                    quoted(&text),
                    quoted(&paths::sanitize_uri_escaped_characters(&text))
                );
            }
            3 => {
                const K_PREFIXES: [&[u8]; 4] = [b"file://", b"file:/", b"FILE://", b""];
                let mut uri = K_PREFIXES[r.below(4) as usize].to_vec();
                uri.extend(gen_uri_text(r));
                p!("  from-uri {} -> {}", quoted(&uri), quoted(&paths::from_uri(&uri)));
            }
            4 => {
                let kind = r.below(3);
                let path = match kind {
                    0 => Vec::new(),
                    1 => {
                        let mut p = b"/".to_vec();
                        p.extend(gen_path_text(r));
                        p
                    }
                    _ => gen_path_text(r),
                };
                p!("  absolute {} -> {}", quoted(&path), quoted(&paths::absolute_path(&path)));
            }
            _ => {
                let exe = paths::get_executable_path();
                let exe_dir = paths::get_executable_directory_path();
                p!(
                    "  exe {} {} dir {} {} caches {}",
                    exe.0 as i32,
                    (!exe.1.is_empty() && exe.1[0] == b'/') as i32,
                    exe_dir.0 as i32,
                    (exe_dir.1 == paths::get_directory_name(&exe.1)) as i32,
                    paths::get_caches_directory().is_valid() as i32
                );
            }
        }
    }
    std::env::set_current_dir(original).unwrap();
}

// ------------------------------------------------------- command line ------

const K_ARG_TOKENS: [&str; 21] = [
    "prog", "", "-", "-x", "--", "--a", "--b", "--a=1", "--a=", "--=", "--=v", "--==", "--===",
    "--==x", "--a=b=c", "--\u{e9}=\u{fc}", "--a\0b=z", "pos", "--b=2", "arg", "\u{e9}",
];

const K_OPTION_NAMES: [&str; 8] = ["a", "b", "", "=", "a\0b", "x", "\u{e9}", "a=1"];

fn command_line_text(cl: &fml::command_line::CommandLine) -> String {
    let mut s = format!(" argv0 {} {}", cl.has_argv0() as i32, quoted(cl.argv0().as_bytes()));
    s.push_str(" opts");
    for option in cl.options() {
        s.push_str(&format!(" {}={}", quoted(option.name.as_bytes()), quoted(option.value.as_bytes())));
    }
    s.push_str(" pos");
    for arg in cl.positional_args() {
        s.push_str(&format!(" {}", quoted(arg.as_bytes())));
    }
    s
}

fn suite_cmdline(r: &mut Rng, cases: i32) {
    use fml::command_line::*;
    for i in 0..cases {
        p!("case {i}");
        let n = r.below(7);
        let argv: Vec<&str> = (0..n).map(|_| K_ARG_TOKENS[r.below(21) as usize]).collect();
        let (cl, first) = command_line_from_iterators_find_first_positional_arg(&argv);
        p!("  parse first {}{}", first, command_line_text(&cl));
        for _ in 0..3 {
            let name = K_OPTION_NAMES[r.below(8) as usize];
            let has = cl.has_option(name);
            let index = has.unwrap_or(12345);
            let mut value = String::from("untouched");
            let got = cl.get_option_value(name, &mut value);
            let values = cl.get_option_values(name);
            let with_default = cl.get_option_value_with_default(name, "dflt");
            w!(
                "  query {} has {} {} got {} {} values",
                quoted(name.as_bytes()),
                has.is_some() as i32,
                index,
                got as i32,
                quoted(value.as_bytes())
            );
            for v in values {
                w!(" {}", quoted(v.as_bytes()));
            }
            p!(" default {}", quoted(with_default.as_bytes()));
        }
        let args = command_line_to_argv(&cl);
        w!("  argv");
        for arg in &args {
            w!(" {}", quoted(arg.as_bytes()));
        }
        let again = command_line_from_iterators(&args);
        p!(" roundtrip {}", (again == cl) as i32);
        let k = r.below(argv.len() as u64 + 1) as usize;
        let with0 = command_line_from_iterators_with_argv0("p0", &argv[k..]);
        p!("  with-argv0 {}{}", k, command_line_text(&with0));
        let built = CommandLine::with_components(cl.argv0().clone(), cl.options(), cl.positional_args());
        let copy = cl.clone();
        let moved = copy;
        let mut assigned = CommandLine::new();
        let empty_equal = assigned == cl;
        assigned = moved.clone();
        p!(
            "  components {} {} copy {} empty {} assigned {}",
            (built == cl) as i32,
            built.has_option("a").is_some() as i32,
            (moved == cl) as i32,
            empty_equal as i32,
            (assigned == cl) as i32
        );
    }
}

// -------------------------------------------------------------- misc ------

fn gen_u64(r: &mut Rng) -> u64 {
    match r.below(6) {
        0 => 0,
        1 => r.below(1000),
        2 => 0xffffffff - r.below(3),
        3 => (1u64 << 32) + r.below(3),
        4 => !0u64 >> r.below(64),
        _ => r.next(),
    }
}

fn suite_misc(r: &mut Rng, cases: i32) {
    use std::collections::HashMap;
    for i in 0..cases {
        p!("case {i}");
        match r.below(5) {
            0 | 1 => {
                let ordered = r.chance(2);
                let n = r.below(8);
                let entries: Vec<(i32, i32)> =
                    (0..n).map(|_| (r.below(16) as i32, r.below(16) as i32)).collect();
                let modulus = 1 + r.below(4) as i32;
                let rem = r.below(modulus as u64) as i32;
                let result: BTreeMap<i32, i32>;
                if ordered {
                    let mut m = BTreeMap::new();
                    for &(k, v) in &entries {
                        m.insert(k, v);
                    }
                    w!("  map visits");
                    fml::container::erase_if(&mut m, |k: &i32, v: &mut i32| {
                        w!(" {k}");
                        (*k + *v) % modulus == rem
                    });
                    result = m;
                } else {
                    let mut m = HashMap::new();
                    for &(k, v) in &entries {
                        m.insert(k, v);
                    }
                    w!("  unordered");
                    fml::container::erase_if(&mut m, |k: &i32, v: &mut i32| (*k + *v) % modulus == rem);
                    result = m.into_iter().collect();
                }
                w!(" keep");
                for (k, v) in &result {
                    w!(" {k}:{v}");
                }
                p!("");
            }
            2 => {
                let mut safe = fml::safe_math::SafeMath::new();
                let steps = 1 + r.below(4);
                for _ in 0..steps {
                    let x = gen_u64(r);
                    let y = gen_u64(r);
                    let product = safe.mul(x as usize, y as usize);
                    p!("  mul {x} {y} = {product} overflow {}", safe.overflow_detected() as i32);
                }
            }
            3 => {
                let text = gen_path_text(r);
                let copy = fml::posix_wrappers::strdup(&fml::platform::posix::libc::c_string(&text));
                p!("  strdup {} -> {} 1", quoted(&text), quoted(copy.as_bytes()));
            }
            _ => {
                p!("  pid {}", (fml::process::get_current_proc_id() == std::process::id() as i32) as i32);
            }
        }
    }
}

// ---------------------------------------------------------- affinity ------

const K_AFFINITIES: [(fml::cpu_affinity::CpuAffinity, &str); 4] = [
    (fml::cpu_affinity::CpuAffinity::kPerformance, "performance"),
    (fml::cpu_affinity::CpuAffinity::kEfficiency, "efficiency"),
    (fml::cpu_affinity::CpuAffinity::kNotPerformance, "not-performance"),
    (fml::cpu_affinity::CpuAffinity::kNotEfficiency, "not-efficiency"),
];

fn gen_number_text(r: &mut Rng) -> Vec<u8> {
    match r.below(12) {
        0 => return b"0x1A".to_vec(),
        1 => return b"whoa this isnt a number".to_vec(),
        _ => {}
    }
    const K_SPACE: [u8; 6] = [b' ', b'\t', b'\n', 0x0b, 0x0c, b'\r'];
    const K_SUFFIXES: [&[u8]; 7] = [b"", b"abc", b" 77", b"\n", b".5", b"x1", b"e3"];
    let mut s = Vec::new();
    let spaces = r.below(3);
    for _ in 0..spaces {
        s.push(K_SPACE[r.below(6) as usize]);
    }
    let sign = r.below(4);
    if sign == 0 {
        s.push(b'+');
    } else if sign == 1 {
        s.push(b'-');
    }
    if !r.chance(4) {
        let digits = 1 + r.below(24);
        for _ in 0..digits {
            s.push(b'0' + r.below(10) as u8);
        }
    }
    s.extend_from_slice(K_SUFFIXES[r.below(7) as usize]);
    s
}

fn suite_affinity(r: &mut Rng, cases: i32) {
    use fml::cpu_affinity::*;
    let dir = ScopedTemporaryDirectory::new();
    w!("efficiency-count {} request", efficiency_core_count().is_some() as i32);
    for (a, _) in K_AFFINITIES {
        w!(" {}", request_affinity(a) as i32);
    }
    p!("");
    const K_SPEEDS: [i64; 9] = [1, 2, 3, 1800000, 2400000, -1, 0, i64::MAX, i64::MIN];
    for i in 0..cases {
        p!("case {i}");
        if r.chance(2) {
            let n = r.below(7);
            w!("  tracker");
            let mut speeds = Vec::new();
            for _ in 0..n {
                let index = r.below(8) as usize;
                let speed = K_SPEEDS[r.below(9) as usize];
                w!(" {index}:{speed}");
                speeds.push(CpuIndexAndSpeed { index, speed });
            }
            let tracker = CPUSpeedTracker::new(speeds);
            p!(" valid {}", tracker.is_valid() as i32);
            for (a, name) in K_AFFINITIES {
                w!("    {name}");
                for index in tracker.get_indices(a) {
                    w!(" {index}");
                }
                p!("");
            }
        } else {
            let kind = r.below(8);
            let mut path = format!("{}/speed", dir.path());
            let mut text = Vec::new();
            if kind == 0 {
                path = format!("{}/missing", dir.path());
            } else if kind == 1 {
                path = dir.path().clone();
            } else {
                text = gen_number_text(r);
                let fd = fml::file::open_file_at(dir.fd(), "speed", true, FilePermission::kReadWrite);
                fml::file::truncate_file(&fd, 0);
                if !text.is_empty() {
                    let data = DataMapping::from_string(&text);
                    fml::file::write_atomically(dir.fd(), "speed", &data);
                }
            }
            let value = read_int_from_file(&path);
            p!("  read {} {} -> {} {}", kind, quoted(&text), value.is_some() as i32, value.unwrap_or(0));
        }
    }
}

// ------------------------------------------------------------ native ------

const K_SYMBOLS: [&str; 6] = ["strlen", "malloc", "IO_putc", "_IO_putc", "no_such_symbol", ""];

fn resolve_some(r: &mut Rng, lib: &fml::native_library::NativeLibrary) {
    for _ in 0..2 {
        let symbol = K_SYMBOLS[r.below(6) as usize];
        p!("    resolve {} -> {}", quoted(symbol.as_bytes()), (!lib.resolve_symbol(symbol).is_null()) as i32);
    }
}

fn suite_native(r: &mut Rng, cases: i32) {
    use fml::mapping::SymbolMapping;
    use fml::memory::ref_ptr::RefPtr;
    use fml::native_library::NativeLibrary;
    let dir = ScopedTemporaryDirectory::new();
    let not_a_library = DataMapping::from_string("hello");
    fml::file::write_atomically(dir.fd(), "notalib", &not_a_library);
    let libraries: [String; 7] = [
        "libc.so.6".into(),
        "libm.so.6".into(),
        "/nonexistent/libnope.so".into(),
        "".into(),
        format!("{}/notalib", dir.path()),
        dir.path().clone(),
        "libpthread.so.0".into(),
    ];
    let libc = NativeLibrary::create("libc.so.6");
    for i in 0..cases {
        p!("case {i}");
        match r.below(5) {
            0 => {
                let path = &libraries[r.below(7) as usize];
                let lib = NativeLibrary::create(path);
                p!("  create {} -> {}", quoted(path.as_bytes()), lib.as_bool() as i32);
                if let Some(lib) = lib.get() {
                    resolve_some(r, lib);
                }
            }
            1 => {
                let lib = NativeLibrary::create_for_current_process();
                p!("  process {}", lib.as_bool() as i32);
                resolve_some(r, &lib);
                p!("    same-strlen {}", (lib.resolve_symbol("strlen") == libc.resolve_symbol("strlen")) as i32);
            }
            2 => {
                let null = r.chance(3);
                let close = r.chance(2);
                let handle = if null {
                    std::ptr::null_mut()
                } else {
                    // SAFETY: the name is NUL-terminated; libm's initializers
                    // are the C library's own.
                    unsafe { dlopen(c"libm.so.6".as_ptr(), 2 /* RTLD_NOW */) }
                };
                {
                    // SAFETY: `handle` is null or fresh from dlopen; with
                    // `close` the library closes it, else the driver does
                    // below, after the library is gone.
                    let lib = unsafe { NativeLibrary::create_with_handle(handle, close) };
                    w!("  handle {} close {} -> {}", null as i32, close as i32, lib.as_bool() as i32);
                    if let Some(lib) = lib.get() {
                        w!(" cos {}", (!lib.resolve_symbol("cos").is_null()) as i32);
                    }
                    p!("");
                }
                if !handle.is_null() && !close {
                    // SAFETY: the handle came from dlopen above and nothing
                    // holds it any more.
                    unsafe { dlclose(handle) };
                }
            }
            3 => {
                let which = r.below(3);
                let null_name = r.chance(5);
                let symbol = K_SYMBOLS[r.below(6) as usize];
                let lib: RefPtr<NativeLibrary> = match which {
                    0 => RefPtr::null(),
                    1 => NativeLibrary::create_for_current_process(),
                    _ => libc.clone(),
                };
                let m = SymbolMapping::new(lib, if null_name { None } else { Some(symbol) });
                p!(
                    "  symbol {} {} size {} null {} dontneed {}",
                    which,
                    quoted(if null_name { b"<null>" } else { symbol.as_bytes() }),
                    m.get_size(),
                    m.get_mapping().is_null() as i32,
                    m.is_dont_need_safe() as i32
                );
            }
            _ => {
                type Strlen = unsafe extern "C" fn(*const std::os::raw::c_char) -> usize;
                let text = gen_path_text(r);
                // SAFETY: strlen's C type is size_t(const char*).
                let strlen_fn = unsafe { libc.resolve_function::<Strlen>("strlen") };
                // SAFETY: any type will do for a symbol that is not found.
                let missing = unsafe { libc.resolve_function::<Strlen>("no_such_symbol") };
                let c_text = fml::platform::posix::libc::c_string(&text);
                // SAFETY: strlen reads the NUL-terminated `c_text`.
                let length = unsafe { strlen_fn.unwrap()(c_text.as_ptr()) };
                p!(
                    "  call {} {} {} -> {}",
                    strlen_fn.is_some() as i32,
                    missing.is_some() as i32,
                    quoted(&text),
                    length
                );
            }
        }
    }
}

// ------------------------------------------------------------- trace ------

fn print_trace_event(
    label: &str,
    timestamp0: i64,
    timestamp1_or_async_id: i64,
    flow_ids: &[i64],
    type_: fml::trace_event::Dart_Timeline_Event_Type,
    argument_names: &[&str],
    argument_values: &[&str],
) {
    w!("    event {} {} {} {} flows", type_ as i32, quoted(label.as_bytes()), timestamp0, timestamp1_or_async_id);
    for id in flow_ids {
        w!(" {id}");
    }
    w!(" args");
    for (name, value) in argument_names.iter().zip(argument_values) {
        w!(" {}={}", quoted(name.as_bytes()), quoted(value.as_bytes()));
    }
    p!("");
}

static G_TRACE_CLOCK: AtomicI64 = AtomicI64::new(0);

fn counting_micros() -> i64 {
    G_TRACE_CLOCK.fetch_add(3, SeqCst) + 3
}

fn constant_micros() -> i64 {
    7
}

const K_TRACE_LABELS: [&str; 7] = ["frame", "raster", "fml::OpenFile", "ui", "Frame Build", "a", ""];
const K_TRACE_WORDS: [&str; 6] = ["fr", "frame", "ra", "fml", "", "u"];

fn trace_label(r: &mut Rng) -> &'static str {
    K_TRACE_LABELS[r.below(7) as usize]
}

fn gen_trace_double(r: &mut Rng) -> f64 {
    const K_VALUES: [f64; 10] =
        [0.0, -0.0, 1.5, -2.25, 1e20, 3.14159265358979, 1e-7, f64::INFINITY, f64::NEG_INFINITY, f64::NAN];
    K_VALUES[r.below(10) as usize]
}

fn gen_trace_point(r: &mut Rng) -> TimePoint {
    TimePoint::from_epoch_delta(TimeDelta::from_microseconds(
        r.below(2000000000001) as i64 - 1000000000000,
    ))
}

fn suite_trace(r: &mut Rng, cases: i32) {
    use fml::trace_event::*;
    use fml::{
        fml_trace_counter, fml_trace_event, trace_event_async_begin0, trace_event_async_begin1,
        trace_event_async_end0, trace_event_instant0, trace_event_instant1, trace_event_instant2,
        trace_event0, trace_event0_with_flow_ids, trace_event1, trace_event1_with_flow_ids,
        trace_event2, trace_event2_int, trace_flow_begin, trace_flow_end, trace_flow_step,
    };
    trace_set_timeline_micros_source(counting_micros);
    for i in 0..cases {
        p!("case {i}");
        match r.below(16) {
            0 => {
                let n = r.below(4);
                w!("  allow");
                let allowlist: Vec<&str> = (0..n)
                    .map(|_| {
                        let word = K_TRACE_WORDS[r.below(6) as usize];
                        w!(" {}", quoted(word.as_bytes()));
                        word
                    })
                    .collect();
                p!("");
                trace_set_allowlist(&allowlist);
            }
            1 => {
                let set = !r.chance(3);
                trace_set_timeline_event_handler(if set { Some(print_trace_event) } else { None });
                p!("  handler {} {}", set as i32, trace_has_timeline_event_handler() as i32);
            }
            2 => {
                let counting = !r.chance(4);
                trace_set_timeline_micros_source(if counting { counting_micros } else { constant_micros });
                p!("  micros {} {}", counting as i32, trace_get_timeline_micros());
            }
            3 => {
                let label = trace_label(r);
                p!("  event0");
                {
                    trace_event0!("flutter", label);
                    p!("  inside");
                }
            }
            4 => {
                let label = trace_label(r);
                let value = trace_label(r);
                p!("  event1");
                {
                    trace_event1!("flutter", label, "k", value);
                    p!("  inside");
                }
            }
            5 => {
                let label = trace_label(r);
                let v1 = trace_label(r);
                let v2 = trace_label(r);
                p!("  event2");
                {
                    trace_event2!("flutter", label, "k1", v1, "k2", v2);
                    p!("  inside");
                }
            }
            6 => {
                let label = trace_label(r);
                let form = r.below(4);
                let n = edge_i64(r);
                let d = gen_trace_double(r);
                let t = gen_trace_point(r);
                p!("  fml-event {form}");
                match form {
                    0 => {
                        fml_trace_event!("flutter", label, "i", n as i32);
                        p!("  inside");
                    }
                    1 => {
                        fml_trace_event!("flutter", label, "s", trace_label(r).to_string(), "d", d);
                        p!("  inside");
                    }
                    2 => {
                        fml_trace_event!("flutter", label, "b", n % 2 == 0, "c", "chars", "t", t);
                        p!("  inside");
                    }
                    _ => {
                        fml_trace_event!("flutter", label, "u", n as u64, "f", d as f32, "n", n);
                        p!("  inside");
                    }
                }
            }
            7 => {
                let label = trace_label(r);
                let id = edge_i64(r);
                let two = r.chance(2);
                let n = edge_i64(r);
                let d = gen_trace_double(r);
                p!("  counter {}", two as i32);
                if two {
                    fml_trace_counter!("flutter", label, id, "x", d, "y", "str");
                } else {
                    fml_trace_counter!("flutter", label, id, "x", n);
                }
            }
            8 => {
                let label = trace_label(r);
                let id = edge_i64(r);
                let value = trace_label(r);
                let which = r.below(4);
                p!("  async {which}");
                match which {
                    0 => {
                        trace_event_async_begin0!("flutter", label, id);
                    }
                    1 => {
                        trace_event_async_end0!("flutter", label, id);
                    }
                    2 => {
                        trace_event_async_begin1!("flutter", label, id, "k", value);
                    }
                    _ => trace_event_async_end1("flutter", label, id, "k", value),
                }
            }
            9 => {
                let label = trace_label(r);
                let v1 = trace_label(r);
                let v2 = trace_label(r);
                let which = r.below(3);
                p!("  instant {which}");
                match which {
                    0 => {
                        trace_event_instant0!("flutter", label);
                    }
                    1 => {
                        trace_event_instant1!("flutter", label, "k", v1);
                    }
                    _ => {
                        trace_event_instant2!("flutter", label, "k1", v1, "k2", v2);
                    }
                }
            }
            10 => {
                let label = trace_label(r);
                let id = edge_i64(r);
                let which = r.below(3);
                p!("  flow {which}");
                match which {
                    0 => {
                        trace_flow_begin!("flutter", label, id);
                    }
                    1 => {
                        trace_flow_step!("flutter", label, id);
                    }
                    _ => {
                        trace_flow_end!("flutter", label, id);
                    }
                }
            }
            11 => {
                let label = trace_label(r);
                let begin = gen_trace_point(r);
                let end = gen_trace_point(r);
                let args = r.chance(2);
                p!("  complete {}", args as i32);
                if args {
                    let (keys, values) = fml::trace_split_arguments!("k", "v");
                    trace_event_async_complete("flutter", label, begin, end, &keys, &values);
                } else {
                    trace_event_async_complete("flutter", label, begin, end, &[], &[]);
                }
            }
            12 => {
                let label = trace_label(r);
                let other = trace_label(r);
                let steps = r.below(3);
                let named_step = r.chance(2);
                let end = r.chance(2);
                let move_ = r.chance(3);
                p!("  traceflow {} {} {} {}", steps, named_step as i32, end as i32, move_ as i32);
                let mut flow = TraceFlow::new(label);
                for _ in 0..steps {
                    flow.step(if named_step { Some(other) } else { None });
                }
                if move_ {
                    let moved = TraceFlow::take(&mut flow);
                    moved.step(None);
                }
                if end {
                    flow.end(Some(other));
                }
            }
            13 => {
                let label = trace_label(r);
                let mut ids = [0u64; 3];
                let count = r.below(4) as usize;
                for id in ids.iter_mut().take(count) {
                    *id = edge_i64(r) as u64;
                }
                let one = r.chance(2);
                let value = trace_label(r);
                p!("  with-flows {} {}", count, one as i32);
                if one {
                    trace_event1_with_flow_ids!("flutter", label, count, ids, "k", value);
                    p!("  inside");
                } else {
                    trace_event0_with_flow_ids!("flutter", label, count, ids);
                    p!("  inside");
                }
            }
            14 => {
                let label = trace_label(r);
                let a = edge_i64(r) as i32;
                let b = edge_i64(r);
                p!("  event2-int");
                {
                    trace_event2_int!("flutter", label, "a", a, "b", b);
                    p!("  inside");
                }
            }
            _ => {
                p!("  openfile nonce {}", trace_nonce());
                fml::file::open_file("/nonexistent-fml-oracle", false, FilePermission::kRead);
            }
        }
    }
    trace_set_timeline_event_handler(None);
}

// --------------------------------------------------------- backtrace ------

fn backtrace_shape(trace: &str) -> &'static str {
    if trace.is_empty() {
        return "empty";
    }
    let mut pos = 0;
    let mut expected = 0;
    while pos < trace.len() {
        let Some(eol) = trace[pos..].find('\n').map(|e| e + pos) else {
            return "unterminated";
        };
        let line = trace[pos..eol].as_bytes();
        let prefix = format!("Frame {expected}: 0x");
        if !line.starts_with(prefix.as_bytes()) {
            return "bad-number";
        }
        let mut i = prefix.len();
        let hex_start = i;
        while i < line.len() && line[i].is_ascii_hexdigit() {
            i += 1;
        }
        if i == hex_start || i + 1 >= line.len() || line[i] != b' ' {
            return "bad-frame";
        }
        expected += 1;
        pos = eol + 1;
    }
    "ok"
}

/// See DeepBacktrace in oracle/fml_dump.cc.
#[inline(never)]
fn deep_backtrace(depth: i32, offset: usize) -> String {
    if depth == 0 {
        return fml::backtrace::backtrace_here(offset);
    }
    let trace = deep_backtrace(std::hint::black_box(depth - 1), offset);
    std::hint::black_box(trace)
}

const K_CRASH_SIGNALS: [i32; 8] = [6, 8, 15, 11, 7, 31, 13, 14];

fn crash_child(signal: i32) {
    fml::backtrace::install_crash_handler();
    // SAFETY: raise sends a signal to this thread, whose handler (just
    // installed) logs and lets it kill the process.
    unsafe { c_raise(signal) };
    p!("survived");
}

fn run_crash_child(signal: i32) {
    use std::os::unix::process::ExitStatusExt;
    let out = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["crash", &signal.to_string(), "0"])
        .stdout(std::process::Stdio::null())
        .output()
        .unwrap();
    let (kind, code) = match out.status.signal() {
        Some(signal) => ("signal", signal),
        None => ("exit", out.status.code().unwrap_or(-1)),
    };
    let text = String::from_utf8_lossy(&out.stderr).into_owned();
    let (header, mut frames) = match text.find('\n') {
        Some(eol) => (text[..eol].to_string(), text[eol + 1..].to_string()),
        None => (text.clone(), String::new()),
    };
    let tail = frames.ends_with("\n\n");
    if tail {
        frames.pop();
    }
    p!("  child {kind} {code} {} frames {} tail {}", escaped(&header), backtrace_shape(&frames), tail as i32);
}

fn suite_backtrace(r: &mut Rng, cases: i32) {
    p!("supported {}", fml::backtrace::is_crash_handling_supported() as i32);
    for i in 0..cases {
        p!("case {i}");
        if r.chance(4) {
            let signal = K_CRASH_SIGNALS[r.below(8) as usize];
            p!("  crash {signal}");
            run_crash_child(signal);
        } else {
            const K_OFFSETS: [usize; 5] = [0, 1, 2, 3, 300];
            let offset = K_OFFSETS[r.below(5) as usize];
            p!("  here {} {}", offset, backtrace_shape(&deep_backtrace(8, offset)));
        }
    }
}
