// lib/features/patients/uploads/patient_uploads_tab.dart
//
// Uploads tab for patient detail: list active uploads, upload button, delete.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/repositories/patient_uploads_repository.dart';
import '../../../models/patient_upload.dart';
import 'patient_upload_viewer_screen.dart';

enum _UploadTypeFilter { all, images, pdfs, other }

enum _UploadSortKey { date, size, type }

class PatientUploadsTab extends StatefulWidget {
  final String clinicId;
  final String patientId;
  final bool canWrite;

  const PatientUploadsTab({
    super.key,
    required this.clinicId,
    required this.patientId,
    required this.canWrite,
  });

  @override
  State<PatientUploadsTab> createState() => _PatientUploadsTabState();
}

class _PatientUploadsTabState extends State<PatientUploadsTab> {
  final PatientUploadsRepository _repo = PatientUploadsRepository();

  String _searchQuery = '';
  _UploadTypeFilter _typeFilter = _UploadTypeFilter.all;
  _UploadSortKey _sortKey = _UploadSortKey.date;
  bool _sortDescending = true; // newest / largest first by default

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PatientUpload>>(
      stream: _repo.streamActiveUploads(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final uploads = _applyFiltersAndSort(snap.data!);
        return Scaffold(
          body: Column(
            children: [
              _buildToolbar(context),
              const Divider(height: 1),
              Expanded(
                child: uploads.isEmpty
                    ? const Center(
                        child: Text(
                          'No uploads match your filters.\nUse the Upload button to add documents or images.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: uploads.length,
                        itemBuilder: (context, index) {
                          final u = uploads[index];
                          return _UploadTile(
                            upload: u,
                            onTap: () => _openViewer(context, u),
                            onDelete: widget.canWrite
                                ? () => _confirmDelete(context, _repo, u)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: widget.canWrite
              ? FloatingActionButton(
                  onPressed: () => _pickAndUpload(context, _repo),
                  child: const Icon(Icons.upload_file),
                )
              : null,
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search uploads',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value.trim().toLowerCase());
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _typeFilter == _UploadTypeFilter.all,
                      onSelected: (_) {
                        setState(() => _typeFilter = _UploadTypeFilter.all);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Images'),
                      selected: _typeFilter == _UploadTypeFilter.images,
                      onSelected: (_) {
                        setState(() => _typeFilter = _UploadTypeFilter.images);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('PDFs'),
                      selected: _typeFilter == _UploadTypeFilter.pdfs,
                      onSelected: (_) {
                        setState(() => _typeFilter = _UploadTypeFilter.pdfs);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Other'),
                      selected: _typeFilter == _UploadTypeFilter.other,
                      onSelected: (_) {
                        setState(() => _typeFilter = _UploadTypeFilter.other);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_UploadSortKey>(
                tooltip: 'Sort uploads',
                onSelected: (key) {
                  setState(() {
                    if (_sortKey == key) {
                      // Toggle direction when clicking same key.
                      _sortDescending = !_sortDescending;
                    } else {
                      _sortKey = key;
                      // Sensible defaults per key.
                      _sortDescending =
                          key == _UploadSortKey.date || key == _UploadSortKey.size;
                    }
                  });
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _UploadSortKey.date,
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Date ${_sortKey == _UploadSortKey.date && _sortDescending ? '(newest)' : _sortKey == _UploadSortKey.date ? '(oldest)' : ''}',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _UploadSortKey.size,
                    child: Row(
                      children: [
                        const Icon(Icons.sd_storage, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Size ${_sortKey == _UploadSortKey.size && _sortDescending ? '(largest)' : _sortKey == _UploadSortKey.size ? '(smallest)' : ''}',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _UploadSortKey.type,
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Type ${_sortKey == _UploadSortKey.type && !_sortDescending ? '(A→Z)' : _sortKey == _UploadSortKey.type ? '(Z→A)' : ''}',
                        ),
                      ],
                    ),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort),
                    const SizedBox(width: 4),
                    Text(_sortLabel()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _sortLabel() {
    switch (_sortKey) {
      case _UploadSortKey.date:
        return _sortDescending ? 'Date (newest)' : 'Date (oldest)';
      case _UploadSortKey.size:
        return _sortDescending ? 'Size (largest)' : 'Size (smallest)';
      case _UploadSortKey.type:
        return _sortDescending ? 'Type (Z→A)' : 'Type (A→Z)';
    }
  }

  List<PatientUpload> _applyFiltersAndSort(List<PatientUpload> source) {
    Iterable<PatientUpload> filtered = source;

    // Text search: file name and uploader id.
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((u) {
        final name = u.fileName.toLowerCase();
        final by = (u.createdByUid ?? '').toLowerCase();
        return name.contains(_searchQuery) || by.contains(_searchQuery);
      });
    }

    // Type filter.
    filtered = filtered.where((u) {
      switch (_typeFilter) {
        case _UploadTypeFilter.all:
          return true;
        case _UploadTypeFilter.images:
          return u.isImage;
        case _UploadTypeFilter.pdfs:
          return u.isPdf;
        case _UploadTypeFilter.other:
          return !u.isImage && !u.isPdf;
      }
    });

    final list = filtered.toList();

    // Sort.
    list.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case _UploadSortKey.date:
          final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          cmp = ad.compareTo(bd);
          break;
        case _UploadSortKey.size:
          cmp = a.sizeBytes.compareTo(b.sizeBytes);
          break;
        case _UploadSortKey.type:
          final at = a.contentType.toLowerCase();
          final bt = b.contentType.toLowerCase();
          cmp = at.compareTo(bt);
          if (cmp == 0) {
            // Secondary by file name for stability.
            cmp = a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
          }
          break;
      }
      return _sortDescending ? -cmp : cmp;
    });

    return list;
  }

  void _openViewer(BuildContext context, PatientUpload u) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PatientUploadViewerScreen(
          clinicId: widget.clinicId,
          patientId: widget.patientId,
          upload: u,
          canDelete: widget.canWrite,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PatientUploadsRepository repo,
    PatientUpload u,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete upload?'),
        content: Text(
          'Remove "${u.fileName}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await repo.delete(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        uploadId: u.id,
        storagePath: u.storagePath,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload deleted.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    PatientUploadsRepository repo,
  ) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Files'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context, ''),
            ),
          ],
        ),
      ),
    );
    if (source == null || source.isEmpty) return;

    Uint8List? bytes;
    String? fileName;
    String? contentType;

    if (source == 'camera' || source == 'gallery') {
      final picker = ImagePicker();
      final XFile? file = source == 'camera'
          ? await picker.pickImage(source: ImageSource.camera)
          : await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      bytes = await file.readAsBytes();
      fileName = file.name;
      contentType = _contentTypeForFileName(fileName);
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
        ],
        withData: true,
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.single.bytes == null) return;
      final f = result.files.single;
      bytes = Uint8List.fromList(f.bytes!);
      fileName = f.name;
      contentType = _contentTypeForFileName(fileName);
    }

    if (fileName.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to upload.')),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading…')),
    );

    try {
      await repo.upload(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
        createdByUid: uid,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploaded.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  static String _contentTypeForFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }
}

class _UploadTile extends StatelessWidget {
  final PatientUpload upload;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _UploadTile({
    required this.upload,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _buildLeadingIcon(context),
        title: Text(upload.fileName),
        subtitle: Text(
          '${_formatSize(upload.sizeBytes)} • ${upload.createdAt != null ? _formatDate(upload.createdAt!) : '—'}'
          '${upload.createdByUid != null ? ' • by ${upload.createdByUid}' : ''}',
        ),
        onTap: onTap,
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              )
            : null,
      ),
    );
  }

  Widget _buildLeadingIcon(BuildContext context) {
    IconData icon;
    if (upload.isPdf) {
      icon = Icons.picture_as_pdf;
    } else if (upload.isImage) {
      icon = Icons.image;
    } else {
      icon = Icons.insert_drive_file;
    }

    return Icon(
      icon,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
