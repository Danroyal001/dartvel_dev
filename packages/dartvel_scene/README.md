# dartvel_scene

The 3D renderer behind `DVBox.scene`, on [Flutter Scene](https://fscene.dev):
Flutter GPU on native targets and Flutter Scene's WebGL2 backend in a browser.

## Use it

```yaml
# pubspec.yaml
dependencies:
  dartvel_scene: ^0.11.4

dartvel:
  scene3d:
    enabled: true
```

That is all. The generated runtime installs the renderer, and `dartvel build`
switches Flutter GPU on in each platform's own files (Android manifest,
iOS and macOS Info.plist, the Linux and Windows runners), taking it out again if
you turn `scene3d` off. You never edit `android/`, `ios/`, `macos/`, `linux/`
or `windows/`. A project that turns `scene3d` on without this package is
refused by the build with the command that fixes it.

```dart
DVBox.scene(
  DVScene(
    label: 'A green box on the ground',
    nodes: <DVSceneNode>[
      DVMesh.plane(10, 10).material(grass),
      DVMesh.box(const DVVec3(1, 1, 1)).material(paint).position(const DVVec3(0, 0.5, 0)),
      DVLight.directional(direction: const DVVec3(-1, -2, -1)).shadows(),
      DVSceneCamera.orbit(distance: 6, controls: true),
    ],
  ),
)
```

## Materials

A mesh's material is an asset holding a small JSON document:

```json
{"baseColor": "#1F8A4C", "metallic": 0, "roughness": 0.8, "emissive": "#000000", "opacity": 1}
```

Every field is optional. A key it does not know, a colour that does not parse
or a number outside 0 to 1 is refused when the scene loads, naming the field,
rather than rendering white.

## Status

Part of the 3D Scenes section of the specification, `Partial` in
[`docs/spec-status.json`](../../docs/spec-status.json).

Built and tested: the renderer adapter (draws, lights, camera, glTF models,
primitives with JSON materials), the poster with `gpuInitFailed` on a target
without Flutter GPU, the per-platform Flutter GPU switch and the generated
install. Rendering is verified in headless Chrome.

Not yet: rendering checked on Linux, Android, iOS, macOS and Windows devices;
environment maps from scene assets (the engine's studio environment lights
every scene); textures and `.fmat` materials; animations; physics.

Needs Flutter 3.47 (3.47.1 for Flutter GPU in Linux and Windows release builds).
