# dartvel_woocommerce

WooCommerce for [Dartvel](https://dartvel.dev) applications: the store's
catalogue and orders through a typed REST API v3 client, and checkout
through the store's own payment gateways, confirmed by the store.

A first-party Dartvel module. It lives in
[`modules/`](https://github.com/Danroyal001/dartvel_dev/tree/main/modules) of
the Dartvel repository and is released with the framework.

The application is the storefront. WooCommerce is the back office: it holds
the products and prices, makes the orders, and takes the money with
whichever gateways it has configured (Paystack, Flutterwave, Stripe, bank
transfer). The application never handles a card or a gateway key.

## Add it

```bash
dartvel add woocommerce
```

That writes the dependency and the mount. Give it the store's address:

```yaml
dartvel:
  modules:
    woocommerce:
      package: dartvel_woocommerce
      backendPolicy: public
      config:
        storeUrl: https://shop.example.com
```

and the store's keys in the **server's** environment:

```
WOOCOMMERCE_CONSUMER_KEY=ck_...
WOOCOMMERCE_CONSUMER_SECRET=cs_...
WOOCOMMERCE_WEBHOOK_SECRET=...
```

The keys are never settings. A mount's `config:` is compiled into the
client, so `consumerSecret:` there is refused by name. They exist only in
the backend process: a client asks your backend, and your backend asks the
store.

### In the store

1. **A REST API key.** WooCommerce > Settings > Advanced > REST API > Add
   key, with Read/Write permission. That gives the consumer key and secret.
2. **A webhook.** WooCommerce > Settings > Advanced > Webhooks > Add
   webhook: topic *Order updated*, delivery URL
   `https://<your app>/_dartvel/woocommerce/webhook`, and a secret of your
   own, which is `WOOCOMMERCE_WEBHOOK_SECRET`.
3. **A payment gateway**, enabled and working on the store's own checkout.
4. The store must be on HTTPS and reachable by the buyer's browser: the
   buyer pays on the store's own page.

## Checkout

```dart
// 1. Make the order and send the buyer to pay it.
final checkout = await DV.Modules.woocommerce.startCheckout(
  cart: [WooCartLine(productId: 12, quantity: 1)],
  billing: WooAddress(firstName: 'Ada', email: 'ada@example.com'),
  idempotencyKey: cart.id,
);
DV.Platform.openUrl(checkout.paymentUrl);

// 2. Wait for the store to say it is paid.
await for (final order in DV.Modules.woocommerce
    .watchOrder(checkout.orderId, checkout.orderKey)) {
  if (order.paid) showThanks();
  if (order.finished && !order.paid) showPaymentFailed(order.status);
}
```

- **The cart is products and quantities.** The store prices the order from
  its own catalogue, so a buyer cannot name their own price.
- **The order is made pending and unpaid**, and `paymentUrl` is the store's
  own page for paying it (`payment_url` in the REST API, the *order-pay*
  page). Whichever gateways the store has configured are offered there.
- **One key, one order.** WooCommerce's API has no idempotency key, so the
  module keeps yours on the order (`_dv_idempotency_key`). A checkout
  started twice with the same key, by a double tap or a retry after a
  timeout, gets the first one's order: from the server's memory, and after
  a restart by looking through the store's orders of the last 24 hours.
  Left out, each call is a new order.
- **Paid means the store says so**, never that the buyer came back. The
  store's webhook says it (`X-WC-Webhook-Signature`, the base64
  HMAC-SHA256 of the body with your secret, is checked on every delivery;
  an unsigned or wrongly signed one is refused, and so is every delivery
  when no secret is configured). And `watchOrder` asks the store every few
  seconds, which confirms the payment even when the webhook never arrives.
  An order is paid in the statuses WooCommerce itself counts as paid:
  `processing` and `completed`.

### When an order is paid

On the backend, once per order:

```dart
DV.Modules.woocommerce.onOrderPaid((order) async {
  await grantAccess(order.email, order.orderId);
});
```

Register it from a `@DVBoot` function that names the server entry. It is
called when the webhook reports the order paid or when the order is found
paid on being asked about, whichever comes first, and not again: the order
is marked in the store (`_dv_purchase_reported`), so a second server or a
restart does not repeat it.

### Analytics

Mount `dartvel_google_analytics` or `dartvel_meta_pixel` beside this module
and a purchase is reported to them when the store confirms it, with nothing
to write:

- At checkout, each analytics module adds what it knows about the buyer
  (Google's client and session ids, Meta's `_fbp`/`_fbc`), **only if the
  buyer's consent allows that module**. It is kept on the order
  (`_dv_analytics`), with the address and user agent the checkout came from.
- When the order is paid the module publishes `commerce.purchase`. Google
  Analytics sends `purchase` through the Measurement Protocol; Meta gets
  `Purchase` through the Conversions API and, when the buyer's browser sees
  the order paid, through the pixel with the same event id.
- A buyer who had not consented has no context on their order, and no
  purchase is reported for them.

The payload of `commerce.purchase` is plain data, for a module of your own
to subscribe to with `DV.Modules.subscribe('commerce.purchase', ...)`:
`transaction_id`, `order_id`, `currency`, `total` (what was paid), `value`
(the items' total after discounts, without tax or shipping), `tax`,
`shipping`, `coupon`, `paid_at`, `payment_method`, `items` (`item_id`,
`item_name`, `price`, `quantity`), `customer` and `context`.

## The catalogue

```dart
final products = await DV.Modules.woocommerce.products(search: 'audit');
final product = await DV.Modules.woocommerce.product(12);
Text('${product.name}: ${product.price}');
```

Only published products, from a client or the backend. Prices are strings,
as the store gives them (`"45000.00"`), with `priceAmount` beside each for
arithmetic.

## The typed API (backend only)

```dart
final api = DV.Modules.woocommerce.api;
final order = await api.order(981);
final customers = await api.customers(email: 'ada@example.com');
final coupon = await api.couponByCode('LAUNCH');
await api.updateOrder(981, status: 'completed');
final currency = await api.currency();
```

`products`, `product`, `variations`, `createOrder`, `order`, `orders`,
`updateOrder`, `customers`, `customer`, `createCustomer`, `coupons`,
`couponByCode`, `currency`. A refusal is a `WooCommerceException` with the
store's own `code` and `message`; it never holds the keys. On a device or in
a browser `api` throws `DVModuleUnavailable`.

## What a client may do

A client's calls reach your backend at
`<apiBasePath>/_dv/modules/woocommerce/<operation>`, which is why the mount
names a `backendPolicy`. `public` suits a shop with guest checkout; name a
policy instead to require a signed-in buyer. The route accepts what a
shopper may do and nothing else:

| Operation | Accepts |
|---|---|
| `products`, `product` | Search, category, ids, paging. Published products only. |
| `startCheckout` | Up to 100 lines of product id and quantity, a billing address, up to 10 coupon codes, a note, the key. Not a price, not a customer id. |
| `orderStatus` | An order id **and** its key. A wrong key and a missing order are the same answer. |

## Settings

Under `dartvel.modules.woocommerce.config`, or as `WooCommerceConfig` passed
to `DV.Modules.woocommerce.configure(...)`:

| Setting | Default | |
|---|---|---|
| `storeUrl` | none | The store's address, HTTPS. The server also reads `WOOCOMMERCE_URL`. |
| `consumerKeyName` | `WOOCOMMERCE_CONSUMER_KEY` | The name of the environment variable holding the consumer key. |
| `consumerSecretName` | `WOOCOMMERCE_CONSUMER_SECRET` | The same for the consumer secret. |
| `webhookSecretName` | `WOOCOMMERCE_WEBHOOK_SECRET` | The same for the webhook's secret. |
| `paidStatuses` | `[processing, completed]` | The order statuses that mean the money has arrived. |
| `pollSeconds` | `5` | How often a watched order is asked about. |
| `pollTimeoutMinutes` | `20` | How long a watched order is asked about. |

## Not covered

- Refunds, shipping rates and tax settings: do those in the store.
- Subscriptions and other WooCommerce extensions' own endpoints.
- A cart kept in the store: the cart is the application's until checkout.
