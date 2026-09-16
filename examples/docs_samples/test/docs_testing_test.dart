// docs:start testing-fakes
import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Declares the hosts in pubspec.yaml, which the app does at startup.
  setUp(configureDartvelHttp);
  tearDown(DVHttp.reset);

  test('the welcome email is sent', () async {
    final DVMemoryMailProvider mail = DV.Test.fakeMail();

    await DV.Notifications.mail.send(const DVMailMessage(
      from: DVMailAddress('hello@example.com'),
      to: <DVMailAddress>[DVMailAddress('ada@example.com')],
      subject: 'Welcome',
      text: 'Hi Ada',
    ));

    expect(mail.sent.single.subject, 'Welcome');
  });

  test('a payment is verified against a stubbed host', () async {
    final DVHttpFake http = DV.Test.fakeHttp(<String, DVHttpStub>{
      'paystack': DVHttpStub.json(<String, Object?>{'status': true}),
    });

    final Response response =
        await DV.Http.host('paystack').get('/transaction/verify/ref-1');

    expect(response.status, 200);
    expect(http.calls, hasLength(1));
  });

  test('jobs run in memory', () async {
    DV.Test.fakeQueue();
    DV.Jobs.register<String>((String name) async {});
    await DV.Jobs.dispatch<String>('hello');
    expect(await DV.Jobs.pending(), hasLength(1));
  });
}
// docs:end

