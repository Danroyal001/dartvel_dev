// Telegram Stars, the store inside a Mini App.
//
// Telegram keeps no product catalogue, so the bot writes each invoice and
// the payload is the only thing that ties a payment back to a product and an
// account. Everything worth testing is a way that tie can be forged or lost
// without anything throwing: a payload edited to name a dearer product, a
// pre-checkout answered "ok" for a price nobody declared, a receipt believed
// without Telegram ever having been paid, a webhook from somebody who is not
// Telegram, and a refund that never takes the purchase back.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const Entitlement exports = Entitlement('exports');

const DVPurchaseProduct coins = DVPurchaseProduct(
  'coins_100',
  billable: DVBillable.digital(telegram: 'coins_100', telegramStars: 50),
  entitlements: <Entitlement>{},
  kind: DVPurchaseKind.consumable,
);

const DVPurchaseProduct lifetime = DVPurchaseProduct(
  'exports_lifetime',
  billable: DVBillable.digital(telegram: 'exports', telegramStars: 250),
  entitlements: <Entitlement>{exports},
  kind: DVPurchaseKind.nonConsumable,
);

const String webhookSecret = 'hook-secret';
final DateTime start = DateTime.utc(2026, 10, 9, 12);

/// Telegram's Bot API as a test sees it: every call recorded, invoice links
/// handed out, and a list of Star transactions answered page by page.
class FakeBotApi {
  final List<(String method, Map<String, Object?> body)> calls =
      <(String, Map<String, Object?>)>[];
  final List<Map<String, Object?>> starTransactions = <Map<String, Object?>>[];
  int status = 200;

  Future<(int, String)> fetch(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    expect(url.host, 'api.telegram.org');
    expect(url.path, startsWith('/bottest-token/'));
    final String apiMethod = url.pathSegments.last;
    final Map<String, Object?> json = body == null
        ? <String, Object?>{}
        : (jsonDecode(body) as Map<Object?, Object?>).cast<String, Object?>();
    calls.add((apiMethod, json));
    if (status != 200) {
      return (status, jsonEncode(<String, Object?>{'ok': false}));
    }
    final Object? result = switch (apiMethod) {
      'createInvoiceLink' => 'https://t.me/\$invoice${calls.length}',
      'answerPreCheckoutQuery' => true,
      'getStarTransactions' => <String, Object?>{
          'transactions': starTransactions
              .skip((json['offset'] as int?) ?? 0)
              .take((json['limit'] as int?) ?? 100)
              .toList(),
        },
      _ => null,
    };
    return (200, jsonEncode(<String, Object?>{'ok': true, 'result': result}));
  }

  /// Records a payment as Telegram does once the person has paid.
  void pay(String payload, {required String chargeId, required int amount}) {
    starTransactions.add(<String, Object?>{
      'id': chargeId,
      'amount': amount,
      'date': start.millisecondsSinceEpoch ~/ 1000,
      'source': <String, Object?>{
        'type': 'user',
        'transaction_type': 'invoice_payment',
        'user': <String, Object?>{'id': 42, 'is_bot': false, 'first_name': 'A'},
        'invoice_payload': payload,
      },
    });
  }

  /// Records the bot refunding [chargeId]: an outgoing transaction with the
  /// same id, to the user.
  void refund(String chargeId, {required int amount}) {
    starTransactions.add(<String, Object?>{
      'id': chargeId,
      'amount': amount,
      'date': start.millisecondsSinceEpoch ~/ 1000 + 60,
      'receiver': <String, Object?>{
        'type': 'user',
        'user': <String, Object?>{'id': 42, 'is_bot': false, 'first_name': 'A'},
      },
    });
  }

  List<Map<String, Object?>> callsTo(String method) => <Map<String, Object?>>[
        for (final (String name, Map<String, Object?> body) in calls)
          if (name == method) body,
      ];
}

/// The payload with one character changed, still valid base64url.
String tamper(String payload) {
  final int middle = payload.length ~/ 2;
  final String swapped = payload[middle] == 'A' ? 'B' : 'A';
  return payload.replaceRange(middle, middle + 1, swapped);
}

void main() {
  late FakeBotApi bot;
  late DVTelegramStarsAdapter stars;

  DVTelegramStarsAdapter adapter({int pageSize = 100}) =>
      DVTelegramStarsAdapter(
        botToken: 'test-token',
        webhookSecret: webhookSecret,
        payloadKey: 'payload-key',
        fetch: bot.fetch,
        clock: () => start.add(const Duration(minutes: 5)),
        pageSize: pageSize,
      );

  Map<String, String> signedHeaders() =>
      <String, String>{DVTelegramStarsAdapter.secretHeader: webhookSecret};

  Future<DVStoreInvoice> invoiceFor(String storeProductId, int amount,
          {Object customer = 'alice'}) =>
      stars.createInvoice(
        storeProductId: storeProductId,
        title: 'Coins',
        amount: amount,
        appAccountToken: DVPurchases.accountTokenFor(customer),
      );

  String preCheckout(String payload, {int amount = 50, String currency = 'XTR'}) =>
      jsonEncode(<String, Object?>{
        'update_id': 1,
        'pre_checkout_query': <String, Object?>{
          'id': 'pcq_1',
          'from': <String, Object?>{'id': 42, 'is_bot': false, 'first_name': 'A'},
          'currency': currency,
          'total_amount': amount,
          'invoice_payload': payload,
        },
      });

  String serviceMessage(String field, String payload,
          {required String chargeId, int amount = 50, int dateOffset = 0}) =>
      jsonEncode(<String, Object?>{
        'update_id': 2,
        'message': <String, Object?>{
          'message_id': 7,
          'date': start.millisecondsSinceEpoch ~/ 1000 + dateOffset,
          'chat': <String, Object?>{'id': 42, 'type': 'private'},
          field: <String, Object?>{
            'currency': 'XTR',
            'total_amount': amount,
            'invoice_payload': payload,
            'telegram_payment_charge_id': chargeId,
            'provider_payment_charge_id': '',
          },
        },
      });

  setUp(() {
    bot = FakeBotApi();
    stars = adapter();
  });

  test('is the telegram store and needs no acknowledgement', () {
    expect(stars.store, DVStore.telegram);
    expect(stars.acknowledgementWindow, isNull);
  });

  group('an invoice', () {
    test('is written in Stars at the declared price, with no provider',
        () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);

      final Map<String, Object?> sent =
          bot.callsTo('createInvoiceLink').single;
      expect(sent['currency'], 'XTR');
      expect(sent['provider_token'], '');
      expect(sent['prices'], <Object?>[
        <String, Object?>{'label': 'Coins', 'amount': 50},
      ]);
      expect(sent['payload'], invoice.receipt);
      expect(invoice.url.toString(), startsWith(r'https://t.me/$invoice'));
    });

    test('carries a payload Telegram accepts: 1-128 bytes', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      expect(utf8.encode(invoice.receipt).length, inInclusiveRange(1, 128));
      final DVStoreInvoice longest =
          await invoiceFor('p' * DVTelegramStarsAdapter.maxProductIdBytes, 50);
      expect(utf8.encode(longest.receipt).length, lessThanOrEqualTo(128));
    });

    test('refuses a product id too long to fit the payload', () async {
      await expectLater(
        invoiceFor('p' * (DVTelegramStarsAdapter.maxProductIdBytes + 1), 50),
        throwsArgumentError,
      );
    });

    test('two invoices for the same thing are different payloads', () async {
      final DVStoreInvoice first = await invoiceFor('coins_100', 50);
      final DVStoreInvoice second = await invoiceFor('coins_100', 50);
      expect(first.receipt, isNot(second.receipt),
          reason: 'one payment must never match another invoice');
    });

    test('an unreachable Bot API is an outage, not a verdict', () async {
      bot.status = 502;
      await expectLater(
          invoiceFor('coins_100', 50), throwsA(isA<DVStoreUnavailable>()));
    });
  });

  group('the pre-checkout query', () {
    test('is approved for an invoice this bot wrote, then nothing applies',
        () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      await expectLater(
        stars.verifyNotification(preCheckout(invoice.receipt), signedHeaders()),
        throwsA(isA<DVStoreNothingToApply>()),
      );
      final Map<String, Object?> answer =
          bot.callsTo('answerPreCheckoutQuery').single;
      expect(answer['pre_checkout_query_id'], 'pcq_1');
      expect(answer['ok'], isTrue);
    });

    test('is declined for a tampered payload', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      await expectLater(
        stars.verifyNotification(
            preCheckout(tamper(invoice.receipt)), signedHeaders()),
        throwsA(isA<DVStoreNothingToApply>()),
      );
      final Map<String, Object?> answer =
          bot.callsTo('answerPreCheckoutQuery').single;
      expect(answer['ok'], isFalse);
      expect(answer['error_message'], isA<String>());
    });

    test('is declined for an amount the invoice did not ask for', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      await expectLater(
        stars.verifyNotification(
            preCheckout(invoice.receipt, amount: 1), signedHeaders()),
        throwsA(isA<DVStoreNothingToApply>()),
      );
      expect(bot.callsTo('answerPreCheckoutQuery').single['ok'], isFalse);
    });

    test('is declined for a currency other than Stars', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      await expectLater(
        stars.verifyNotification(
            preCheckout(invoice.receipt, currency: 'USD'), signedHeaders()),
        throwsA(isA<DVStoreNothingToApply>()),
      );
      expect(bot.callsTo('answerPreCheckoutQuery').single['ok'], isFalse);
    });
  });

  group('a receipt', () {
    test('verifies only once Telegram has the payment', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      await expectLater(stars.verifyReceipt(invoice.receipt),
          throwsA(isA<DVStoreRefusal>()));

      bot.pay(invoice.receipt, chargeId: 'charge_1', amount: 50);
      final DVStoreTransaction paid = await stars.verifyReceipt(invoice.receipt);

      expect(paid.store, DVStore.telegram);
      expect(paid.originalTransactionId, 'charge_1');
      expect(paid.transactionId, 'charge_1');
      expect(paid.storeProductId, 'coins_100');
      expect(paid.appAccountToken, DVPurchases.accountTokenFor('alice'));
      expect(paid.purchasedAt, start);
      expect(paid.revokedAt, isNull);
      expect(paid.acknowledged, isTrue);
    });

    test('is found past the first page of transactions', () async {
      stars = adapter(pageSize: 2);
      for (int i = 0; i < 5; i++) {
        bot.pay('someone-else-$i', chargeId: 'other_$i', amount: 10);
      }
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      bot.pay(invoice.receipt, chargeId: 'charge_1', amount: 50);
      expect((await stars.verifyReceipt(invoice.receipt)).originalTransactionId,
          'charge_1');
    });

    test('a tampered payload is refused without asking Telegram', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      bot.pay(tamper(invoice.receipt), chargeId: 'charge_1', amount: 50);
      await expectLater(stars.verifyReceipt(tamper(invoice.receipt)),
          throwsA(isA<DVStoreRefusal>()));
      expect(bot.callsTo('getStarTransactions'), isEmpty);
    });

    test('a payment of a different amount is refused', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      bot.pay(invoice.receipt, chargeId: 'charge_1', amount: 1);
      await expectLater(stars.verifyReceipt(invoice.receipt),
          throwsA(isA<DVStoreRefusal>()));
    });

    test('a refunded payment verifies as revoked', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      bot.pay(invoice.receipt, chargeId: 'charge_1', amount: 50);
      bot.refund('charge_1', amount: 50);
      final DVStoreTransaction refunded =
          await stars.verifyReceipt(invoice.receipt);
      expect(refunded.revokedAt, start.add(const Duration(seconds: 60)));
    });

    test('an unreachable Bot API is an outage, not a refusal', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      bot.status = 500;
      await expectLater(stars.verifyReceipt(invoice.receipt),
          throwsA(isA<DVStoreUnavailable>()));
    });
  });

  group('the webhook', () {
    test('refuses an update without Telegram\'s secret', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      final String body =
          serviceMessage('successful_payment', invoice.receipt, chargeId: 'c');
      await expectLater(stars.verifyNotification(body, const <String, String>{}),
          throwsA(isA<DVStoreRefusal>()));
      await expectLater(
        stars.verifyNotification(body,
            <String, String>{DVTelegramStarsAdapter.secretHeader: 'guess'}),
        throwsA(isA<DVStoreRefusal>()),
      );
    });

    test('reads the header whatever its case', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      final DVStoreNotification paid = await stars.verifyNotification(
        serviceMessage('successful_payment', invoice.receipt, chargeId: 'c1'),
        <String, String>{'x-telegram-bot-api-secret-token': webhookSecret},
      );
      expect(paid.notificationId, 'telegram:c1:paid');
    });

    test('an update that is not a payment has nothing to apply', () async {
      await expectLater(
        stars.verifyNotification(
          jsonEncode(<String, Object?>{
            'update_id': 3,
            'message': <String, Object?>{'message_id': 1, 'date': 0, 'text': 'hi'},
          }),
          signedHeaders(),
        ),
        throwsA(isA<DVStoreNothingToApply>()),
      );
    });

    test('a successful payment with a forged payload is refused', () async {
      final DVStoreInvoice invoice = await invoiceFor('coins_100', 50);
      await expectLater(
        stars.verifyNotification(
          serviceMessage('successful_payment', tamper(invoice.receipt),
              chargeId: 'c1'),
          signedHeaders(),
        ),
        throwsA(isA<DVStoreRefusal>()),
      );
    });
  });

  group('through DV.Purchases', () {
    late List<DVPurchaseChange> changes;
    late DVPurchases server;

    setUp(() {
      changes = <DVPurchaseChange>[];
      server = DVPurchases(
        products: const <DVPurchaseProduct>[coins, lifetime],
        stores: <DVStoreAdapter>[stars],
        ledger: DVMemoryPurchaseLedger(),
        clock: () => start.add(const Duration(minutes: 5)),
        onChange: changes.add,
        logger: DVLogger(sinks: <DVLogSink>[DVMemoryLogSink()]),
      );
    });

    test('a paid non-consumable is granted, and a refund takes it back',
        () async {
      final DVStoreInvoice invoice =
          await server.invoice(lifetime, customer: 'alice');
      expect(bot.callsTo('createInvoiceLink').single['prices'], <Object?>[
        <String, Object?>{'label': 'exports_lifetime', 'amount': 250},
      ]);
      bot.pay(invoice.receipt, chargeId: 'charge_9', amount: 250);

      final DVPurchaseResult granted = await server.verifyPurchase(
          DVStore.telegram, invoice.receipt,
          customer: 'alice');
      expect(granted.granted, <Entitlement>{exports});
      expect(await server.entitled('alice', exports), isTrue);

      // Telegram's own service message arrives after the device verified:
      // older than what was applied, so it changes nothing.
      final DVPurchaseResult late = await server.acceptNotification(
        DVContext(),
        DVStore.telegram,
        body: serviceMessage('successful_payment', invoice.receipt,
            chargeId: 'charge_9', amount: 250),
        headers: signedHeaders(),
      );
      expect(late.granted, isEmpty);

      final DVPurchaseResult refunded = await server.acceptNotification(
        DVContext(),
        DVStore.telegram,
        body: serviceMessage('refunded_payment', invoice.receipt,
            chargeId: 'charge_9', amount: 250, dateOffset: 600),
        headers: signedHeaders(),
      );
      expect(refunded.revoked, <Entitlement>{exports});
      expect(await server.entitled('alice', exports), isFalse);
      expect(changes.last.revokedAt, isNotNull,
          reason: 'a refund, not a lapse');
    });

    test('a paid consumable is credited once and its refund reversed',
        () async {
      final DVStoreInvoice invoice =
          await server.invoice(coins, customer: 'alice');
      bot.pay(invoice.receipt, chargeId: 'charge_c', amount: 50);

      final DVPurchaseResult first = await server.verifyPurchase(
          DVStore.telegram, invoice.receipt,
          customer: 'alice');
      final DVPurchaseResult again = await server.verifyPurchase(
          DVStore.telegram, invoice.receipt,
          customer: 'alice');
      expect(first.consumed, <String>{'coins_100'});
      expect(again.consumed, isEmpty);

      await server.acceptNotification(
        DVContext(),
        DVStore.telegram,
        body: serviceMessage('refunded_payment', invoice.receipt,
            chargeId: 'charge_c', dateOffset: 600),
        headers: signedHeaders(),
      );
      expect(changes.last.refunded, <String>{'coins_100'});
    });

    test('a receipt paid for by another account grants nothing', () async {
      final DVStoreInvoice invoice =
          await server.invoice(lifetime, customer: 'bob');
      bot.pay(invoice.receipt, chargeId: 'charge_b', amount: 250);
      await expectLater(
        server.verifyPurchase(DVStore.telegram, invoice.receipt,
            customer: 'alice'),
        throwsA(isA<DVPurchaseRefused>()),
      );
    });
  });
}
