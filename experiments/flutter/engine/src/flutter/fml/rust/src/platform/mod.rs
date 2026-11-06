// Not an upstream file: the module root for flutter/fml/platform.
//
// Ported: the Linux message loop and paths, and the POSIX files (file,
// mapping, paths, native libraries, command line, process,
// posix_wrappers). The other platforms' loops are not portable POSIX:
// Android's is an ALooper (with a timerfd), Darwin's a CFRunLoop, Fuchsia's
// an async::Loop and Windows' a Win32 message window; each waits for its
// platform's bindings.

#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(unix)]
pub mod posix;
