/// Telegram Stars as a store: the payment a Mini App takes for a digital good.
///
/// Telegram requires digital goods sold inside a Mini App to be paid in Stars
/// (`XTR`), and unlike the App Store and Play it keeps no product catalogue.
/// The bot writes every invoice itself through the Bot API, so the invoice's
/// payload is the only thing that ties a payment back to a product, a price
/// and an application account. This adapter makes that tie unforgeable and
/// checks it at each of the three places it comes back:
///
/// * **Pre-checkout.** Telegram asks the bot, within ten seconds, whether to
///   take the payment. A payload this bot did not sign, or an amount or
///   currency other than the one it signed, is declined there, before any
///   Stars move.
/// * **The receipt.** After paying, the device presents the payload. It is
///   believed only when the bot's own Star transactions, read from the Bot
///   API with `getStarTransactions`, show an incoming invoice payment
///   carrying it for the signed amount. A device saying "paid" is not
///   evidence; Telegram's ledger is.
/// * **The webhook.** Service messages for a successful or refunded payment
///   arrive at the bot's webhook, believed only with the secret Telegram was
///   given in `setWebhook(secret_token: ...)`.
///
/// The payload is binary, base64url encoded, and at most 128 bytes, which is
/// Telegram's limit for `invoice_payload`: a version, a random nonce so no
/// two invoices share a payload, the Stars amount, the account token as its
/// sixteen UUID bytes, the product id, and an HMAC-SHA256 over all of it,
/// truncated to sixteen bytes. The account token is the one-way
/// [DVPurchases.accountTokenFor] value, so the payload carries nobody's user
/// id through Telegram.
///
/// A price is not reported on the transaction: Stars have no minor unit and
/// the billing currency table does not list `XTR`, so a `DVMoney` in Stars
/// would read as a hundredth of what was paid. The amount is checked against
/// the signed payload instead.
library dartvel.purchases.telegram_stars;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'purchases.dart';

/// Sends one HTTP request and answers with its status and body. Injected so
/// the adapter is tested without Telegram.
typedef DVTelegramFetch = Future<(int status, String body)> Function(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
);

/// The invoice payload, once its signature has been checked.
class _SignedPayload {
  const _SignedPayload({
    required this.storeProductId,
    required this.amount,
    required this.appAccountToken,
  });

  final String storeProductId;
  final int amount;
  final String appAccountToken;
}

/// Telegram Stars, for [DVPurchases].
class DVTelegramStarsAdapter implements DVStoreAdapter, DVStoreInvoiceIssuer {
  DVTelegramStarsAdapter({
    required String botToken,
    required String webhookSecret,
    required String payloadKey,
    DVTelegramFetch? fetch,
    DateTime Function()? clock,
    Random? random,
    this.pageSize = 100,
    this.maxPagesPerLookup = 200,
  })  : _botToken = botToken,
        _webhookSecret = webhookSecret,
        _payloadKey = utf8.encode(payloadKey),
        _fetch = fetch ?? _noNetwork,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure() {
    if (botToken.isEmpty) {
      throw ArgumentError.value(botToken, 'botToken', 'is required');
    }
    if (webhookSecret.isEmpty) {
      // An empty secret matches an update that carries no header at all,
      // which is every update anybody can post to the endpoint.
      throw ArgumentError.value(webhookSecret, 'webhookSecret',
          'an empty secret accepts an update from anybody');
    }
    if (payloadKey.isEmpty) {
      throw ArgumentError.value(payloadKey, 'payloadKey',
          'an empty key signs every payload the same way');
    }
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(
          pageSize, 'pageSize', 'getStarTransactions takes 1 to 100');
    }
  }

  /// The header Telegram puts the webhook's secret token in.
  static const String secretHeader = 'X-Telegram-Bot-Api-Secret-Token';

  /// The longest product id that fits Telegram's 128-byte payload once it
  /// is signed and encoded.
  static const int maxProductIdBytes = 50;

  static const int _version = 1;
  static const int _nonceBytes = 8;
  static const int _macBytes = 16;

  /// Transactions asked for per `getStarTransactions` call.
  final int pageSize;

  /// The most pages one receipt lookup reads before giving up.
  ///
  /// Telegram lists a bot's Star transactions oldest first and says nothing
  /// of how many there are, so finding a recent one means reading forward.
  /// The adapter remembers how far it has read and starts the next lookup a
  /// few pages back from there, so only the first lookup after a restart
  /// reads from the start; this bounds that one.
  final int maxPagesPerLookup;

  final String _botToken;
  final String _webhookSecret;
  final List<int> _payloadKey;
  final DVTelegramFetch _fetch;
  final DateTime Function() _clock;
  final Random _random;

  /// Where the next lookup starts reading, kept a few pages behind the end
  /// of what has been read.
  int _readFrom = 0;

  static Future<(int, String)> _noNetwork(
          String method, Uri url, Map<String, String> headers, String? body) =>
      throw const DVStoreUnavailable(
          'No HTTP transport was configured for the Telegram Bot API.');

  @override
  DVStore get store => DVStore.telegram;

  /// Telegram has nothing to acknowledge: a payment is final once made, and
  /// the pre-checkout answer is given before it is.
  @override
  Duration? get acknowledgementWindow => null;

  @override
  Future<void> acknowledge({
    required String originalTransactionId,
    required String transactionId,
    required String storeProductId,
  }) async {}

  // -- invoices --------------------------------------------------------------

  @override
  Future<DVStoreInvoice> createInvoice({
    required String storeProductId,
    required String title,
    required int amount,
    required String appAccountToken,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'a price in Stars is positive');
    }
    final String payload = _sign(
      storeProductId: storeProductId,
      amount: amount,
      appAccountToken: appAccountToken,
    );
    // Telegram limits a title to 32 characters and a description to 255; a
    // longer one is refused by the Bot API and nothing is sold.
    final String shortTitle = _clip(title, 32);
    final Object? link = await _call('createInvoiceLink', <String, Object?>{
      'title': shortTitle,
      'description': _clip(title, 255),
      'payload': payload,
      // An empty provider token is how the Bot API is told the invoice is
      // in Stars.
      'provider_token': '',
      'currency': 'XTR',
      'prices': <Object?>[
        <String, Object?>{'label': shortTitle, 'amount': amount},
      ],
    });
    if (link is! String) {
      throw const DVStoreUnavailable(
          'createInvoiceLink answered without a link');
    }
    return DVStoreInvoice(url: Uri.parse(link), receipt: payload);
  }

  static String _clip(String text, int length) =>
      text.length <= length ? text : text.substring(0, length);

  // -- receipts --------------------------------------------------------------

  @override
  Future<DVStoreTransaction> verifyReceipt(String receipt) async {
    final _SignedPayload? payload = _read(receipt);
    if (payload == null) {
      // Checked before Telegram is asked: a payload this bot did not sign
      // cannot be a payment for anything it sells.
      throw DVStoreRefusal(store, 'the invoice payload is not one this bot signed');
    }

    final List<Map<String, Object?>> transactions = await _recentTransactions();
    Map<String, Object?>? payment;
    for (final Map<String, Object?> transaction in transactions) {
      final Map<String, Object?>? source = _map(transaction['source']);
      if (source == null || source['type'] != 'user') continue;
      final Object? kind = source['transaction_type'];
      if (kind != null && kind != 'invoice_payment') continue;
      if (source['invoice_payload'] == receipt) payment = transaction;
    }
    if (payment == null) {
      throw DVStoreRefusal(store, 'no payment for this invoice');
    }
    if (payment['amount'] != payload.amount) {
      throw DVStoreRefusal(
        store,
        'the payment was ${payment['amount']} Stars and the invoice asked for '
        '${payload.amount}',
      );
    }
    final String chargeId = '${payment['id']}';

    // A refund is an outgoing transaction to the user that keeps the id of
    // the payment it returns.
    DateTime? refundedAt;
    for (final Map<String, Object?> transaction in transactions) {
      if ('${transaction['id']}' != chargeId) continue;
      final Map<String, Object?>? receiver = _map(transaction['receiver']);
      if (receiver != null && receiver['type'] == 'user') {
        refundedAt = _unixTime(transaction['date']);
      }
    }

    return DVStoreTransaction(
      store: store,
      originalTransactionId: chargeId,
      transactionId: chargeId,
      storeProductId: payload.storeProductId,
      purchasedAt: _unixTime(payment['date']) ?? _clock().toUtc(),
      signedAt: _clock().toUtc(),
      revokedAt: refundedAt,
      appAccountToken: payload.appAccountToken,
      acknowledged: true,
    );
  }

  /// The bot's Star transactions from a little before where the last lookup
  /// stopped to the end of the list.
  Future<List<Map<String, Object?>>> _recentTransactions() async {
    final List<Map<String, Object?>> read = <Map<String, Object?>>[];
    int offset = _readFrom;
    for (int page = 0; page < maxPagesPerLookup; page++) {
      final Object? result = await _call('getStarTransactions',
          <String, Object?>{'offset': offset, 'limit': pageSize});
      final Map<String, Object?>? answer = _map(result);
      final Object? list = answer?['transactions'];
      if (list is! List) {
        throw const DVStoreUnavailable(
            'getStarTransactions answered without transactions');
      }
      for (final Object? item in list) {
        final Map<String, Object?>? transaction = _map(item);
        if (transaction != null) read.add(transaction);
      }
      offset += list.length;
      if (list.length < pageSize) break;
    }
    // Five pages back: a receipt is presented minutes after it is paid, and
    // a refund lands within that window of the payment often enough that
    // reading both is the common case.
    _readFrom = max(0, offset - pageSize * 5);
    return read;
  }

  // -- the webhook -----------------------------------------------------------

  @override
  Future<DVStoreNotification> verifyNotification(
    String body,
    Map<String, String> headers,
  ) async {
    String? secret;
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.toLowerCase() == secretHeader.toLowerCase()) {
        secret = header.value;
      }
    }
    if (secret == null) {
      throw DVStoreRefusal(store, 'the update carries no secret token');
    }
    if (!_constantTimeEquals(utf8.encode(secret), utf8.encode(_webhookSecret))) {
      throw DVStoreRefusal(store, 'the update\'s secret token does not match');
    }

    final Map<String, Object?>? update;
    try {
      update = _map(jsonDecode(body));
    } on FormatException {
      throw DVStoreRefusal(store, 'the update is not JSON');
    }
    if (update == null) throw DVStoreRefusal(store, 'the update is not an object');

    final Map<String, Object?>? query = _map(update['pre_checkout_query']);
    if (query != null) {
      await _answerPreCheckout(query);
      throw const DVStoreNothingToApply(
          'a pre-checkout query, answered; the payment arrives separately');
    }

    final Map<String, Object?>? message = _map(update['message']);
    final Map<String, Object?>? paid = _map(message?['successful_payment']);
    final Map<String, Object?>? refunded = _map(message?['refunded_payment']);
    if (paid == null && refunded == null) {
      throw const DVStoreNothingToApply('a Telegram update that is not a payment');
    }
    final Map<String, Object?> payment = paid ?? refunded!;
    if (payment['currency'] != 'XTR') {
      throw const DVStoreNothingToApply('a payment in a currency other than Stars');
    }
    final String receipt = '${payment['invoice_payload'] ?? ''}';
    final _SignedPayload? payload = _read(receipt);
    if (payload == null) {
      throw DVStoreRefusal(store, 'the payment names an invoice this bot did not sign');
    }
    if (paid != null && paid['total_amount'] != payload.amount) {
      throw DVStoreRefusal(store, 'the payment amount does not match its invoice');
    }
    final String chargeId = '${payment['telegram_payment_charge_id'] ?? ''}';
    if (chargeId.isEmpty) {
      throw DVStoreRefusal(store, 'the payment carries no charge id');
    }
    final DateTime sentAt = _unixTime(message!['date']) ?? _clock().toUtc();
    final DateTime now = _clock().toUtc();

    // The payment message is dated when it was paid, so one retried after a
    // refund is older than the refund and stale. The refund is dated no
    // earlier than now, so it is never stale against a receipt verified a
    // moment ago on a clock a little ahead of Telegram's.
    final DateTime signedAt =
        refunded != null && now.isAfter(sentAt) ? now : sentAt;
    return DVStoreNotification(
      notificationId: 'telegram:$chargeId:${paid != null ? 'paid' : 'refunded'}',
      type: paid != null ? 'successful_payment' : 'refunded_payment',
      signedAt: signedAt,
      transaction: DVStoreTransaction(
        store: store,
        originalTransactionId: chargeId,
        transactionId: chargeId,
        storeProductId: payload.storeProductId,
        purchasedAt: sentAt,
        signedAt: signedAt,
        revokedAt: refunded != null ? signedAt : null,
        appAccountToken: payload.appAccountToken,
        acknowledged: true,
      ),
    );
  }

  /// Approves a checkout for an invoice this bot signed, at the signed
  /// amount in Stars, and declines anything else.
  Future<void> _answerPreCheckout(Map<String, Object?> query) async {
    final _SignedPayload? payload = _read('${query['invoice_payload'] ?? ''}');
    final String? problem = payload == null
        ? 'This invoice was not issued by this application.'
        : query['currency'] != 'XTR'
            ? 'This invoice is payable only in Stars.'
            : query['total_amount'] != payload.amount
                ? 'This invoice\'s amount has changed. Please try again.'
                : null;
    await _call('answerPreCheckoutQuery', <String, Object?>{
      'pre_checkout_query_id': '${query['id']}',
      'ok': problem == null,
      if (problem != null) 'error_message': problem,
    });
  }

  // -- the payload -----------------------------------------------------------

  String _sign({
    required String storeProductId,
    required int amount,
    required String appAccountToken,
  }) {
    final List<int> product = utf8.encode(storeProductId);
    if (product.isEmpty || product.length > maxProductIdBytes) {
      throw ArgumentError.value(storeProductId, 'storeProductId',
          'must be 1 to $maxProductIdBytes bytes to fit a Telegram payload');
    }
    if (amount > 0xffffffff) {
      throw ArgumentError.value(amount, 'amount', 'is too large for an invoice');
    }
    final List<int>? token = _uuidBytes(appAccountToken);
    if (token == null) {
      throw ArgumentError.value(appAccountToken, 'appAccountToken',
          'is DVPurchases.accountTokenFor(customer), a UUID');
    }
    final BytesBuilder bytes = BytesBuilder()
      ..addByte(_version)
      ..add(<int>[for (int i = 0; i < _nonceBytes; i++) _random.nextInt(256)])
      ..add((ByteData(4)..setUint32(0, amount)).buffer.asUint8List())
      ..add(token)
      ..addByte(product.length)
      ..add(product);
    final Uint8List body = bytes.takeBytes();
    return base64Url
        .encode(<int>[...body, ..._mac(body)])
        .replaceAll('=', '');
  }

  /// [payload]'s contents when this bot signed it, or null.
  _SignedPayload? _read(String payload) {
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(payload));
    } on FormatException {
      return null;
    }
    const int fixed = 1 + _nonceBytes + 4 + 16 + 1;
    if (bytes.length < fixed + 1 + _macBytes) return null;
    final Uint8List body = bytes.sublist(0, bytes.length - _macBytes);
    final Uint8List mac = bytes.sublist(bytes.length - _macBytes);
    if (!_constantTimeEquals(mac, _mac(body))) return null;
    if (body[0] != _version) return null;
    final int productLength = body[fixed - 1];
    if (body.length != fixed + productLength) return null;
    final int amount =
        ByteData.sublistView(body, 1 + _nonceBytes, 1 + _nonceBytes + 4)
            .getUint32(0);
    final String token = _uuidString(
        body.sublist(1 + _nonceBytes + 4, 1 + _nonceBytes + 4 + 16));
    final String product;
    try {
      product = utf8.decode(body.sublist(fixed));
    } on FormatException {
      return null;
    }
    return _SignedPayload(
        storeProductId: product, amount: amount, appAccountToken: token);
  }

  List<int> _mac(List<int> body) => Hmac(sha256, _payloadKey)
      .convert(<int>[...utf8.encode('dartvel.telegram.invoice'), ...body])
      .bytes
      .sublist(0, _macBytes);

  static List<int>? _uuidBytes(String uuid) {
    final String hex = uuid.replaceAll('-', '').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) return null;
    return <int>[
      for (int i = 0; i < 32; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)
    ];
  }

  static String _uuidString(List<int> bytes) {
    final String hex =
        bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // -- the Bot API -----------------------------------------------------------

  /// Calls Bot API [method] and answers with its `result`.
  ///
  /// Every failure is an outage rather than a verdict: a wrong token or a
  /// Telegram error says nothing about whether somebody paid, and refusing a
  /// real payment over it would lose the purchase.
  Future<Object?> _call(String method, Map<String, Object?> parameters) async {
    final Uri url = Uri.https('api.telegram.org', '/bot$_botToken/$method');
    final (int status, String text) = await _fetch(
      'POST',
      url,
      const <String, String>{'content-type': 'application/json'},
      jsonEncode(parameters),
    );
    Map<String, Object?>? answer;
    try {
      answer = _map(jsonDecode(text));
    } on FormatException {
      answer = null;
    }
    if (status != 200 || answer == null || answer['ok'] != true) {
      // The description is Telegram's; the token is in the URL, never here.
      throw DVStoreUnavailable(
          'the Bot API answered $method with $status'
          '${answer?['description'] != null ? ': ${answer!['description']}' : ''}');
    }
    return answer['result'];
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static DateTime? _unixTime(Object? seconds) => seconds is int
      ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
      : null;

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
