import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// The generator reads model sources as text, so nothing else proves these
// annotations are valid Dart. This file is compiled by the test runner: if a
// field constructor is not a usable const annotation, it fails to build.
@DVModel()
class _Post {
  @DVModel.featuredImage()
  final DVImage cover;
  @DVModel.pageTitle()
  final String headline;
  @DVModel.mainContent()
  final String body;
  @DVModel.pageOrder(3)
  final String author;
  @DVModel.hideFromPage()
  final String internalReference;
  @DVModel.sensitiveField()
  final String auditToken;
  @DVModel.searchableField()
  final String tags;

  const _Post({
    required this.cover,
    required this.headline,
    required this.body,
    required this.author,
    required this.internalReference,
    required this.auditToken,
    required this.tags,
  });
}

void main() {
  test('page-composition annotations are model-scoped', () {
    // Grouped under DVModel like sensitiveField/searchableField, rather than
    // standing alone.
    expect(const DVModel.featuredImage().pageRole,
        DVModelPageRole.featuredImage);
    expect(const DVModel.pageTitle().pageRole, DVModelPageRole.pageTitle);
    expect(const DVModel.mainContent().pageRole, DVModelPageRole.mainContent);
    expect(const DVModel.hideFromPage().pageRole, DVModelPageRole.hidden);

    expect(const DVModel.pageOrder(3).pageOrderIndex, 3);
    expect(const DVModel.pageOrder(3).pageRole, isNull);
  });

  test('a model annotation carries no field-scoped metadata', () {
    const model = DVModel();

    expect(model.pageRole, isNull);
    expect(model.pageOrderIndex, isNull);
    expect(model.showInForms, isFalse);
  });

  test('the annotated input compiles and stays a private schema input', () {
    const post = _Post(
      cover: DVImage.asset('assets/cover.png'),
      headline: 'Headline',
      body: 'Body',
      author: 'Ada',
      internalReference: 'ref-1',
      auditToken: 'token',
      tags: 'dart',
    );

    expect(post.headline, 'Headline');
  });
}
