/// Tax: asked of a provider, never calculated by the framework, and never
/// zero because the asking failed.
///
/// Dartvel ships no rates. A rate compiled into a release is wrong somewhere
/// before the release finishes rolling out, so the amount comes from a
/// [DVTaxProvider] -- Stripe Tax, Avalara, whatever a finance team already
/// pays for. What lives here is the part a provider cannot own: refusing the
/// sale when the provider cannot answer, checking that an answer adds up
/// before it is charged, and the one fallback an application may declare --
/// a table of its own with an expiry, whose every sale is marked for
/// re-rating.
///
/// [DVTaxTable] is also the reference implementation of the rounding rules,
/// which a provider adapter or a finance team can check itself against: rates
/// are exact decimals, an exact half rounds by a declared mode, document
/// rounding rounds once and allocates by largest remainder, and the lines of
/// every quote sum to its total.
library dartvel.commerce.tax;

import 'dart:async';
import 'dart:convert';

import '../billing/money.dart';
import '../observability/observability.dart';
import 'exact.dart';

/// What is being sold, as tax law classifies it.
///
/// Declared, never inferred: the same price is taxed differently as a digital
/// service, a physical good and a piece of professional advice, and guessing
/// wrong is an under-collection that surfaces at audit. An application with a
/// category of its own names it; a provider adapter maps ids to its own codes
/// and refuses an id it has no mapping for.
class DVTaxCategory {
  const DVTaxCategory(this.id);

  static const DVTaxCategory digitalService = DVTaxCategory('digitalService');
  static const DVTaxCategory physicalGood = DVTaxCategory('physicalGood');
  static const DVTaxCategory professionalService =
      DVTaxCategory('professionalService');

  final String id;

  @override
  bool operator ==(Object other) => other is DVTaxCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DVTaxCategory($id)';
}

/// Where a sale is taxed: normally the customer's billing address.
class DVTaxAddress {
  const DVTaxAddress({
    required this.country,
    this.region,
    this.postalCode,
    this.city,
    this.line1,
  });

  /// ISO 3166-1 alpha-2, in either case.
  final String country;

  /// The ISO 3166-2 subdivision, with or without its country prefix: `NY` or
  /// `US-NY`.
  final String? region;
  final String? postalCode;
  final String? city;
  final String? line1;

  String get _country => country.trim().toUpperCase();

  /// Jurisdiction keys from most to least specific.
  List<String> get jurisdictionKeys {
    final String c = _country;
    final String? r = region?.trim().toUpperCase();
    if (r == null || r.isEmpty) return <String>[c];
    final String subdivision = r.startsWith('$c-') ? r.substring(c.length + 1) : r;
    return <String>['$c-$subdivision', c];
  }
}

/// Whether a line's amount already includes its tax.
enum DVTaxBehavior {
  /// Tax is added on top: a 10.00 line at 20% charges 12.00.
  exclusive,

  /// Tax is inside the amount: a 12.00 line at 20% charges 12.00, of which
  /// 2.00 is tax.
  inclusive,
}

/// One line of a sale, as tax sees it.
class DVTaxLine {
  DVTaxLine({
    required this.reference,
    required this.amount,
    required this.category,
    DVMoney? discount,
  }) : discount = discount ?? DVMoney(amount: 0, currency: amount.currency) {
    if (reference.isEmpty) {
      throw ArgumentError.value(reference, 'reference', 'must not be empty');
    }
    if (this.discount.currency != amount.currency) {
      throw ArgumentError.value(this.discount, 'discount',
          'is in a different currency from the line it discounts');
    }
    if (this.discount.amount > amount.amount) {
      throw ArgumentError.value(this.discount, 'discount',
          'is larger than the line; a discount does not pay the customer');
    }
  }

  /// The application's name for the line, echoed on the quote.
  final String reference;

  /// The line's price before any discount, in minor units.
  final DVMoney amount;

  /// What promotions took off this line.
  ///
  /// Carried separately rather than netted off [amount], because whether tax
  /// is due on the price before or after a discount is a jurisdiction's rule
  /// and not the application's to decide by subtracting early.
  final DVMoney discount;
  final DVTaxCategory category;

  /// What the customer is charged for the line before tax is added.
  DVMoney get net =>
      DVMoney(amount: amount.amount - discount.amount, currency: amount.currency);
}

/// What a provider is asked to price.
class DVTaxRequest {
  DVTaxRequest({
    required List<DVTaxLine> lines,
    required this.to,
    this.behavior = DVTaxBehavior.exclusive,
  }) : lines = List<DVTaxLine>.unmodifiable(lines) {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'a sale has at least one line');
    }
    final Set<String> references = <String>{};
    for (final DVTaxLine line in lines) {
      if (line.amount.currency != lines.first.amount.currency) {
        throw ArgumentError.value(line.amount, 'lines',
            'mixes currencies; one quote is one currency');
      }
      if (!references.add(line.reference)) {
        throw ArgumentError.value(line.reference, 'lines',
            'reference is used twice, so a quote line could not be matched');
      }
    }
  }

  final List<DVTaxLine> lines;
  final DVTaxAddress to;
  final DVTaxBehavior behavior;

  String get currency => lines.first.amount.currency;
}

/// Where a quote's numbers came from.
enum DVTaxSource {
  /// The configured provider answered.
  provider,

  /// The application's declared offline table, because the provider could
  /// not be asked. The sale is to be re-rated.
  offlineTable,
}

/// One line of a quote.
class DVTaxQuoteLine {
  const DVTaxQuoteLine({
    required this.reference,
    required this.taxable,
    required this.tax,
    this.rate,
  });

  final String reference;

  /// The amount tax was computed on: after or before the discount as the
  /// jurisdiction rules, and net of tax for an inclusive price.
  final DVMoney taxable;
  final DVMoney tax;

  /// The rate applied, as a percentage string, when the source says.
  final String? rate;
}

/// A tax amount for a sale, and where it came from.
class DVTaxQuote {
  DVTaxQuote({
    required this.currency,
    required List<DVTaxQuoteLine> lines,
    required this.jurisdiction,
    required this.source,
    required this.quotedAt,
    DVMoney? tax,
    this.providerReference,
    this.behavior = DVTaxBehavior.exclusive,
  })  : lines = List<DVTaxQuoteLine>.unmodifiable(lines),
        tax = tax ??
            DVMoney(
              amount: lines.fold<int>(
                  0, (int sum, DVTaxQuoteLine l) => sum + l.tax.amount),
              currency: currency,
            );

  final String currency;
  final List<DVTaxQuoteLine> lines;
  final DVMoney tax;

  /// The jurisdiction the amount is for, such as `GB` or `US-NY`.
  final String jurisdiction;
  final DVTaxSource source;

  /// The provider's calculation id, which its invoice and its filing refer
  /// to. Kept on the sale; the invoice itself is the provider's.
  final String? providerReference;
  final DateTime quotedAt;
  final DVTaxBehavior behavior;

  /// Whether this sale was priced without the provider and has to be re-rated
  /// once it can be asked. `DV-COMMERCE-001`.
  bool get needsRerating => source == DVTaxSource.offlineTable;

  /// The quote line for [reference].
  DVTaxQuoteLine line(String reference) =>
      lines.firstWhere((DVTaxQuoteLine l) => l.reference == reference);
}

/// A tax service Dartvel asks.
abstract class DVTaxProvider {
  /// Prices [request].
  ///
  /// Throws [DVTaxUnavailable] when the service cannot be reached -- the one
  /// failure a declared offline table may stand in for -- and [DVTaxRefusal]
  /// when it answered and would not price the sale.
  Future<DVTaxQuote> quote(DVTaxRequest request);
}

/// The tax service could not be asked. Nothing was decided.
class DVTaxUnavailable implements Exception {
  const DVTaxUnavailable(this.message);
  final String message;

  @override
  String toString() => 'DVTaxUnavailable: $message';
}

/// The tax service, or a table, answered and would not price the sale.
///
/// A verdict, and never replaced by the offline table: yesterday's rates do
/// not overrule a service that looked at the address and said no.
class DVTaxRefusal implements Exception {
  const DVTaxRefusal(this.reason);
  final String reason;

  @override
  String toString() => 'DVTaxRefusal: $reason';
}

/// The sale was refused, with the diagnostic that says why.
class DVSaleRefused implements Exception {
  const DVSaleRefused(this.reason, {required this.code});
  final String reason;
  final String code;

  @override
  String toString() => 'DVSaleRefused: $code: $reason';
}

/// How an exact half of a minor unit is rounded.
enum DVTaxRoundingMode { halfUp, halfEven }

/// Where rounding happens.
enum DVTaxRoundingScope {
  /// Each line is rounded, and the total is their sum.
  line,

  /// The document's exact total is rounded once, and the lines are allocated
  /// from it by largest remainder.
  document,
}

/// Whether a discount reduces the amount tax is charged on.
enum DVDiscountTaxBasis { afterDiscount, beforeDiscount }

/// One row of a [DVTaxTable].
class DVTaxJurisdiction {
  const DVTaxJurisdiction({
    required this.code,
    required this.discountBasis,
    required this.rates,
  });

  final String code;
  final DVDiscountTaxBasis discountBasis;

  /// Percentages by category id, exactly as written.
  final Map<String, String> rates;
}

/// An application's own rate table: the offline fallback, and the reference
/// implementation of the rounding rules.
///
/// Its rates are the application's, not Dartvel's -- the framework ships no
/// table. Everything a calculation depends on is declared in the file and
/// nothing is defaulted: the date the rates were true, the rounding mode and
/// scope, and per jurisdiction whether a discount reduces the taxable amount.
///
/// ```json
/// {
///   "asOf": "2026-09-01",
///   "rounding": {"mode": "halfUp", "scope": "document"},
///   "jurisdictions": {
///     "GB": {"discountBasis": "afterDiscount",
///            "rates": {"digitalService": "20"}}
///   }
/// }
/// ```
///
/// A rate is a decimal string. A JSON number is refused, because the parser
/// makes a double of `8.875` before this code sees it.
class DVTaxTable {
  DVTaxTable({
    required this.asOf,
    required this.roundingMode,
    required this.roundingScope,
    required Map<String, DVTaxJurisdiction> jurisdictions,
  }) : jurisdictions = Map<String, DVTaxJurisdiction>.unmodifiable(
            <String, DVTaxJurisdiction>{
              for (final MapEntry<String, DVTaxJurisdiction> e
                  in jurisdictions.entries)
                e.key.toUpperCase(): e.value,
            }) {
    for (final DVTaxJurisdiction j in this.jurisdictions.values) {
      for (final MapEntry<String, String> rate in j.rates.entries) {
        if (dvParseDecimal(rate.value) == null) {
          throw FormatException(
              '${j.code} ${rate.key}: a rate is a decimal percentage such as '
              '"8.875"',
              rate.value);
        }
      }
    }
  }

  /// Reads a table file.
  factory DVTaxTable.fromJson(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('a tax table is a JSON object');
    }
    final Object? asOf = decoded['asOf'];
    if (asOf is! String) {
      throw const FormatException(
          'a tax table declares "asOf", the date its rates were true; '
          'without it nothing can say when the table went stale');
    }
    final Object? rounding = decoded['rounding'];
    if (rounding is! Map<String, Object?>) {
      throw const FormatException(
          'a tax table declares "rounding": {"mode": ..., "scope": ...}');
    }
    final Object? rows = decoded['jurisdictions'];
    if (rows is! Map<String, Object?> || rows.isEmpty) {
      throw const FormatException('a tax table declares "jurisdictions"');
    }
    return DVTaxTable(
      asOf: _parseDate(asOf),
      roundingMode: _enum(DVTaxRoundingMode.values, rounding['mode'], 'mode'),
      roundingScope:
          _enum(DVTaxRoundingScope.values, rounding['scope'], 'scope'),
      jurisdictions: <String, DVTaxJurisdiction>{
        for (final MapEntry<String, Object?> row in rows.entries)
          row.key: _jurisdiction(row.key.toUpperCase(), row.value),
      },
    );
  }

  /// When the rates were true, in UTC.
  final DateTime asOf;
  final DVTaxRoundingMode roundingMode;
  final DVTaxRoundingScope roundingScope;
  final Map<String, DVTaxJurisdiction> jurisdictions;

  /// Prices [request] from this table.
  ///
  /// Throws [DVTaxRefusal] when no row covers the address or the row does not
  /// declare a category: the most specific row is the one that applies, and
  /// borrowing a missing category from the country row would charge a rate
  /// that belongs to somewhere else.
  DVTaxQuote price(
    DVTaxRequest request, {
    required DVTaxSource source,
    required DateTime at,
  }) {
    DVTaxJurisdiction? row;
    for (final String key in request.to.jurisdictionKeys) {
      row = jurisdictions[key];
      if (row != null) break;
    }
    if (row == null) {
      throw DVTaxRefusal(
          'the table has no row for ${request.to.jurisdictionKeys.first}');
    }
    final String currency = request.currency;
    final bool halfEven = roundingMode == DVTaxRoundingMode.halfEven;

    final List<DVExact> exact = <DVExact>[];
    final List<int> bases = <int>[];
    final List<String> rates = <String>[];
    for (final DVTaxLine line in request.lines) {
      final String? percent = row.rates[line.category.id];
      if (percent == null) {
        throw DVTaxRefusal(
            '${row.code} declares no rate for ${line.category.id}');
      }
      final DVExact rate =
          dvParseDecimal(percent)!.scale(BigInt.one, BigInt.from(100));
      final int base = row.discountBasis == DVDiscountTaxBasis.afterDiscount
          ? line.net.amount
          : line.amount.amount;
      bases.add(base);
      rates.add(percent);
      exact.add(switch (request.behavior) {
        DVTaxBehavior.exclusive =>
          DVExact.integer(base).scale(rate.numerator, rate.denominator),
        // Tax inside a gross amount: gross * r / (1 + r).
        DVTaxBehavior.inclusive => DVExact.integer(base).scale(
            rate.numerator, rate.denominator + rate.numerator),
      });
    }

    final List<int> taxes = switch (roundingScope) {
      DVTaxRoundingScope.line => <int>[
          for (final DVExact e in exact) e.round(halfEven: halfEven),
        ],
      DVTaxRoundingScope.document => dvAllocate(
          exact.reduce((DVExact a, DVExact b) => a + b).round(halfEven: halfEven),
          exact,
        ),
    };

    return DVTaxQuote(
      currency: currency,
      jurisdiction: row.code,
      source: source,
      quotedAt: at,
      behavior: request.behavior,
      lines: <DVTaxQuoteLine>[
        for (int i = 0; i < request.lines.length; i++)
          DVTaxQuoteLine(
            reference: request.lines[i].reference,
            taxable: DVMoney(
              amount: request.behavior == DVTaxBehavior.inclusive
                  ? bases[i] - taxes[i]
                  : bases[i],
              currency: currency,
            ),
            tax: DVMoney(amount: taxes[i], currency: currency),
            rate: rates[i],
          ),
      ],
    );
  }

  static DateTime _parseDate(String value) {
    final RegExpMatch? day =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (day != null) {
      return DateTime.utc(int.parse(day.group(1)!), int.parse(day.group(2)!),
          int.parse(day.group(3)!));
    }
    // A timestamp without a zone is local time on whichever machine reads
    // it, which moves the expiry by up to a day between two servers.
    if (RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value)) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw FormatException(
        '"asOf" is a date (2026-09-01) or a timestamp with a zone', value);
  }

  static T _enum<T extends Enum>(List<T> values, Object? name, String field) {
    for (final T value in values) {
      if (value.name == name) return value;
    }
    throw FormatException(
      '"$field" is one of ${values.map((T v) => v.name).join(', ')}',
      '$name',
    );
  }

  static DVTaxJurisdiction _jurisdiction(String code, Object? row) {
    if (row is! Map<String, Object?>) {
      throw FormatException('$code is not an object');
    }
    final Object? rates = row['rates'];
    if (rates is! Map<String, Object?>) {
      throw FormatException('$code declares no "rates"');
    }
    if (!row.containsKey('discountBasis')) {
      throw FormatException(
          '$code declares no "discountBasis". Whether a discount reduces the '
          'taxable amount is the jurisdiction\'s rule, so it is written down '
          'rather than assumed');
    }
    return DVTaxJurisdiction(
      code: code,
      discountBasis: _enum(
          DVDiscountTaxBasis.values, row['discountBasis'], 'discountBasis'),
      rates: <String, String>{
        for (final MapEntry<String, Object?> rate in rates.entries)
          rate.key: switch (rate.value) {
            final String text => text,
            final int whole => '$whole',
            _ => throw FormatException(
                '$code ${rate.key}: a rate is a string such as "8.875"; a '
                'JSON number with a fraction has already been a double',
                '${rate.value}'),
          },
      },
    );
  }
}

/// A [DVTaxTable] as a provider, for development and tests.
///
/// The rates are the table's, which is to say the application's.
class DVTableTaxProvider implements DVTaxProvider {
  DVTableTaxProvider(this.table, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DVTaxTable table;
  final DateTime Function() _clock;

  @override
  Future<DVTaxQuote> quote(DVTaxRequest request) async =>
      table.price(request, source: DVTaxSource.provider, at: _clock().toUtc());
}

/// The kiosk that cannot ask: a declared table with an expiry.
///
/// ```yaml
/// dartvel:
///   tax:
///     offline:
///       table: assets/tax/gb-2026.json
///       staleAfter: 14d
/// ```
class DVOfflineTaxTable {
  DVOfflineTaxTable({required this.table, required this.staleAfter}) {
    if (staleAfter <= Duration.zero) {
      throw ArgumentError.value(staleAfter, 'staleAfter', 'must be positive');
    }
  }

  /// Reads the `dartvel.tax.offline` block, loading the table through [read].
  factory DVOfflineTaxTable.fromConfig(
    Map<String, Object?> config, {
    required String Function(String path) read,
  }) {
    final Object? path = config['table'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('dartvel.tax.offline declares a "table"');
    }
    final Object? stale = config['staleAfter'];
    if (stale is! String) {
      throw const FormatException(
          'dartvel.tax.offline declares "staleAfter". A fallback table with '
          'no expiry charges last year\'s rates for as long as nobody '
          'notices');
    }
    return DVOfflineTaxTable(
      table: DVTaxTable.fromJson(read(path)),
      staleAfter: parseStaleAfter(stale),
    );
  }

  /// `14d` or `36h`.
  static Duration parseStaleAfter(String value) {
    final RegExpMatch? match = RegExp(r'^([1-9]\d*)([dh])$').firstMatch(value);
    if (match == null) {
      throw FormatException(
          'staleAfter is a whole number of days or hours: 14d, 36h', value);
    }
    final int n = int.parse(match.group(1)!);
    return match.group(2) == 'd' ? Duration(days: n) : Duration(hours: n);
  }

  final DVTaxTable table;
  final Duration staleAfter;

  /// The moment sales stop being priced from this table.
  DateTime get expiresAt => table.asOf.add(staleAfter);
}

/// `DV.Tax`: tax asked of the configured provider.
class DVTax {
  DVTax({
    required this.provider,
    this.offline,
    this.timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
    DVLogger? logger,
  })  : _clock = clock ?? DateTime.now,
        _logger = logger;

  final DVTaxProvider provider;

  /// The declared fallback, or null. Null is the default and means an outage
  /// refuses every sale.
  final DVOfflineTaxTable? offline;

  /// How long the provider is waited for before it counts as unreachable.
  final Duration timeout;
  final DateTime Function() _clock;
  final DVLogger? _logger;

  DVLogger get _log => _logger ?? DVObservability.logger;

  static DVTax? _current;

  /// Sets what `DV.Tax` answers with.
  static void configure(DVTax tax) => _current = tax;
  static void unconfigure() => _current = null;

  static DVTax get current {
    final DVTax? tax = _current;
    if (tax == null) {
      throw StateError(
        'DV.Tax is not configured. Call DVTax.configure(DVTax(provider: ...)) '
        'at startup. There is no default provider, because the only one that '
        'needs no configuration is one that charges no tax.',
      );
    }
    return tax;
  }

  /// Tax on a single [amount] of category [of], sold [to] an address.
  Future<DVTaxQuote> quote({
    required DVMoney amount,
    required DVTaxAddress to,
    required DVTaxCategory of,
    DVMoney? discount,
    DVTaxBehavior behavior = DVTaxBehavior.exclusive,
  }) =>
      quoteLines(DVTaxRequest(
        to: to,
        behavior: behavior,
        lines: <DVTaxLine>[
          DVTaxLine(
            reference: 'amount',
            amount: amount,
            category: of,
            discount: discount,
          ),
        ],
      ));

  /// Tax on every line of [request].
  ///
  /// Throws [DVSaleRefused] rather than returning a quote it cannot stand
  /// behind: `DV-COMMERCE-002` when tax could not be resolved, including a
  /// provider answer that does not add up, and `DV-COMMERCE-007` when the
  /// provider is unreachable and the declared table is past its expiry.
  Future<DVTaxQuote> quoteLines(DVTaxRequest request) async {
    final Object outage;
    try {
      final DVTaxQuote quote = await provider.quote(request).timeout(timeout);
      final String? wrong = _disagreement(request, quote);
      if (wrong != null) {
        throw _refuse(request, 'the provider answered and $wrong');
      }
      return quote;
    } on DVSaleRefused {
      rethrow;
    } on DVTaxRefusal catch (refusal) {
      throw _refuse(request, 'the provider refused: ${refusal.reason}');
    } on DVTaxUnavailable catch (error) {
      outage = error;
    } on TimeoutException {
      outage = 'no answer within ${timeout.inMilliseconds}ms';
    } on Object catch (error) {
      // Not known to be an outage, so not something the table may cover.
      throw _refuse(request, 'the provider failed: $error');
    }

    final DVOfflineTaxTable? fallback = offline;
    if (fallback == null) {
      throw _refuse(request,
          'the provider could not be asked ($outage) and no offline table is '
          'declared');
    }
    final DateTime now = _clock().toUtc();
    if (!now.isBefore(fallback.expiresAt)) {
      const String code = 'DV-COMMERCE-007';
      final String reason =
          'the provider could not be asked ($outage) and the offline tax '
          'table expired at ${fallback.expiresAt.toIso8601String()}';
      _log.log('$code: $reason; the sale was refused',
          level: DVLogLevel.error,
          code: code,
          context: _context(request));
      throw DVSaleRefused(reason, code: code);
    }
    final DVTaxQuote quote;
    try {
      quote = fallback.table
          .price(request, source: DVTaxSource.offlineTable, at: now);
    } on DVTaxRefusal catch (refusal) {
      throw _refuse(request,
          'the provider could not be asked ($outage) and the offline table '
          'cannot price it: ${refusal.reason}');
    }
    _log.log(
      'DV-COMMERCE-001: priced from the offline tax table as of '
      '${fallback.table.asOf.toIso8601String()} because the provider could '
      'not be asked ($outage); the sale is marked for re-rating',
      level: DVLogLevel.warn,
      code: 'DV-COMMERCE-001',
      context: <String, Object?>{
        ..._context(request),
        'jurisdiction': quote.jurisdiction,
        'tax': quote.tax.amount,
      },
    );
    return quote;
  }

  /// Why [quote] cannot be the answer to [request], or null when it can.
  static String? _disagreement(DVTaxRequest request, DVTaxQuote quote) {
    if (quote.source != DVTaxSource.provider) {
      return 'claimed a source other than the provider';
    }
    if (quote.currency != request.currency ||
        quote.tax.currency != request.currency) {
      return 'priced it in ${quote.currency}, not ${request.currency}';
    }
    final Set<String> asked = <String>{
      for (final DVTaxLine l in request.lines) l.reference,
    };
    final Set<String> answered = <String>{};
    int sum = 0;
    for (final DVTaxQuoteLine line in quote.lines) {
      if (line.tax.currency != request.currency ||
          line.taxable.currency != request.currency) {
        return 'priced line ${line.reference} in another currency';
      }
      if (!answered.add(line.reference)) {
        return 'answered line ${line.reference} twice';
      }
      sum += line.tax.amount;
    }
    if (answered.length != asked.length || !answered.containsAll(asked)) {
      return 'its lines are not the lines asked about';
    }
    if (sum != quote.tax.amount) {
      return 'its lines sum to $sum while its total is ${quote.tax.amount}';
    }
    return null;
  }

  DVSaleRefused _refuse(DVTaxRequest request, String why) {
    const String code = 'DV-COMMERCE-002';
    _log.log('$code: tax could not be resolved and the sale was refused: $why',
        level: DVLogLevel.error, code: code, context: _context(request));
    return DVSaleRefused(why, code: code);
  }

  /// No street, no postcode: the country and region are what a reader of
  /// the log needs, and the rest identifies a person.
  static Map<String, Object?> _context(DVTaxRequest request) =>
      <String, Object?>{
        'currency': request.currency,
        'jurisdiction': request.to.jurisdictionKeys.first,
      };
}
