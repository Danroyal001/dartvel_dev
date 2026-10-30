// Port of flutter/fml/file_unittest.cc.

use std::cell::RefCell;
use std::collections::BTreeSet;

use super::file::*;
use super::mapping::{DataMapping, FileMapping, Mapping, Protection};
use super::paths;
use super::unique_fd::UniqueFD;

fn write_string_to_file(fd: &UniqueFD, contents: &str) -> bool {
    if !truncate_file(fd, contents.len()) {
        return false;
    }

    let mapping = FileMapping::new(fd, &[Protection::kWrite]);
    if mapping.get_size() != contents.len() {
        return false;
    }

    if mapping.get_mutable_mapping().is_null() {
        return false;
    }

    // SAFETY: the mapping is shared and writable, and holds exactly
    // contents.len() bytes.
    unsafe {
        std::ptr::copy(contents.as_ptr(), mapping.get_mutable_mapping(), contents.len());
    }
    true
}

fn read_string_from_file(fd: &UniqueFD) -> String {
    let mapping = FileMapping::new_read_only(fd);

    if mapping.get_mapping().is_null() {
        return String::new();
    }

    // SAFETY: a read-only mapping of get_size() readable bytes.
    let bytes = unsafe { std::slice::from_raw_parts(mapping.get_mapping(), mapping.get_size()) };
    String::from_utf8_lossy(bytes).into_owned()
}

fn names_visitor(names: &RefCell<BTreeSet<String>>) -> impl FnMut(&UniqueFD, &[u8]) -> bool + '_ {
    |_: &UniqueFD, filename: &[u8]| {
        names.borrow_mut().insert(String::from_utf8_lossy(filename).into_owned());
        true
    }
}

fn set(names: &[&str]) -> BTreeSet<String> {
    names.iter().map(|s| s.to_string()).collect()
}

#[test]
fn create_temporary_and_unlink() {
    let dir_name = create_temporary_directory();
    assert_ne!(dir_name, "");
    let mut dir = open_directory(&dir_name, false, FilePermission::kRead);
    assert!(dir.is_valid());
    dir.reset_invalid();
    assert!(unlink_directory(&dir_name));
}

#[test]
fn scoped_temp_dir_is_valid() {
    let dir = ScopedTemporaryDirectory::new();
    assert!(dir.fd().is_valid());
}

#[test]
fn can_open_file_for_writing() {
    let dir = ScopedTemporaryDirectory::new();
    assert!(dir.fd().is_valid());

    let mut fd = open_file_at(dir.fd(), "some.txt", true, FilePermission::kWrite);
    assert!(fd.is_valid());
    fd.reset_invalid();
    assert!(unlink_file_at(dir.fd(), "some.txt"));
}

#[test]
fn can_truncate_and_write() {
    let dir = ScopedTemporaryDirectory::new();
    assert!(dir.fd().is_valid());

    let contents = "some contents here";

    // On the first iteration, this tests writing and then reading a file that
    // didn't exist yet. On the second iteration it tests truncating, writing,
    // and reading a file that already existed.
    for _ in 0..2 {
        {
            let fd = open_file_at(dir.fd(), "some.txt", true, FilePermission::kReadWrite);
            assert!(fd.is_valid());

            assert!(truncate_file(&fd, contents.len()));

            let mapping = FileMapping::new(&fd, &[Protection::kWrite]);
            assert_eq!(mapping.get_size(), contents.len());
            assert!(!mapping.get_mutable_mapping().is_null());

            // SAFETY: shared, writable, contents.len() bytes.
            unsafe {
                std::ptr::copy_nonoverlapping(
                    contents.as_ptr(),
                    mapping.get_mutable_mapping(),
                    contents.len(),
                );
            }
        }

        {
            let fd = open_file_at(dir.fd(), "some.txt", false, FilePermission::kRead);
            assert!(fd.is_valid());

            let mapping = FileMapping::new_read_only(&fd);
            assert_eq!(mapping.get_size(), contents.len());

            // SAFETY: read-only mapping of get_size() bytes.
            let bytes = unsafe { std::slice::from_raw_parts(mapping.get_mapping(), mapping.get_size()) };
            assert_eq!(bytes, contents.as_bytes());
        }
    }

    unlink_file_at(dir.fd(), "some.txt");
}

#[test]
fn create_directory_structure() {
    let dir = ScopedTemporaryDirectory::new();

    let contents = "These are my contents";
    {
        let sub = create_directory(dir.fd(), &["a", "b", "c"], FilePermission::kReadWrite);
        assert!(sub.is_valid());
        let file = open_file_at(&sub, "my_contents", true, FilePermission::kReadWrite);
        assert!(file.is_valid());
        assert!(write_string_to_file(&file, contents));
    }

    let file_path = "a/b/c/my_contents";

    {
        let contents_file = open_file_at(dir.fd(), file_path, false, FilePermission::kRead);
        assert_eq!(read_string_from_file(&contents_file), contents);
    }

    // Cleanup.
    assert!(unlink_file_at(dir.fd(), file_path));
    assert!(unlink_directory_at(dir.fd(), "a/b/c"));
    assert!(unlink_directory_at(dir.fd(), "a/b"));
    assert!(unlink_directory_at(dir.fd(), "a"));
}

#[test]
fn visit_files_can_be_called_twice() {
    let dir = ScopedTemporaryDirectory::new();

    {
        let file = open_file_at(dir.fd(), "my_contents", true, FilePermission::kReadWrite);
        assert!(file.is_valid());
    }

    let mut count = 0;
    let mut count_visitor = |_: &UniqueFD, _: &[u8]| {
        count += 1;
        true
    };
    visit_files(dir.fd(), &mut count_visitor);
    assert_eq!(count, 1);

    // Without `rewinddir` in `VisitFiles`, the following check would fail.
    count = 0;
    let mut count_visitor = |_: &UniqueFD, _: &[u8]| {
        count += 1;
        true
    };
    visit_files(dir.fd(), &mut count_visitor);
    assert_eq!(count, 1);

    assert!(unlink_file_at(dir.fd(), "my_contents"));
}

#[test]
fn can_list_files_recursively() {
    let dir = ScopedTemporaryDirectory::new();

    {
        let c = create_directory(dir.fd(), &["a", "b", "c"], FilePermission::kReadWrite);
        assert!(c.is_valid());
        let file1 = open_file_at(&c, "file1", true, FilePermission::kReadWrite);
        let file2 = open_file_at(&c, "file2", true, FilePermission::kReadWrite);
        let d = create_directory(&c, &["d"], FilePermission::kReadWrite);
        assert!(d.is_valid());
        let file3 = open_file_at(&d, "file3", true, FilePermission::kReadWrite);
        assert!(file1.is_valid());
        assert!(file2.is_valid());
        assert!(file3.is_valid());
    }

    let names = RefCell::new(BTreeSet::new());
    visit_files_recursively(dir.fd(), &mut names_visitor(&names));
    assert_eq!(*names.borrow(), set(&["a", "b", "c", "d", "file1", "file2", "file3"]));

    // Cleanup.
    assert!(unlink_file_at(dir.fd(), "a/b/c/d/file3"));
    assert!(unlink_file_at(dir.fd(), "a/b/c/file1"));
    assert!(unlink_file_at(dir.fd(), "a/b/c/file2"));
    assert!(unlink_directory_at(dir.fd(), "a/b/c/d"));
    assert!(unlink_directory_at(dir.fd(), "a/b/c"));
    assert!(unlink_directory_at(dir.fd(), "a/b"));
    assert!(unlink_directory_at(dir.fd(), "a"));
}

#[test]
fn can_stop_visit_early() {
    let dir = ScopedTemporaryDirectory::new();

    {
        let d = create_directory(dir.fd(), &["a", "b", "c", "d"], FilePermission::kReadWrite);
        assert!(d.is_valid());
    }

    let mut names = BTreeSet::new();
    let mut visitor = |_: &UniqueFD, filename: &[u8]| {
        names.insert(String::from_utf8_lossy(filename).into_owned());
        filename != b"c" // stop if c is found
    };

    // Check the d is not visited as we stop at c.
    assert!(!visit_files_recursively(dir.fd(), &mut visitor));
    assert_eq!(names, set(&["a", "b", "c"]));

    // Cleanup.
    assert!(unlink_directory_at(dir.fd(), "a/b/c/d"));
    assert!(unlink_directory_at(dir.fd(), "a/b/c"));
    assert!(unlink_directory_at(dir.fd(), "a/b"));
    assert!(unlink_directory_at(dir.fd(), "a"));
}

#[test]
fn atomic_write_test() {
    let dir = ScopedTemporaryDirectory::new();

    let contents = "These are my contents.";

    let data = DataMapping::new(contents.as_bytes().to_vec());

    // Write.
    assert!(write_atomically(dir.fd(), "precious_data", &data));

    // Read and verify.
    assert_eq!(
        contents,
        read_string_from_file(&open_file_at(dir.fd(), "precious_data", false, FilePermission::kRead))
    );

    // Cleanup.
    assert!(unlink_file_at(dir.fd(), "precious_data"));
}

#[test]
fn ignore_base_dir_when_path_is_absolute() {
    let dir = ScopedTemporaryDirectory::new();

    // Make an absolute path.
    let filename = "filename.txt";
    let full_path = paths::absolute_path(paths::join_paths(&[dir.path().as_str(), filename]));

    let contents = "These are my contents.";
    let data = DataMapping::new(contents.as_bytes().to_vec());

    // Write.
    assert!(write_atomically(dir.fd(), &full_path, &data));

    // Test existence.
    assert!(file_exists(dir.fd(), &full_path));

    // Read and verify.
    assert_eq!(
        contents,
        read_string_from_file(&open_file_at(dir.fd(), &full_path, false, FilePermission::kRead))
    );

    // Cleanup.
    assert!(unlink_file_at(dir.fd(), &full_path));
}

#[test]
fn empty_mapping_test() {
    let dir = ScopedTemporaryDirectory::new();

    {
        let file = open_file_at(dir.fd(), "my_contents", true, FilePermission::kReadWrite);

        let mapping = FileMapping::new_read_only(&file);
        assert!(mapping.is_valid());
        assert_eq!(mapping.get_size(), 0);
        assert!(mapping.get_mapping().is_null());
    }

    assert!(unlink_file_at(dir.fd(), "my_contents"));
}

#[test]
fn mapping_dont_need_safe_test() {
    let dir = ScopedTemporaryDirectory::new();

    {
        let file = open_file_at(dir.fd(), "my_contents", true, FilePermission::kReadWrite);
        write_string_to_file(&file, "some content");
    }

    {
        let file = open_file_at(dir.fd(), "my_contents", false, FilePermission::kRead);
        let mapping = FileMapping::new_read_only(&file);
        assert!(mapping.is_valid());
        assert!(mapping.get_mutable_mapping().is_null());
        assert!(mapping.is_dont_need_safe());
    }

    {
        let file = open_file_at(dir.fd(), "my_contents", false, FilePermission::kReadWrite);
        let mapping = FileMapping::new(&file, &[Protection::kRead, Protection::kWrite]);
        assert!(mapping.is_valid());
        assert!(!mapping.get_mutable_mapping().is_null());
        assert!(!mapping.is_dont_need_safe());
    }
    assert!(unlink_file_at(dir.fd(), "my_contents"));
}

#[test]
fn file_tests_work() {
    let dir = ScopedTemporaryDirectory::new();
    assert!(dir.fd().is_valid());
    let filename = "some.txt";
    let mut fd = open_file_at(dir.fd(), filename, true, FilePermission::kWrite);
    assert!(fd.is_valid());
    fd.reset_invalid();
    assert!(file_exists(dir.fd(), filename));
    assert!(is_file(paths::join_paths(&[dir.path().as_str(), filename])));
    assert!(unlink_file_at(dir.fd(), filename));
}

#[test]
fn file_tests_supports_unicode() {
    let dir = ScopedTemporaryDirectory::new();
    assert!(dir.fd().is_valid());
    let filename = "äëïöüテスト☃";
    let mut fd = open_file_at(dir.fd(), filename, true, FilePermission::kWrite);
    assert!(fd.is_valid());
    fd.reset_invalid();
    assert!(file_exists(dir.fd(), filename));
    assert!(is_file(paths::join_paths(&[dir.path().as_str(), filename])));
    assert!(unlink_file_at(dir.fd(), filename));
}

// Not upstream's: ScopedTemporaryDirectory's destructor empties and removes
// its directory, including subdirectories (upstream only checks the fd).
#[test]
fn scoped_temp_dir_removes_its_tree() {
    let path;
    {
        let dir = ScopedTemporaryDirectory::new();
        path = dir.path().clone();
        let sub = create_directory(dir.fd(), &["x", "y"], FilePermission::kReadWrite);
        assert!(sub.is_valid());
        assert!(write_atomically(&sub, "f", &DataMapping::from_string("z")));
    }
    assert!(!std::path::Path::new(&path).exists());
}
