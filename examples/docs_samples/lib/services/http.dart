import '../dartvel_client/dartvel_client.dart';

Future<void> verifyPayment(String reference) async {
  // docs:start http-host
  final Response response =
      await DV.Http.host('paystack').get('/transaction/verify/$reference');
  final Object? data = await response.body!.jsonDecode();
  // docs:end
  DV.log('${response.status} $data');
}

Future<void> fetchAny(String url) async {
  // docs:start http-undeclared
  try {
    // A URL known only at run time is checked when it runs.
    await DV.Http.get(url);
  } on DVHttpUndeclaredHostException catch (error) {
    // DV-HTTP-001: no declared host covers this URL, and nothing was sent.
    DV.log(error.toString());
  }
  // docs:end
}
