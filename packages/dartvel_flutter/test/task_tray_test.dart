// The background-task tray every page carries.
//
// Error, Empty, and Loading States: "a background-task tray shows uploads,
// exports and imports from the typed progress events" the framework already
// has. The tray is the rendering of DVTrayTasks, in the page shell, so no
// page has to remember it; it shows nobody anything while nothing runs.
import 'package:dartvel_core/dartvel.dart' show DVProgress, DVTrayTask, DVTrayTasks;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/state/task_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, DVTrayTasks tasks) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: DVTaskTray(tasks: tasks)),
  ));
  await tester.pump();
}

void main() {
  tearDown(DV.I18n.reset);

  pageShellCarriesTheTray();

  testWidgets('nothing running shows nothing', (WidgetTester tester) async {
    await _show(tester, DVTrayTasks());
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a running task shows its name and how far it is', (WidgetTester tester) async {
    final DVTrayTasks tasks = DVTrayTasks();
    await _show(tester, tasks);
    final DVTrayTask task = tasks.begin('Importing customers');
    task.report(const DVProgress(0.4));
    await tester.pump();

    expect(find.text('Importing customers'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      0.4,
    );
  });

  testWidgets('before its first report it is indeterminate, not at 0%', (WidgetTester tester) async {
    final DVTrayTasks tasks = DVTrayTasks();
    tasks.begin('Uploading photo');
    await _show(tester, tasks);
    expect(
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
      isNull,
    );
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('a task that ends leaves the tray', (WidgetTester tester) async {
    final DVTrayTasks tasks = DVTrayTasks();
    final DVTrayTask task = tasks.begin('Exporting orders');
    await _show(tester, tasks);
    task.end();
    await tester.pump();
    expect(find.text('Exporting orders'), findsNothing);
  });

  testWidgets('a screen reader hears the task and its progress as one sentence',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final DVTrayTasks tasks = DVTrayTasks();
    tasks.begin('Importing customers').report(const DVProgress(0.25));
    await _show(tester, tasks);
    expect(find.bySemanticsLabel('Importing customers, 25% done'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the words around the name are a framework string', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        DVFrameworkStrings.taskProgress: '{label}, {percent} % effectué',
      },
    ));
    DV.I18n.useLocale(LocaleTag.frFR);
    final DVTrayTasks tasks = DVTrayTasks();
    tasks.begin('Import').report(const DVProgress(0.5));
    await _show(tester, tasks);
    expect(find.bySemanticsLabel('Import, 50 % effectué'), findsOneWidget);
    semantics.dispose();
  });
}

// Kept apart from main() above so the page-shell case reads as its own claim.
void pageShellCarriesTheTray() {
  testWidgets('a page nobody wrapped shows a labelled task', (WidgetTester tester) async {
    final DVTrayTask task = DVTrayTasks.current.begin('Uploading invoice.pdf');
    addTearDown(task.end);
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Orders'),
        child: Text('the page'),
      ),
    ));
    await tester.pump();
    expect(find.text('Uploading invoice.pdf'), findsOneWidget);
    expect(find.text('the page'), findsOneWidget);
  });
}
