// Studio Slice 9 parity: undo/redo, autosave, preview mode, and publish pipeline.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Undo and Redo parity', () {
    test('tracks mutation history, undos and redos cleanly', () {
      final doc = DVPageDocument(route: '/home', title: 'Home');
      final controller = DVStudioEditorController(doc, autosave: false);

      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);

      final node1 = DVPageNode.text('Heading');
      controller.insert(node1, parent: doc.root.id);

      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);
      expect(controller.document.root.children.length, 1);
      expect(controller.document.root.children.first.properties['text'], 'Heading');

      final node2 = DVPageNode.button(label: 'Click me');
      controller.insert(node2, parent: doc.root.id);
      expect(controller.document.root.children.length, 2);

      // Undo once -> reverts node2
      controller.undo();
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isTrue);
      expect(controller.document.root.children.length, 1);
      expect(controller.document.root.children.first.properties['text'], 'Heading');

      // Redo -> restores node2
      controller.redo();
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);
      expect(controller.document.root.children.length, 2);

      // New mutation clears redo stack
      controller.undo();
      expect(controller.canRedo, isTrue);
      controller.insert(DVPageNode.text('Subheading'), parent: doc.root.id);
      expect(controller.canRedo, isFalse);
      expect(controller.document.root.children.length, 2);
      expect(controller.document.root.children.last.properties['text'], 'Subheading');

      controller.dispose();
    });

    test('updatePageSeo participates in undo/redo history', () {
      final doc = DVPageDocument(route: '/about', title: 'Original Title');
      final controller = DVStudioEditorController(doc, autosave: false);

      controller.updatePageSeo(
        title: 'New SEO Title',
        description: 'Meta description for search engines',
      );

      expect(controller.document.title, 'New SEO Title');
      expect(controller.document.description, 'Meta description for search engines');
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.document.title, 'Original Title');
      expect(controller.document.description, isNull);
      expect(controller.canRedo, isTrue);

      controller.redo();
      expect(controller.document.title, 'New SEO Title');
      expect(controller.document.description, 'Meta description for search engines');

      controller.dispose();
    });

    test('history limit bounds maximum undo snapshots', () {
      final doc = DVPageDocument(route: '/limit');
      final controller = DVStudioEditorController(doc, historyLimit: 3, autosave: false);

      for (var i = 0; i < 6; i++) {
        controller.insert(DVPageNode.text('Item $i'), parent: doc.root.id);
      }

      var undos = 0;
      while (controller.canUndo) {
        controller.undo();
        undos++;
      }
      expect(undos, 3);

      controller.dispose();
    });
  });

  group('Autosave parity', () {
    test('mutations mark controller dirty and trigger debounced autosave', () async {
      final doc = DVPageDocument(route: '/auto');
      var saveCount = 0;
      final controller = DVStudioEditorController(
        doc,
        autosave: true,
        autosaveInterval: const Duration(milliseconds: 50),
      );
      controller.publisher = (DVPageDocument savedDoc) async {
        saveCount++;
      };

      expect(controller.isDirty, isFalse);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.idle);
      expect(controller.lastSaved, isNull);

      controller.insert(DVPageNode.text('Text 1'), parent: doc.root.id);

      expect(controller.isDirty, isTrue);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.dirty);
      expect(saveCount, 0);

      // Wait for debounce timer
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(saveCount, 1);
      expect(controller.isDirty, isFalse);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.saved);
      expect(controller.lastSaved, isNotNull);

      controller.dispose();
    });

    test('manual save immediately persists and cancels pending timer', () async {
      final doc = DVPageDocument(route: '/manual');
      var saveCount = 0;
      final controller = DVStudioEditorController(
        doc,
        autosave: true,
        autosaveInterval: const Duration(seconds: 10),
      );
      controller.publisher = (DVPageDocument savedDoc) async {
        saveCount++;
      };

      controller.insert(DVPageNode.text('Immediate'), parent: doc.root.id);
      expect(controller.isDirty, isTrue);
      expect(saveCount, 0);

      await controller.save();

      expect(saveCount, 1);
      expect(controller.isDirty, isFalse);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.saved);

      // Wait a bit, ensure debounced timer was cancelled
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(saveCount, 1);

      controller.dispose();
    });

    test('failed save transitions status to error', () async {
      final doc = DVPageDocument(route: '/err');
      final controller = DVStudioEditorController(doc, autosave: false);
      controller.publisher = (DVPageDocument savedDoc) async {
        throw Exception('Storage failure');
      };

      controller.insert(DVPageNode.text('Fails'), parent: doc.root.id);

      expect(() => controller.save(), throwsA(isA<Exception>()));
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.error);

      controller.dispose();
    });
  });

  group('Preview mode parity', () {
    test('preview mode toggles and clears selected node', () {
      final doc = DVPageDocument(route: '/preview');
      final controller = DVStudioEditorController(doc, autosave: false);
      final node = DVPageNode.text('Hello');
      controller.insert(node, parent: doc.root.id);
      controller.select(node.id);

      expect(controller.selectedId, node.id);
      expect(controller.previewMode, isFalse);

      controller.togglePreview();
      expect(controller.previewMode, isTrue);
      expect(controller.selectedId, isNull);

      controller.togglePreview();
      expect(controller.previewMode, isFalse);

      controller.dispose();
    });

    testWidgets('preview mode on canvas disables node chrome and renders live widgets',
        (WidgetTester tester) async {
      final doc = DVPageDocument(route: '/canvas-preview');
      final controller = DVStudioEditorController(doc, autosave: false);
      final node = DVPageNode.button(label: 'Submit Action');
      controller.insert(node, parent: doc.root.id);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DVStudioCanvas(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In edit mode: canvas renders node
      expect(find.byType(DVStudioCanvas), findsOneWidget);
      expect(find.text('Submit Action'), findsOneWidget);

      // Toggle preview mode
      controller.previewMode = true;
      await tester.pumpAndSettle();

      // In preview mode: live interactive widgets render cleanly
      expect(find.text('Submit Action'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('DVStudioScreen toolbar toggles preview mode and renders preview banner',
        (WidgetTester tester) async {
      final database = SqliteDVDatabaseAdapter.memory();
      DV.Database.configure(database);
      DVPageStore.resetCache();
      addTearDown(() {
        database.close();
        DVPageStore.resetCache();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Material(child: DVStudioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Create a page
      await tester.enterText(find.byType(EditableText).first, '/preview-page');
      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
      await tester.pumpAndSettle();

      // Verify preview button exists in toolbar
      final previewBtn = find.byKey(const ValueKey<String>('dv-studio-preview'));
      expect(previewBtn, findsOneWidget);

      // Verify autosave indicator exists in toolbar
      final autosaveInd = find.byKey(const ValueKey<String>('dv-studio-autosave-indicator'));
      expect(autosaveInd, findsOneWidget);

      // Preview banner is initially not visible
      expect(find.byKey(const ValueKey<String>('dv-studio-preview-banner')), findsNothing);

      // Tap Preview button
      await tester.tap(previewBtn);
      await tester.pumpAndSettle();

      // Preview banner is now visible
      expect(find.byKey(const ValueKey<String>('dv-studio-preview-banner')), findsOneWidget);
      expect(find.textContaining('Preview mode — canvas is interactive'), findsOneWidget);

      // Tap Exit preview button
      final exitBtn = find.byKey(const ValueKey<String>('dv-studio-exit-preview'));
      expect(exitBtn, findsOneWidget);
      await tester.tap(exitBtn);
      await tester.pumpAndSettle();

      // Banner is dismissed
      expect(find.byKey(const ValueKey<String>('dv-studio-preview-banner')), findsNothing);
    });
  });

  group('Publish parity', () {
    testWidgets('deploy button publishes page to store and shows feedback',
        (WidgetTester tester) async {
      final database = SqliteDVDatabaseAdapter.memory();
      DV.Database.configure(database);
      DVPageStore.resetCache();
      addTearDown(() {
        database.close();
        DVPageStore.resetCache();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Material(child: DVStudioScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).first, '/publish-test');
      await tester.tap(find.byKey(const ValueKey<String>('dv-studio-create')));
      await tester.pumpAndSettle();

      // Tap Deploy
      final deployBtn = find.byKey(const ValueKey<String>('dv-studio-publish'));
      expect(deployBtn, findsOneWidget);
      await tester.tap(deployBtn);
      await tester.pumpAndSettle();

      // Page is now stored and published
      expect(await const DVPageStore().routes(), contains('/publish-test'));

      // Check feedback SnackBar
      expect(find.textContaining('deployed successfully'), findsOneWidget);
    });
  });
}
