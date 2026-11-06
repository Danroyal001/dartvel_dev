// Regression tests for the differential harness (not an upstream port).
#[path = "support/oracle.rs"]
#[allow(dead_code)]
mod oracle;

use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
};

struct Dumps(PathBuf);
impl Dumps {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "analyzer-oracle-comparison-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(dir.join("dart")).unwrap();
        fs::create_dir_all(dir.join("rust")).unwrap();
        Self(dir)
    }
    fn compare(&self) -> (usize, usize, String) {
        oracle::compare(&self.0.join("dart"), &self.0.join("rust"))
    }
}
impl Drop for Dumps {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

#[test]
fn missing_empty_dump_is_a_difference() {
    let dumps = Dumps::new();
    fs::write(dumps.0.join("dart/empty.body"), "").unwrap();
    let (files, differences, report) = dumps.compare();
    assert_eq!(files, 1);
    assert_eq!(
        differences, 1,
        "missing output must not match an empty dump"
    );
    assert!(report.contains("empty.body"));
    assert!(dumps.0.join("dart/empty.body").exists());
}

#[test]
fn extra_empty_dump_is_a_difference() {
    let dumps = Dumps::new();
    fs::write(dumps.0.join("rust/extra.body"), "").unwrap();
    let (files, differences, _) = dumps.compare();
    assert_eq!((files, differences), (0, 1));
}

#[test]
fn identical_empty_and_nonempty_dumps_match() {
    let dumps = Dumps::new();
    for side in ["dart", "rust"] {
        fs::write(dumps.0.join(side).join("empty.body"), "").unwrap();
        fs::write(dumps.0.join(side).join("literal.body"), "type=String\n").unwrap();
    }
    let (files, differences, _) = dumps.compare();
    assert_eq!((files, differences), (2, 0));
}
