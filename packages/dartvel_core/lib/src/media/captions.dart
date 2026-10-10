/// Captions and subtitles for `DVBox.video` and `DVBox.audio`.
///
/// Drawn by Dartvel as text over the player, on every target, rather than
/// burned into the frames or left to each platform player's own caption
/// renderer. Text is what a screen reader can read, what Ctrl+F can find and
/// what follows the application's theme, and one renderer is one behaviour:
/// six platform renderers would be six opinions about where a cue goes and
/// when it leaves.
library;

import 'media_source.dart';

/// One caption: what is said between [start] and [end].
final class DVCaptionCue {
  const DVCaptionCue(this.start, this.end, this.text);

  /// Inclusive.
  final Duration start;

  /// Exclusive.
  final Duration end;

  /// Plain text, lines separated by `\n`. Styling markup is removed when a
  /// file is parsed: it is presentation, and read aloud it is noise.
  final String text;

  bool covers(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is DVCaptionCue &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'DVCaptionCue($start, $end, $text)';
}

/// One language's captions.
final class DVCaptionTrack {
  /// Captions in a WebVTT (`.vtt`) or SubRip (`.srt`) file, read when the
  /// track is first shown.
  DVCaptionTrack.source(this.language, DVMediaSource this.source,
      {String? label})
      : label = label ?? language,
        _cues = null;

  /// Captions the application already holds.
  DVCaptionTrack.cues(this.language, List<DVCaptionCue> cues, {String? label})
      : label = label ?? language,
        source = null,
        _cues = _sorted(cues);

  DVCaptionTrack._(this.language, this.label, this.source, this._cues);

  /// A BCP 47 tag: `en`, `pt-BR`.
  final String language;

  /// What the caption menu shows. The language tag when none is given.
  final String label;

  /// Where the cues come from, for a track that has not been read yet.
  final DVMediaSource? source;

  final List<DVCaptionCue>? _cues;

  bool get isLoaded => _cues != null;

  /// The cues, in time order. Empty until loaded.
  List<DVCaptionCue> get cues => _cues ?? const <DVCaptionCue>[];

  /// This track with [cues] read.
  DVCaptionTrack withCues(List<DVCaptionCue> cues) =>
      DVCaptionTrack._(language, label, source, _sorted(cues));

  /// The cue showing at [position], or null.
  ///
  /// A binary search, because this runs on every position report and a
  /// feature film carries a couple of thousand cues.
  DVCaptionCue? cueAt(Duration position) {
    final List<DVCaptionCue> all = cues;
    int low = 0;
    int high = all.length - 1;
    int found = -1;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      if (all[mid].start <= position) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    // Overlapping cues: the latest one to start that still covers.
    for (int i = found; i >= 0 && i > found - 4; i--) {
      if (all[i].covers(position)) return all[i];
    }
    return null;
  }

  static List<DVCaptionCue> _sorted(List<DVCaptionCue> cues) =>
      List<DVCaptionCue>.unmodifiable(List<DVCaptionCue>.of(cues)
        ..sort((DVCaptionCue a, DVCaptionCue b) => a.start.compareTo(b.start)));
}

/// The caption tracks a player offers.
///
/// `DVBox.video(source, captions: DVCaptions.track('en', vtt))`. The
/// standard controls show a captions button when there is at least one
/// track, and the player's `captionTrack` signal says which is showing.
final class DVCaptions {
  DVCaptions(List<DVCaptionTrack> tracks,
      {this.initial, this.showByDefault = true})
      : tracks = List<DVCaptionTrack>.unmodifiable(tracks);

  /// One track from a file.
  DVCaptions.track(String language, DVMediaSource source,
      {String? label, this.showByDefault = true})
      : tracks = List<DVCaptionTrack>.unmodifiable(<DVCaptionTrack>[
          DVCaptionTrack.source(language, source, label: label),
        ]),
        initial = language;

  final List<DVCaptionTrack> tracks;

  /// The language shown first. The first track when null.
  final String? initial;

  /// Whether captions start on. Off still offers them in the controls.
  final bool showByDefault;

  /// The track shown when the player starts, or null for none.
  DVCaptionTrack? get initialTrack {
    if (!showByDefault || tracks.isEmpty) return null;
    for (final DVCaptionTrack track in tracks) {
      if (track.language == initial) return track;
    }
    return tracks.first;
  }

  /// The track for [language], or null.
  DVCaptionTrack? trackFor(String? language) {
    if (language == null) return null;
    for (final DVCaptionTrack track in tracks) {
      if (track.language == language) return track;
    }
    return null;
  }

  /// Cues in a WebVTT or SubRip file. Which one is decided by the content,
  /// not the extension: a `.vtt` served as `text/plain` is still WebVTT.
  static List<DVCaptionCue> parse(String text) {
    final String normalized =
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final List<DVCaptionCue> cues = <DVCaptionCue>[];
    for (final String block in normalized.split(RegExp(r'\n[ \t]*\n'))) {
      final List<String> lines = block
          .split('\n')
          .where((String line) => line.trim().isNotEmpty)
          .toList();
      final int timing = lines.indexWhere((String l) => l.contains('-->'));
      if (timing < 0) continue;
      final List<String> sides = lines[timing].split('-->');
      final Duration? start = _time(sides[0]);
      final Duration? end = sides.length < 2
          ? null
          : _time(sides[1].trim().split(RegExp(r'\s+')).first);
      if (start == null || end == null || end <= start) continue;
      final String body = lines
          .skip(timing + 1)
          .map((String line) => _plain(line).trim())
          .where((String line) => line.isNotEmpty)
          .join('\n');
      if (body.isEmpty) continue;
      cues.add(DVCaptionCue(start, end, body));
    }
    return cues;
  }

  static final RegExp _timestamp =
      RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d+))?$');

  static Duration? _time(String raw) {
    final RegExpMatch? match = _timestamp.firstMatch(raw.trim());
    if (match == null) return null;
    final int hours = int.parse(match.group(1) ?? '0');
    final int minutes = int.parse(match.group(2)!);
    final int seconds = int.parse(match.group(3)!);
    final String fraction = match.group(4) ?? '0';
    // A fraction of a second, whatever its length: ",5" is 500 ms.
    final int millis =
        int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(
        hours: hours, minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  static String _plain(String line) => line
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lrm;', '')
      .replaceAll('&rlm;', '')
      .replaceAll('&amp;', '&');
}
