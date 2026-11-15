// Ours (not a ported file): a whole-program Dart compiler. See ../README.md.
//
// Pipeline: the ported `parseString` (../analyzer) parses the program and
// the core library (prelude.dart); lower.rs resolves names into ir.rs;
// shake.rs computes what can run; emit.rs writes C for exactly that; the
// system C compiler makes the executable.
#![forbid(unsafe_code)]

pub mod emit;
pub mod ir;
pub mod lower;
pub mod natives;
pub mod shake;
pub mod syntax;

use std::path::Path;
use std::process::Command;

pub use lower::CompileError;
pub use shake::Mode;

pub const PRELUDE: &str = include_str!("prelude.dart");

/// The result of compiling one program.
pub struct Compiled {
    pub c_source: String,
    pub program: ir::Program,
    pub reach: shake::Reach,
}

impl Compiled {
    /// A plain-text account of what was kept, one item per line, for
    /// `--report` and the tests.
    pub fn report(&self) -> String {
        let p = &self.program;
        let r = &self.reach;
        let mut out = String::new();
        out.push_str(&format!(
            "functions {} of {}\nclasses {} of {}\nselectors {}\nclass-names {}\n",
            r.funcs.len(),
            p.funcs.len(),
            r.classes.len(),
            p.classes.len(),
            r.selectors.len(),
            if r.class_names { "kept" } else { "dropped" }
        ));
        for &f in &r.funcs {
            out.push_str(&format!("function {}\n", p.funcs[f].name));
        }
        for &c in &r.classes {
            out.push_str(&format!("class {}\n", p.classes[c].name));
        }
        for s in &r.selectors {
            out.push_str(&format!("selector {s}\n"));
        }
        out
    }
}

fn syntax_error(file: &str, errors: Vec<syntax::SyntaxError>) -> CompileError {
    let first = &errors[0];
    CompileError {
        file: file.to_string(),
        offset: first.offset,
        message: format!("syntax error: {}", first.message),
    }
}

/// Compiles the Dart program [source] (read from [path]) to C.
pub fn compile(source: &str, path: &str, mode: Mode) -> Result<Compiled, CompileError> {
    let prelude =
        syntax::parse(PRELUDE, "prelude.dart").map_err(|e| syntax_error("prelude.dart", e))?;
    let user = syntax::parse(source, path).map_err(|e| syntax_error(path, e))?;
    let program = lower::lower(&prelude, &user, path)?;
    let reach = shake::analyse(&program, mode);
    let c_source = emit::emit(&program, &reach)?;
    Ok(Compiled {
        c_source,
        program,
        reach,
    })
}

/// The flags the C compiler gets: size first, no unwind tables (nothing
/// unwinds), sections the linker can drop, symbols stripped. Code and
/// read-only data share a segment (`-z noseparate-code`), which saves the
/// page of padding between them; the executable stays position-independent
/// with RELRO and a non-executable stack.
pub const C_FLAGS: &[&str] = &[
    "-Wl,-z,noseparate-code",
    "-Wl,--build-id=none",
    "-std=gnu11",
    "-Os",
    "-s",
    "-w",
    "-fno-strict-aliasing",
    "-fno-asynchronous-unwind-tables",
    "-fno-unwind-tables",
    "-ffunction-sections",
    "-fdata-sections",
    "-Wl,--gc-sections",
];

/// Writes [c_source] next to [output] and runs the C compiler (`$CC`, or
/// `cc`) on it.
pub fn build_executable(c_source: &str, output: &Path) -> Result<(), String> {
    let c_path = output.with_extension("c");
    std::fs::write(&c_path, c_source)
        .map_err(|e| format!("cannot write {}: {e}", c_path.display()))?;
    let cc = std::env::var("CC").unwrap_or_else(|_| "cc".to_string());
    let result = Command::new(&cc)
        .args(C_FLAGS)
        .arg("-o")
        .arg(output)
        .arg(&c_path)
        .output()
        .map_err(|e| format!("cannot run the C compiler `{cc}`: {e}"))?;
    if !result.status.success() {
        return Err(format!(
            "the C compiler failed:\n{}",
            String::from_utf8_lossy(&result.stderr)
        ));
    }
    Ok(())
}
