import '../dartvel_client/dartvel_client.dart';

// docs:start start-configure
@DVBoot()
void _configure(DVBoot boot) {
  DV.Auth.configure(DVLocalAuthProvider());
  DV.Notifications.mail.useProvider(DVMemoryMailProvider());
}
// docs:end
