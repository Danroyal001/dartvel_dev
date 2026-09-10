/// Turning a feature record into something with structure.
///
/// Each record is one string, written as the repository's own account of what
/// a section does. That is the right shape for spec-status.json, where a
/// person reads one entry at a time, and the wrong shape for a card in a grid
/// of thirty-six: a single paragraph with "Present:" and "Absent:" inside it
/// as words rather than as the two different things they are.
///
/// Parsed rather than rewritten, because the text is the record and the card
/// should not carry a second copy of it that can drift.
library dartvel_site.components.record;

/// A record split into what is built and what is not.
class SiteRecordParts {
  const SiteRecordParts({required this.present, required this.absent});

  /// Paragraphs describing what the section does.
  final List<String> present;

  /// Paragraphs describing what it does not, empty when it says nothing.
  final List<String> absent;
}

/// The word, only where it is being used as a label.
///
/// "Absent" is an ordinary word in these records -- a binding that is absent
/// throws rather than returning a lie -- so splitting on it wherever it
/// appears would move half a sentence into the wrong half and change what the
/// card says. As a label it opens a clause and is followed by a colon, so
/// that is what this looks for.
/// A lookbehind rather than a match, so the stop that ended the sentence
/// before the label stays with that sentence. Consuming it left the present
/// half ending in mid-air.
final RegExp _absentLabel = RegExp(r'(?:(?<=[.;])\s+|^)Absent:\s*');
final RegExp _presentLabel = RegExp(r'^Present:\s*');

/// [body] split into its two halves, each broken into paragraphs.
SiteRecordParts siteRecordParts(String body) {
  final RegExpMatch? label = _absentLabel.firstMatch(body);

  if (label == null) {
    return SiteRecordParts(
      present: siteParagraphs(body.replaceFirst(_presentLabel, '')),
      absent: const <String>[],
    );
  }

  // The separator that introduced the label belongs to the sentence before
  // it, so the present half keeps its full stop and does not end mid-air.
  final String head = body.substring(0, label.start).trimRight();
  final String tail = body.substring(label.end).trim();

  return SiteRecordParts(
    present: siteParagraphs(head.replaceFirst(_presentLabel, '')),
    absent: siteParagraphs(tail),
  );
}

/// How long a paragraph may run before it is worth breaking.
///
/// Characters rather than lines, deliberately: the same text is one column on
/// a phone and two on a laptop, so a line count is a different amount of
/// reading at every width, while the number of words in a paragraph is not.
const int kSiteParagraphTarget = 280;

/// A sentence ending, which is not the same as a full stop.
///
/// Version numbers are everywhere in these records -- Dart 3.12.2, API 31 --
/// and a rule that breaks at any full stop puts the next paragraph in the
/// middle of one. A sentence ends with a stop, then a space, then a capital.
final RegExp _sentenceBreak = RegExp(r'(?<=[.?!]) (?=[A-Z])');

/// [text] as paragraphs, broken only between whole sentences.
///
/// Returns one paragraph when the text is short enough to be one, which most
/// records now are. Nothing is added, removed or reordered: joining the result
/// with a space gives the input back.
List<String> siteParagraphs(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return const <String>[];
  if (trimmed.length <= kSiteParagraphTarget) return <String>[trimmed];

  final List<String> sentences = trimmed.split(_sentenceBreak);
  // One long sentence, or prose this cannot see the joints in. Left whole
  // rather than cut somewhere arbitrary -- a paragraph break in the middle of
  // a clause is worse than a paragraph that runs long.
  if (sentences.length < 2) return <String>[trimmed];

  final List<String> paragraphs = <String>[];
  StringBuffer current = StringBuffer();

  for (final String sentence in sentences) {
    if (current.isNotEmpty &&
        current.length + sentence.length > kSiteParagraphTarget) {
      paragraphs.add(current.toString().trim());
      current = StringBuffer();
    }
    if (current.isNotEmpty) current.write(' ');
    current.write(sentence);
  }
  if (current.isNotEmpty) paragraphs.add(current.toString().trim());

  // A last paragraph of a few words reads as a mistake rather than as
  // emphasis, so it goes back onto the one before it.
  if (paragraphs.length > 1 && paragraphs.last.length < 80) {
    final String orphan = paragraphs.removeLast();
    paragraphs[paragraphs.length - 1] = '${paragraphs.last} $orphan';
  }

  return paragraphs;
}

/// Lines of the opening paragraph a folded record shows.
///
/// Four is about forty words, which is the first two sentences of most of
/// these -- and the first two sentences are the summary, because they were
/// written as one. It bounds the height as well: a paragraph runs to
/// [kSiteParagraphTarget] characters, which in one column on a phone is seven
/// lines and a card nobody can compare with its neighbour.
const int kSiteFoldedLines = 4;
