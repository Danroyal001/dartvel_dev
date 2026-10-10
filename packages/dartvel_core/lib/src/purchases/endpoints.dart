/// The `/_dartvel/purchases` endpoints the generated backend serves when a
/// project declares `dartvel.purchases`.
///
/// Two kinds, authenticated differently, and the difference is the point:
///
/// * The device's calls -- verify, entitlements, the account token, a
///   checkout, a Stars invoice, an offer signature -- run behind the
///   authentication stage and act for the signed-in session. Nothing in the
///   body says who the customer is: a body is the client's to write, and a
///   receipt granted to whoever it names is a receipt anybody can move.
/// * The stores' notifications carry no session. Each adapter checks its own
///   store's signature, and the answer is chosen for the store's retry rule:
///   200 for everything that was decided, including a replay and a test
///   message, 400 for a signature that does not verify, and 503 when the
///   store or the ledger could not be reached, so the store tries again.
library dartvel.purchases.endpoints;

import 'dart:convert';
import 'dart:typed_data';

import '../../dartvel.dart' show DVBillingCustomer;
import '../auth/session_authentication.dart';
import '../http/wintercg.dart';
import '../middleware/body_limit.dart';
import '../transaction/transaction.dart';
import 'device.dart';
import 'purchases.dart';

class DVPurchaseEndpoints {
  const DVPurchaseEndpoints._();

  /// The largest body a device call reads: a restore of many receipts.
  static const int deviceMaxBytes = 512 * 1024;

  /// The largest store notification read. Apple's signed payloads carry
  /// three certificate chains.
  static const int notificationMaxBytes = 256 * 1024;

  /// The most receipts one restore presents.
  static const int maxReceipts = 100;

  static const Map<String, Object?> _noStore = <String, Object?>{
    'cache-control': 'no-store',
  };

  static Response _json(Object? data, {int status = 200}) =>
      Response.json(data, status: status, headers: Headers(_noStore));

  static Response _error(int status, String reason, {String? code}) => _json(
      <String, Object?>{'reason': reason, if (code != null) 'code': code},
      status: status);

  static Response _notServed() => Response.text('Not Found', status: 404);

  /// Who the session is, as Billing names customers: the user object when
  /// the application's resolver made one that knows its billing id, the
  /// user id otherwise.
  static Object? _customer() {
    final DVSessionPrincipal? principal = DVSessionPrincipal.current;
    if (principal == null) return null;
    final Object? user = principal.user;
    return user is DVBillingCustomer ? user : principal.userId;
  }

  static Future<Response> _device(
    Request request,
    Future<Response> Function(DVPurchases server, Object customer,
            Map<String, Object?> body)
        run, {
    bool readsBody = true,
  }) async {
    final DVPurchases? server = DVPurchases.configuredOrNull;
    if (server == null || server.device != null) return _notServed();
    final Object? customer = _customer();
    if (customer == null) {
      return _error(401, 'a purchase is made for a signed-in account');
    }
    Map<String, Object?> body = const <String, Object?>{};
    if (readsBody) {
      if (dvDeclaredTooLarge(
          contentLength: request.headers.get('content-length'),
          limit: deviceMaxBytes)) {
        return _error(413, 'the body is larger than $deviceMaxBytes bytes');
      }
      final Uint8List? bytes =
          await dvReadCapped(request.body.stream, deviceMaxBytes);
      if (bytes == null) {
        return _error(413, 'the body is larger than $deviceMaxBytes bytes');
      }
      try {
        final Object? decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) return _error(400, 'the body is a JSON object');
        body = decoded.cast<String, Object?>();
      } on FormatException {
        return _error(400, 'the body is not JSON');
      }
    }
    try {
      return await run(server, customer, body);
    } on DVPurchaseRefused catch (refusal) {
      return _error(409, refusal.reason, code: refusal.code);
    } on DVStoreUnavailable catch (error) {
      return _error(503, error.message);
    } on ArgumentError catch (error) {
      return _error(400, '${error.message}');
    } on StateError catch (error) {
      // A store with no adapter, an adapter that cannot sign: the backend
      // is not set up to sell this way, which the device reports as a
      // missing purchase path rather than a crash.
      return _error(409, error.message, code: 'DV-PURCHASE-009');
    }
  }

  static DVPurchaseProduct _product(DVPurchases server, Map<String, Object?> body) {
    final Object? id = body['product'];
    final DVPurchaseProduct? product =
        id is String ? server.productById(id) : null;
    if (product == null) {
      throw ArgumentError('"product" names no declared product');
    }
    return product;
  }

  /// `POST verify`: `{store, receipts}`, answered with a [DVPurchaseVerdict].
  static Future<Response> verify(Request request) => _device(request,
          (DVPurchases server, Object customer, Map<String, Object?> body) async {
        final Object? storeName = body['store'];
        final DVStore? store = storeName is String
            ? DVStore.values.asNameMap()[storeName]
            : null;
        if (store == null) return _error(400, '"store" names no store');
        final Object? listed = body['receipts'];
        if (listed is! List ||
            listed.isEmpty ||
            listed.length > maxReceipts ||
            listed.any((Object? receipt) => receipt is! String)) {
          return _error(400,
              '"receipts" is a list of 1 to $maxReceipts receipt strings');
        }
        final List<DVPurchaseResult> results = await server.restore(
            customer: customer, store: store, receipts: listed.cast<String>());
        return _json(DVPurchaseVerdict(
                results: results, snapshots: await server.snapshots(customer))
            .toJson());
      });

  /// `GET entitlements`: what the session holds, as snapshots with an end.
  static Future<Response> entitlements(Request request) => _device(request,
      (DVPurchases server, Object customer, _) async => _json(<String, Object?>{
            'snapshots': <Object?>[
              for (final DVEntitlementSnapshot snapshot
                  in await server.snapshots(customer))
                snapshot.toJson(),
            ],
          }),
      readsBody: false);

  /// `GET account-token`: the token a purchase sheet carries for this
  /// session, so a receipt can be checked against who it was bought for.
  static Future<Response> accountToken(Request request) => _device(request,
      (DVPurchases server, Object customer, _) async => _json(
          <String, Object?>{'token': DVPurchases.accountTokenFor(customer)}),
      readsBody: false);

  /// `POST checkout`: `{product}`, answered with the gateway's `{url}`.
  static Future<Response> checkout(Request request) => _device(request,
          (DVPurchases server, Object customer, Map<String, Object?> body) async {
        final Uri url =
            await server.checkout(_product(server, body), customer: customer);
        return _json(<String, Object?>{'url': url.toString()});
      });

  /// `POST invoice`: `{product}`, answered with a Telegram Stars invoice.
  static Future<Response> invoice(Request request) => _device(request,
      (DVPurchases server, Object customer, Map<String, Object?> body) async =>
          _json((await server.invoice(_product(server, body),
                  customer: customer))
              .toJson()));

  /// `POST offer-signature`: `{product, offer}`, answered with the signature
  /// an App Store promotional offer is opened with.
  static Future<Response> offerSignature(Request request) => _device(request,
          (DVPurchases server, Object customer, Map<String, Object?> body) async {
        final Object? offer = body['offer'];
        if (offer is! String || offer.isEmpty) {
          return _error(400, '"offer" names the offer');
        }
        return _json((await server.signOffer(_product(server, body), offer,
                customer: customer))
            .toJson());
      });

  /// `POST notifications/<store>`: a store server notification.
  static Future<Response> notification(Request request, DVStore store) async {
    final DVPurchases? server = DVPurchases.configuredOrNull;
    if (server == null || server.device != null) return _notServed();
    if (dvDeclaredTooLarge(
        contentLength: request.headers.get('content-length'),
        limit: notificationMaxBytes)) {
      return _error(413, 'too large');
    }
    final Uint8List? bytes =
        await dvReadCapped(request.body.stream, notificationMaxBytes);
    if (bytes == null) return _error(413, 'too large');
    final String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      return _error(400, 'the body is not UTF-8');
    }
    try {
      final DVPurchaseResult result = await server.acceptNotification(
        DVContext(),
        store,
        body: body,
        headers: request.headers.singleValueMap,
      );
      // Only what the store needs: that it was taken. The result names no
      // customer.
      return _json(<String, Object?>{
        'handled': result.handled,
        'ignored': result.ignored,
        'replayed': result.replayed,
        'stale': result.stale,
      });
    } on DVPurchaseRefused catch (refusal) {
      return _error(400, refusal.reason, code: refusal.code);
    } on StateError {
      // No adapter for this store: nothing here can check its signature.
      return _notServed();
    } on Object {
      // The store, the ledger or an acknowledgement failed part-way. The
      // grant and the claim were rolled back; the store's retry applies it.
      return _error(503, 'not applied; retry');
    }
  }
}

/// Whether a project's `dartvel:` section declares purchases: a
/// `purchases:` map, or `purchases: true`.
///
/// One rule for every half that reads it: the generated backend serves the
/// endpoints, `dartvel build ios`/`macos` compiles the StoreKit shim and
/// `dartvel build android` adds Play Billing, all from this answer. Three
/// readings of the same key is how a build ships the sheet and no server to
/// verify what it sold.
bool dvPurchasesDeclared(Object? dartvelSection) {
  if (dartvelSection is! Map) return false;
  final Object? purchases = dartvelSection['purchases'];
  return purchases is Map || purchases == true;
}
