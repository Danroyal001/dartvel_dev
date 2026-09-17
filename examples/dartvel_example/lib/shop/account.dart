// Who is signed in, as a global the tabs and the guard both read.
import '../dartvel_client/dartvel_client.dart';

/// The account the demo comes with. The local auth provider really hashes
/// and checks the password; it simply keeps everything on this device.
const String demoEmail = 'maya@oakline.coffee';
const String demoPassword = 'flat-white-42';
const String demoName = 'Maya Okafor';

class Account {
  const Account([this.user]);

  final DVAuthUser? user;

  bool get signedIn => user != null;

  String get email => user?.email ?? '';

  String get name => (user?.metadata['name'] as String?) ?? email;

  String get firstName => name.split(' ').first;
}

Account get currentAccount => DV.global<Account>();

/// Registers the demo account with [provider] without leaving it signed in.
Future<void> registerDemoAccount(DVLocalAuthProvider provider) async {
  if (provider.accounts.contains(demoEmail)) return;
  await provider.signUp(
    email: demoEmail,
    password: demoPassword,
    metadata: const <String, Object?>{'name': demoName},
  );
  await provider.signOut();
}

/// Signs in through DV.Auth and publishes the account. Throws what the
/// provider throws for a wrong password.
Future<Account> signIn({
  required String email,
  required String password,
}) async {
  await DV.Auth.signInWithEmailAndPassword(email: email, password: password);
  final Account account = Account(DV.Auth.currentUser);
  DV.global<Account>(account);
  // Durable work rather than an await on the tap: a welcome mail that fails
  // is retried by the queue, and the person is already in.
  await SendWelcomeEmail(userId: account.user!.id).dispatch();
  await DV.Queues.work(queue: SendWelcomeEmail.queue);
  return account;
}

Future<void> signOut() async {
  await DV.Auth.signOut();
  DV.global<Account>(const Account());
}
