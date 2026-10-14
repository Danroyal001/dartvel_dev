import 'package:dartvel_core/dartvel.dart' as core show DVStudioMediaFile;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<core.DVStudioMediaFile> _sampleFiles = <core.DVStudioMediaFile>[
  const core.DVStudioMediaFile(
    id: 'media/logo.png',
    name: 'logo.png',
    key: 'media/logo.png',
    size: 15360,
    mimeType: 'image/png',
    updatedAt: '2026-10-14T12:00:00Z',
    url: 'api/media/file?key=media%2Flogo.png',
  ),
  const core.DVStudioMediaFile(
    id: 'media/promo.mp4',
    name: 'promo.mp4',
    key: 'media/promo.mp4',
    size: 2097152,
    mimeType: 'video/mp4',
    updatedAt: '2026-10-14T13:00:00Z',
    url: 'api/media/file?key=media%2Fpromo.mp4',
  ),
  const core.DVStudioMediaFile(
    id: 'media/guide.pdf',
    name: 'guide.pdf',
    key: 'media/guide.pdf',
    size: 512000,
    mimeType: 'application/pdf',
    updatedAt: '2026-10-14T14:00:00Z',
    url: 'api/media/file?key=media%2Fguide.pdf',
  ),
];

DVStudioTransport _mediaTransport({
  List<core.DVStudioMediaFile>? initialFiles,
  List<String>? calls,
}) {
  final List<core.DVStudioMediaFile> files = <core.DVStudioMediaFile>[
    ...initialFiles ?? _sampleFiles,
  ];

  return (String method, String path, {Object? body}) async {
    calls?.add('$method $path');
    final Uri uri = Uri.parse(path);

    if (method == 'GET' && uri.path == 'api/media') {
      final String? q = uri.queryParameters['q']?.toLowerCase();
      final String? type = uri.queryParameters['type'];
      Iterable<core.DVStudioMediaFile> filtered = files;
      if (q != null && q.isNotEmpty) {
        filtered = filtered.where((core.DVStudioMediaFile f) =>
            f.name.toLowerCase().contains(q) || f.key.toLowerCase().contains(q));
      }
      if (type != null && type.isNotEmpty && type != 'all') {
        filtered = filtered.where((core.DVStudioMediaFile f) {
          return switch (type) {
            'image' => f.isImage,
            'video' => f.isVideo,
            'audio' => f.isAudio,
            'document' => f.isDocument,
            _ => true,
          };
        });
      }
      final List<core.DVStudioMediaFile> result = filtered.toList();
      return DVStudioReply(200, <String, Object?>{
        'files': <Object?>[for (final core.DVStudioMediaFile f in result) f.toJson()],
        'total': result.length,
      });
    }

    if (method == 'POST' && uri.path == 'api/media') {
      final Map<String, Object?> map = body is Map ? body.cast<String, Object?>() : <String, Object?>{};
      final String name = '${map['name'] ?? 'upload.png'}';
      final String mimeType = '${map['mimeType'] ?? 'image/png'}';
      final core.DVStudioMediaFile uploaded = core.DVStudioMediaFile(
        id: 'media/$name',
        name: name,
        key: 'media/$name',
        size: 1024,
        mimeType: mimeType,
        updatedAt: '2026-10-14T15:00:00Z',
        url: 'api/media/file?key=media%2F$name',
      );
      files.add(uploaded);
      return DVStudioReply(201, uploaded.toJson());
    }

    if (method == 'DELETE' && uri.path == 'api/media') {
      final String key = uri.queryParameters['key'] ?? '';
      files.removeWhere((core.DVStudioMediaFile f) => f.key == key || f.id == key);
      return const DVStudioReply(200, <String, Object?>{'ok': true});
    }

    return const DVStudioReply(404, <String, Object?>{});
  };
}

Future<void> _pumpMediaSection(
  WidgetTester tester, {
  DVStudioTransport? transport,
  String? selectedKey,
  ValueChanged<String?>? onSelect,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DVStudioMediaSection(
          client: DVStudioClient(transport ?? _mediaTransport()),
          selectedKey: selectedKey,
          onSelect: onSelect,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('media library displays title, search, type filter, view toggle and upload button', (
    WidgetTester tester,
  ) async {
    await _pumpMediaSection(tester);

    expect(find.text('Media'), findsOneWidget);
    expect(
      find.text('The pictures, videos and documents uploaded to this application.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('dv-studio-media-search')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('dv-studio-media-type-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('dv-studio-media-view-mode')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('dv-studio-media-upload-button')), findsOneWidget);
  });

  testWidgets('media library displays uploaded files in grid view with names and formatted sizes', (
    WidgetTester tester,
  ) async {
    await _pumpMediaSection(tester);

    expect(find.byKey(const ValueKey<String>('dv-studio-media-grid')), findsOneWidget);
    expect(find.text('logo.png'), findsOneWidget);
    expect(find.text('15.0 KB'), findsOneWidget);
    expect(find.text('promo.mp4'), findsOneWidget);
    expect(find.text('2.0 MB'), findsOneWidget);
    expect(find.text('guide.pdf'), findsOneWidget);
    expect(find.text('500.0 KB'), findsOneWidget);
  });

  testWidgets('empty state displays friendly prompt when no files exist', (
    WidgetTester tester,
  ) async {
    await _pumpMediaSection(tester, transport: _mediaTransport(initialFiles: const <core.DVStudioMediaFile>[]));

    expect(find.text('No media files uploaded yet.'), findsOneWidget);
    expect(
      find.text('Upload pictures, videos or documents to use them across your pages.'),
      findsOneWidget,
    );
    expect(find.text('Upload your first file'), findsOneWidget);
  });

  testWidgets('search box filters media files by query', (WidgetTester tester) async {
    final List<String> calls = <String>[];
    await _pumpMediaSection(tester, transport: _mediaTransport(calls: calls));

    await tester.enterText(find.byKey(const ValueKey<String>('dv-studio-media-search')), 'promo');
    await tester.pumpAndSettle();

    expect(calls.any((String c) => c.contains('api/media?q=promo')), isTrue);
    expect(find.text('promo.mp4'), findsOneWidget);
    expect(find.text('logo.png'), findsNothing);
  });

  testWidgets('selecting a file in grid opens inspector with details and calls onSelect', (
    WidgetTester tester,
  ) async {
    String? selected;
    await _pumpMediaSection(tester, onSelect: (String? k) => selected = k);

    // Inspector not open initially
    expect(find.byKey(const ValueKey<String>('dv-studio-media-inspector')), findsNothing);

    // Tap logo.png
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-item-logo.png')));
    await tester.pumpAndSettle();

    expect(selected, 'media/logo.png');
    expect(find.byKey(const ValueKey<String>('dv-studio-media-inspector')), findsOneWidget);
    expect(find.text('Attachment details'), findsOneWidget);
    expect(find.text('image/png'), findsOneWidget);
    expect(find.text('media/logo.png'), findsAtLeastNWidgets(1));
    expect(find.byKey(const ValueKey<String>('dv-studio-media-copy-url')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('dv-studio-media-delete-button')), findsOneWidget);
  });

  testWidgets('view mode toggles between grid and table', (WidgetTester tester) async {
    await _pumpMediaSection(tester);

    expect(find.byKey(const ValueKey<String>('dv-studio-media-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('dv-studio-media-table')), findsNothing);

    // Toggle to table view
    await tester.tap(find.byTooltip('Table view'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('dv-studio-media-grid')), findsNothing);
    expect(find.byKey(const ValueKey<String>('dv-studio-media-table')), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
  });

  testWidgets('uploading a file through upload dialog refreshes the list', (
    WidgetTester tester,
  ) async {
    await _pumpMediaSection(tester);

    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-upload-button')));
    await tester.pumpAndSettle();

    expect(find.text('Upload media file'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('dv-studio-media-upload-name')),
      'new-icon.png',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('dv-studio-media-upload-content')),
      'some image bytes',
    );

    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-upload-submit')));
    await tester.pumpAndSettle();

    // Dialog closed and new file appears
    expect(find.text('Upload media file'), findsNothing);
    expect(find.text('new-icon.png'), findsOneWidget);
  });

  testWidgets('deleting a file through inspector prompts confirmation and deletes', (
    WidgetTester tester,
  ) async {
    await _pumpMediaSection(tester, selectedKey: 'media/logo.png');

    expect(find.text('Attachment details'), findsOneWidget);

    // Tap delete button in inspector
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-delete-button')));
    await tester.pumpAndSettle();

    expect(find.text('Delete media file?'), findsOneWidget);

    // Confirm delete
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-delete-confirm')));
    await tester.pumpAndSettle();

    // Dialog and inspector closed, file removed
    expect(find.text('Delete media file?'), findsNothing);
    expect(find.text('logo.png'), findsNothing);
    expect(find.text('promo.mp4'), findsOneWidget);
  });
}
