// Framework strings are i18n keys with catalogue defaults.
//
// Error, Empty, and Loading States: DVTable's empty label defaulted to the
// literal 'No rows', so an application localised into six languages still
// said "No rows" in all of them. The failure is silent -- the English text is
// a plausible rendering in every locale -- so these tests load a catalogue and
// check the table actually reads it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _showEmpty(WidgetTester tester, {String? emptyLabel}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: emptyLabel == null
          ? DVTable<String>(
              const <String>[],
              columns: <DVTableColumn<String>>[
                DVTableColumn<String>(label: 'Name', value: (String s) => s),
              ],
            )
          : DVTable<String>(
              const <String>[],
              columns: <DVTableColumn<String>>[
                DVTableColumn<String>(label: 'Name', value: (String s) => s),
              ],
              emptyLabel: emptyLabel,
            ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => DV.I18n.reset());

  group('a framework string', () {
    test('is a key, and with no catalogue it reads its English default', () {
      expect(DVFrameworkStrings.tableEmpty.value, 'dv.table.empty');
      expect(DV.I18n.t(DVFrameworkStrings.tableEmpty), 'No rows');
    });

    test('a strict lookup does not throw for a key the framework defaults', () {
      expect(
        DV.I18n.t(DVFrameworkStrings.tableEmpty, strict: true),
        'No rows',
      );
    });

    test('a catalogue for the current locale replaces the default', () {
      DV.I18n.load(const DVTranslationCatalog(
        locale: LocaleTag.frFR,
        messages: <DVTranslationKey, String>{
          DVFrameworkStrings.tableEmpty: 'Aucune ligne',
        },
      ));
      DV.I18n.useLocale(LocaleTag.frFR);

      expect(DV.I18n.t(DVFrameworkStrings.tableEmpty), 'Aucune ligne');
    });

    test('an application key with no translation still renders its name', () {
      // The default belongs to framework keys only; an application key that
      // is missing stays visibly missing.
      expect(DV.I18n.t(const DVTranslationKey('app.checkout')), 'app.checkout');
    });
  });

  group('an empty DVTable', () {
    testWidgets('says the framework default when nothing is loaded',
        (WidgetTester tester) async {
      await _showEmpty(tester);
      expect(find.text('No rows'), findsOneWidget);
    });

    testWidgets('speaks the reader\'s language', (WidgetTester tester) async {
      DV.I18n.load(const DVTranslationCatalog(
        locale: LocaleTag.frFR,
        messages: <DVTranslationKey, String>{
          DVFrameworkStrings.tableEmpty: 'Aucune ligne',
        },
      ));
      DV.I18n.useLocale(LocaleTag.frFR);

      await _showEmpty(tester);

      expect(find.text('Aucune ligne'), findsOneWidget);
      expect(find.text('No rows'), findsNothing);
      expect(find.bySemanticsLabel('Aucune ligne'), findsOneWidget);
    });

    testWidgets('is rebranded by an English catalogue',
        (WidgetTester tester) async {
      DV.I18n.load(const DVTranslationCatalog(
        locale: LocaleTag.enUS,
        messages: <DVTranslationKey, String>{
          DVFrameworkStrings.tableEmpty: 'Nothing here yet',
        },
      ));

      await _showEmpty(tester);

      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('an explicit label is the application\'s own words',
        (WidgetTester tester) async {
      await _showEmpty(tester, emptyLabel: 'No orders');
      expect(find.text('No orders'), findsOneWidget);
    });
  });
}
