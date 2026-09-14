// Tax is asked for, never calculated -- and when it cannot be asked, it is
// never zero.
//
// Every failure worth a test here produces a plausible number. A rate held as
// a double that is a hundredth of a cent out, a document rounded line by line
// that collects a cent more than its total says, tax charged on the price
// before a discount where the jurisdiction taxes the price after it, a
// provider outage that resolves to "no tax due", a sale priced from
// yesterday's table that nothing marks for re-rating. None of those throws,
// and each is money the application owes and did not collect.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String gbTable = '''
{
  "asOf": "2026-09-01",
  "rounding": {"mode": "halfUp", "scope": "document"},
  "jurisdictions": {
    "GB": {
      "discountBasis": "afterDiscount",
      "rates": {"digitalService": "20", "physicalGood": "20", "books": "0"}
    },
    "US": {
      "discountBasis": "beforeDiscount",
      "rates": {"digitalService": "5"}
    },
    "US-NY": {
      "discountBasis": "afterDiscount",
      "rates": {"digitalService": "8.875", "physicalGood": "8.5"}
    }
  }
}
''';

const DVTaxAddress london = DVTaxAddress(country: 'gb', postalCode: 'SW1A 1AA');
const DVTaxAddress newYork = DVTaxAddress(country: 'US', region: 'NY');
const DVTaxAddress california = DVTaxAddress(country: 'US', region: 'CA');

DVMoney gbp(int amount) => DVMoney(amount: amount, currency: 'GBP');
DVMoney usd(int amount) => DVMoney(amount: amount, currency: 'USD');

String table({
  String mode = 'halfUp',
  String scope = 'document',
  String asOf = '2026-09-01',
}) =>
    gbTable
        .replaceFirst('"mode": "halfUp"', '"mode": "$mode"')
        .replaceFirst('"scope": "document"', '"scope": "$scope"')
        .replaceFirst('"asOf": "2026-09-01"', '"asOf": "$asOf"');

/// A provider that answers with whatever the test hands it.
class ScriptedTaxProvider implements DVTaxProvider {
  ScriptedTaxProvider(this.answer);

  Future<DVTaxQuote> Function(DVTaxRequest request) answer;
  int calls = 0;

  @override
  Future<DVTaxQuote> quote(DVTaxRequest request) {
    calls++;
    return answer(request);
  }
}

void main() {
  final DateTime now = DateTime.utc(2026, 9, 14, 12);

  group('the reference table', () {
    DVTaxQuote price(
      DVTaxRequest request, {
      String mode = 'halfUp',
      String scope = 'document',
    }) =>
        DVTaxTable.fromJson(table(mode: mode, scope: scope)).price(
          request,
          source: DVTaxSource.provider,
          at: now,
        );

    test('a decimal rate is exact, not a double', () {
      // 8.875% of $10.00 is 88.75 cents. As a double, 1000 * 0.08875 is
      // 88.74999999999999, which rounds half-up to 88.
      final DVTaxQuote quote = price(DVTaxRequest(
        to: newYork,
        lines: <DVTaxLine>[
          DVTaxLine(
            reference: 'a',
            amount: usd(1000),
            category: DVTaxCategory.digitalService,
          ),
        ],
      ));
      expect(quote.tax, usd(89));
      expect(quote.jurisdiction, 'US-NY');
    });

    test('an exact half rounds by the declared mode', () {
      // 8.5% of 100 cents is exactly 8.5.
      DVTaxRequest request() => DVTaxRequest(
            to: newYork,
            lines: <DVTaxLine>[
              DVTaxLine(
                reference: 'a',
                amount: usd(100),
                category: DVTaxCategory.physicalGood,
              ),
            ],
          );
      expect(price(request(), mode: 'halfUp').tax, usd(9));
      expect(price(request(), mode: 'halfEven').tax, usd(8));
    });

    test('document rounding rounds once and the lines still sum to it', () {
      // Three 33p lines at 20% are 6.6p each. Rounded per line that is 21p;
      // the document's exact tax is 19.8p, which is 20p.
      final DVTaxRequest request = DVTaxRequest(
        to: london,
        lines: <DVTaxLine>[
          for (final String ref in <String>['a', 'b', 'c'])
            DVTaxLine(
              reference: ref,
              amount: gbp(33),
              category: DVTaxCategory.digitalService,
            ),
        ],
      );
      final DVTaxQuote document = price(request, scope: 'document');
      expect(document.tax, gbp(20));
      expect(
        document.lines.fold<int>(0, (int sum, DVTaxQuoteLine l) => sum + l.tax.amount),
        20,
      );
      expect(
        document.lines.map((DVTaxQuoteLine l) => l.tax.amount).toList(),
        <int>[7, 7, 6],
      );

      final DVTaxQuote perLine = price(request, scope: 'line');
      expect(perLine.tax, gbp(21));
      expect(
        perLine.lines.map((DVTaxQuoteLine l) => l.tax.amount).toList(),
        <int>[7, 7, 7],
      );
    });

    test('lines always sum to the total, across mixed rates and many lines', () {
      for (int seed = 1; seed < 400; seed++) {
        final List<DVTaxLine> lines = <DVTaxLine>[
          for (int i = 0; i < 1 + seed % 7; i++)
            DVTaxLine(
              reference: 'l$i',
              amount: usd((seed * 7919 + i * 104729) % 10007),
              category: i.isEven
                  ? DVTaxCategory.digitalService
                  : DVTaxCategory.physicalGood,
            ),
        ];
        for (final String scope in <String>['line', 'document']) {
          final DVTaxQuote quote = price(
            DVTaxRequest(to: newYork, lines: lines),
            scope: scope,
            mode: seed.isEven ? 'halfEven' : 'halfUp',
          );
          expect(
            quote.lines.fold<int>(0, (int s, DVTaxQuoteLine l) => s + l.tax.amount),
            quote.tax.amount,
            reason: 'seed $seed, $scope',
          );
        }
      }
    });

    test('an inclusive price has its tax extracted, not added', () {
      DVTaxQuote inclusive(int gross, String mode) => price(
            DVTaxRequest(
              to: london,
              behavior: DVTaxBehavior.inclusive,
              lines: <DVTaxLine>[
                DVTaxLine(
                  reference: 'a',
                  amount: gbp(gross),
                  category: DVTaxCategory.digitalService,
                ),
              ],
            ),
            mode: mode,
          );
      expect(inclusive(1200, 'halfUp').tax, gbp(200));
      expect(inclusive(1200, 'halfUp').lines.single.taxable, gbp(1000));
      // 999 * 20/120 is exactly 166.5.
      expect(inclusive(999, 'halfUp').tax, gbp(167));
      expect(inclusive(999, 'halfEven').tax, gbp(166));
    });

    test('a discount reduces the taxable amount where the jurisdiction says so',
        () {
      DVTaxQuote discounted(DVTaxAddress to) => price(DVTaxRequest(
            to: to,
            lines: <DVTaxLine>[
              DVTaxLine(
                reference: 'a',
                amount: to.country.toUpperCase() == 'GB' ? gbp(10000) : usd(10000),
                discount: to.country.toUpperCase() == 'GB' ? gbp(2000) : usd(2000),
                category: DVTaxCategory.digitalService,
              ),
            ],
          ));
      // GB taxes the price after the discount: 20% of 80.00.
      final DVTaxQuote gb = discounted(london);
      expect(gb.tax, gbp(1600));
      expect(gb.lines.single.taxable, gbp(8000));
      // The US row declares the price before it: 5% of 100.00.
      final DVTaxQuote us = discounted(california);
      expect(us.tax, usd(500));
      expect(us.lines.single.taxable, usd(10000));
    });

    test('the most specific jurisdiction wins, and the country is a fallback',
        () {
      DVTaxRequest to(DVTaxAddress address) => DVTaxRequest(
            to: address,
            lines: <DVTaxLine>[
              DVTaxLine(
                reference: 'a',
                amount: usd(10000),
                category: DVTaxCategory.digitalService,
              ),
            ],
          );
      expect(price(to(newYork)).jurisdiction, 'US-NY');
      expect(price(to(california)).jurisdiction, 'US');
      expect(price(to(california)).tax, usd(500));
    });

    test('an unknown jurisdiction or undeclared category is refused, not zero',
        () {
      expect(
        () => price(DVTaxRequest(
          to: const DVTaxAddress(country: 'FR'),
          lines: <DVTaxLine>[
            DVTaxLine(
              reference: 'a',
              amount: DVMoney(amount: 1000, currency: 'EUR'),
              category: DVTaxCategory.digitalService,
            ),
          ],
        )),
        throwsA(isA<DVTaxRefusal>()),
      );
      expect(
        () => price(DVTaxRequest(
          to: london,
          lines: <DVTaxLine>[
            DVTaxLine(
              reference: 'a',
              amount: gbp(1000),
              category: DVTaxCategory.professionalService,
            ),
          ],
        )),
        throwsA(isA<DVTaxRefusal>()),
      );
    });

    test('a declared zero rate is zero, which is not the same as unknown', () {
      final DVTaxQuote quote = price(DVTaxRequest(
        to: london,
        lines: <DVTaxLine>[
          DVTaxLine(
            reference: 'a',
            amount: gbp(1000),
            category: const DVTaxCategory('books'),
          ),
        ],
      ));
      expect(quote.tax, gbp(0));
    });

    test('a table refuses what it cannot read exactly', () {
      String without(String needle, String replacement) =>
          gbTable.replaceFirst(needle, replacement);
      // A rate written as a JSON number has already been through a double.
      expect(
        () => DVTaxTable.fromJson(without('"8.875"', '8.875')),
        throwsFormatException,
      );
      expect(
        () => DVTaxTable.fromJson(without('"asOf": "2026-09-01",', '')),
        throwsFormatException,
      );
      expect(
        () => DVTaxTable.fromJson(
            without('"rounding": {"mode": "halfUp", "scope": "document"},', '')),
        throwsFormatException,
      );
      expect(
        () => DVTaxTable.fromJson(
            without('"discountBasis": "beforeDiscount",', '')),
        throwsFormatException,
      );
      expect(
        () => DVTaxTable.fromJson(without('"8.5"', '"8.5%"')),
        throwsFormatException,
      );
    });

    test('a request is one currency, with unique line references', () {
      expect(
        () => DVTaxRequest(to: london, lines: <DVTaxLine>[
          DVTaxLine(
              reference: 'a',
              amount: gbp(1),
              category: DVTaxCategory.digitalService),
          DVTaxLine(
              reference: 'b',
              amount: usd(1),
              category: DVTaxCategory.digitalService),
        ]),
        throwsArgumentError,
      );
      expect(
        () => DVTaxRequest(to: london, lines: <DVTaxLine>[
          for (int i = 0; i < 2; i++)
            DVTaxLine(
                reference: 'a',
                amount: gbp(1),
                category: DVTaxCategory.digitalService),
        ]),
        throwsArgumentError,
      );
      expect(
        () => DVTaxLine(
          reference: 'a',
          amount: gbp(100),
          discount: gbp(101),
          category: DVTaxCategory.digitalService,
        ),
        throwsArgumentError,
      );
    });
  });

  group('DVTax', () {
    late DVMemoryLogSink logs;
    late DVLogger logger;
    late DateTime clock;

    List<String> codes() =>
        logs.records.map((DVLogRecord r) => r.code).whereType<String>().toList();

    setUp(() {
      logs = DVMemoryLogSink();
      logger = DVLogger(sinks: <DVLogSink>[logs]);
      clock = now;
    });

    DVOfflineTaxTable offline({String staleAfter = '14d'}) =>
        DVOfflineTaxTable(
          table: DVTaxTable.fromJson(gbTable),
          staleAfter: DVOfflineTaxTable.parseStaleAfter(staleAfter),
        );

    DVTax tax(DVTaxProvider provider, {DVOfflineTaxTable? fallback}) => DVTax(
          provider: provider,
          offline: fallback,
          clock: () => clock,
          logger: logger,
          timeout: const Duration(milliseconds: 200),
        );

    Future<DVTaxQuote> ask(DVTax tax) => tax.quote(
          amount: gbp(1000),
          to: london,
          of: DVTaxCategory.digitalService,
        );

    test('the provider is asked, and its answer is the quote', () async {
      final ScriptedTaxProvider provider =
          ScriptedTaxProvider((DVTaxRequest request) async => DVTaxQuote(
                currency: 'GBP',
                jurisdiction: 'GB',
                source: DVTaxSource.provider,
                providerReference: 'taxcalc_1',
                quotedAt: now,
                lines: <DVTaxQuoteLine>[
                  DVTaxQuoteLine(
                    reference: request.lines.single.reference,
                    taxable: gbp(1000),
                    tax: gbp(200),
                  ),
                ],
              ));
      final DVTaxQuote quote = await ask(tax(provider));
      expect(quote.tax, gbp(200));
      expect(quote.providerReference, 'taxcalc_1');
      expect(quote.needsRerating, isFalse);
      expect(codes(), isEmpty);
    });

    test('an outage with no fallback refuses the sale; it is never zero',
        () async {
      final DVTax subject = tax(ScriptedTaxProvider(
          (_) async => throw const DVTaxUnavailable('connection refused')));
      await expectLater(
        ask(subject),
        throwsA(isA<DVSaleRefused>()
            .having((DVSaleRefused e) => e.code, 'code', 'DV-COMMERCE-002')),
      );
      expect(codes(), <String>['DV-COMMERCE-002']);
    });

    test('any other provider failure refuses the same way', () async {
      final DVTax subject =
          tax(ScriptedTaxProvider((_) async => throw StateError('bad json')));
      await expectLater(
        ask(subject),
        throwsA(isA<DVSaleRefused>()
            .having((DVSaleRefused e) => e.code, 'code', 'DV-COMMERCE-002')),
      );
    });

    test('an outage with a fresh fallback prices from it and marks the sale',
        () async {
      final DVTax subject = tax(
        ScriptedTaxProvider(
            (_) async => throw const DVTaxUnavailable('connection refused')),
        fallback: offline(),
      );
      final DVTaxQuote quote = await ask(subject);
      expect(quote.tax, gbp(200));
      expect(quote.source, DVTaxSource.offlineTable);
      expect(quote.needsRerating, isTrue);
      expect(codes(), <String>['DV-COMMERCE-001']);
      expect(logs.records.single.level, DVLogLevel.warn);
    });

    test('a provider that never answers is an outage, bounded by the timeout',
        () async {
      final DVTax subject = tax(
        ScriptedTaxProvider((_) => Completer<DVTaxQuote>().future),
        fallback: offline(),
      );
      final DVTaxQuote quote =
          await ask(subject).timeout(const Duration(seconds: 5));
      expect(quote.source, DVTaxSource.offlineTable);
    });

    test('a stale fallback refuses rather than guesses', () async {
      clock = DateTime.utc(2026, 9, 15); // asOf 2026-09-01 plus 14 days
      final DVTax subject = tax(
        ScriptedTaxProvider(
            (_) async => throw const DVTaxUnavailable('connection refused')),
        fallback: offline(),
      );
      await expectLater(
        ask(subject),
        throwsA(isA<DVSaleRefused>()
            .having((DVSaleRefused e) => e.code, 'code', 'DV-COMMERCE-007')),
      );
      expect(codes(), <String>['DV-COMMERCE-007']);
      expect(logs.records.single.level, DVLogLevel.error);
    });

    test('a provider verdict is not overridden by the fallback', () async {
      final DVTax subject = tax(
        ScriptedTaxProvider(
            (_) async => throw const DVTaxRefusal('address is not deliverable')),
        fallback: offline(),
      );
      await expectLater(
        ask(subject),
        throwsA(isA<DVSaleRefused>()
            .having((DVSaleRefused e) => e.code, 'code', 'DV-COMMERCE-002')),
      );
      expect(codes(), <String>['DV-COMMERCE-002']);
    });

    test('a fallback with no row for the address refuses', () async {
      final DVTax subject = tax(
        ScriptedTaxProvider(
            (_) async => throw const DVTaxUnavailable('connection refused')),
        fallback: offline(),
      );
      await expectLater(
        subject.quote(
          amount: DVMoney(amount: 1000, currency: 'EUR'),
          to: const DVTaxAddress(country: 'FR'),
          of: DVTaxCategory.digitalService,
        ),
        throwsA(isA<DVSaleRefused>()
            .having((DVSaleRefused e) => e.code, 'code', 'DV-COMMERCE-002')),
      );
    });

    test('a provider answer that does not add up is refused', () async {
      DVTaxQuote answer(DVTaxRequest request,
              {String currency = 'GBP', int lineTax = 200, String? ref}) =>
          DVTaxQuote(
            currency: currency,
            jurisdiction: 'GB',
            source: DVTaxSource.provider,
            quotedAt: now,
            tax: DVMoney(amount: 200, currency: currency),
            lines: <DVTaxQuoteLine>[
              DVTaxQuoteLine(
                reference: ref ?? request.lines.single.reference,
                taxable: DVMoney(amount: 1000, currency: currency),
                tax: DVMoney(amount: lineTax, currency: currency),
              ),
            ],
          );
      for (final DVTaxQuote Function(DVTaxRequest) bad
          in <DVTaxQuote Function(DVTaxRequest)>[
        (DVTaxRequest r) => answer(r, lineTax: 199),
        (DVTaxRequest r) => answer(r, currency: 'USD'),
        (DVTaxRequest r) => answer(r, ref: 'somebody-else'),
      ]) {
        final DVTax subject =
            tax(ScriptedTaxProvider((DVTaxRequest r) async => bad(r)));
        await expectLater(
          ask(subject),
          throwsA(isA<DVSaleRefused>()
              .having((DVSaleRefused e) => e.code, 'code', 'DV-COMMERCE-002')),
        );
      }
    });

    test('an answer claiming the fallback source is not the provider', () async {
      // Only DVTax marks a sale offline; a provider cannot launder one in
      // unmarked, nor mark a real answer as needing re-rating.
      final DVTax subject = tax(ScriptedTaxProvider((DVTaxRequest r) async =>
          DVTaxQuote(
            currency: 'GBP',
            jurisdiction: 'GB',
            source: DVTaxSource.offlineTable,
            quotedAt: now,
            lines: <DVTaxQuoteLine>[
              DVTaxQuoteLine(
                  reference: r.lines.single.reference,
                  taxable: gbp(1000),
                  tax: gbp(200)),
            ],
          )));
      await expectLater(ask(subject), throwsA(isA<DVSaleRefused>()));
    });

    test('DV.Tax is configured, not assumed', () {
      DVTax.unconfigure();
      expect(() => DVTax.current, throwsStateError);
      final DVTax configured = tax(DVTableTaxProvider(DVTaxTable.fromJson(gbTable)));
      DVTax.configure(configured);
      addTearDown(DVTax.unconfigure);
      expect(DVTax.current, same(configured));
    });
  });

  group('the offline declaration', () {
    test('staleAfter is days or hours, and required', () {
      expect(DVOfflineTaxTable.parseStaleAfter('14d'), const Duration(days: 14));
      expect(DVOfflineTaxTable.parseStaleAfter('36h'), const Duration(hours: 36));
      for (final String bad in <String>['14', '', '0d', '-1d', '2w', '1.5d']) {
        expect(() => DVOfflineTaxTable.parseStaleAfter(bad),
            throwsFormatException,
            reason: bad);
      }
    });

    test('the pubspec block names a table and an expiry, both required', () {
      final DVOfflineTaxTable table = DVOfflineTaxTable.fromConfig(
        <String, Object?>{'table': 'assets/tax/gb-2026.json', 'staleAfter': '14d'},
        read: (String path) {
          expect(path, 'assets/tax/gb-2026.json');
          return gbTable;
        },
      );
      expect(table.expiresAt, DateTime.utc(2026, 9, 15));
      expect(
        () => DVOfflineTaxTable.fromConfig(
            <String, Object?>{'table': 'x.json'},
            read: (_) => gbTable),
        throwsFormatException,
      );
      expect(
        () => DVOfflineTaxTable.fromConfig(<String, Object?>{'staleAfter': '14d'},
            read: (_) => gbTable),
        throwsFormatException,
      );
    });
  });
}
