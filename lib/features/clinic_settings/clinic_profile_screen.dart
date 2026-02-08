// lib/features/clinic/settings/ui/clinic_profile_screen.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../app/clinic_context.dart';
import '../../../../data/repositories/clinic_repository.dart';

import 'clinic_closures_screen.dart';
import '../clinic_settings/audit/closure_override_audit_screen.dart';

// ✅ Opening hours UI
import '../clinic/settings/ui/clinic_opening_hours_screen.dart';

// ✅ Staff settings UI
import '../../staff/staff_settings_screen.dart';
import '../notes/ui/notes_settings_screen.dart';
import '../settings/ui/clinical_test_registry_screen.dart';
import '../settings/security_screen.dart';

/// Settings hub screen (inside Settings tab).
/// - Clinic profile (edit)
/// - Staff
/// - Closures
/// - Closure override audit
/// - Clinic opening hours
class ClinicProfileScreen extends StatelessWidget {
  const ClinicProfileScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute(builder: (_) => const ClinicProfileScreen());
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();

    if (!clinicCtx.hasClinic) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected.')),
      );
    }

    // ✅ Session may not be bootstrapped yet (avoid throwing)
    if (!clinicCtx.hasSession) {
      return Scaffold(
        appBar: AppBar(title: const Text('Clinic settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final clinicId = clinicCtx.clinicId;

    final session = clinicCtx.session;
    final canWriteSettings = session.permissions.has('settings.write');
    final canAudit = session.permissions.has('audit.read');
    final canViewNotes = session.permissions.viewClinical;
    final canManageNotes = session.permissions.settingsWrite;

    final canManageStaff = session.permissions.has('members.manage');
    final canReadMembers =
        session.permissions.has('members.read') || canManageStaff;

    return Scaffold(
      appBar: AppBar(title: const Text('Clinic settings')),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // ─────────────────────────────
          // Clinic profile
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Clinic profile'),
            subtitle: Text(
              canWriteSettings
                  ? 'Name, address, contact, timezone'
                  : 'No permission (settings.write required)',
            ),
            enabled: canWriteSettings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const _ClinicProfileEditScreen(),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Security (account-level MFA)
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Security'),
            subtitle: const Text('Two-step verification (MFA)'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SecurityScreen()),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Staff
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Staff'),
            subtitle: Text(
              canReadMembers
                  ? (canManageStaff
                      ? 'Invite, suspend, permissions'
                      : 'Read-only staff list')
                  : 'No permission (members.read required)',
            ),
            enabled: canReadMembers,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StaffSettingsScreen()),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Notes templates
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.note_outlined),
            title: const Text('Notes templates'),
            subtitle: Text(
              canViewNotes
                  ? (canManageNotes
                      ? 'View and manage templates'
                      : 'View templates (read-only)')
                  : 'No permission (clinical.read or notes.read required)',
            ),
            enabled: canViewNotes,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotesSettingsScreen(clinicId: clinicId),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Clinical test registry
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Clinical test registry'),
            subtitle: Text(
              canViewNotes
                  ? (canManageNotes
                      ? 'Manage objective/special tests for this clinic'
                      : 'View registry (read-only)')
                  : 'No permission (clinical.read or notes.read required)',
            ),
            enabled: canViewNotes,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ClinicalTestRegistryScreen(clinicId: clinicId),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Opening hours
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Clinic opening hours'),
            subtitle: Text(
              canWriteSettings
                  ? 'Set opening hours for each day (affects clinician + public booking)'
                  : 'No permission (settings.write required)',
            ),
            enabled: canWriteSettings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ClinicOpeningHoursScreen(clinicId: clinicId),
              ),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Closures
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text('Closures'),
            subtitle: Text(
              canWriteSettings
                  ? 'Manage closed hours / holidays'
                  : 'No permission (settings.write required)',
            ),
            enabled: canWriteSettings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ClinicClosuresScreen()),
            ),
          ),

          const Divider(height: 1),

          // ─────────────────────────────
          // Audit
          // ─────────────────────────────
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Closure override audit'),
            subtitle: Text(
              canAudit
                  ? 'View overrides + export'
                  : 'No permission (audit.read required)',
            ),
            enabled: canAudit,
            onTap: () => Navigator.of(context).push(
              ClosureOverrideAuditScreen.route(),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Profile editor screen (kept in same file to avoid import churn).
class _ClinicProfileEditScreen extends StatefulWidget {
  const _ClinicProfileEditScreen();

  @override
  State<_ClinicProfileEditScreen> createState() =>
      _ClinicProfileEditScreenState();
}

class _ClinicProfileEditScreenState extends State<_ClinicProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  // ✅ Public contact links (for top-right icons on public portal)
  final _websiteUrlCtrl = TextEditingController();
  final _landingUrlCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();

  String _timezone = 'Europe/Prague';
  String _defaultLanguage = 'en';

  bool _dirty = false;
  bool _saving = false;
  bool _uploadingLogo = false;

  static const _timezones = <String>[
    'Europe/Prague',
    'Europe/London',
    'Europe/Berlin',
    'Europe/Paris',
    'Europe/Warsaw',
    'Europe/Vienna',
    'Europe/Bratislava',
    'Europe/Budapest',
    'America/New_York',
    'America/Los_Angeles',
    'Australia/Sydney',
    'Pacific/Auckland',
  ];

  static const _languages = <String>['en', 'cs', 'de', 'fr', 'es'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _logoUrlCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();

    _websiteUrlCtrl.dispose();
    _landingUrlCtrl.dispose();
    _whatsappCtrl.dispose();

    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String _s(dynamic v) => (v ?? '').toString();

  Map<String, dynamic> _readProfileLike(Map<String, dynamic> data) {
    // Prefer root keys (new schema), fall back to legacy `profile` map.
    final profileMap = (data['profile'] is Map)
        ? Map<String, dynamic>.from(data['profile'] as Map)
        : <String, dynamic>{};

    dynamic pick(String key) {
      if (data.containsKey(key) && data[key] != null) return data[key];
      if (profileMap.containsKey(key) && profileMap[key] != null) {
        return profileMap[key];
      }
      return null;
    }

    return <String, dynamic>{
      'name': pick('name'),
      'logoUrl': pick('logoUrl'),
      'address': pick('address'),
      'phone': pick('phone'),
      'email': pick('email'),
      'websiteUrl': pick('websiteUrl'),
      'landingUrl': pick('landingUrl'),
      'whatsapp': pick('whatsapp'),
      'timezone': pick('timezone'),
      'defaultLanguage': pick('defaultLanguage'),
    };
  }

  bool _looksLikeUrl(String v) {
    final s = v.trim();
    if (s.isEmpty) return true;
    final u = s.toLowerCase();
    if (u.contains(' ')) return false;
    return u.startsWith('http://') || u.startsWith('https://') || u.contains('.');
  }

  bool _looksLikePhoneOrWhatsapp(String v) {
    final s = v.trim();
    if (s.isEmpty) return true;

    final lower = s.toLowerCase();
    if (lower.startsWith('https://wa.me/') || lower.startsWith('http://wa.me/')) {
      return true;
    }
    if (lower.startsWith('https://') || lower.startsWith('http://')) return true;

    return RegExp(r'^\+?[0-9\s\-\(\)]{6,20}$').hasMatch(s);
  }

  String? _normalizeUrlOrNull(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final lower = v.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return v;
    if (lower.contains('.')) return 'https://$v';
    return v;
  }

  String? _normalizeWhatsappOrNull(String raw) {
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }

  String _contentTypeForExt(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Widget _logoPreview(String url) {
    final u = url.trim();
    if (u.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 84,
          color: Colors.black12,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Image.network(
            u,
            height: 56,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Text('Logo URL invalid / failed to load'),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadLogo(String clinicId) async {
    if (_uploadingLogo) return;

    setState(() => _uploadingLogo = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // IMPORTANT for web
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        throw StateError(
          'No file bytes available (upload requires withData:true).',
        );
      }

      final ext = (file.extension ?? 'png').toLowerCase();
      final safeExt =
          (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp')
              ? ext
              : 'png';

      // ✅ clinic-scoped public branding path
      final path = 'clinics/$clinicId/public/branding/logo.$safeExt';
      final ref = FirebaseStorage.instance.ref(path);

      final meta = SettableMetadata(
        contentType: _contentTypeForExt(safeExt),
        cacheControl: 'public,max-age=3600',
      );

      await ref.putData(bytes, meta);

      final url = await ref.getDownloadURL();

      if (!mounted) return;
      setState(() {
        _logoUrlCtrl.text = url;
        _dirty = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logo uploaded (remember to Save)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logo upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save({
    required String clinicId,
    required ClinicRepository repo,
  }) async {
    if (_saving) return;

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'logoUrl': _logoUrlCtrl.text.trim().isEmpty
            ? null
            : _logoUrlCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty
            ? null
            : _emailCtrl.text.trim(),
        'landingUrl': _normalizeUrlOrNull(_landingUrlCtrl.text),
        'websiteUrl': _normalizeUrlOrNull(_websiteUrlCtrl.text),
        'whatsapp': _normalizeWhatsappOrNull(_whatsappCtrl.text),
        'timezone': _timezone,
        'defaultLanguage': _defaultLanguage,
      };

      await repo.updateClinicProfile(clinicId: clinicId, patch: patch);

      if (!mounted) return;
      setState(() => _dirty = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clinic profile saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicCtx = context.watch<ClinicContext>();
    if (!clinicCtx.hasClinic) {
      return const Scaffold(
        body: Center(child: Text('No clinic selected')),
      );
    }

    final clinicId = clinicCtx.clinicId;
    final repo = context.read<ClinicRepository>();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.watchClinic(clinicId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Clinic profile')),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final doc = snapshot.data!;
        final data = doc.data() ?? <String, dynamic>{};
        final p = _readProfileLike(data);

        if (!_dirty && !_saving && !_uploadingLogo) {
          _nameCtrl.text = _s(p['name']);
          _logoUrlCtrl.text = _s(p['logoUrl']);
          _addressCtrl.text = _s(p['address']);
          _phoneCtrl.text = _s(p['phone']);
          _emailCtrl.text = _s(p['email']);

          _websiteUrlCtrl.text = _s(p['websiteUrl']);
          _landingUrlCtrl.text = _s(p['landingUrl']);
          _whatsappCtrl.text = _s(p['whatsapp']);

          final tz = p['timezone'];
          if (tz is String && tz.isNotEmpty) _timezone = tz;

          final lang = p['defaultLanguage'];
          if (lang is String && lang.isNotEmpty) {
            _defaultLanguage = _languages.contains(lang) ? lang : 'en';
          }
        }

        final busy = _saving || _uploadingLogo;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Clinic profile'),
            actions: [
              TextButton.icon(
                onPressed: (!_dirty || busy)
                    ? null
                    : () => _save(clinicId: clinicId, repo: repo),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              onChanged: _markDirty,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Clinic name'),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'Clinic name is required';
                      if (value.length > 80) return 'Max 80 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  _logoPreview(_logoUrlCtrl.text),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _logoUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Logo URL (optional)',
                            helperText:
                                'You can paste a URL or upload an image.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ElevatedButton.icon(
                          onPressed: busy ? null : () => _uploadLogo(clinicId),
                          icon: _uploadingLogo
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload),
                          label: const Text('Upload'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Address (optional)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Phone (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Email (optional)'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return null;
                      final looksValid =
                          value.contains('@') && value.contains('.');
                      if (!looksValid) return 'Enter a valid email';
                      if (value.length > 120) return 'Max 120 characters';
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    'Public contact links',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These show as icons on the public portal (top-right). Leave blank to hide an icon.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _landingUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Landing page URL (optional)',
                      helperText: 'If set, the globe icon opens this first.',
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return null;
                      if (!_looksLikeUrl(value)) return 'Enter a valid URL';
                      if (value.length > 240) return 'Max 240 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _websiteUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Website URL (optional)',
                      helperText: 'Used if Landing URL is blank.',
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return null;
                      if (!_looksLikeUrl(value)) return 'Enter a valid URL';
                      if (value.length > 240) return 'Max 240 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _whatsappCtrl,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp / phone (optional)',
                      helperText:
                          'Preferred: +420... (E.164). Or paste a wa.me link.',
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return null;
                      if (value.length > 120) return 'Max 120 characters';
                      if (!_looksLikePhoneOrWhatsapp(value)) {
                        return 'Enter +countrycode number or a WhatsApp link';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Locale',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _languages.contains(_defaultLanguage)
                        ? _defaultLanguage
                        : 'en',
                    items: _languages
                        .map((l) =>
                            DropdownMenuItem(value: l, child: Text(l)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _defaultLanguage = v;
                        _dirty = true;
                      });
                    },
                    decoration:
                        const InputDecoration(labelText: 'Default language'),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Timezone',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _timezones.contains(_timezone)
                        ? _timezone
                        : 'Europe/Prague',
                    items: _timezones
                        .map((tz) =>
                            DropdownMenuItem(value: tz, child: Text(tz)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _timezone = v;
                        _dirty = true;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Clinic timezone (IANA)',
                      helperText:
                          'Used for appointment display and booking rules.',
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    'Clinic ID: $clinicId',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
