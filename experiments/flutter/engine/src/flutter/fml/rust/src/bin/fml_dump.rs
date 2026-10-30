// Not an upstream file: the port's side of the oracle (see oracle/fml_dump.cc,
// which this mirrors suite by suite and line by line).
//
//   fml_dump <suite> <seed> <cases>     suite: time strings codec hash endian
//                                              trie queues all
//   fml_dump bench <name> <iterations>  name: queues time strings hash dispatch

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
use std::sync::{Arc, Weak};

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

macro_rules! w {
    ($($arg:tt)*) => {{
        let mut out = OUT.lock().unwrap();
        write!(out, $($arg)*).unwrap();
    }};
}
macro_rules! p {
    ($($arg:tt)*) => {{
        let mut out = OUT.lock().unwrap();
        writeln!(out, $($arg)*).unwrap();
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
    let mut rounds = Vec::new();
    for i in 0..iterations {
        let start = std::time::Instant::now();
        if name == "queues" {
            bench_register_and_get_tasks();
        } else {
            let mut r = Rng { s: i as u64 };
            match name {
                "time" => suite_time(&mut r, 20000),
                "strings" => suite_strings(&mut r, 20000),
                "hash" => suite_hash(&mut r, 20000),
                "dispatch" => suite_queues(&mut r, 2000),
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
    let mut r = Rng { s: args[2].parse().unwrap_or(0) };
    let cases: i32 = args[3].parse().unwrap_or(0);
    if !run_suite(suite, &mut r, cases) {
        eprintln!("unknown suite {suite}");
        std::process::exit(2);
    }
    std::io::stdout().write_all(&OUT.lock().unwrap()).unwrap();
}
