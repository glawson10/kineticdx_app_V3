import 'package:flutter/material.dart';
import 'package:kineticdx_app_v3/services/clinical_notes_service.dart';

class CreateNoteScreen extends StatefulWidget {
  const CreateNoteScreen({
    super.key,
    required this.clinicId,
    required this.episodeId,
    required this.patientId,
  });

  final String clinicId;
  final String episodeId;
  final String patientId;

  @override
  State<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends State<CreateNoteScreen> {
  final _service = ClinicalNotesService();
  bool _saving = false;

  Future<void> _saveNote() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      await _service.createClinicalNote(
        clinicId: widget.clinicId,
        episodeId: widget.episodeId,
        patientId: widget.patientId,
        payload: {
          'subjective': {'pain': 6},
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note saved')),
      );
      Navigator.of(context).pop(true); // return success to previous screen
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save note')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Clinical Note')),
      body: Center(
        child: ElevatedButton(
          onPressed: _saving ? null : _saveNote,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save note'),
        ),
      ),
    );
  }
}
