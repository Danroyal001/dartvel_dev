// Port of flutter/fml/backtrace.h and flutter/fml/backtrace.cc (the POSIX
// branch; Windows' CaptureStackBackTrace and CRT report mode are not
// ported, and backtrace_stub.cc is what a build without backtraces uses).
//
// The frames come from the C library's backtrace(), as upstream's do. Each
// is named as absl::Symbolize names it on Linux, from the ELF symbol tables
// of the object mapped at its address (found through /proc/self/maps):
// `.symtab`, then `.dynsym`, the function or object whose range holds the
// address. absl then demangles C++ names; the names here are left as the
// object file spells them (a Rust frame reads `_ZN...E` or `_R...`), so a
// frame's name text differs from an absl-symbolized one while its line,
// "Frame <i>: <address> <name>", is upstream's. "Unknown" is a frame no
// symbol covers.
//
// The symbolizer reads files and allocates, as upstream's crash handler
// logs (and allocates) from inside a signal handler; neither is
// async-signal-safe. Parsed objects are cached; the cache is only tried
// (never waited for), so a signal arriving while it is held does not
// deadlock, it reads the object again.

use std::collections::HashMap;
use std::os::raw::{c_int, c_void};
use std::sync::{Arc, Mutex};

use crate::fml_log_at;

const FILE: &str = "flutter/fml/backtrace.cc";

const K_K_UNKNOWN_FRAME_NAME: &str = "Unknown";

// SAFETY: declarations only, each matching its prototype in <execinfo.h> and <signal.h>
// for the LP64 Linux/Apple targets this crate builds for; every call
// below is in its own unsafe block that says why it is sound.
unsafe extern "C" {
    #[link_name = "backtrace"]
    fn c_backtrace(buffer: *mut *mut c_void, size: c_int) -> c_int;
    fn signal(signum: c_int, handler: usize) -> usize;
    fn raise(sig: c_int) -> c_int;
}

const SIG_DFL: usize = 0;
const SIG_ERR: usize = !0;

const SIGABRT: c_int = 6;
const SIGFPE: c_int = 8;
const SIGTERM: c_int = 15;
const SIGSEGV: c_int = 11;
const SIGBUS: c_int = 7;
const SIGSYS: c_int = 31;
const SIGPIPE: c_int = 13;
const SIGALRM: c_int = 14;

// ------------------------------------------------------------ symbolize ---

/// One object's symbols: its loadable segments and its function and object
/// symbols, sorted by address.
struct ElfSymbols {
    /// (p_offset, p_vaddr, p_filesz) of each PT_LOAD.
    loads: Vec<(u64, u64, u64)>,
    /// (st_value, st_size, name), .symtab's first, then .dynsym's.
    symbols: Vec<(u64, u64, String)>,
}

fn u16_at(b: &[u8], o: usize) -> Option<u16> {
    Some(u16::from_le_bytes(b.get(o..o + 2)?.try_into().ok()?))
}
fn u32_at(b: &[u8], o: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(o..o + 4)?.try_into().ok()?))
}
fn u64_at(b: &[u8], o: usize) -> Option<u64> {
    Some(u64::from_le_bytes(b.get(o..o + 8)?.try_into().ok()?))
}

fn c_str_at(b: &[u8], o: usize) -> Option<String> {
    let rest = b.get(o..)?;
    let end = rest.iter().position(|&c| c == 0)?;
    Some(String::from_utf8_lossy(&rest[..end]).into_owned())
}

/// Parses a little-endian ELF64 file's program headers and symbol tables.
fn parse_elf(b: &[u8]) -> Option<ElfSymbols> {
    if b.get(0..4)? != b"\x7fELF" || *b.get(4)? != 2 || *b.get(5)? != 1 {
        return None;
    }
    let phoff = u64_at(b, 0x20)? as usize;
    let shoff = u64_at(b, 0x28)? as usize;
    let phentsize = u16_at(b, 0x36)? as usize;
    let phnum = u16_at(b, 0x38)? as usize;
    let shentsize = u16_at(b, 0x3a)? as usize;
    let shnum = u16_at(b, 0x3c)? as usize;

    let mut loads = Vec::new();
    for i in 0..phnum {
        let p = phoff + i * phentsize;
        if u32_at(b, p)? == 1 {
            loads.push((u64_at(b, p + 8)?, u64_at(b, p + 16)?, u64_at(b, p + 32)?));
        }
    }

    let mut symbols = Vec::new();
    for wanted in [2u32 /* SHT_SYMTAB */, 11 /* SHT_DYNSYM */] {
        for i in 0..shnum {
            let s = shoff + i * shentsize;
            if u32_at(b, s + 4)? != wanted {
                continue;
            }
            let offset = u64_at(b, s + 24)? as usize;
            let size = u64_at(b, s + 32)? as usize;
            let link = u32_at(b, s + 40)? as usize;
            let entsize = (u64_at(b, s + 56)? as usize).max(24);
            let strtab = shoff + link * shentsize;
            let str_offset = u64_at(b, strtab + 24)? as usize;
            for k in 0..size / entsize {
                let sym = offset + k * entsize;
                let info = *b.get(sym + 4)?;
                let shndx = u16_at(b, sym + 6)?;
                let kind = info & 0xf;
                if shndx == 0 || (kind != 1 && kind != 2) {
                    continue;
                }
                let value = u64_at(b, sym + 8)?;
                let sym_size = u64_at(b, sym + 16)?;
                let name = c_str_at(b, str_offset + u32_at(b, sym)? as usize)?;
                if !name.is_empty() {
                    symbols.push((value, sym_size, name));
                }
            }
        }
    }
    Some(ElfSymbols { loads, symbols })
}

static SYMBOL_CACHE: Mutex<Option<HashMap<String, Option<Arc<ElfSymbols>>>>> = Mutex::new(None);

fn symbols_of(path: &str) -> Option<Arc<ElfSymbols>> {
    if let Ok(cache) = SYMBOL_CACHE.try_lock() {
        if let Some(found) = cache.as_ref().and_then(|c| c.get(path)) {
            return found.clone();
        }
    }
    let parsed = std::fs::read(path).ok().and_then(|bytes| parse_elf(&bytes)).map(Arc::new);
    if let Ok(mut cache) = SYMBOL_CACHE.try_lock() {
        cache.get_or_insert_with(HashMap::new).insert(path.to_string(), parsed.clone());
    }
    parsed
}

/// The name of the symbol covering `pc`, as absl::Symbolize finds it (see
/// the top of the file).
fn symbolize(pc: usize) -> Option<String> {
    let maps = std::fs::read_to_string("/proc/self/maps").ok()?;
    for line in maps.lines() {
        let mut fields = line.split_whitespace();
        let range = fields.next()?;
        let _perms = fields.next()?;
        let offset = u64::from_str_radix(fields.next()?, 16).ok()?;
        let _dev = fields.next();
        let _inode = fields.next();
        let path = fields.collect::<Vec<_>>().join(" ");
        let (start, end) = range.split_once('-')?;
        let start = usize::from_str_radix(start, 16).ok()?;
        let end = usize::from_str_radix(end, 16).ok()?;
        if pc < start || pc >= end {
            continue;
        }
        if !path.starts_with('/') {
            return None;
        }
        let elf = symbols_of(&path)?;
        let file_offset = (pc - start) as u64 + offset;
        let &(p_offset, p_vaddr, _) = elf
            .loads
            .iter()
            .find(|&&(p_offset, _, p_filesz)| p_offset <= file_offset && file_offset < p_offset + p_filesz)?;
        let vaddr = file_offset - p_offset + p_vaddr;
        return elf
            .symbols
            .iter()
            .find(|(value, size, _)| *value <= vaddr && (vaddr < value + size || (*size == 0 && vaddr == *value)))
            .map(|(_, _, name)| name.clone());
    }
    None
}

// ------------------------------------------------------------ backtrace ---

fn get_symbol_name(symbol: *mut c_void) -> String {
    symbolize(symbol as usize).unwrap_or_else(|| K_K_UNKNOWN_FRAME_NAME.to_string())
}

fn backtrace(symbols: &mut [*mut c_void]) -> c_int {
    // SAFETY: backtrace writes at most `len` pointers into the buffer.
    unsafe { c_backtrace(symbols.as_mut_ptr(), symbols.len() as c_int) }
}

/// The current thread's stack, one "Frame <i>: <address> <name>" line per
/// frame, leaving out this function's own frames and `offset` more.
#[inline(never)]
pub fn backtrace_here(mut offset: usize) -> String {
    const K_MAX_FRAMES: usize = 256;
    let mut symbols = [std::ptr::null_mut::<c_void>(); K_MAX_FRAMES];
    let available_frames = backtrace(&mut symbols);
    if available_frames <= 0 {
        return String::new();
    }

    // Exclude here.
    offset += 2;

    let mut stream = String::new();
    let mut i = offset;
    while i < available_frames as usize {
        stream.push_str(&format!(
            "Frame {}: {:p} {}\n",
            i - offset,
            symbols[i],
            get_symbol_name(symbols[i])
        ));
        i += 1;
    }
    stream
}

const K_KNOWN_SIGNAL_HANDLERS: [c_int; 8] = [
    SIGABRT, // abort program
    SIGFPE,  // floating-point exception
    SIGTERM, // software termination signal
    SIGSEGV, // segmentation violation
    SIGBUS,  // bus error
    SIGSYS,  // non-existent system call invoked
    SIGPIPE, // write on a pipe with no reader
    SIGALRM, // real-time timer expired
];

fn signal_name_to_string(signal: c_int) -> String {
    match signal {
        SIGABRT => "SIGABRT".into(),
        SIGFPE => "SIGFPE".into(),
        SIGSEGV => "SIGSEGV".into(),
        SIGTERM => "SIGTERM".into(),
        SIGBUS => "SIGBUS".into(),
        SIGSYS => "SIGSYS".into(),
        SIGPIPE => "SIGPIPE".into(),
        SIGALRM => "SIGALRM".into(),
        _ => signal.to_string(),
    }
}

extern "C" fn signal_handler(signal: c_int) {
    // We are a crash signal handler. This can only happen once. Since we don't
    // want to catch crashes while we are generating the crash reports, disable
    // all set signal handlers to their default values before reporting the crash
    // and re-raising the signal.
    toggle_signal_handlers(false);

    fml_log_at!(
        kLogError,
        FILE,
        108,
        "Caught signal {} during program execution.\n{}",
        signal_name_to_string(signal),
        backtrace_here(3)
    );

    // SAFETY: raise only sends a signal to this thread; the handlers were
    // reset to the defaults above, so it terminates as the signal would have.
    unsafe {
        raise(signal);
    }
}

fn toggle_signal_handlers(set: bool) {
    for signal_name in K_KNOWN_SIGNAL_HANDLERS {
        let handler = if set { signal_handler as extern "C" fn(c_int) as usize } else { SIG_DFL };

        // SAFETY: signal installs either SIG_DFL or `signal_handler`, an
        // `extern "C" fn(c_int)` that lives for the whole program, for a
        // signal that may be caught.
        if unsafe { signal(signal_name, handler) } == SIG_ERR {
            fml_log_at!(kLogError, FILE, 121, "Could not attach signal handler for {}", signal_name);
        }
    }
}

/// Installs a handler for crash signals that logs the signal and a
/// backtrace at ERROR, then lets the signal kill the process. Replaces
/// whatever handlers were there (Rust's own SIGSEGV stack-overflow reporter
/// and its SIGPIPE ignore among them, as upstream's replaces the C++
/// runtime's).
pub fn install_crash_handler() {
    // absl::InitializeSymbolizer(GetExecutablePath()) has no counterpart:
    // the symbolizer here finds objects through /proc/self/maps when asked.
    toggle_signal_handlers(true);
}

pub fn is_crash_handling_supported() -> bool {
    true
}
