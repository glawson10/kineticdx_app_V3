// lib/features/patients/uploads/patient_uploads_tab.dart
//
// Uploads tab for patient detail: list active uploads, upload button, delete.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

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
  final Map<String, String> _memberNameCache = {};
  final Set<String> _memberNameLoading = {};
  Set<String> _selectedTags = {};

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
                          final uploaderName = _memberNameFor(u.createdByUid);
                          return _UploadTile(
                            key: ValueKey(u.id),
                            upload: u,
                            repo: _repo,
                            uploadedByLabel: uploaderName,
                            canWrite: widget.canWrite,
                            onOpen: () => _openViewer(context, u),
                            onEditNotes: () => _openEditNotesSheet(context, u),
                            onEditTags: () => _openEditTagsSheet(context, u),
                            onShare: () => _shareUpload(context, u),
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
              OutlinedButton.icon(
                onPressed: () => _openTagFilterSheet(context),
                icon: const Icon(Icons.local_offer_outlined, size: 18),
                label: Text(_tagFilterLabel()),
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
                      _sortDescending = key == _UploadSortKey.date ||
                          key == _UploadSortKey.size;
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

  String _tagFilterLabel() {
    final count = _selectedTags.length;
    if (count == 0) return 'Tags';
    return 'Tags ($count)';
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

    if (_selectedTags.isNotEmpty) {
      filtered = filtered.where((u) {
        final tags = u.tags.toSet();
        return _selectedTags.every(tags.contains);
      });
    }

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

  Future<void> _openTagFilterSheet(BuildContext context) async {
    final local = <String>{..._selectedTags};
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Filter by tags',
                          style: Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in kPatientUploadTags)
                          FilterChip(
                            label: Text(tag),
                            selected: local.contains(tag),
                            onSelected: (selected) {
                              setModalState(() {
                                if (selected) {
                                  local.add(tag);
                                } else {
                                  local.remove(tag);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: local.isEmpty
                              ? null
                              : () => setModalState(() => local.clear()),
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            setState(() => _selectedTags = local);
                            Navigator.pop(sheetContext);
                          },
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _memberNameFor(String? uid) {
    final clean = (uid ?? '').trim();
    if (clean.isEmpty) return '-';
    final cached = _memberNameCache[clean];
    if (cached != null) return cached;
    _fetchMemberName(clean);
    return clean;
  }

  Future<void> _fetchMemberName(String uid) async {
    if (_memberNameLoading.contains(uid)) return;
    _memberNameLoading.add(uid);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('clinics')
          .doc(widget.clinicId)
          .collection('members')
          .doc(uid)
          .get();
      final data = snap.data() ?? const <String, dynamic>{};
      final name = snap.exists ? _nameFromMemberData(data, uid) : uid;
      _memberNameCache[uid] = name;
      if (mounted) setState(() {});
    } catch (_) {
      _memberNameCache[uid] = uid;
      if (mounted) setState(() {});
    } finally {
      _memberNameLoading.remove(uid);
    }
  }

  String _nameFromMemberData(Map<String, dynamic> data, String uid) {
    final displayName = (data['displayName'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;
    final name = (data['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return uid;
  }

  void _openViewer(BuildContext context, PatientUpload u) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PatientUploadViewerScreen(
          clinicId: widget.clinicId,
          patientId: widget.patientId,
          upload: u,
          canDelete: widget.canWrite,
          canEditNotes: widget.canWrite,
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

  Future<void> _openEditNotesSheet(
    BuildContext context,
    PatientUpload upload,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to edit notes.')),
      );
      return;
    }

    final controller = TextEditingController(text: upload.notes);
    var saving = false;
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Edit notes',
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          hintText: 'Add notes...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    setModalState(() => saving = true);
                                    try {
                                      final notes = controller.text.trim();
                                      await _repo.updateNotes(
                                        clinicId: widget.clinicId,
                                        patientId: widget.patientId,
                                        uploadId: upload.id,
                                        notes: notes,
                                        updatedByUid: uid,
                                      );
                                      if (!mounted) return;
                                      Navigator.pop(sheetContext);
                                      messenger.showSnackBar(
                                        const SnackBar(
                                            content: Text('Notes saved.')),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      setModalState(() => saving = false);
                                      messenger.showSnackBar(
                                        SnackBar(
                                            content: Text('Save failed: $e')),
                                      );
                                    }
                                  },
                            icon: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: Text(saving ? 'Saving...' : 'Save notes'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _openEditTagsSheet(
    BuildContext context,
    PatientUpload upload,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to edit tags.')),
      );
      return;
    }

    final initial = <String>{...upload.tags};
    final selected = <String>{...upload.tags};
    var saving = false;
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final hasChanges = !_setEquals(selected, initial);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Edit tags',
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in kPatientUploadTags)
                            FilterChip(
                              label: Text(tag),
                              selected: selected.contains(tag),
                              onSelected: saving
                                  ? null
                                  : (value) {
                                      setModalState(() {
                                        if (value) {
                                          selected.add(tag);
                                        } else {
                                          selected.remove(tag);
                                        }
                                      });
                                    },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: (!hasChanges || saving)
                                ? null
                                : () async {
                                    setModalState(() => saving = true);
                                    try {
                                      await _repo.updateTags(
                                        clinicId: widget.clinicId,
                                        patientId: widget.patientId,
                                        uploadId: upload.id,
                                        tags: selected.toList(),
                                        updatedByUid: uid,
                                      );
                                      if (!mounted) return;
                                      Navigator.pop(sheetContext);
                                      messenger.showSnackBar(
                                        const SnackBar(
                                            content: Text('Tags saved.')),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      setModalState(() => saving = false);
                                      messenger.showSnackBar(
                                        SnackBar(
                                            content: Text('Save failed: $e')),
                                      );
                                    }
                                  },
                            icon: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: Text(saving ? 'Saving...' : 'Save tags'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  Future<void> _shareUpload(
    BuildContext context,
    PatientUpload upload,
  ) async {
    final ok = await _confirmShare(context);
    if (ok != true) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing share...')),
      );
      final bytes = await _repo.getBytes(storagePath: upload.storagePath);
      final dir = await getTemporaryDirectory();
      final ext = upload.fileName.contains('.')
          ? upload.fileName.split('.').last
          : (upload.isPdf ? 'pdf' : 'bin');
      final file = File('${dir.path}/share_${upload.id}.$ext');
      await file.writeAsBytes(bytes);
      if (!context.mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Patient document: ${upload.fileName}',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  Future<bool?> _confirmShare(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Share clinical information'),
        content: const Text(
          'Sharing patient documents outside the clinic may violate privacy. '
          'Only share when appropriate and with proper consent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
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

enum _UploadMenuAction { open, editNotes, editTags, share, delete }

class _UploadTile extends StatelessWidget {
  final PatientUpload upload;
  final PatientUploadsRepository repo;
  final String uploadedByLabel;
  final bool canWrite;
  final VoidCallback onOpen;
  final VoidCallback onEditNotes;
  final VoidCallback onEditTags;
  final VoidCallback onShare;
  final VoidCallback? onDelete;

  const _UploadTile({
    super.key,
    required this.upload,
    required this.repo,
    required this.uploadedByLabel,
    required this.canWrite,
    required this.onOpen,
    required this.onEditNotes,
    required this.onEditTags,
    required this.onShare,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        isThreeLine: true,
        leading: _UploadThumbnail(upload: upload, repo: repo),
        title: Text(
          upload.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _subtitleLine(),
            ),
            const SizedBox(height: 2),
            _notesPreview(context),
            _tagChips(context),
          ],
        ),
        onTap: onOpen,
        trailing: PopupMenuButton<_UploadMenuAction>(
          tooltip: 'More actions',
          onSelected: (action) {
            switch (action) {
              case _UploadMenuAction.open:
                onOpen();
                break;
              case _UploadMenuAction.editNotes:
                onEditNotes();
                break;
              case _UploadMenuAction.editTags:
                onEditTags();
                break;
              case _UploadMenuAction.share:
                onShare();
                break;
              case _UploadMenuAction.delete:
                onDelete?.call();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _UploadMenuAction.open,
              child: Row(
                children: const [
                  Icon(Icons.open_in_new, size: 18),
                  SizedBox(width: 8),
                  Text('Open'),
                ],
              ),
            ),
            if (canWrite)
              PopupMenuItem(
                value: _UploadMenuAction.editNotes,
                child: Row(
                  children: const [
                    Icon(Icons.edit_note, size: 18),
                    SizedBox(width: 8),
                    Text('Edit notes'),
                  ],
                ),
              ),
            if (canWrite)
              PopupMenuItem(
                value: _UploadMenuAction.editTags,
                child: Row(
                  children: const [
                    Icon(Icons.local_offer_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Edit tags'),
                  ],
                ),
              ),
            PopupMenuItem(
              value: _UploadMenuAction.share,
              child: Row(
                children: const [
                  Icon(Icons.share, size: 18),
                  SizedBox(width: 8),
                  Text('Share / Export'),
                ],
              ),
            ),
            if (onDelete != null)
              PopupMenuItem(
                value: _UploadMenuAction.delete,
                child: Row(
                  children: const [
                    Icon(Icons.delete_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Delete'),
                  ],
                ),
              ),
          ],
          child: const Icon(Icons.more_vert),
        ),
      ),
    );
  }

  String _subtitleLine() {
    final dateLabel =
        upload.createdAt != null ? _formatDate(upload.createdAt!) : '-';
    final by = uploadedByLabel.trim();
    final byLabel = (by.isEmpty || by == '-') ? '' : ' • by $by';
    return '${_formatSize(upload.sizeBytes)} • $dateLabel$byLabel';
  }

  Widget _notesPreview(BuildContext context) {
    final notes = upload.notes.trim();
    final theme = Theme.of(context);
    if (notes.isEmpty) {
      return Text(
        'Add notes...',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.hintColor,
        ),
      );
    }
    return Text(
      notes,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall,
    );
  }

  Widget _tagChips(BuildContext context) {
    final tags = upload.tags;
    if (tags.isEmpty) return const SizedBox.shrink();
    final visible = tags.take(2).toList();
    final extra = tags.length - visible.length;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final tag in visible) _tagChip(context, tag),
          if (extra > 0) _tagChip(context, '+$extra'),
        ],
      ),
    );
  }

  Widget _tagChip(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall,
      ),
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

class _UploadThumbnail extends StatefulWidget {
  final PatientUpload upload;
  final PatientUploadsRepository repo;

  const _UploadThumbnail({
    required this.upload,
    required this.repo,
  });

  @override
  State<_UploadThumbnail> createState() => _UploadThumbnailState();
}

class _UploadThumbnailState extends State<_UploadThumbnail> {
  static const double _size = 52;
  static const int _pdfPreviewMaxBytes = 2 * 1024 * 1024;

  Uint8List? _imageBytes;
  Uint8List? _pdfPreviewBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _UploadThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upload.storagePath != widget.upload.storagePath ||
        oldWidget.upload.contentType != widget.upload.contentType) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.upload.isImage && !widget.upload.isPdf) {
      setState(() {
        _imageBytes = null;
        _pdfPreviewBytes = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _imageBytes = null;
      _pdfPreviewBytes = null;
    });

    if (_skipPdfPreview) {
      setState(() {
        _loading = false;
      });
      return;
    }

    final maxBytes =
        widget.upload.isPdf ? _pdfPreviewMaxBytes : 5 * 1024 * 1024;
    final bytes = await widget.repo.getThumbnailBytes(
      storagePath: widget.upload.storagePath,
      maxBytes: maxBytes,
    );
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _loading = false;
      });
      return;
    }

    if (widget.upload.isPdf) {
      final preview = await _renderPdfPreview(bytes);
      if (!mounted) return;
      setState(() {
        _pdfPreviewBytes = preview;
        _loading = false;
      });
      return;
    }

    setState(() {
      _imageBytes = bytes;
      _loading = false;
    });
  }

  Future<Uint8List?> _renderPdfPreview(Uint8List bytes) async {
    PdfDocument? doc;
    PdfPage? page;
    try {
      doc = await PdfDocument.openData(bytes);
      page = await doc.getPage(1);
      const double targetWidth = 120.0;
      final scale = targetWidth / page.width;
      final double targetHeight = page.height * scale;
      final pageImage = await page.render(
        width: targetWidth,
        height: targetHeight,
        format: PdfPageImageFormat.png,
      );
      return pageImage?.bytes;
    } catch (_) {
      return null;
    } finally {
      try {
        await page?.close();
      } catch (_) {}
      try {
        await doc?.close();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_skipPdfPreview) {
      return _fallbackThumb(
        context,
        icon: Icons.picture_as_pdf,
        badge: 'PDF',
      );
    }
    if (_loading) {
      return _loadingThumb(context);
    }
    if (widget.upload.isImage && _imageBytes != null) {
      return _imageThumb(_imageBytes!);
    }
    if (widget.upload.isPdf && _pdfPreviewBytes != null) {
      return _imageThumb(_pdfPreviewBytes!);
    }

    if (widget.upload.isPdf) {
      return _fallbackThumb(
        context,
        icon: Icons.picture_as_pdf,
        badge: 'PDF',
      );
    }
    if (widget.upload.isImage) {
      return _fallbackThumb(
        context,
        icon: Icons.image,
        badge: _extBadge(widget.upload.fileName),
      );
    }
    return _fallbackThumb(
      context,
      icon: Icons.insert_drive_file,
      badge: _extBadge(widget.upload.fileName),
    );
  }

  Widget _imageThumb(Uint8List bytes) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackThumb(
          context,
          icon: Icons.broken_image,
          badge: _extBadge(widget.upload.fileName),
        ),
      ),
    );
  }

  Widget _loadingThumb(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  bool get _skipPdfPreview =>
      widget.upload.isPdf && widget.upload.sizeBytes > _pdfPreviewMaxBytes;

  Widget _fallbackThumb(
    BuildContext context, {
    required IconData icon,
    required String badge,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 26,
            ),
          ),
          if (badge.isNotEmpty)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _extBadge(String fileName) {
    final lower = fileName.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot == -1 || dot == lower.length - 1) return '';
    final ext = lower.substring(dot + 1);
    if (ext.length > 4) return ext.substring(0, 4).toUpperCase();
    return ext.toUpperCase();
  }
}
