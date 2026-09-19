// Where a page Studio deploys goes: every app, or the targets picked.
//
// Studio's Deploy menu lists the places a site owner ships to -- the web,
// phones and tablets, desktop apps, TVs, browser extensions and devices -- in
// those words. A page deployed to phones only is served by the phone apps and
// left alone by the website, which keeps its compiled page.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument page(String route, {Set<DVDeployTarget>? targets}) {
  final DVPageDocument document =
      DVPageDocument(route: route, title: route, targets: targets);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(route), parent: document.root.id);
  return document;
}

void main() {
  group('a document', () {
    test('keeps the targets it was deployed to', () {
      final DVPageDocument document = page('/menu',
          targets: <DVDeployTarget>{DVDeployTarget.phones, DVDeployTarget.tvs});

      final DVPageDocument back = DVPageDocument.fromJson(document.toJson());

      expect(back.targets, <DVDeployTarget>{
        DVDeployTarget.phones,
        DVDeployTarget.tvs,
      });
    });

    test('with no targets goes everywhere, and says nothing about it', () {
      // Every document stored before targets existed has none, and must
      // keep reaching every app.
      final Map<String, Object?> json = page('/menu').toJson();

      expect(json.containsKey('targets'), isFalse);
      final DVPageDocument back = DVPageDocument.fromJson(json);
      for (final DVDeployTarget target in DVDeployTarget.values) {
        expect(back.reaches(target), isTrue, reason: target.name);
      }
    });

    test('an unknown target from a newer Studio is skipped, not fatal', () {
      final Map<String, Object?> json = page('/menu').toJson()
        ..['targets'] = <String>['web', 'cars'];

      expect(DVPageDocument.fromJson(json).targets,
          <DVDeployTarget>{DVDeployTarget.web});
    });
  });

  group('each app knows which target it is', () {
    DVDeployTarget of(String platform,
            {bool isTV = false, bool isExtension = false}) =>
        DVDeployTarget.of(
            platform: platform, isTV: isTV, isExtension: isExtension);

    test('phones and tablets', () {
      expect(of('android'), DVDeployTarget.phones);
      expect(of('ios'), DVDeployTarget.phones);
    });

    test('desktop apps', () {
      expect(of('macos'), DVDeployTarget.desktop);
      expect(of('windows'), DVDeployTarget.desktop);
      expect(of('linux'), DVDeployTarget.desktop);
    });

    test('TVs, by platform and by the TV flag', () {
      expect(of('tizen'), DVDeployTarget.tvs);
      expect(of('webos'), DVDeployTarget.tvs);
      expect(of('tvos'), DVDeployTarget.tvs);
      expect(of('android', isTV: true), DVDeployTarget.tvs);
    });

    test('the web, and a browser extension built from it', () {
      expect(of('web'), DVDeployTarget.web);
      expect(of('web', isExtension: true), DVDeployTarget.extensions);
    });

    test('embedded devices', () {
      expect(of('sony-elinux'), DVDeployTarget.devices);
      expect(of('fuchsia'), DVDeployTarget.devices);
    });

    test('every target has a label a site owner reads', () {
      expect(<String>[for (final t in DVDeployTarget.values) t.label], <String>[
        'Website',
        'Phones and tablets',
        'Desktop apps',
        'TVs',
        'Browser extensions',
        'Devices',
      ]);
    });
  });

  group('an app serves only the pages deployed to it', () {
    setUp(() {
      DVPageStore.resetCache();
      DVPageStore.source = () async => <DVPageDocument>[
            page('/everywhere'),
            page('/phones', targets: <DVDeployTarget>{DVDeployTarget.phones}),
          ];
    });

    tearDown(() {
      DVPageStore.source = null;
      DVDeployTarget.debugCurrent = null;
      DVPageStore.resetCache();
    });

    test('a phone app serves both', () async {
      DVDeployTarget.debugCurrent = DVDeployTarget.phones;
      await DVPageStore.prime();

      expect(DVPageStore.cached('/everywhere'), isNotNull);
      expect(DVPageStore.cached('/phones'), isNotNull);
    });

    test('the website keeps its compiled page for one deployed to phones',
        () async {
      DVDeployTarget.debugCurrent = DVDeployTarget.web;
      await DVPageStore.prime();

      expect(DVPageStore.cached('/everywhere'), isNotNull);
      expect(DVPageStore.cached('/phones'), isNull);
    });
  });
}
