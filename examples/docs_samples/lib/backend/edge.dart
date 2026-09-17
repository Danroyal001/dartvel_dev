import 'package:dartvel_core/dartvel.dart';

// docs:start edge-waf
final DVWaf adminFirewall = DVWaf(
  const <DVWafRule>[
    DVWafRule(
      name: 'admin-from-office-countries',
      paths: <String>['/admin/**'],
      from: DVWafSource.notIn(<String>['NG', 'GB']),
    ),
  ],
  // Believed only when the request came through a trusted proxy.
  countryOf: DVWaf.countryHeader('cf-ipcountry'),
);

final MiddlewareChain edgeChain = MiddlewareChain()..use(adminFirewall.middleware());
// docs:end

// docs:start edge-credentials
DVCredentialGuard credentialGuard() => DVCredentialGuard(
      provider: LocalAuthProvider(),
      velocity: DVVelocityLimiter(
        perAccount: const DVVelocityBudget(5, Duration(minutes: 15)),
      ),
      // A range query sends 5 characters of the password's SHA-1, never the password.
      breachedPasswords: DVRangeQueryBreachedPasswords.overHttp(
        (String prefix) => Uri.parse('https://api.pwnedpasswords.com/range/$prefix'),
      ),
    );
// docs:end
