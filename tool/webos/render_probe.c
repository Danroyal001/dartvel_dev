/* Run the engine on ARM and get a frame out of it.
 *
 * The software renderer, so there is no GL, no display and no window system to
 * arrange: the engine hands back a buffer of pixels and this writes them out.
 * That is the whole of "it runs" — the AOT library loads, a Dart isolate
 * starts, the widget tree builds, and something is rasterised.
 *
 * A television adds a window and an input stack on top of this. It does not
 * add anything that would make a working engine stop working.
 *
 * Built against the engine's own embedder.h rather than a hand copy of it. The
 * first attempt copied the structs by eye and got kInvalidArguments, because
 * FlutterRendererConfig is a union with no struct_size and the copy was a
 * struct with one.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#include "flutter_embedder.h"

/* Written on the raster thread, read on the main one. */
static volatile int frames = 0;

static bool present(void* user_data, const void* allocation, size_t row_bytes,
                    size_t height) {
  /* The counter is raised at the end rather than here, so that it means "a
   * complete frame is on disk" rather than "a frame arrived". The main thread
   * exits the moment it sees this, and raising it first left it racing the
   * write on the raster thread -- which produced a present callback, a
   * success, and a zero-byte file. */
  /* The first frame only. The engine keeps presenting, and a later callback
   * reopening the file with "wb" truncates the good frame and then loses the
   * race with the exit -- which is how a complete render produced a file
   * 84% of the right size. */
  if (frames > 0) return true;

  FILE* out = fopen("frame.ppm.part", "wb");
  if (!out) return true;
  const size_t width = row_bytes / 4;
  fprintf(out, "P6\n%zu %zu\n255\n", width, height);
  const uint8_t* pixels = allocation;
  for (size_t y = 0; y < height; y++) {
    for (size_t x = 0; x < width; x++) {
      const uint8_t* p = pixels + y * row_bytes + x * 4;
      fputc(p[2], out);
      fputc(p[1], out);
      fputc(p[0], out);
    }
  }
  fclose(out);
  /* Renamed rather than written in place, so the file the caller looks at is
   * either absent or whole. */
  rename("frame.ppm.part", "frame.ppm");
  frames++;
  return true;
}

int main(int argc, char** argv) {
  /* Unbuffered, because this runs under CI with stdout on a pipe. Block
   * buffering there means a probe killed by a timeout reports nothing at all,
   * and "no output" cannot be told apart from "hung before the first line". */
  setvbuf(stdout, NULL, _IONBF, 0);

  if (argc < 3) {
    printf("usage: render <assets> <icudtl.dat> [libapp.so]\n");
    return 2;
  }

  FlutterRendererConfig renderer = {0};
  renderer.type = kSoftware;
  renderer.software.struct_size = sizeof(FlutterSoftwareRendererConfig);
  renderer.software.surface_present_callback = present;

  FlutterProjectArgs args = {0};
  args.struct_size = sizeof(FlutterProjectArgs);
  args.assets_path = argv[1];
  args.icu_data_path = argv[2];

  /* A release engine has no interpreter, so it needs the AOT snapshot handed
   * to it. Without this it looks for a VM snapshot it cannot infer and stops
   * at "VM snapshot invalid and could not be inferred from settings" --
   * which reads as a broken engine and is a missing argument. */
  if (argc > 3) {
    FlutterEngineAOTDataSource source = {0};
    source.type = kFlutterEngineAOTDataSourceTypeElfPath;
    source.elf_path = argv[3];

    FlutterEngineAOTData aot = NULL;
    FlutterEngineResult aot_result = FlutterEngineCreateAOTData(&source, &aot);
    printf("FlutterEngineCreateAOTData: %d\n", aot_result);
    if (aot_result != kSuccess) return 1;
    args.aot_data = aot;
  }

  FlutterEngine engine = NULL;
  FlutterEngineResult result =
      FlutterEngineRun(FLUTTER_ENGINE_VERSION, &renderer, &args, NULL, &engine);
  printf("FlutterEngineRun: %d\n", result);
  if (result != kSuccess) return 1;

  FlutterWindowMetricsEvent metrics = {0};
  metrics.struct_size = sizeof(FlutterWindowMetricsEvent);
  metrics.width = 800;
  metrics.height = 480;
  metrics.pixel_ratio = 1.0;
  FlutterEngineSendWindowMetricsEvent(engine, &metrics);

  /* Emulated ARM is slow and this is a whole Dart isolate starting, so the
   * wait is generous. It says where it has got to each second: a probe that
   * is merely slow and one that is wedged look identical from outside. */
  const int deadline = 300;
  for (int i = 0; i < deadline * 10 && frames == 0; i++) {
    if (i % 10 == 0) printf("waiting for a frame: %ds\n", i / 10);
    usleep(100000);
  }
  printf("frames presented: %d\n", frames);
  if (frames == 0) {
    FlutterEngineShutdown(engine);
    return 1;
  }

  /* The frame is on disk and it is the whole result. Shutting the engine down
   * means joining threads that an emulated ARM run can leave the probe
   * waiting on indefinitely, and there is nothing left to learn from it. */
  fflush(stdout);
  _exit(0);
}
