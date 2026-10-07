# The web-server binary loads only what a request needs

`dartvel build web-server` writes one file, `build/server`. Nothing is
deployed beside it; at run time it keeps only its data directory
(`dartvel_data`, moved by `DARTVEL_DATA_DIR`) and a cache it manages itself
(`dartvel_data/cache`, moved by `DARTVEL_CACHE_DIR`, safe to delete).

## Layout

`dart compile exe` output is the runtime, the AOT snapshot on a 64 KiB
boundary, and a trailer naming the snapshot. The build puts a payload
between the runtime and the snapshot (see
`packages/dartvel_core/lib/src/process/binary_payload.dart`):

| Section | What it is | How it is read |
|---|---|---|
| `native` | dartvel_shelf's Rust server library | copied a megabyte at a time into a memfd and `dlopen`ed; no copy stays in the Dart heap |
| `assets` | the indexed asset pack: `web/…` and, with Studio, `admin/…` (protected) | index read at start; each file read by a positioned read when a request asks for it |
| `admin.mount` | Studio's mount | read at start |
| `unit.<n>` | AOT loading unit *n*, 64 KiB-aligned | mapped with `Dart_LoadELF(exe, offset)` the first time code in it runs |

Older binaries wrote every web file into `dartvel_data/.web` and
`dartvel_data/.admin` at start; a new binary deletes those directories.

## Guarded pages

A page behind a `_guard.dart`, a page policy or the account pages' session gate is answered by the
server, not only by the client. A request with no live session gets a `302` to the sign-in page
(`dvSignInRoute`, the one the client's gate uses) carrying `from=<path and query>`, so nobody signed out
is ever sent the guarded screen's HTML. An application with no sign-in page answers `401` with the bare
shell. `dartvel dev --release` behaves the same.

## Assets

Each file is kept the smallest way the build finds it
(`packages/dartvel_cli/lib/src/build/server_assets.dart`): brotli 11 from the
native library the binary embeds, skipping formats that are compressed
already (PNG, JPEG, WebP, woff2, archives, media). Identical files are stored
once, which matters because Studio carries the same engine files as the site.
Encodings are cached in `.dart_tool/dartvel/asset_encodings` by content hash,
so a rebuild encodes only what changed.

On dartvel.dev's 43 MB of web files (Studio excluded; `.symbols` are never
carried), measured with the codec in the native library:

| Type | Raw | gzip -9 | brotli 11 | zstd 19 (LDM, 8 MiB window) |
|---|---:|---:|---:|---:|
| wasm | 28.8 MB | 11.8 MB | **9.1 MB** | 9.7 MB |
| js | 4.1 MB | 1.31 MB | **1.04 MB** | 1.12 MB |
| NOTICES | 1.38 MB | 109 KB | **45 KB** | 53 KB |
| json | 1.16 MB | 188 KB | **135 KB** | 154 KB |
| ttf/otf | 375 KB | 173 KB | **150 KB** | 162 KB |
| png | 7.4 MB | 7.1 MB | 7.1 MB | 7.0 MB (kept as is) |
| **total** | 43.4 MB | 20.7 MB | **17.5 MB** | 18.2 MB |

Brotli is smaller for every text type and every browser accepts it
(zstd is not accepted by Safari), so it is the default;
`dartvel.web.server.compression: zstd | gzip | none` picks another. zstd
streams are limited to the 8 MiB window RFC 8878 requires browsers to accept.

A client that accepts the kept encoding is sent those bytes untouched: no
compression per request. One that does not gets the file decoded once; the
result is kept in a memory LRU (small files) or on disk under the build id
(large ones), so a new deploy never serves an old file. Protected (Studio)
files are never kept by either.

## HTTP caching

Declared under `dartvel.web.server.http` in pubspec.yaml and carried in the
manifest:

```yaml
dartvel:
  web:
    server:
      compression: brotli        # zstd | gzip | none
      http:
        maxAge: 0                # seconds for files whose name is not hashed
        sMaxAge: 3600            # CDN seconds
        staleWhileRevalidate: 60
        immutable: [canvaskit/**]
        documents: no-cache
        memoryCacheMB: 16
        diskCache: true
```

Defaults, right with nothing declared:

- a file whose name carries a content hash (`app.3f2a9c1b.js`):
  `public, max-age=31536000, immutable`;
- every other file: `public, no-cache` with an ETag. Flutter's output keeps
  its names across builds, so a browser keeping `main.dart.js` for a fixed
  time would pair it with the next build's parts;
- documents: `no-cache`;
- Studio and anything protected: `private, no-store`, whatever is declared.

Every file has a strong ETag per encoding (`"<hash>-br"`), a weak one when the
server's transport may gzip the body on the way out, `If-None-Match` 304 across
encodings, single byte ranges of the decoded file with `If-Range` and 416, and
`Vary: Accept-Encoding` wherever the answer depends on it (said once: the
transport adds its own only when it compresses).

## Code: loading units

Verified on Dart 3.13.4 (linux-x64):

```
$ gen_snapshot --snapshot_kind=app-aot-elf --elf=main.aot --loading_unit_manifest=units.json main.dill
$ ls
main.aot  main.aot-2.part.so  units.json
$ dartaotruntime main.aot go         # with main.aot-2.part.so beside it
deferred-work-0-0,deferred-work-1-7,deferred-work-2-14
$ dartaotruntime main.aot go         # without it
DeferredLoadException: 'Failed to load main.aot-2.part.so'
$ strings dartaotruntime | grep part.so
%s-%ld.part.so
$ nm -D --defined-only dartaotruntime | grep -E 'Dart_(SetDeferredLoadHandler|LoadELF|DeferredLoadComplete)'
T Dart_DeferredLoadComplete
T Dart_DeferredLoadCompleteError
T Dart_LoadELF
T Dart_LoadELF_Fd
T Dart_LoadELF_Memory
T Dart_SetDeferredLoadHandler
```

So the SDK can split an AOT program into units and the standalone runtime can
load them; what `dart compile exe` does not do is pass
`--loading_unit_manifest`, and the runtime's own handler only looks for
`<program>-N.part.so` files beside the program. No SDK capability is missing:
the build runs the two steps `dart compile exe` runs (`gen_kernel --aot` on
the product platform, then `gen_snapshot`) with the manifest flag, assembles
the executable byte for byte as `dart compile exe` does, and carries each unit
as a 64 KiB-aligned payload section. The native server library installs a
deferred-load handler (`aw_units_load` in `dartvel_shelf/rust/src/units.rs`)
that maps the unit straight from the executable with the runtime's
`Dart_LoadELF(path, offset)` and completes it with `Dart_DeferredLoadComplete`.
It is native, not a Dart callback, because the VM calls it on whichever isolate
asked and a Dart callback aborts when called from another isolate; a second
isolate asking for a unit its group already has is completed through its own
`dart:core` `_completeLoads`, since the VM refuses a unit twice.

Units are built on Linux hosts. On macOS and Windows `dart compile exe` puts
the snapshot in a Mach-O or PE image the ELF loader does not map, so the build
there compiles one unit, as before, and `deferred` imports load at once.

What is split today: `package:image` (the image endpoint's resizer, a third of
the site's compiled code). Studio's server code is not yet a unit of its own:
`package:dartvel_core/dartvel.dart` re-exports it, and a library reachable
through any non-deferred import lands in the root unit. Moving it out of that
barrel is the next step, and waits for the Studio-as-app-routes work to land.

## Disabled modules are not compiled in

The generated backend puts every Studio reference behind

```dart
const bool dartvelStudio = bool.fromEnvironment('dartvel.studio', defaultValue: true);
```

and the release build passes `-Ddartvel.studio=false` when it resolved no
Studio mount, so AOT drops the dashboard, its API, its grants, published pages
and the models' data API. With `dartvel.admin.enabled: false` the generator
emits none of it. Dart's conditional imports (`if (dart.library.io)`) test
platform libraries only, not custom flags, so they are not used for this.
`server_binary_build_test.dart` builds a real binary both ways: the Studio
build carries `DVAdminServer`, `DVStudioApi`, `DVStudioGrants` and Studio's
messages; the other carries none of them nor any Studio file, is smaller, and
answers `/__studio` exactly as a path nobody serves.
