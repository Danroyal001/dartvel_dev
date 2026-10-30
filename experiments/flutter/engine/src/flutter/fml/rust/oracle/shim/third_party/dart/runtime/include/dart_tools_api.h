// Not an upstream file: stands in for the Dart VM's dart_tools_api.h when the
// oracle is built (the shim directory is searched before engine/src).
//
// flutter/fml/trace_event.h includes the real header for one declaration,
// the timeline event type its handler is called with; this checkout does not
// carry the Dart VM. The enum is copied from
// third_party/dart/runtime/include/dart_tools_api.h, values and order
// unchanged. Nothing else of the Dart API is declared, so fml's tracing is
// built as it is when no Dart VM has installed a timeline handler.

#ifndef RUNTIME_INCLUDE_DART_TOOLS_API_H_
#define RUNTIME_INCLUDE_DART_TOOLS_API_H_

typedef enum {
  Dart_Timeline_Event_Begin,          // Phase = 'B'.
  Dart_Timeline_Event_End,            // Phase = 'E'.
  Dart_Timeline_Event_Instant,        // Phase = 'i'.
  Dart_Timeline_Event_Duration,       // Phase = 'X'.
  Dart_Timeline_Event_Async_Begin,    // Phase = 'b'.
  Dart_Timeline_Event_Async_End,      // Phase = 'e'.
  Dart_Timeline_Event_Async_Instant,  // Phase = 'n'.
  Dart_Timeline_Event_Counter,        // Phase = 'C'.
  Dart_Timeline_Event_Flow_Begin,     // Phase = 's'.
  Dart_Timeline_Event_Flow_Step,      // Phase = 't'.
  Dart_Timeline_Event_Flow_End,       // Phase = 'f'.
} Dart_Timeline_Event_Type;

#endif  // RUNTIME_INCLUDE_DART_TOOLS_API_H_
