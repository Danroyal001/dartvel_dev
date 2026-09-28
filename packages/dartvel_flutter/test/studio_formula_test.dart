// The formula bar's language: what a selected element's fields read as, and
// what typing into one means.
//
// Excel and PowerApps put a value and the expression that makes it in one
// line anyone can edit. Here a field is one of the element's properties, or
// its action, and a formula is a literal of that property's kind -- a
// number (with arithmetic), a colour, a choice, TRUE or FALSE, a string --
// or Navigate(...) for an action. What matters is refusing what is wrong
// with where it is wrong, before anything reaches the document: a colour
// that is not one, a choice that is not offered, arithmetic that does not
// close, a route no page has.
import 'package:dartvel_flutter/src/studio/page_document.dart';
import 'package:dartvel_flutter/src/studio/studio_formula.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DVPageNode text = DVPageNode.text('Welcome')
      .withProperty('fontSize', 18)
      .withProperty('color', '#111827')
      .withProperty('fontWeight', 'bold');

  group('fields', () {
    test('a text element offers its text first, then its properties', () {
      final List<DVFormulaField> fields = dvFormulaFields(text);
      expect(fields.first.name, 'text');
      expect(fields.map((DVFormulaField f) => f.name),
          containsAll(<String>['fontSize', 'color', 'fontWeight', 'action']));
    });

    test('a field reads as its formula', () {
      DVFormulaField f(String n) =>
          dvFormulaFields(text).firstWhere((DVFormulaField x) => x.name == n);
      expect(dvFormulaOf(text, f('text')), '"Welcome"');
      expect(dvFormulaOf(text, f('fontSize')), '18');
      expect(dvFormulaOf(text, f('color')), '#111827');
      expect(dvFormulaOf(text, f('fontWeight')), 'bold');
      expect(dvFormulaOf(text, f('action')), 'None');
      expect(
          dvFormulaOf(text.withAction(<String, Object?>{'type': 'navigate', 'to': '/pricing'}),
              f('action')),
          'Navigate("/pricing")');
    });
  });

  group('parsing', () {
    DVFormulaField field(String n) =>
        dvFormulaFields(text).firstWhere((DVFormulaField x) => x.name == n);
    const DVFormulaVocabulary words =
        DVFormulaVocabulary(routes: <String>['/', '/pricing']);

    test('numbers, with arithmetic', () {
      expect(dvParseFormula('24', field('fontSize'), words).value, 24);
      expect(dvParseFormula('=12 * 2 + 4', field('fontSize'), words).value, 28);
      expect(dvParseFormula('(10 + 2) / 4', field('fontSize'), words).value, 3);
    });

    test('text, quoted or bare', () {
      expect(dvParseFormula('"Hi, there"', field('text'), words).value, 'Hi, there');
      expect(dvParseFormula('Hi there', field('text'), words).value, 'Hi there');
      expect(dvParseFormula(r'"Say \"hi\""', field('text'), words).value, 'Say "hi"');
    });

    test('colours as hex or rgb()', () {
      expect(dvParseFormula('#FF0000', field('color'), words).value, '#FF0000');
      expect(dvParseFormula('rgb(17, 24, 39)', field('color'), words).value, '#111827');
    });

    test('an action is Navigate to a known route, or None', () {
      expect(dvParseFormula('Navigate("/pricing")', field('action'), words).value,
          <String, Object?>{'type': 'navigate', 'to': '/pricing'});
      expect(dvParseFormula('None', field('action'), words).value, isNull);
      expect(dvParseFormula('None', field('action'), words).error, isNull);
    });

    test('what is wrong is refused, and says where', () {
      final DVFormulaResult colour = dvParseFormula('#GG0000', field('color'), words);
      expect(colour.error, contains('colour'));
      expect(colour.column, 0);
      final DVFormulaResult choice = dvParseFormula('heavy', field('fontWeight'), words);
      expect(choice.error, contains('bold'));
      final DVFormulaResult open = dvParseFormula('(1 + 2', field('fontSize'), words);
      expect(open.error, contains(')'));
      expect(open.column, 6);
      final DVFormulaResult route = dvParseFormula('Navigate("/nowhere")', field('action'), words);
      expect(route.error, contains('/nowhere'));
      final DVFormulaResult word = dvParseFormula('big', field('fontSize'), words);
      expect(word.error, isNotNull);
    });
  });

  group('highlighting', () {
    test('a formula is split into the kinds it is made of', () {
      final List<DVFormulaToken> tokens =
          dvFormulaTokens('Navigate("/pricing") + 12');
      expect(tokens.map((DVFormulaToken t) => t.kind), <DVFormulaTokenKind>[
        DVFormulaTokenKind.function,
        DVFormulaTokenKind.punctuation,
        DVFormulaTokenKind.string,
        DVFormulaTokenKind.punctuation,
        DVFormulaTokenKind.operator,
        DVFormulaTokenKind.number,
      ]);
    });
  });

  group('completion', () {
    const DVFormulaVocabulary words = DVFormulaVocabulary(
      routes: <String>['/', '/pricing', '/privacy'],
      models: <String, List<String>>{'Article': <String>['title', 'slug']},
      functions: <String>['publishArticle'],
    );

    test('a choice offers its choices', () {
      final DVFormulaField weight = dvFormulaFields(text)
          .firstWhere((DVFormulaField x) => x.name == 'fontWeight');
      expect(dvFormulaSuggestions('se', 2, weight, words).map((DVFormulaSuggestion s) => s.insert),
          contains('semibold'));
    });

    test('inside Navigate the routes are offered', () {
      final DVFormulaField action = dvFormulaFields(text)
          .firstWhere((DVFormulaField x) => x.name == 'action');
      expect(
          dvFormulaSuggestions('Navigate("/pr', 13, action, words)
              .map((DVFormulaSuggestion s) => s.insert),
          <String>['/pricing', '/privacy']);
    });

    test('models, their fields and functions are offered by name', () {
      final DVFormulaField t = dvFormulaFields(text).first;
      expect(dvFormulaSuggestions('Art', 3, t, words).map((DVFormulaSuggestion s) => s.insert),
          contains('Article'));
      expect(dvFormulaSuggestions('Article.t', 9, t, words).map((DVFormulaSuggestion s) => s.insert),
          contains('title'));
      expect(dvFormulaSuggestions('pub', 3, t, words).map((DVFormulaSuggestion s) => s.insert),
          contains('publishArticle'));
    });
  });
}
