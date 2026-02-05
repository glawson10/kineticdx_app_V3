// lib/features/patients/uploads/patient_upload_viewer_screen.dart
//
// View PDF or image with zoom; share (with warning) and delete.

import 'dart:io';
import 'dart:typed_data';

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

  const PatientUploadViewerScreen({
    super.key,
    required this.clinicId,
    required this.patientId,
    required this.upload,
    required this.canDelete,
  });

  @override
  State<PatientUploadViewerScreen> createState() =>
      _PatientUploadViewerScreenState();
}

class _PatientUploadViewerScreenState extends State<PatientUploadViewerScreen> {
  final PatientUploadsRepository _repo = PatientUploadsRepository();
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
