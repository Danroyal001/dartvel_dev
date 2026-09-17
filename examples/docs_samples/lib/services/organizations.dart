import '../dartvel_client/dartvel_client.dart';

// docs:start orgs-setup
final DVOrganizations organizations = DVOrganizations(
  database: DV.Database.adapter,
  seats: const DVSeats.activeWithin(Duration(days: 30)), // who counts as a seat
  seatLimit: (String tenant) => 25,
);
// docs:end

Future<void> organizationFlow() async {
  // docs:start orgs-create
  await organizations.ensureSchema();

  // One organization per tenant. The creator is its owner.
  final DVOrganization acme = await organizations.create(
    name: 'Acme',
    tenant: 'acme',
    ownerId: 'user-ada',
    ownerEmail: 'ada@acme.example',
  );
  // docs:end

  // docs:start orgs-invite
  final DVIssuedInvitation invitation = await organizations.invite(
    acme.id,
    'bob@acme.example',
    role: DVOrgRole.member,
    invitedBy: 'user-ada',
    acceptUrl: Uri.parse('https://app.example.com/invitations/accept'),
  );
  await DV.Notifications.mail.send(DVMailMessage(
    from: const DVMailAddress('team@app.example.com'),
    to: const <DVMailAddress>[DVMailAddress('bob@acme.example')],
    subject: 'Join Acme',
    text: 'Accept here: ${invitation.link.url}',
  ));

  // On the accept page, once Bob has signed in with that address:
  final DVMembership bob = await organizations.accept(
    invitation.link.token,
    userId: 'user-bob',
    email: 'bob@acme.example',
  );
  // docs:end

  // docs:start orgs-roles
  if (await organizations.hasRole(acme.id, 'user-bob', DVOrgRole.admin)) {
    DV.log('Bob can manage members');
  }
  await organizations.changeRole(acme.id, 'user-bob', DVOrgRole.admin, actor: 'user-ada');
  await organizations.transferOwnership(acme.id, from: 'user-ada', to: 'user-bob', actor: 'user-ada');
  final int used = await organizations.seatsUsed(acme.id);
  // docs:end
  DV.log('${bob.role.name} $used');
}
