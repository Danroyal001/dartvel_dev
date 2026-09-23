import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Audio and video, 3D scenes and spatial (XR) presentation. Most of each is a
// platform-independent runtime waiting on native backends, and the status
// boxes say which targets have none. Source: docs/spec-status.json.
@DVPage(
  title: 'Dartvel media, 3D and XR: players, scenes and spatial windows',
  description: 'Players, recorders, 3D scenes and spatial windows in Dartvel, '
      'and which targets have a native player, renderer or headset '
      'binding today.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsMedia3dPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsmedia3d,
      lead: <String>[
        'Players, recorders, 3D scenes and spatial windows share one rule: '
            'their state moves only when the device confirms it.',
        'The runtime is built and tested. Most targets have no native player, '
            'renderer or headset binding yet, and each section says which.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'media',
          title: 'Play audio and video, and record',
          children: <Widget>[
            Bullets(<String>[
              'DVBox.video and DVBox.audio own their player while they are on '
                  'screen, and release it when the page closes.',
              'A player is not playing until the device says so, and a '
                  'recording cut short by the app going to the background ends '
                  'as interrupted, with the partial file kept.',
              'Protected content with no DRM adapter is refused up front, '
                  'never played broken.',
            ]),
            DocsCode('media3d-video'),
            DocsStatus('Media Playback and Capture', missing: <String>[
              'Linux plays through GStreamer, and only the audio: video frames '
                  'are not drawn yet.',
              'No player or recorder backend yet for Android, iOS, macOS, '
                  'Windows, the web or TVs, and no camera capture anywhere.',
              'No captions, lock-screen controls, picture-in-picture or '
                  'casting.',
            ]),
          ],
        ),
        DocsSection(
          id: 'scenes',
          title: 'Describe a 3D scene',
          children: <Widget>[
            Bullets(<String>[
              'A scene is a document of nodes, cameras and glTF assets with '
                  'stated units and axes, and it round-trips exactly.',
              'Tapping picks the node under the finger by its real shape.',
              'Assets must come from your own storage or listed hosts, with a '
                  'digest that is checked before use.',
            ]),
            DocsCode('media3d-scene'),
            DocsStatus('3D Scenes', missing: <String>[
              'There is no GPU renderer yet, so every target shows the scene\'s '
                  'poster image.',
              'No animation, physics or build-time asset import.',
            ]),
          ],
        ),
        DocsSection(
          id: 'xr',
          title: 'Open a window in space',
          children: <Widget>[
            Bullets(<String>[
              'A window can be a volume or an immersive space, with comfort '
                  'settings, on a headset or glasses.',
              'Passthrough asks for the camera first, and a world anchor is '
                  'kept only with consent.',
            ]),
            DocsStatus('XR: Spatial Presentation', missing: <String>[
              'No native XR binding on any target yet, so spatial windows are '
                  'not available on a device.',
              'No dartvel build target for Android XR, Meta Horizon or '
                  'visionOS.',
            ]),
          ],
        ),
      ],
    );
