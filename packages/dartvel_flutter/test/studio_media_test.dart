import 'dart:convert';

import 'package:dartvel_core/dartvel.dart' as core show DVStudioMediaFile;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  List<Map<String, Object?>>? uploads,
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
      uploads?.add(map);
      if ('${map['name']}'.endsWith('.svg')) {
        return const DVStudioReply(415, <String, Object?>{
          'error': 'unsupported_type',
          'message': 'The media library does not take this kind of file.',
        });
      }
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
  DVStudioPickFiles? pickFiles,
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
          pickFiles: pickFiles,
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

  // Uploading is choosing files, as in every media library: the bytes of
  // the file picked reach the server unchanged. It used to be a text box
  // whose contents were uploaded as the file.
  testWidgets('uploading sends the bytes of the files picked', (
    WidgetTester tester,
  ) async {
    final List<Map<String, Object?>> uploads = <Map<String, Object?>>[];
    await _pumpMediaSection(
      tester,
      transport: _mediaTransport(uploads: uploads),
      pickFiles: () async => <DVStudioPickedFile>[
        (name: 'new-icon.png', bytes: <int>[0x89, 0x50, 0x4E, 0x47]),
        (name: 'notes.txt', bytes: utf8.encode('hello')),
      ],
    );

    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-upload-button')));
    await tester.pumpAndSettle();

    expect(<Object?>[for (final Map<String, Object?> u in uploads) u['name']],
        <String>['new-icon.png', 'notes.txt']);
    expect(base64Decode('${uploads.first['bytes']}'), <int>[0x89, 0x50, 0x4E, 0x47]);
    expect(find.text('new-icon.png'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
  });

  testWidgets('a file the library refuses says why', (WidgetTester tester) async {
    await _pumpMediaSection(
      tester,
      pickFiles: () async => <DVStudioPickedFile>[
        (name: 'logo.svg', bytes: utf8.encode('<svg/>')),
      ],
    );
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-upload-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not take this kind of file'), findsOneWidget);
  });

  testWidgets('picking nothing uploads nothing', (WidgetTester tester) async {
    final List<Map<String, Object?>> uploads = <Map<String, Object?>>[];
    await _pumpMediaSection(
      tester,
      transport: _mediaTransport(uploads: uploads),
      pickFiles: () async => const <DVStudioPickedFile>[],
    );
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-upload-button')));
    await tester.pumpAndSettle();
    expect(uploads, isEmpty);
  });

  testWidgets('Copy URL copies the address visitors are served the file at', (
    WidgetTester tester,
  ) async {
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add('${(call.arguments as Map)['text']}');
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _pumpMediaSection(tester, selectedKey: 'media/logo.png');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-media-copy-url')));
    await tester.pumpAndSettle();
    expect(copied, <String>['${Uri.base.resolve('/_dartvel/media/logo.png')}']);
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
