// What a features card shows is its lead: the first sentence of the record,
// in at most three lines. Two ways it went wrong on the built site, both seen
// only in a screenshot at phone width.
//
// A second sentence that starts with a command, "... with TLS. dartvel db
// migrate runs ...", has no capital after its full stop, so the sentence
// splitter read two sentences as one and the card cut the second off
// mid-word with an ellipsis. And a lead that was one sentence, but a long
// one, was cut the same way. 110 characters is what three lines hold in a
// card on a 390-pixel phone.
//
// The capital a lead gets when a "Present:" label is cut off its front turned
// code into something else: "dartvel build web" read "Dartvel build web",
// "context.signal" read "Context.signal", and "webOS" read "WebOS".
import 'package:dartvel_site/components/record.dart';
import 'package:dartvel_site/pages/features.dart' show partial, shipped;
import 'package:flutter_test/flutter_test.dart';

const int kLeadLimit = 110;

void main() {
  test('a code-shaped first word keeps its case', () {
    expect(siteLead('dartvel build web writes the head. More.'),
        'dartvel build web writes the head.');
    expect(siteLead('context.signal and DV.global. More.'),
        'context.signal and DV.global.');
    expect(siteLead('background: true compiles onto the queue.'),
        'background: true compiles onto the queue.');
    expect(siteGap('Present: a thing. Absent: dartvel ci init.'),
        'dartvel ci init.');
    expect(siteGap('Present: a thing. Absent: webOS and Fuchsia.'),
        'webOS and Fuchsia.');
    // And a plain word still gets its capital.
    expect(siteLead('Present: a module is a whole app. More.'),
        'A module is a whole app.');
  });

  final List<(String, String, String)> cards = <(String, String, String)>[
    ...shipped,
    ...partial,
  ];

  test('every card lead is one sentence', () {
    final List<String> joined = <String>[
      for (final (String area, String _, String body) in cards)
        if (RegExp(r'[.?!] [a-z@]').hasMatch(siteLead(body)))
          '$area: "${siteLead(body)}"',
    ];
    expect(joined, isEmpty, reason: joined.join('\n'));
  });

  test('every card lead fits three lines on a phone', () {
    final List<String> long = <String>[
      for (final (String area, String _, String body) in cards)
        if (siteLead(body).length > kLeadLimit)
          '$area (${siteLead(body).length}): "${siteLead(body)}"',
      for (final (String area, String _, String body) in cards)
        if (siteGap(body).length > kLeadLimit)
          '$area gap (${siteGap(body).length}): "${siteGap(body)}"',
    ];
    expect(long, isEmpty, reason: long.join('\n'));
  });
}
