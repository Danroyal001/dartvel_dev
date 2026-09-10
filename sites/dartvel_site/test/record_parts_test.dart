// Splitting a record into something with structure.
//
// Every feature card carried one string. Trimming them from six thousand
// characters to five hundred made the wall shorter and left it a wall: a
// single paragraph, with "Present:" and "Absent:" buried inside it as words
// rather than shown as the two different things they are.
//
// So the string is parsed into parts before it is drawn. This is the parsing,
// tested on its own, because it is the half that can be wrong without looking
// wrong -- a record whose "Absent" half silently ends up in its "Present" half
// reads perfectly and says the opposite of the truth.
import 'package:dartvel_site/components/record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what is built and what is not', () {
    test('a record with both halves is split at the word', () {
      const String body = 'Present: the policy and the state machine. '
          'Absent: iPadOS and Tizen.';
      final SiteRecordParts parts = siteRecordParts(body);

      expect(parts.present.join(' '),
          'the policy and the state machine.');
      expect(parts.absent.join(' '), 'iPadOS and Tizen.');
    });

    test('the Present label is dropped rather than drawn', () {
      // It becomes a heading over the block, so leaving it in the text would
      // print it twice.
      final SiteRecordParts parts =
          siteRecordParts('Present: a thing. Absent: another.');
      expect(parts.present.join(' '), isNot(contains('Present:')));
    });

    test('a record with no Absent half has an empty one', () {
      final SiteRecordParts parts =
          siteRecordParts('One layout primitive with a fluent chain.');
      expect(parts.absent, isEmpty);
      expect(parts.present.join(' '),
          'One layout primitive with a fluent chain.');
    });

    test('the word only counts as a label where a label goes', () {
      // "absent" appears inside plenty of these records as an ordinary word.
      // Splitting on it would move the rest of a sentence into the wrong
      // half and change what the card says.
      const String body =
          'A binding that is absent throws rather than returning a lie.';
      final SiteRecordParts parts = siteRecordParts(body);
      expect(parts.absent, isEmpty);
      expect(parts.present.join(' '), body);
    });
  });

  group('paragraphing', () {
    test('a short record stays one paragraph', () {
      expect(siteParagraphs('A file under lib/pages is a route.'), hasLength(1));
    });

    test('a long one is broken at a sentence, not mid-thought', () {
      const String a = 'The build finds the module and takes its own route '
          'base off and puts the mount point on instead of it. ';
      const String b = 'A federated module publishes a signed manifest that '
          'the parent verifies before it will mount anything at all. ';
      const String c = 'Shell, auth, theme and data modes each apply at run '
          'time rather than being read and dropped on the floor. ';
      final List<String> paragraphs = siteParagraphs('$a$b$c');

      expect(paragraphs.length, greaterThan(1));
      // Every paragraph is whole sentences: nothing starts lower-case, which
      // is what a cut in the middle of one looks like.
      for (final String paragraph in paragraphs) {
        expect(paragraph.trim(), isNotEmpty);
        expect(paragraph.trimLeft()[0], matches(RegExp(r'[A-Z]')));
      }
      // And nothing was lost or duplicated in the splitting.
      expect(paragraphs.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
          '$a$b$c'.replaceAll(RegExp(r'\s+'), ' ').trim());
    });

    test('a version number is not a sentence ending', () {
      // "Dart 3.12.2 is the floor." would break after "3." with a naive rule,
      // and the second paragraph would start with a digit.
      const String text = 'The floor is Dart 3.12.2 and Flutter 3.44.0, which '
          'every package declares identically so there is one number to '
          'satisfy rather than two that disagree with each other. It used to '
          'be two floors and reasoning from the lower one recorded webOS '
          'wrongly. State which wall a target hits rather than assuming.';
      for (final String paragraph in siteParagraphs(text)) {
        expect(paragraph.trimLeft()[0], matches(RegExp(r'[A-Z]')));
      }
    });
  });
}
