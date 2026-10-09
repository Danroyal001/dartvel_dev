// The EGL context Flutter's Linux embedder leaves current on the GTK main
// thread has to be released, or GDK's next GLX paint makes libglvnd raise
// BadAccess and GDK ends the process. This makes a real EGL context current on
// the test's thread, as the embedder does, and checks the release clears it.
//
// Live: needs libEGL with Mesa's surfaceless platform, which every Mesa
// install has. Skipped where there is no libEGL at all.
@TestOn('linux')
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as ffi show calloc;

import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter_test/flutter_test.dart';

const int eglPlatformSurfacelessMesa = 0x31DD;
const int eglOpenGlEsApi = 0x30A0;
const int eglNone = 0x3038;
const int eglContextClientVersion = 0x3098;

void main() {
  ffi.DynamicLibrary? egl;
  try {
    egl = ffi.DynamicLibrary.open('libEGL.so.1');
  } on ArgumentError {
    egl = null;
  }

  test('releases an EGL context left current on this thread', () {
    final lib = egl!;
    final getPlatformDisplay = lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Uint32, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.IntPtr>),
        ffi.Pointer<ffi.Void> Function(int, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.IntPtr>)>(
      'eglGetPlatformDisplay',
    );
    final initialize = lib.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Int32>)>('eglInitialize');
    final bindApi = lib.lookupFunction<ffi.Uint32 Function(ffi.Uint32), int Function(int)>('eglBindAPI');
    final createContext = lib.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int32>)>(
      'eglCreateContext',
    );
    final makeCurrent = lib.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>('eglMakeCurrent');
    final currentContext = lib.lookupFunction<ffi.Pointer<ffi.Void> Function(), ffi.Pointer<ffi.Void> Function()>(
      'eglGetCurrentContext',
    );
    final destroyContext = lib.lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
        int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>('eglDestroyContext');

    final display = getPlatformDisplay(eglPlatformSurfacelessMesa, ffi.nullptr, ffi.nullptr);
    expect(display, isNot(ffi.nullptr), reason: 'no surfaceless EGL display');
    expect(initialize(display, ffi.nullptr, ffi.nullptr), isNonZero);
    expect(bindApi(eglOpenGlEsApi), isNonZero);
    // No config: EGL_KHR_no_config_context, which Mesa has.
    // EGL_CONTEXT_CLIENT_VERSION 2: without it the context is GLES 1.
    final attributes = ffi.calloc<ffi.Int32>(3);
    attributes[0] = eglContextClientVersion;
    attributes[1] = 2;
    attributes[2] = eglNone;
    final context = createContext(display, ffi.nullptr, ffi.nullptr, attributes);
    ffi.calloc.free(attributes);
    expect(context, isNot(ffi.nullptr), reason: 'could not create an EGL context');
    expect(makeCurrent(display, ffi.nullptr, ffi.nullptr, context), isNonZero);
    expect(currentContext(), context);

    expect(DVWindowHost.debugReleaseCurrentEglContext(), isTrue);

    expect(currentContext(), ffi.nullptr);
    destroyContext(display, context);
  }, skip: egl == null ? 'no libEGL on this machine' : false);

  test('is a no-op when nothing is current', () {
    expect(DVWindowHost.debugReleaseCurrentEglContext(), isFalse);
  }, skip: egl == null ? 'no libEGL on this machine' : false);
}
