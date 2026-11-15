import 'dart:convert';

void main() {
  final order = <String, Object?>{
    'id': 1042,
    'customer': 'Ada "the countess" Lovelace',
    'paid': true,
    'coupon': null,
    'lines': [
      {'sku': 'tea-01', 'qty': 2, 'price': 350},
      {'sku': 'mug-07', 'qty': 1, 'price': 1200},
    ],
    'tags': ['gift', 'express', 'tab\there', 'line\nbreak'],
  };

  final encoded = jsonEncode(order);
  print(encoded);

  final decoded = jsonDecode(encoded) as Map<String, dynamic>;
  print(decoded['customer']);
  final lines = decoded['lines'] as List;
  var total = 0;
  for (final line in lines) {
    final map = line as Map;
    final qty = map['qty'] as int;
    final price = map['price'] as int;
    total += qty * price;
  }
  print('total: $total');
  print('lines: ${lines.length}, tags: ${decoded['tags']}');
  print('paid is bool: ${decoded['paid'] is bool}, coupon: ${decoded['coupon']}');

  final again = jsonEncode(decoded);
  print(again == encoded ? 'round trip identical' : 'round trip DIFFERENT');

  final nested = jsonDecode(' { "a" : [ 1 , -2 , [ ] , { } ] , "b" : "\\u0041\\/\\\\" } ');
  print(nested);
  print(jsonEncode(nested));
}
