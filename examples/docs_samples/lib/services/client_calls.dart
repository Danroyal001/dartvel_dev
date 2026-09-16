import '../dartvel_client/dartvel_client.dart';

Future<void> callBackend() async {
  // docs:start backend-client
  // In a page or anywhere in the app.
  final Map<String, Object?> greeting = await hello(name: 'Ada');

  final Map<String, Object?> order = await updateOrder(id: '42', status: 'shipped');

  getTicks().listen((String tick) => DV.log(tick));
  // docs:end
  DV.log('$greeting $order');
}
