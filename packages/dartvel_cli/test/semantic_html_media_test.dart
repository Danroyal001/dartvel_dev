// Players and cameras in the crawler-visible HTML.
//
// A Flutter page's player is a canvas until JavaScript runs. The page the
// web build prerenders and the web-server answers with is the same document a
// reader with scripting off gets, and in it a video should be a video: a real
// <video controls> that plays, with its captions as <track>, rather than the
// words "Video player" and nothing to press.
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:test/test.dart';

void main() {
  test('a captured identifier carries the media description', () {
    final List<DVSemanticNode> nodes = DVSemanticNode.listFromJson('''
[{"role":"video","label":"Video: Launch film","media":{"src":"https://cdn.test/a.mp4","poster":"https://cdn.test/a.jpg","tracks":[{"srclang":"en","label":"English","src":"https://cdn.test/a.en.vtt"}]},"children":[{"role":"button","label":"Play","children":[]}]}]
''');
    expect(nodes.single.media?['src'], 'https://cdn.test/a.mp4');
  });

  test('a video is a <video> with controls, poster and caption tracks', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      const DVSemanticNode(
        role: 'video',
        label: 'Video: Launch film',
        media: <String, Object?>{
          'src': 'https://cdn.test/a.mp4?x=1&y=2',
          'poster': 'https://cdn.test/a.jpg',
          'tracks': <Object?>[
            <String, Object?>{
              'srclang': 'en',
              'label': 'English',
              'src': 'https://cdn.test/a.en.vtt',
            },
          ],
        },
        children: <DVSemanticNode>[DVSemanticNode(role: 'button', label: 'Play')],
      ),
    ]);
    expect(
        html,
        '<video controls preload="metadata" '
        'src="https://cdn.test/a.mp4?x=1&amp;y=2" '
        'poster="https://cdn.test/a.jpg" aria-label="Video: Launch film">'
        '<track kind="captions" srclang="en" label="English" '
        'src="https://cdn.test/a.en.vtt">'
        '<a href="https://cdn.test/a.mp4?x=1&amp;y=2">Video: Launch film</a>'
        '</video>');
    // The player's own buttons are the browser's now; Flutter's are not
    // repeated as paragraphs.
    expect(html, isNot(contains('Play')));
  });

  test('audio is an <audio> with controls', () {
    expect(
        dvSemanticHtml(<DVSemanticNode>[
          const DVSemanticNode(
              role: 'audio',
              label: 'Audio: Episode 4',
              media: <String, Object?>{'src': 'assets/ep4.mp3'}),
        ]),
        '<audio controls preload="metadata" src="assets/ep4.mp3" '
        'aria-label="Audio: Episode 4">'
        '<a href="assets/ep4.mp3">Audio: Episode 4</a></audio>');
  });

  test('a player with nothing a browser can open is described, not broken',
      () {
    // A file on the device has no address the page could load.
    expect(
        dvSemanticHtml(<DVSemanticNode>[
          const DVSemanticNode(
              role: 'video', label: 'Video player', media: <String, Object?>{}),
        ]),
        '<figure role="img" aria-label="Video player">'
        '<figcaption>Video player</figcaption></figure>');
  });

  test('a camera is a labelled placeholder', () {
    expect(
        dvSemanticHtml(<DVSemanticNode>[
          const DVSemanticNode(
              role: 'camera',
              label: 'Camera',
              media: <String, Object?>{},
              children: <DVSemanticNode>[
                DVSemanticNode(role: 'button', label: 'Take photo'),
              ]),
        ]),
        '<figure role="group" aria-label="Camera">'
        '<figcaption>Camera: the live picture needs JavaScript and '
        'permission to use the camera.</figcaption></figure>');
  });

  test('a script in a source cannot break out of the attribute', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      const DVSemanticNode(
          role: 'video',
          label: 'x',
          media: <String, Object?>{'src': '"><script>alert(1)</script>'}),
    ]);
    expect(html, isNot(contains('<script>')));
  });

  test('a javascript: URL is not emitted as a source', () {
    final String html = dvSemanticHtml(<DVSemanticNode>[
      const DVSemanticNode(
          role: 'video',
          label: 'x',
          media: <String, Object?>{'src': 'javascript:alert(1)'}),
    ]);
    expect(html, isNot(contains('javascript:')));
  });
}
