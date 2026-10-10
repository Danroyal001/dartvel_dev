import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start media3d-video
// Playback is a mode of the box, so the box keeps its size, modifiers,
// gestures and semantics, and the source says what is played.
// The box's element owns the player, so leaving the page releases the
// decoder and the audio focus with it.
Widget trailer() => DVBox.video(
      const DVMediaSource.url('https://cdn.example.com/trailer.mp4'),
      captions: DVCaptions.track(
        'en',
        const DVMediaSource.url('https://cdn.example.com/trailer.en.vtt'),
      ),
      session: const DVMediaSession(title: 'Launch trailer'),
    ).modifier(const DVModifier().width(640));
// docs:end

// docs:start media3d-precache
// The first megabyte is on disk before the page that plays it opens.
Future<bool> warmTrailer() => DV.Platform.media.precache(
      const DVMediaSource.url('https://cdn.example.com/trailer.mp4'),
      bytes: 1024 * 1024,
    );
// docs:end

// docs:start media3d-camera
Widget scanner(void Function(DVFile photo) keep) =>
    DVBox.camera(lens: .back, onPhoto: keep);
// docs:end

// docs:start media3d-scene
// A scene is a list of nodes, so what is in it is data a page builds rather
// than a sequence of calls into a renderer. The viewport reports how it had
// to degrade instead of quietly drawing less.
Widget mug(DVSceneAsset model) => DVBox.scene(
      DVScene(
        label: 'A stoneware mug, turning',
        nodes: <DVSceneNode>[
          DVModel3D(model).id('mug'),
          DVSceneCamera.orbit(distance: 2.5, controls: true),
          DVLight.directional(direction: const DVVec3(-1, -2, -1)).shadows(),
        ],
      ),
    );
// docs:end
