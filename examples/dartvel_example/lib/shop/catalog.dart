// The coffees on the shelf, and the local store they are kept in.
import '../backend/catalog_rows.dart';
import '../dartvel_client/dartvel_client.dart';

/// What the roastery sells this season: the same rows the server seeds its
/// database with. Written once into the store the first time the app opens;
/// after that the store is the truth, and the Manage screen edits it.
final List<Product> seedCatalog = <Product>[
  for (final Map<String, Object?> row in catalogRows) ProductParser.fromJson(row),
];

/// Opens the store the shop reads: the tables its models need, and the
/// catalogue on first run. Safe to call more than once.
Future<void> openShopStore() => _opening ??= _open();

Future<void>? _opening;

/// Forgets that the store was opened, for a test that gives the shop a fresh
/// database.
void resetShopStore() => _opening = null;

Future<void> _open() async {
  await DV.Database.execute(seedCatalog.first.createTableSql);
  await DV.Database.execute(
    const Order(
      id: '',
      email: '',
      summary: '',
      itemCount: 0,
      totalCents: 0,
      status: '',
      placedAt: 0,
    ).createTableSql,
  );
  if ((await Product.all()).isEmpty) {
    for (final Product coffee in seedCatalog) {
      await coffee.save();
    }
  }
}

/// "$17.00", in the project's native currency.
String formatPrice(int cents) {
  final String whole = (cents ~/ 100).toString();
  final String part = (cents % 100).toString().padLeft(2, '0');
  return '\$$whole.$part';
}
