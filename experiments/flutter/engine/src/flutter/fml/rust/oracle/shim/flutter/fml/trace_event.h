// Not an upstream file: stands in for flutter/fml/trace_event.h when the
// oracle is built (the shim directory is searched before engine/src).
//
// The real header includes the Dart VM's dart_tools_api.h, which this
// checkout does not carry. Of the oracle's sources only
// concurrent_message_loop.cc traces (TRACE_EVENT0 "ConcurrentWorkerWake"),
// and a trace event has no effect the oracle could observe, so it is a no-op
// here as it is in a FLUTTER_RELEASE build of the real header.

#ifndef FLUTTER_FML_TRACE_EVENT_H_
#define FLUTTER_FML_TRACE_EVENT_H_

#define TRACE_EVENT0(category_group, name)

#endif  // FLUTTER_FML_TRACE_EVENT_H_
