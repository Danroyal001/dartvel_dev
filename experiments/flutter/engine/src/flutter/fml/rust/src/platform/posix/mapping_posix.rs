// Port of flutter/fml/platform/posix/mapping_posix.cc: FileMapping's
// constructor (fstat, then mmap) and destructor (munmap).

use crate::mapping::{FileMapping, Protection};
use crate::platform::posix::libc;
use crate::unique_fd::UniqueFD;

fn to_posix_protection_flags(protection_flags: &[Protection]) -> i32 {
    let mut flags = 0;
    for protection in protection_flags {
        match protection {
            Protection::kRead => flags |= libc::PROT_READ,
            Protection::kWrite => flags |= libc::PROT_WRITE,
            Protection::kExecute => {
                // Do not combine write flags with execute flags.
                return libc::PROT_READ | libc::PROT_EXEC;
            }
        }
    }
    flags
}

fn is_writable(protection_flags: &[Protection]) -> bool {
    protection_flags.contains(&Protection::kWrite)
}

impl FileMapping {
    /// `FileMapping(fd, protection)`. Upstream's default protection is
    /// `{kRead}`. Note that `{kWrite, kExecute}` maps read and execute only
    /// (execute wins) yet shared and with a mutable pointer, as upstream
    /// does: writing through it faults.
    pub fn new(handle: &UniqueFD, protection: &[Protection]) -> FileMapping {
        let mut this = FileMapping {
            valid_: false,
            size_: 0,
            mapping_: std::ptr::null_mut(),
            mutable_mapping_: std::ptr::null_mut(),
        };
        if !handle.is_valid() {
            return this;
        }

        let mut stat_buffer = libc::stat::zeroed();

        // SAFETY: fstat writes one `struct stat`, which `stat_buffer` is.
        if unsafe { libc::fstat(handle.get(), &mut stat_buffer) } != 0 {
            return this;
        }

        if stat_buffer.st_size == 0 {
            this.valid_ = true;
            return this;
        }

        let is_writable = is_writable(protection);

        // SAFETY: a fresh mapping at an address the kernel picks (addr null)
        // aliases nothing of ours; it is unmapped only by Drop, with the same
        // size.
        let mapping = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                stat_buffer.st_size as usize,
                to_posix_protection_flags(protection),
                if is_writable { libc::MAP_SHARED } else { libc::MAP_PRIVATE },
                handle.get(),
                0,
            )
        };

        if mapping == libc::MAP_FAILED {
            return this;
        }

        this.mapping_ = mapping as *mut u8;
        this.size_ = stat_buffer.st_size as usize;
        this.valid_ = true;
        if is_writable {
            this.mutable_mapping_ = this.mapping_;
        }
        this
    }

    /// `FileMapping(fd)`: read only.
    pub fn new_read_only(handle: &UniqueFD) -> FileMapping {
        FileMapping::new(handle, &[Protection::kRead])
    }
}

impl Drop for FileMapping {
    fn drop(&mut self) {
        if !self.mapping_.is_null() {
            // SAFETY: mapping_ and size_ are exactly what mmap returned and
            // was given; nothing borrowed from the mapping outlives `self`.
            unsafe {
                libc::munmap(self.mapping_ as *mut std::os::raw::c_void, self.size_);
            }
        }
    }
}
