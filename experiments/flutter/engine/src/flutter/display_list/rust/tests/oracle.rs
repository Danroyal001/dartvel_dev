// Not an upstream file: byte comparison with the real upstream C++ foundation.
#![forbid(unsafe_code)]
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn build_oracle() -> PathBuf {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let src = manifest.join("../../..").canonicalize().unwrap();
    let work = std::env::temp_dir().join(format!("display-list-oracle-{}", std::process::id()));
    std::fs::create_dir_all(&work).unwrap();
    let binary = work.join("foundation_dump");
    let cxx = std::env::var("DL_ORACLE_CXX").unwrap_or_else(|_| "clang++-18".into());
    let mut command = Command::new(&cxx);
    command.args([
        "-std=c++20",
        "-O2",
        "-march=x86-64",
        "-ffp-contract=on",
        "-fwrapv",
        "-DNDEBUG",
        "-stdlib=libc++",
        "-fno-exceptions",
        "-fno-rtti",
    ]);
    command
        .arg("-I")
        .arg(&src)
        .arg("-I")
        .arg(src.join("flutter"));
    command.arg(manifest.join("oracle/foundation_dump.cc"));
    for file in [
        "display_list/utils/dl_accumulation_rect.cc",
        "fml/logging.cc",
        "fml/log_settings.cc",
        "fml/log_settings_state.cc",
    ] {
        command.arg(src.join("flutter").join(file));
    }
    let output = command.arg("-o").arg(&binary).output().unwrap_or_else(|e| {
        panic!(
            "C++ oracle compiler {cxx}: {e}. Set DL_ORACLE_CXX explicitly to use another toolchain."
        )
    });
    assert!(
        output.status.success(),
        "C++ build failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    binary
}

fn run(binary: &Path, input: &str) -> Vec<u8> {
    // Input and output can both exceed pipe capacity; a temporary input file
    // avoids a writer thread or a stdin/stdout pipe deadlock.
    let input_path =
        std::env::temp_dir().join(format!("display-list-input-{}", std::process::id()));
    std::fs::write(&input_path, input).unwrap();
    let output = Command::new(binary)
        .stdin(std::fs::File::open(&input_path).unwrap())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .unwrap();
    std::fs::remove_file(input_path).unwrap();
    assert!(
        output.status.success(),
        "{}: {}",
        binary.display(),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unexpected stderr: {:?}",
        output.stderr
    );
    output.stdout
}

#[test]
fn foundation_matches_real_cpp() {
    let cpp = build_oracle();
    let rust = Path::new(env!("CARGO_BIN_EXE_display_list_dump"));
    compare(&cpp, rust, &upstream_cases());
    let mut input = String::from("enums\nreset\n");
    let edges: [f32; 14] = [
        0.0,
        -0.0,
        1.0,
        -1.0,
        2.0,
        -2.0,
        f32::MIN_POSITIVE,
        f32::from_bits(1),
        f32::MAX,
        f32::MIN,
        f32::INFINITY,
        f32::NEG_INFINITY,
        f32::NAN,
        f32::from_bits(0xffc00000),
    ];
    // A small input per run keeps stdout safely below pipe capacity.
    for &x in &edges {
        for &y in &edges {
            input.push_str(&format!("point {} {}\n", x.to_bits(), y.to_bits()));
        }
        input.push_str("reset\n");
    }
    compare(&cpp, rust, &input);
    let seed_base: u64 = std::env::var("DL_ORACLE_SEED_BASE")
        .unwrap_or_else(|_| "1".into())
        .parse()
        .unwrap();
    for seed in seed_base..seed_base + 16 {
        let mut state = seed;
        for _ in 0..16 {
            let mut input = String::from("reset\n");
            for i in 0..64 {
                let mut next = || {
                    state = state.wrapping_add(0x9e3779b97f4a7c15);
                    let mut z = state;
                    z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
                    z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
                    ((z ^ (z >> 31)) as u32) % 512
                };
                let mut value = || {
                    let n = next();
                    if n < edges.len() as u32 {
                        edges[n as usize].to_bits()
                    } else {
                        ((n as f32 - 256.0) / 8.0).to_bits()
                    }
                };
                match i % 8 {
                    0 => input.push_str("reset\n"),
                    1 => input.push_str("overlap\n"),
                    2..=4 => input.push_str(&format!("point {} {}\n", value(), value())),
                    5..=6 => input.push_str(&format!(
                        "rect {} {} {} {}\n",
                        value(),
                        value(),
                        value(),
                        value()
                    )),
                    _ => input.push_str(&format!(
                        "merge 2 {} {} {} {} {} {} {} {}\n",
                        value(),
                        value(),
                        value(),
                        value(),
                        value(),
                        value(),
                        value(),
                        value()
                    )),
                }
            }
            compare(&cpp, rust, &input);
        }
    }
    std::fs::remove_dir_all(cpp.parent().unwrap()).unwrap();
}

// Cases from utils/dl_accumulation_rect_unittests.cc, including point and
// accumulator overloads' degenerate/empty distinction.
fn upstream_cases() -> String {
    let mut input = String::from("reset\n");
    for points in [
        vec![[10.0, 10.0]],
        vec![[10.0, 10.0], [10.0, 10.0]],
        vec![[10.0, 10.0], [20.0, 10.0]],
        vec![[10.0, 10.0], [10.0, 20.0]],
        vec![[10.0, 10.0], [20.0, 20.0]],
        vec![[10.0, 10.0]; 3],
        vec![[10.0, 10.0], [20.0, 10.0], [15.0, 10.0]],
        vec![[10.0, 10.0], [10.0, 20.0], [10.0, 15.0]],
        vec![[10.0, 10.0], [20.0, 20.0], [25.0, 15.0]],
        vec![[10.0, 10.0], [20.0, 20.0], [15.0, 15.0]],
    ] {
        input.push_str("reset\n");
        for [x, y] in points {
            input.push_str(&format!("point {} {}\n", f32::to_bits(x), f32::to_bits(y)));
        }
    }
    for r in [
        [10.0; 4],
        [10.0, 10.0, 20.0, 10.0],
        [10.0, 10.0, 10.0, 20.0],
        [10.0, 10.0, 20.0, 20.0],
    ] {
        for op in ["rect", "merge 1"] {
            input.push_str(&format!(
                "reset\n{op} {} {} {} {}\n",
                f32::to_bits(r[0]),
                f32::to_bits(r[1]),
                f32::to_bits(r[2]),
                f32::to_bits(r[3])
            ));
        }
    }
    for (a, b) in [
        ([10.0; 4], [20.0; 4]),
        ([10.0, 10.0, 20.0, 10.0], [10.0, 10.0, 10.0, 20.0]),
        ([10.0; 4], [15.0, 15.0, 20.0, 20.0]),
        ([10.0, 10.0, 15.0, 15.0], [20.0; 4]),
        ([10.0, 10.0, 15.0, 15.0], [15.0, 15.0, 20.0, 20.0]),
        ([10.0, 10.0, 15.0, 15.0], [16.0, 16.0, 20.0, 20.0]),
        ([10.0, 10.0, 16.0, 16.0], [15.0, 15.0, 20.0, 20.0]),
    ] {
        for op in ["rect", "merge 1"] {
            input.push_str("reset\n");
            for r in [a, b] {
                input.push_str(&format!(
                    "{op} {} {} {} {}\n",
                    f32::to_bits(r[0]),
                    f32::to_bits(r[1]),
                    f32::to_bits(r[2]),
                    f32::to_bits(r[3])
                ));
            }
        }
    }
    input
}

fn compare(cpp: &Path, rust: &Path, input: &str) {
    let expected = run(cpp, input);
    let actual = run(rust, input);
    if expected != actual {
        let a = String::from_utf8_lossy(&actual);
        let e = String::from_utf8_lossy(&expected);
        let index = e
            .lines()
            .zip(a.lines())
            .position(|(x, y)| x != y)
            .unwrap_or(0);
        panic!(
            "oracle difference at line {index}: C++ {:?}, Rust {:?}; input:\n{input}",
            e.lines().nth(index),
            a.lines().nth(index)
        );
    }
}
