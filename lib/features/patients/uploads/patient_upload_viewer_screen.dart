// lib/features/patients/uploads/patient_upload_viewer_screen.dart
//
// View PDF or image with zoom; share (with warning) and delete.

import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import '../../../data/repositories/patient_uploads_repository.dart';
import '../../../models/patient_upload.dart';

class PatientUploadViewerScreen extends StatefulWidget {
  final String clinicId;
  final String patientId;
  final PatientUpload upload;
  final bool canDelete;
  final bool canEditNotes;

  const PatientUploadViewerScreen({
    super.key,
    required this.clinicId,
    required this.patientId,
    required this.upload,
    required this.canDelete,
    required this.canEditNotes,
  });

  @override
  State<PatientUploadViewerScreen> createState() =>
      _PatientUploadViewerScreenState();
}

class _PatientUploadViewerScreenState extends State<PatientUploadViewerScreen> {
  final PatientUploadsRepository _repo = PatientUploadsRepository();
  final TextEditingController _notesCtl = TextEditingController();
  String _lastSavedNotes = '';
  bool _savingNotes = false;
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _notesCtl.text = widget.upload.notes;
    _lastSavedNotes = widget.upload.notes.trim();
    _notesCtl.addListener(_onNotesChanged);
    _load();
  }

  @override
  void dispose() {
    _notesCtl.removeListener(_onNotesChanged);
    _notesCtl.dispose();
    super.dispose();
  }

  void _onNotesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final bytes =
          await _repo.getBytes(storagePath: widget.upload.storagePath);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.upload.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: _bytes != null ? _share : null,
          ),
          if (widget.canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Expanded(child: _buildPreview()),
        const Divider(height: 1),
        _buildDetailsPanel(),
      ],
    );
  }

  Widget _buildPreview() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load file: $_error'),
        ),
      );
    }
    if (_bytes == null) {
      return const Center(child: Text('No file data available.'));
    }
    final bytes = _bytes!;
    if (widget.upload.isPdf) {
      return _PdfView(bytes: bytes);
    }
    if (widget.upload.isImage) {
      return _ImageView(bytes: bytes);
    }
    return const Center(
      child: Text('Preview not available for this file type.'),
    );
  }

  Widget _buildDetailsPanel() {
    final createdAt = widget.upload.createdAt;
    final createdLabel = createdAt != null ? _formatDateTime(createdAt) : '-';
    final canEdit = widget.canEditNotes;
    final notesHint = canEdit ? 'Add notes...' : 'No notes';

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Details',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _detailRow('File', Text(widget.upload.fileName)),
                _detailRow('Uploaded', Text(createdLabel)),
                _detailRow('Uploaded by', Text(_uploadedByLabel())),
                if (!widget.upload.isPdf && !widget.upload.isImage) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _bytes != null ? _share : null,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Download / Share'),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Notes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _notesCtl,
                  minLines: 3,
                  maxLines: 6,
                  readOnly: !canEdit,
                  decoration: InputDecoration(
                    hintText: notesHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed:
                        (!_notesDirty || _savingNotes) ? null : _saveNotes,
                    icon: _savingNotes
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_savingNotes ? 'Saving...' : 'Save notes'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, Widget value) {
    final labelStyle = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: Theme.of(context).hintColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: Text(label, style: labelStyle)),
          const SizedBox(width: 8),
          Expanded(child: value),
        ],
      ),
    );
  }

  String _uploadedByLabel() {
    final createdBy = widget.upload.createdByUid;
    if (createdBy == null || createdBy.trim().isEmpty) return '-';
    final current = FirebaseAuth.instance.currentUser;
    if (current != null && current.uid == createdBy) {
      final displayName = (current.displayName ?? '').trim();
      return displayName.isNotEmpty ? displayName : 'You';
    }
    return createdBy;
  }

  String _formatDateTime(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $h:$min';
  }

  bool get _notesDirty => _notesValue != _lastSavedNotes;

  String get _notesValue => _notesCtl.text.trim();

  Future<void> _saveNotes() async {
    if (_savingNotes || !widget.canEditNotes) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to edit notes.')),
      );
      return;
    }
    setState(() => _savingNotes = true);
    try {
      final notes = _notesValue;
      await _repo.updateNotes(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        uploadId: widget.upload.id,
        notes: notes,
        updatedByUid: uid,
      );
      if (!mounted) return;
      setState(() {
        _lastSavedNotes = notes;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notes saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  Future<void> _share() async {
    final ok = await showDialog<bool>(
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
    if (ok != true || !mounted) return;

    try {
      final dir = await getTemporaryDirectory();
      final ext = widget.upload.fileName.contains('.')
          ? widget.upload.fileName.split('.').last
          : (widget.upload.isPdf ? 'pdf' : 'bin');
      final file = File('${dir.path}/share_${widget.upload.id}.$ext');
      await file.writeAsBytes(_bytes!);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Patient document: ${widget.upload.fileName}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete upload?'),
        content: Text(
          'Remove "${widget.upload.fileName}"? This cannot be undone.',
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
    if (ok != true || !mounted) return;
    try {
      await _repo.delete(
        clinicId: widget.clinicId,
        patientId: widget.patientId,
        uploadId: widget.upload.id,
        storagePath: widget.upload.storagePath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload deleted.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }
}

class _PdfView extends StatefulWidget {
  final Uint8List bytes;

  const _PdfView({required this.bytes});

  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView> {
  PdfControllerPinch? _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.bytes),
      initialPage: 1,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return const Center(child: Text('No PDF'));
    return PdfViewPinch(
      controller: _controller!,
      scrollDirection: Axis.vertical,
    );
  }
}

class _ImageView extends StatelessWidget {
  final Uint8List bytes;

  const _ImageView({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image, size: 48),
        ),
      ),
    );
  }
}
