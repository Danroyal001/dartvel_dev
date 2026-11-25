/// A plain class of the application's own (not a data model), passed to a
/// backend function: the client sends it with [toJson], and the server builds
/// it again with [OrderDraft.fromJson] before the function runs.
class OrderDraft {
  const OrderDraft({required this.table, this.items = const <String>[]});

  factory OrderDraft.fromJson(Map<String, Object?> json) => OrderDraft(
        table: json['table']! as String,
        items: <String>[...(json['items'] as List<Object?>? ?? const <Object?>[]).cast<String>()],
      );

  final String table;
  final List<String> items;

  Map<String, Object?> toJson() => <String, Object?>{'table': table, 'items': items};
}
