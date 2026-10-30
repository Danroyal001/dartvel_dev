// Not an upstream file: the port's side of the oracle (see oracle/fml_dump.cc,
// which this mirrors suite by suite and line by line).
//
//   fml_dump <suite> <seed> <cases>     suite: time strings codec hash endian
//                                              trie queues all
//   fml_dump bench <name> <iterations>  name: queues time strings hash dispatch

use std::io::Write;

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

// -------------------------------------------------------------- main -------

fn run_suite(suite: &str, r: &mut Rng, cases: i32) -> bool {
    let all = suite == "all";
    let mut known = false;
    if all || suite == "time" {
        known = true;
        suite_time(r, cases);
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
    let mut r = Rng { s: args[2].parse().unwrap_or(0) };
    let cases: i32 = args[3].parse().unwrap_or(0);
    if !run_suite(suite, &mut r, cases) {
        eprintln!("unknown suite {suite}");
        std::process::exit(2);
    }
    std::io::stdout().write_all(&OUT.lock().unwrap()).unwrap();
}
