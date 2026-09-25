import '../dartvel_client/dartvel_client.dart';

void configureServices() {
  // docs:start start-configure
  DV.Auth.configure(DVLocalAuthProvider());
  DV.Notifications.mail.useProvider(DVMemoryMailProvider());
  // docs:end
}
