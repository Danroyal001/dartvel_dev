// Not an upstream file: the module root for flutter/fml/platform.
//
// Only the Linux message loop is ported. The other platforms' loops are not
// portable POSIX: Android's is an ALooper (with a timerfd), Darwin's a
// CFRunLoop, Fuchsia's an async::Loop and Windows' a Win32 message window;
// each waits for its platform's bindings.

#[cfg(target_os = "linux")]
pub mod linux;
