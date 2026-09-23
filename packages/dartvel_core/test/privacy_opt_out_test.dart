// Global Privacy Control: a header that is an instruction.
//
// A browser, or an extension somebody installed on purpose, sends
// `Sec-GPC: 1`. Under California's CPRA — and Colorado's and Connecticut's
// laws after it — that is a valid opt-out of the sale or sharing of personal
// information, and a business has to honour it without asking again.
//
// The failure mode is the quiet one. Nothing throws when a request's opt-out
// is dropped: the page renders, the events are collected, and the only way to
// find out is a regulator asking why a signal the browser sent was ignored.
// So the signal is read on the request, carried through the work the request
// does, and answered where consent is decided rather than wherever somebody
// remembers to check.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVConsentCategory advertising = DVConsentCategory('advertising');
const DVConsentCategory product = DVConsentCategory('product');

final DVConsentPolicy policy = DVConsentPolicy(
  version: '2026-09-01',
  categories: const <DVConsentDeclaration>[
    DVConsentDeclaration(DVConsentCategory.essential, required: true),
    // What "sale or sharing" means in the statute is what `tracking` means
    // here: measurement that follows somebody across other companies.
    DVConsentDeclaration(advertising, defaultGranted: true, tracking: true),
    DVConsentDeclaration(product, defaultGranted: true),
  ],
);

Future<DVConsent> openConsent() async {
  final DVConsent consent = DVConsent(
    policy: policy,
    database: MemoryDVDatabaseAdapter(),
    installId: 'install-1',
    onDiagnostic: (String code, String message) {},
  );
  await consent.ensureSchema();
  await consent.load();
  return consent;
}

void main() {
  group('reading the header', () {
    test('Sec-GPC: 1 is the signal', () {
      expect(dvGlobalPrivacyControl(<String, String>{'Sec-GPC': '1'}), isTrue);
    });

    test('a header name is not case-sensitive, and arrives lower-cased', () {
      // Shelf lower-cases every header name it hands over, and a check
      // written against the spelling in the specification would have read
      // nothing on every request.
      expect(dvGlobalPrivacyControl(<String, String>{'sec-gpc': '1'}), isTrue);
    });

    test('anything other than 1 is not an opt-out', () {
      // The specification defines exactly one value. `0` is a browser saying
      // it is not sending the signal, which is not the same as consent and is
      // certainly not an opt-out.
      expect(dvGlobalPrivacyControl(<String, String>{'sec-gpc': '0'}), isFalse);
      expect(dvGlobalPrivacyControl(<String, String>{'sec-gpc': ''}), isFalse);
      expect(dvGlobalPrivacyControl(<String, String>{'sec-gpc': 'true'}),
          isFalse);
      expect(dvGlobalPrivacyControl(const <String, String>{}), isFalse);
    });
  });

  group('carrying it through the request', () {
    test('nothing said means nothing opted out of', () {
      expect(dvPrivacyOptOut, isFalse);
    });

    test('a scope carries it, and only inside itself', () {
      final bool inside = dvWithPrivacyOptOut(true, () => dvPrivacyOptOut);
      expect(inside, isTrue);
      expect(dvPrivacyOptOut, isFalse);
    });

    test('it survives an await, which is the whole reason it is a zone', () async {
      // A field set at the top of a handler is overwritten by the next
      // request to arrive at the first await, and this request then decides
      // somebody else's opt-out. That is the bug the tenant scope was written
      // against, and it would be this one too.
      final bool after = await dvWithPrivacyOptOut(true, () async {
        await Future<void>.delayed(Duration.zero);
        return dvPrivacyOptOut;
      });
      expect(after, isTrue);
    });

    test('two scopes do not bleed into each other', () async {
      final List<bool> seen = <bool>[];
      await Future.wait(<Future<void>>[
        dvWithPrivacyOptOut(true, () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          seen.add(dvPrivacyOptOut);
        }),
        dvWithPrivacyOptOut(false, () async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          seen.add(dvPrivacyOptOut);
        }),
      ]);
      expect(seen, containsAll(<bool>[true, false]));
    });
  });

  group('what it changes', () {
    test('a tracking category is denied however it was granted', () async {
      final DVConsent consent = await openConsent();
      expect(consent.isGranted(advertising), isTrue);

      expect(dvWithPrivacyOptOut(true, () => consent.isGranted(advertising)),
          isFalse);
    });

    test('a recorded grant does not override the signal', () async {
      // The order matters: the header is the person's own instruction, sent
      // now, and a stored answer is what they clicked once.
      final DVConsent consent = await openConsent();
      await consent.record(<DVConsentCategory, bool>{advertising: true});
      expect(consent.isGranted(advertising), isTrue);

      expect(dvWithPrivacyOptOut(true, () => consent.isGranted(advertising)),
          isFalse);
    });

    test('a category that is not tracking is not affected', () async {
      // GPC is an opt-out of sale and sharing, not of everything. Denying a
      // first-party measurement category would be a framework deciding a
      // question the law did not ask.
      final DVConsent consent = await openConsent();
      expect(dvWithPrivacyOptOut(true, () => consent.isGranted(product)),
          isTrue);
    });

    test('what the application needs to work still works', () async {
      final DVConsent consent = await openConsent();
      expect(
          dvWithPrivacyOptOut(
              true, () => consent.isGranted(DVConsentCategory.essential)),
          isTrue);
    });
  });
}
