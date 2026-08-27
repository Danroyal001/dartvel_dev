# Running the engine on ARM without a television

`render_probe.c` starts the Flutter engine with the software renderer, sends
one window-metrics event, and writes the first presented frame to a PPM file.
No GL, no display, no window system: the engine hands back a buffer of pixels
and the probe writes them out.

That is the whole of "it runs" for webOS — the ARM engine loads, the AOT
library's Dart isolate starts, the widget tree builds, and something is
rasterised. Under `qemu-arm-static` it runs on any x86-64 machine, which is
why this is in CI and a television is not.

## What it does not prove

A television adds a window, an input stack and a GL path on top of this. None
of them would make a working engine stop working, but none of them is
exercised here. The status in `docs/build-targets.md` says so.

## Two things that cost a cycle each

The renderer config is a **union** with no `struct_size`.
`FlutterRendererConfig` copied by eye as a struct with one returns
`kInvalidArguments` and reads as a broken engine. The probe includes the
engine's own `embedder.h` rather than a hand copy.

A release engine has **no interpreter**, so it needs the AOT snapshot handed
to it through `FlutterEngineCreateAOTData`. Without that it stops at *"VM
snapshot invalid and could not be inferred from settings"* — which also reads
as a broken engine and is a missing argument.

## Running it

```sh
arm-linux-gnueabihf-gcc -o render render_probe.c -L. -lflutter_engine \
  -Wl,-rpath,'$ORIGIN'
qemu-arm-static -L /usr/arm-linux-gnueabihf ./render assets icudtl.dat libapp.so
```
