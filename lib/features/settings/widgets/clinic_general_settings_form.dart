// Shared clinic profile / general settings form (name, logo, contact, public links, locale).
// Used by Settings → Clinic → General and by Clinic profile edit screen.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/clinic_repository.dart';

class ClinicGeneralSettingsForm extends StatefulWidget {
  const ClinicGeneralSettingsForm({
    super.key,
    required this.clinicId,
    this.showSaveButton = true,
  });

  final String clinicId;
  /// When true, shows a Save button at the bottom. When false, caller provides Save (e.g. in AppBar).
  final bool showSaveButton;

  @override
  State<ClinicGeneralSettingsForm> createState() =>
      _ClinicGeneralSettingsFormState();
}

class _ClinicGeneralSettingsFormState extends State<ClinicGeneralSettingsForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _logoUrlCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _websiteUrlCtrl;
  late final TextEditingController _landingUrlCtrl;
  late final TextEditingController _whatsappCtrl;

  String _timezone = 'Europe/Prague';
  String _defaultLanguage = 'en';
  int _sessionTimeoutMinutes = 120;

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

  static const _sessionTimeoutOptions = <int>[30, 60, 120, 180, 240];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _logoUrlCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _websiteUrlCtrl = TextEditingController();
    _landingUrlCtrl = TextEditingController();
    _whatsappCtrl = TextEditingController();
  }

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

    final settings = (data['settings'] is Map)
        ? Map<String, dynamic>.from(data['settings'] as Map)
        : <String, dynamic>{};
    final timeout =
        pick('sessionTimeoutMinutes') ?? settings['sessionTimeoutMinutes'];
    final timeoutInt = timeout is int && _sessionTimeoutOptions.contains(timeout)
        ? timeout
        : 120;

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
      'sessionTimeoutMinutes': timeoutInt,
    };
  }

  bool _looksLikeUrl(String v) {
    final s = v.trim();
    if (s.isEmpty) return true;
    final u = s.toLowerCase();
    if (u.contains(' ')) return false;
    return u.startsWith('http://') ||
        u.startsWith('https://') ||
        u.contains('.');
  }

  bool _looksLikePhoneOrWhatsapp(String v) {
    final s = v.trim();
    if (s.isEmpty) return true;
    final lower = s.toLowerCase();
    if (lower.startsWith('https://wa.me/') ||
        lower.startsWith('http://wa.me/')) {
      return true;
    }
    if (lower.startsWith('https://') || lower.startsWith('http://')) {
      return true;
    }
    return RegExp(r'^\+?[0-9\s\-\(\)]{6,20}$').hasMatch(s);
  }

  String? _normalizeUrlOrNull(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final lower = v.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return v;
    }
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
        withData: true,
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

  Future<void> _save(ClinicRepository repo) async {
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
        'address':
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'phone':
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'email':
            _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'landingUrl': _normalizeUrlOrNull(_landingUrlCtrl.text),
        'websiteUrl': _normalizeUrlOrNull(_websiteUrlCtrl.text),
        'whatsapp': _normalizeWhatsappOrNull(_whatsappCtrl.text),
        'timezone': _timezone,
        'defaultLanguage': _defaultLanguage,
        'sessionTimeoutMinutes': _sessionTimeoutMinutes,
      };

      await repo.updateClinicProfile(clinicId: widget.clinicId, patch: patch);

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
    final repo = context.read<ClinicRepository>();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.watchClinic(widget.clinicId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
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
          final timeout = p['sessionTimeoutMinutes'];
          if (timeout is int && _sessionTimeoutOptions.contains(timeout)) {
            _sessionTimeoutMinutes = timeout;
          }
        }

        final busy = _saving || _uploadingLogo;

        return Form(
          key: _formKey,
          onChanged: _markDirty,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Clinic profile
              Text(
                'Clinic profile',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Name and address shown in admin and (optionally) on the public portal.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Clinic name',
                  hintText: 'Required',
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Clinic name is required';
                  if (value.length > 80) return 'Max 80 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                  alignLabelWithHint: true,
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 24),
              // Branding
              Text(
                'Branding',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Logo appears on the public portal (home, price list, booking).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                        helperText: 'Paste a URL or upload an image.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ElevatedButton.icon(
                      onPressed: busy ? null : () => _uploadLogo(widget.clinicId),
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

              const SizedBox(height: 24),
              // Contact (internal)
              Text(
                'Contact (internal)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Phone and email for display and admin. Public contact links below drive what patients see.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return null;
                  final looksValid =
                      value.contains('@') && value.contains('.');
                  if (!looksValid) return 'Enter a valid email';
                  if (value.length > 254) return 'Max 254 characters';
                  return null;
                },
              ),

              const SizedBox(height: 24),
              // Public contact links
              Text(
                'Public contact links',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'These appear as icons on the public portal (home, price list, booking). Leave blank to hide an icon.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                  if (value.length > 2048) return 'Max 2048 characters';
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
                  if (value.length > 2048) return 'Max 2048 characters';
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
                  if (value.length > 256) return 'Max 256 characters';
                  if (!_looksLikePhoneOrWhatsapp(value)) {
                    return 'Enter +countrycode number or a WhatsApp link';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),
              // Locale & behaviour
              Text(
                'Locale & behaviour',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _languages.contains(_defaultLanguage)
                    ? _defaultLanguage
                    : 'en',
                items: _languages
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
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
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _sessionTimeoutOptions.contains(_sessionTimeoutMinutes)
                    ? _sessionTimeoutMinutes
                    : 120,
                items: _sessionTimeoutOptions
                    .map((m) => DropdownMenuItem<int>(
                          value: m,
                          child: Text(
                            m == 60
                                ? '1 hour'
                                : m == 120
                                    ? '2 hours (default)'
                                    : m == 180
                                        ? '3 hours'
                                        : m == 240
                                            ? '4 hours'
                                            : '$m minutes',
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _sessionTimeoutMinutes = v;
                    _dirty = true;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Session timeout',
                  helperText:
                      'Users are signed out after this period with no activity.',
                ),
              ),

              if (widget.showSaveButton) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: (!_dirty || busy)
                      ? null
                      : () => _save(repo),
                  icon: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
