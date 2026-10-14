import 'dart:convert';
import 'package:dartvel_core/dartvel.dart' as core show DVStudioMediaFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_server.dart';
import 'studio_style.dart';

/// The Media library: pictures, videos, audio and documents uploaded to the application.
class const DVStudioMediaSection({
  super.key,
  required final DVStudioClient client,
  final String? selectedKey,
  final ValueChanged<String?>? onSelect,
}) extends StatefulWidget {
  @override
  State<DVStudioMediaSection> createState() => _DVStudioMediaSectionState();
}

enum _DVStudioMediaViewMode { grid, table }

class _DVStudioMediaSectionState extends State<DVStudioMediaSection> {
  late Future<({List<core.DVStudioMediaFile> files, int total})> _future;
  String? _error;
  String _search = '';
  String _type = 'all';
  _DVStudioMediaViewMode _viewMode = _DVStudioMediaViewMode.grid;
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _selectedKey = widget.selectedKey;
    _reload();
  }

  @override
  void didUpdateWidget(DVStudioMediaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedKey != widget.selectedKey) {
      setState(() {
        _selectedKey = widget.selectedKey;
      });
    }
  }

  void _reload() {
    setState(() {
      _error = null;
      _future = widget.client.mediaFiles(
        q: _search.isEmpty ? null : _search,
        type: _type == 'all' ? null : _type,
      ).catchError((Object err) {
        setState(() {
          _error = '$err';
        });
        return (files: const <core.DVStudioMediaFile>[], total: 0);
      });
    });
  }

  void _selectFile(String? key) {
    setState(() {
      _selectedKey = key;
    });
    widget.onSelect?.call(key);
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconFor(core.DVStudioMediaFile file) {
    if (file.isImage) return Icons.image_outlined;
    if (file.isVideo) return Icons.movie_outlined;
    if (file.isAudio) return Icons.audiotrack_outlined;
    return Icons.description_outlined;
  }

  Future<void> _openUploadDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController contentController = TextEditingController();
    String mimeType = 'image/png';

    final bool? uploaded = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
          title: const Text('Upload media file'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: <Widget>[
                TextField(
                  key: const ValueKey<String>('dv-studio-media-upload-name'),
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'File name',
                    hintText: 'e.g. banner.png or document.pdf',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mimeType,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'image/png', child: Text('Image (PNG)')),
                    DropdownMenuItem<String>(value: 'image/jpeg', child: Text('Image (JPEG)')),
                    DropdownMenuItem<String>(value: 'video/mp4', child: Text('Video (MP4)')),
                    DropdownMenuItem<String>(value: 'audio/mpeg', child: Text('Audio (MP3)')),
                    DropdownMenuItem<String>(value: 'application/pdf', child: Text('Document (PDF)')),
                    DropdownMenuItem<String>(value: 'text/plain', child: Text('Text file')),
                  ],
                  onChanged: (String? val) {
                    if (val != null) setDialogState(() => mimeType = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('dv-studio-media-upload-content'),
                  controller: contentController,
                  decoration: const InputDecoration(
                    labelText: 'Content / Text / Base64',
                    hintText: 'Enter file text or base64 data',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const ValueKey<String>('dv-studio-media-upload-submit'),
              onPressed: () async {
                final String name = nameController.text.trim();
                final String text = contentController.text;
                if (name.isEmpty) return;
                List<int> bytes;
                try {
                  bytes = base64Decode(text);
                } on Object {
                  bytes = utf8.encode(text.isEmpty ? 'Sample content' : text);
                }
                await widget.client.uploadMedia(
                  name: name,
                  bytes: bytes,
                  mimeType: mimeType,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );

    if (uploaded == true) {
      _reload();
    }
  }

  Future<void> _deleteFile(core.DVStudioMediaFile file) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete media file?'),
        content: Text('Are you sure you want to delete "${file.name}"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const ValueKey<String>('dv-studio-media-delete-confirm'),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.client.deleteMedia(file.key);
      if (_selectedKey == file.key) {
        _selectFile(null);
      }
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      key: const ValueKey<String>('dv-studio-media'),
      backgroundColor: colors.surface,
      body: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          // Header bar
          Padding(
            padding: const .symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: <Widget>[
                Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    DVStudioStyle.heading('Media'),
                    const SizedBox(height: 4),
                    Text(
                      'The pictures, videos and documents uploaded to this application.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
                Tooltip(
                  message: 'Upload media',
                  child: ElevatedButton.icon(
                    key: const ValueKey<String>('dv-studio-media-upload-button'),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Upload media'),
                    onPressed: _openUploadDialog,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Filters and controls bar
          Padding(
            padding: const .symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: <Widget>[
                // Search box
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      key: const ValueKey<String>('dv-studio-media-search'),
                      decoration: InputDecoration(
                        hintText: 'Search media...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        contentPadding: const .symmetric(horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                tooltip: 'Clear search',
                                onPressed: () {
                                  setState(() => _search = '');
                                  _reload();
                                },
                              )
                            : null,
                      ),
                      onChanged: (String val) {
                        setState(() => _search = val);
                        _reload();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Type filter dropdown
                DropdownButton<String>(
                  key: const ValueKey<String>('dv-studio-media-type-filter'),
                  value: _type,
                  underline: const SizedBox.shrink(),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'all', child: Text('All media items')),
                    DropdownMenuItem<String>(value: 'image', child: Text('Images')),
                    DropdownMenuItem<String>(value: 'video', child: Text('Videos')),
                    DropdownMenuItem<String>(value: 'audio', child: Text('Audio')),
                    DropdownMenuItem<String>(value: 'document', child: Text('Documents')),
                  ],
                  onChanged: (String? val) {
                    if (val != null) {
                      setState(() => _type = val);
                      _reload();
                    }
                  },
                ),
                const Spacer(),

                // View mode toggle
                SegmentedButton<_DVStudioMediaViewMode>(
                  key: const ValueKey<String>('dv-studio-media-view-mode'),
                  segments: const <ButtonSegment<_DVStudioMediaViewMode>>[
                    ButtonSegment<_DVStudioMediaViewMode>(
                      value: _DVStudioMediaViewMode.grid,
                      icon: Icon(Icons.grid_view, size: 18),
                      tooltip: 'Grid view',
                    ),
                    ButtonSegment<_DVStudioMediaViewMode>(
                      value: _DVStudioMediaViewMode.table,
                      icon: Icon(Icons.view_list, size: 18),
                      tooltip: 'Table view',
                    ),
                  ],
                  selected: <_DVStudioMediaViewMode>{_viewMode},
                  onSelectionChanged: (Set<_DVStudioMediaViewMode> next) {
                    setState(() => _viewMode = next.first);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Main content: gallery and optional side inspector
          Expanded(
            child: FutureBuilder<({List<core.DVStudioMediaFile> files, int total})>(
              future: _future,
              builder: (BuildContext context, AsyncSnapshot<({List<core.DVStudioMediaFile> files, int total})> snapshot) {
                if (_error != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: .min,
                      children: <Widget>[
                        DVStudioStyle.heading('Media could not be read'),
                        const SizedBox(height: 8),
                        Text(_error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _reload,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<core.DVStudioMediaFile> files = snapshot.data!.files;
                if (files.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: .min,
                      children: <Widget>[
                        Icon(Icons.perm_media_outlined, size: 48, color: colors.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(
                          _search.isNotEmpty || _type != 'all'
                              ? 'No media files match your search.'
                              : 'No media files uploaded yet.',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Upload pictures, videos or documents to use them across your pages.',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Upload your first file'),
                          onPressed: _openUploadDialog,
                        ),
                      ],
                    ),
                  );
                }

                final core.DVStudioMediaFile? selectedFile = files
                    .where((core.DVStudioMediaFile f) => f.key == _selectedKey || f.name == _selectedKey)
                    .firstOrNull;

                return Row(
                  children: <Widget>[
                    // Gallery area
                    Expanded(
                      flex: 3,
                      child: _viewMode == _DVStudioMediaViewMode.grid
                          ? _buildGrid(files)
                          : _buildTable(files),
                    ),

                    // Inspector panel if a file is selected
                    if (selectedFile != null) ...<Widget>[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 340,
                        child: _buildInspector(selectedFile),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<core.DVStudioMediaFile> files) => GridView.builder(
        key: const ValueKey<String>('dv-studio-media-grid'),
        padding: const .all(24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: files.length,
        itemBuilder: (BuildContext context, int index) {
          final core.DVStudioMediaFile file = files[index];
          final bool isSelected = file.key == _selectedKey || file.name == _selectedKey;
          final ThemeData theme = Theme.of(context);
          final ColorScheme colors = theme.colorScheme;

          return Focus(
            child: Builder(
              builder: (BuildContext focusContext) {
                final bool hasFocus = Focus.of(focusContext).hasFocus;
                return Semantics(
                  button: true,
                  label: file.name,
                  selected: isSelected,
                  child: Tooltip(
                    message: file.name,
                    child: InkWell(
                      key: ValueKey<String>('dv-studio-media-item-${file.name}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _selectFile(isSelected ? null : file.key),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? colors.primary
                                : (hasFocus ? colors.primary.withValues(alpha: 0.5) : colors.outlineVariant),
                            width: isSelected ? 2 : 1,
                          ),
                          color: isSelected ? colors.primaryContainer.withValues(alpha: 0.2) : colors.surface,
                        ),
                        child: Column(
                          crossAxisAlignment: .stretch,
                          children: <Widget>[
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
                                  borderRadius: const .vertical(top: Radius.circular(7)),
                                ),
                                child: Center(
                                  child: Icon(_iconFor(file), size: 40, color: colors.primary),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const .all(8),
                              child: Column(
                                crossAxisAlignment: .start,
                                children: <Widget>[
                                  Text(
                                    file.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatSize(file.size),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );

  Widget _buildTable(List<core.DVStudioMediaFile> files) => SingleChildScrollView(
        key: const ValueKey<String>('dv-studio-media-table'),
        padding: const .all(24),
        child: DataTable(
          showCheckboxColumn: false,
          columns: const <DataColumn>[
            DataColumn(label: Text('File')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Size')),
            DataColumn(label: Text('Actions')),
          ],
          rows: <DataRow>[
            for (final core.DVStudioMediaFile file in files)
              DataRow(
                selected: file.key == _selectedKey || file.name == _selectedKey,
                onSelectChanged: (bool? selected) => _selectFile(selected == true ? file.key : null),
                cells: <DataCell>[
                  DataCell(
                    Row(
                      mainAxisSize: .min,
                      children: <Widget>[
                        Icon(_iconFor(file), size: 20),
                        const SizedBox(width: 8),
                        Text(file.name),
                      ],
                    ),
                  ),
                  DataCell(Text(file.mimeType)),
                  DataCell(Text(_formatSize(file.size))),
                  DataCell(
                    Row(
                      mainAxisSize: .min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.link, size: 18),
                          tooltip: 'Copy URL',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: file.url ?? file.key));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('URL copied to clipboard')),
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Delete file',
                          onPressed: () => _deleteFile(file),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      );

  Widget _buildInspector(core.DVStudioMediaFile file) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return SingleChildScrollView(
      key: const ValueKey<String>('dv-studio-media-inspector'),
      padding: const .all(20),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Attachment details',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Close inspector',
                onPressed: () => _selectFile(null),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // File preview card
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Center(
              child: Icon(_iconFor(file), size: 64, color: colors.primary),
            ),
          ),
          const SizedBox(height: 16),

          // Metadata properties
          _metaRow('File name', file.name),
          _metaRow('File type', file.mimeType),
          _metaRow('File size', _formatSize(file.size)),
          _metaRow('Storage key', file.key),
          if (file.updatedAt != null) _metaRow('Uploaded', file.updatedAt!),
          const SizedBox(height: 16),

          // URL field and copy button
          TextField(
            readOnly: true,
            controller: TextEditingController(text: file.url ?? file.key),
            decoration: InputDecoration(
              labelText: 'File URL',
              border: const OutlineInputBorder(),
              contentPadding: const .symmetric(horizontal: 10, vertical: 8),
              suffixIcon: IconButton(
                key: const ValueKey<String>('dv-studio-media-copy-url'),
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy URL',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: file.url ?? file.key));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL copied to clipboard')),
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Actions
          OutlinedButton.icon(
            key: const ValueKey<String>('dv-studio-media-delete-button'),
            style: OutlinedButton.styleFrom(foregroundColor: colors.error),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete permanently'),
            onPressed: () => _deleteFile(file),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) => Padding(
        padding: const .symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: .start,
          children: <Widget>[
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
              ),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
}
