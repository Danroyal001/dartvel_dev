import 'package:sqlparser/sqlparser.dart';
import 'package:sqlparser/src/reader/tokenizer/scanner.dart';
import 'package:test/test.dart';

import '../parser/utils.dart';

void main() {
  test('parses ** as two tokens when not using drift mode', () {
    final tokens = Scanner(fakeSpan('**')).scanTokens();
    expect(tokens.map((e) => e.type),
        containsAllInOrder([TokenType.star, TokenType.star]));
  });

  test('throws when seeing an invalid token', () {
    expect(
      () => SqlEngine().tokenize(fakeSpan('!')),
      throwsA(isA<CumulatedTokenizerException>()),
    );
  });

  test('scans identifiers with backticks', () {
    expect(
      Scanner(fakeSpan('`SELECT`')).scanTokens(),
      contains(isA<IdentifierToken>()
          .having((e) => e.identifier, 'identifier', 'SELECT')),
    );
  });

  test('scans identifiers with double quotes', () {
    expect(
      Scanner(fakeSpan('"SELECT"')).scanTokens(),
      contains(isA<IdentifierToken>()
          .having((e) => e.identifier, 'identifier', 'SELECT')),
    );
  });

  test('scans new tokens for JSON extraction', () {
    expect(Scanner(fakeSpan('- -> ->>')).scanTokens(), [
      isA<Token>().having((e) => e.type, 'tokenType', TokenType.minus),
      isA<Token>().having((e) => e.type, 'tokenType', TokenType.dashRangle),
      isA<Token>()
          .having((e) => e.type, 'tokenType', TokenType.dashRangleRangle),
      isA<Token>().having((e) => e.type, 'tokenType', TokenType.eof),
    ]);
  });

  group('reports error message', () {
    test(r'for missing identifier after `$`', () {
      expect(
        () => SqlEngine().tokenize(fakeSpan(r'$ order')),
        throwsA(
          isA<CumulatedTokenizerException>().having(
            (e) => e.errors,
            'errors',
            contains(
              isA<TokenizerError>()
                  .having((e) => e.message, 'message',
                      r'Expected identifier after `$`')
                  .having((e) => e.location.offset, 'location.offset', 1),
            ),
          ),
        ),
      );
    });

    test('for missing identifier after `@`', () {
      expect(
        () => SqlEngine().tokenize(fakeSpan('@ order')),
        throwsA(
          isA<CumulatedTokenizerException>().having(
            (e) => e.errors,
            'errors',
            contains(
              isA<TokenizerError>()
                  .having((e) => e.message, 'message',
                      r'Expected identifier after `@`')
                  .having((e) => e.location.offset, 'location.offset', 1),
            ),
          ),
        ),
      );
    });
  });

  test('does not crash on non-SQL input', () async {
    // Regression test for https://github.com/simolus3/drift/issues/3273#issuecomment-2468988502
    const badInput = '''
class Screen extends ConsumerStatefulWidget {
  const Screen({super.key});

  @override
  ConsumerState<Screen> createState() => _ScreenState();
}
''';

    expect(() => SqlEngine().tokenizeString(badInput),
        throwsA(isA<CumulatedTokenizerException>()));

    final parsed = SqlEngine().parse(badInput);
    expect(parsed.errors, isNotEmpty);
    expect(parsed.rootNode, isA<InvalidStatement>());
  });
}
