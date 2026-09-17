// What is in the bag, held as one global object.
//
// `DV.global<Cart>` is the registry every screen reads: the tab badge, the
// cart page and a coffee's "Add" button all see one cart, and replacing it
// rebuilds whatever read it. A cart is a value, so each change is a new one.
import '../dartvel_client/dartvel_client.dart';

/// Orders at or over this ship free.
const int freeShippingFromCents = 3000;
const int shippingCents = 450;

class Cart {
  const Cart([this.lines = const <String, int>{}]);

  /// Quantity by coffee slug, in the order they were added.
  final Map<String, int> lines;

  bool get isEmpty => lines.isEmpty;

  /// How many bags.
  int get count => lines.values.fold(0, (int sum, int n) => sum + n);

  int quantityOf(String slug) => lines[slug] ?? 0;

  Cart add(String slug, [int quantity = 1]) =>
      setQuantity(slug, quantityOf(slug) + quantity);

  /// Zero or less takes the coffee out.
  Cart setQuantity(String slug, int quantity) {
    final Map<String, int> next = Map<String, int>.of(lines);
    if (quantity <= 0) {
      next.remove(slug);
    } else {
      next[slug] = quantity;
    }
    return Cart(Map<String, int>.unmodifiable(next));
  }

  /// The coffees in the cart, with their quantities, in cart order. A slug
  /// the catalogue no longer has is left out rather than priced at nothing.
  List<CartLine> linesIn(Iterable<Product> catalog) {
    final Map<String, Product> bySlug = <String, Product>{
      for (final Product p in catalog) p.slug: p,
    };
    return <CartLine>[
      for (final MapEntry<String, int> line in lines.entries)
        if (bySlug[line.key] != null) CartLine(bySlug[line.key]!, line.value),
    ];
  }

  int subtotalCents(Iterable<Product> catalog) =>
      linesIn(catalog).fold(0, (int sum, CartLine l) => sum + l.totalCents);

  int shippingCentsFor(Iterable<Product> catalog) {
    final int subtotal = subtotalCents(catalog);
    return subtotal == 0 || subtotal >= freeShippingFromCents
        ? 0
        : shippingCents;
  }

  int totalCents(Iterable<Product> catalog) =>
      subtotalCents(catalog) + shippingCentsFor(catalog);

  /// "2 × Huila, 1 × Nyeri", as the receipt lists it.
  String summary(Iterable<Product> catalog) => linesIn(
    catalog,
  ).map((CartLine l) => '${l.quantity} × ${l.coffee.name}').join(', ');
}

class CartLine {
  const CartLine(this.coffee, this.quantity);

  final Product coffee;
  final int quantity;

  int get totalCents => coffee.priceCents * quantity;
}

/// The cart everyone reads.
Cart get currentCart => DV.global<Cart>();

/// Replaces the cart, rebuilding every widget that read it.
void updateCart(Cart Function(Cart cart) change) {
  DV.global<Cart>(change(currentCart));
}
