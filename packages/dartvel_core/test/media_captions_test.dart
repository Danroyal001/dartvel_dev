// Captions: WebVTT and SubRip parsed into cues, and the cue showing at a
// position.
//
// The failures worth a test are the ones a viewer reads as the film being
// wrong rather than the captions: a cue shown a second late because the
// milliseconds were read as centiseconds, a cue that never goes away because
// its end was dropped, styling markup read out to a screen reader as text.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('WebVTT', () {
    test('reads cues with hours, without hours, and with identifiers', () {
      final List<DVCaptionCue> cues = DVCaptions.parse('''
WEBVTT - a film

NOTE written by somebody

intro
00:00:01.000 --> 00:00:02.500
Hello

00:03.250 --> 00:04.000 align:start position:10%
<v Roger>Two</v> lines
of <i>text</i>
''');
      expect(cues, hasLength(2));
      expect(cues[0].start, const Duration(seconds: 1));
      expect(cues[0].end, const Duration(milliseconds: 2500));
      expect(cues[0].text, 'Hello');
      expect(cues[1].start, const Duration(milliseconds: 3250));
      expect(cues[1].end, const Duration(seconds: 4));
      // Markup is presentation. Read aloud it is noise.
      expect(cues[1].text, 'Two lines\nof text');
    });

    test('entities are decoded once', () {
      final List<DVCaptionCue> cues = DVCaptions.parse(
          'WEBVTT\n\n00:00.000 --> 00:01.000\nFish &amp; chips &lt;3\n');
      expect(cues.single.text, 'Fish & chips <3');
    });

    test('a cue with no end time is skipped rather than shown forever', () {
      final List<DVCaptionCue> cues = DVCaptions.parse(
          'WEBVTT\n\n00:00.000 -->\nbroken\n\n00:01.000 --> 00:02.000\nok\n');
      expect(cues.single.text, 'ok');
    });

    test('Windows line endings', () {
      final List<DVCaptionCue> cues = DVCaptions.parse(
          'WEBVTT\r\n\r\n00:00:05.000 --> 00:00:06.000\r\nline\r\n');
      expect(cues.single.start, const Duration(seconds: 5));
      expect(cues.single.text, 'line');
    });
  });

  group('SubRip', () {
    test('reads comma milliseconds and the counter line', () {
      final List<DVCaptionCue> cues = DVCaptions.parse('''
1
00:00:01,200 --> 00:00:03,000
First

2
00:00:03,500 --> 00:00:05,000
Second
line
''');
      expect(cues, hasLength(2));
      expect(cues[0].start, const Duration(milliseconds: 1200));
      expect(cues[1].text, 'Second\nline');
    });

    test('fractions shorter than three digits are not centiseconds', () {
      // "00:00:01,5" is half a second, not five milliseconds.
      final List<DVCaptionCue> cues =
          DVCaptions.parse('1\n00:00:01,5 --> 00:00:02,25\nx\n');
      expect(cues.single.start, const Duration(milliseconds: 1500));
      expect(cues.single.end, const Duration(milliseconds: 2250));
    });
  });

  group('cue at a position', () {
    final DVCaptionTrack track = DVCaptionTrack.cues('en', <DVCaptionCue>[
      const DVCaptionCue(Duration(seconds: 5), Duration(seconds: 6), 'late'),
      const DVCaptionCue(Duration(seconds: 1), Duration(seconds: 2), 'early'),
    ]);

    test('cues are kept in time order', () {
      expect(track.cueAt(const Duration(milliseconds: 1500))?.text, 'early');
      expect(track.cueAt(const Duration(milliseconds: 5500))?.text, 'late');
    });

    test('start is inclusive and end exclusive', () {
      expect(track.cueAt(const Duration(seconds: 1))?.text, 'early');
      expect(track.cueAt(const Duration(seconds: 2)), isNull);
    });

    test('nothing between cues', () {
      expect(track.cueAt(const Duration(seconds: 3)), isNull);
      expect(track.cueAt(.zero), isNull);
    });
  });

  group('tracks', () {
    test('a source track names its language and is loaded later', () {
      final DVCaptionTrack track = DVCaptionTrack.source(
        'fr',
        const DVMediaSource.url('https://cdn.test/a.fr.vtt'),
        label: 'Français',
      );
      expect(track.language, 'fr');
      expect(track.label, 'Français');
      expect(track.isLoaded, isFalse);
      expect(track.withCues(const <DVCaptionCue>[]).isLoaded, isTrue);
    });

    test('a track with no label is labelled by its language', () {
      expect(DVCaptionTrack.cues('en', const <DVCaptionCue>[]).label, 'en');
    });

    test('DVCaptions picks the default track, or the first', () {
      final DVCaptions captions = DVCaptions(<DVCaptionTrack>[
        DVCaptionTrack.cues('en', const <DVCaptionCue>[]),
        DVCaptionTrack.cues('fr', const <DVCaptionCue>[]),
      ], initial: 'fr');
      expect(captions.initialTrack?.language, 'fr');
      expect(
          DVCaptions(<DVCaptionTrack>[
            DVCaptionTrack.cues('en', const <DVCaptionCue>[]),
          ]).initialTrack?.language,
          'en');
      expect(
          DVCaptions(<DVCaptionTrack>[
            DVCaptionTrack.cues('en', const <DVCaptionCue>[]),
          ], showByDefault: false)
              .initialTrack,
          isNull);
    });
  });
}
