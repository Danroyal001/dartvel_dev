// The names an imported document turns into.
//
// Shared by every importer, so a mistake here is a mistake in all of them at
// once -- which is the point of sharing it, and the reason it is worth
// testing on its own rather than through whichever importer noticed.
import 'package:dartvel_cli/src/import/import_names.dart';
import 'package:test/test.dart';

void main() {
  group('class names', () {
    test('separators of any kind become word breaks', () {
      expect(dvImportClassName('order-line'), 'OrderLine');
      expect(dvImportClassName('order_line'), 'OrderLine');
      expect(dvImportClassName('order line'), 'OrderLine');
      expect(dvImportClassName('order.line'), 'OrderLine');
    });

    test('something with no letters at all still produces a name', () {
      expect(dvImportClassName('---'), 'Model');
    });
  });

  group('file names', () {
    test('a word break becomes an underscore', () {
      expect(dvImportFileName('OrderLine'), 'order_line');
      expect(dvImportFileName('order-line'), 'order_line');
    });

    test('an acronym stays one word', () {
      // "Catalog API" came out as catalog_a_p_i, which is the sort of name
      // nobody would have typed and everybody would have to live with. Real
      // documents are full of these: API, HTTP, ID, URL.
      expect(dvImportFileName('Catalog API'), 'catalog_api');
      expect(dvImportFileName('APIKey'), 'api_key');
      expect(dvImportFileName('HTTPResponse'), 'http_response');
      expect(dvImportFileName('UserID'), 'user_id');
    });

    test('a trailing acronym is not split from itself', () {
      expect(dvImportFileName('ProductSKU'), 'product_sku');
    });
  });

  group('field names', () {
    test('the first letter is lower and the rest keep their case', () {
      expect(dvImportFieldName('line-total'), 'lineTotal');
      expect(dvImportFieldName('id'), 'id');
    });
  });
}
