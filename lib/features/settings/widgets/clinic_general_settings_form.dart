// Shared clinic profile / general settings form (name, logo, contact, public links, locale).
// Used by Settings → Clinic → General and by Clinic profile edit screen.
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/clinic_repository.dart';
import '../../../../ui/design_tokens.dart';
import 'general_settings_section_card.dart';

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
  late final TextEditingController _currencyCtrl;
  late final TextEditingController _terminologyCtrl;
  late final TextEditingController _adminContactFirstNameCtrl;
  late final TextEditingController _adminContactLastNameCtrl;
  late final TextEditingController _adminContactEmailCtrl;
  late final TextEditingController _replyToEmailCtrl;

  String _timezone = 'Europe/Prague';
  String _defaultLanguage = 'en';
  int _sessionTimeoutMinutes = 120;
  bool _require2FA = false;

  bool _dirty = false;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _showSavedFeedback = false;
  Timer? _savedFeedbackTimer;
  /// After save, avoid overwriting logo from a stale stream snapshot.
  String? _lastSavedLogoUrl;

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
    _currencyCtrl = TextEditingController();
    _terminologyCtrl = TextEditingController();
    _adminContactFirstNameCtrl = TextEditingController();
    _adminContactLastNameCtrl = TextEditingController();
    _adminContactEmailCtrl = TextEditingController();
    _replyToEmailCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _savedFeedbackTimer?.cancel();
    _nameCtrl.dispose();
    _logoUrlCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _websiteUrlCtrl.dispose();
    _landingUrlCtrl.dispose();
    _whatsappCtrl.dispose();
    _currencyCtrl.dispose();
    _terminologyCtrl.dispose();
    _adminContactFirstNameCtrl.dispose();
    _adminContactLastNameCtrl.dispose();
    _adminContactEmailCtrl.dispose();
    _replyToEmailCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
    _lastSavedLogoUrl = null;
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
      'currency': pick('currency'),
      'terminology': pick('terminology'),
      'adminContactFirstName': pick('adminContactFirstName'),
      'adminContactLastName': pick('adminContactLastName'),
      'adminContactEmail': pick('adminContactEmail'),
      'replyToEmail': pick('replyToEmail'),
      'require2FA': pick('require2FA'),
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

  /// Compact logo preview (72–96px). Placeholder when no URL.
  Widget _compactLogoPreview(BuildContext context, String url) {
    const height = 80.0;
    final theme = Theme.of(context);
    final u = url.trim();

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: u.isEmpty
              ? Row(
                  children: [
                    Icon(Icons.image_outlined, size: 28, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(
                      'No logo',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              : Image.network(
                  u,
                  height: 56,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    'Invalid or failed to load',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
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
        'currency': _currencyCtrl.text.trim().isEmpty ? null : _currencyCtrl.text.trim(),
        'terminology': _terminologyCtrl.text.trim().isEmpty ? null : _terminologyCtrl.text.trim(),
        'adminContactFirstName': _adminContactFirstNameCtrl.text.trim().isEmpty ? null : _adminContactFirstNameCtrl.text.trim(),
        'adminContactLastName': _adminContactLastNameCtrl.text.trim().isEmpty ? null : _adminContactLastNameCtrl.text.trim(),
        'adminContactEmail': _adminContactEmailCtrl.text.trim().isEmpty ? null : _adminContactEmailCtrl.text.trim().toLowerCase(),
        'replyToEmail': _replyToEmailCtrl.text.trim().isEmpty ? null : _replyToEmailCtrl.text.trim().toLowerCase(),
        'require2FA': _require2FA,
      };

      await repo.updateClinicProfile(clinicId: widget.clinicId, patch: patch);

      if (!mounted) return;
      final savedLogo = patch['logoUrl'] is String ? (patch['logoUrl'] as String).trim() : '';
      setState(() {
        _dirty = false;
        _lastSavedLogoUrl = savedLogo.isEmpty ? null : savedLogo;
        if (savedLogo.isNotEmpty) _logoUrlCtrl.text = savedLogo;
      });
      _savedFeedbackTimer?.cancel();
      setState(() => _showSavedFeedback = true);
      _savedFeedbackTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _showSavedFeedback = false);
      });
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
    if (widget.clinicId.trim().isEmpty) {
      return const Center(child: Text('No clinic selected.'));
    }
    final repo = context.read<ClinicRepository>();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: repo.watchClinic(widget.clinicId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load clinic settings.',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final doc = snapshot.data!;
        final data = doc.data() ?? <String, dynamic>{};
        final p = _readProfileLike(data);

        if (!_dirty && !_saving && !_uploadingLogo) {
          _nameCtrl.text = _s(p['name']);
          final streamLogo = _s(p['logoUrl']);
          if (_lastSavedLogoUrl != null && streamLogo != _lastSavedLogoUrl) {
            // Stale stream: don't overwrite with old logo after a successful save.
          } else {
            _logoUrlCtrl.text = streamLogo;
            _lastSavedLogoUrl = null;
          }
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
          _currencyCtrl.text = _s(p['currency']);
          _terminologyCtrl.text = _s(p['terminology']);
          _adminContactFirstNameCtrl.text = _s(p['adminContactFirstName']);
          _adminContactLastNameCtrl.text = _s(p['adminContactLastName']);
          _adminContactEmailCtrl.text = _s(p['adminContactEmail']);
          _replyToEmailCtrl.text = _s(p['replyToEmail']);
          final r2fa = p['require2FA'];
          if (r2fa is bool) _require2FA = r2fa;
        }

        final busy = _saving || _uploadingLogo;
        final theme = Theme.of(context);
        final showSaveBar = widget.showSaveButton && (_dirty || _saving || _showSavedFeedback);

        final inputTheme = theme.inputDecorationTheme.copyWith(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          focusColor: theme.colorScheme.primary,
          helperStyle: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          errorStyle: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.error,
          ),
        );

        return Form(
          key: _formKey,
          onChanged: _markDirty,
          child: Theme(
            data: theme.copyWith(inputDecorationTheme: inputTheme),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding,
                    vertical: AppSpacing.lg,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSizes.generalSettingsMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GeneralSettingsSectionCard(
                            title: 'Clinic identity',
                            description: 'Basic clinic details shown internally and, where enabled, on the public portal.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                TextFormField(
                                  controller: _addressCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Address (optional)',
                                    alignLabelWithHint: true,
                                  ),
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          GeneralSettingsSectionCard(
                            title: 'Branding',
                            description: 'Logo and visual assets used in the public portal and booking surfaces.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _compactLogoPreview(context, _logoUrlCtrl.text),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                Row(
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
                                    _UploadButton(
                                      busy: busy,
                                      uploading: _uploadingLogo,
                                      onUpload: () => _uploadLogo(widget.clinicId),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          GeneralSettingsSectionCard(
                            title: 'Internal contact',
                            description: 'Internal contact details used for administration.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextFormField(
                                  controller: _phoneCtrl,
                                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                TextFormField(
                                  controller: _emailCtrl,
                                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    final value = (v ?? '').trim();
                                    if (value.isEmpty) return null;
                                    final looksValid = value.contains('@') && value.contains('.');
                                    if (!looksValid) return 'Enter a valid email';
                                    if (value.length > 254) return 'Max 254 characters';
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          GeneralSettingsSectionCard(
                            title: 'Public contact links',
                            description: 'These links appear on public-facing booking and portal screens when provided.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
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
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                TextFormField(
                                  controller: _whatsappCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'WhatsApp / phone (optional)',
                                    helperText: 'Preferred: +420... (E.164). Or paste a wa.me link.',
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
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          GeneralSettingsSectionCard(
                            title: 'Locale & behaviour',
                            description: 'Controls language, timezone, and default session behaviour.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: _languages.contains(_defaultLanguage) ? _defaultLanguage : _languages.first,
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
                                  decoration: const InputDecoration(labelText: 'Default language'),
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                DropdownButtonFormField<String>(
                                  initialValue: _timezones.contains(_timezone) ? _timezone : _timezones.first,
                                  items: _timezones
                                      .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
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
                                    helperText: 'Used for appointment display and booking rules.',
                                  ),
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
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
                                    helperText: 'Users are signed out after this period with no activity.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          GeneralSettingsSectionCard(
                            title: 'Admin contact',
                            description: 'Primary contact for the clinic (e.g. for support or compliance). If you set any field, all three are required.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextFormField(
                                  controller: _adminContactFirstNameCtrl,
                                  decoration: const InputDecoration(labelText: 'Admin first name (optional)'),
                                  textCapitalization: TextCapitalization.words,
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                TextFormField(
                                  controller: _adminContactLastNameCtrl,
                                  decoration: const InputDecoration(labelText: 'Admin last name (optional)'),
                                  textCapitalization: TextCapitalization.words,
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                TextFormField(
                                  controller: _adminContactEmailCtrl,
                                  decoration: const InputDecoration(labelText: 'Admin email (optional)'),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    final first = _adminContactFirstNameCtrl.text.trim();
                                    final last = _adminContactLastNameCtrl.text.trim();
                                    final email = (v ?? '').trim();
                                    if (first.isEmpty && last.isEmpty && email.isEmpty) return null;
                                    if (first.isEmpty || last.isEmpty) return 'When admin contact is set, first name, last name and email are all required.';
                                    if (email.isEmpty) return 'Admin email is required when first/last name are set.';
                                    if (!email.contains('@') || !email.contains('.')) return 'Enter a valid email.';
                                    if (email.length > 254) return 'Max 254 characters.';
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          GeneralSettingsSectionCard(
                            title: 'Policy & billing',
                            description: 'Currency, terminology, and email used for outgoing messages. Require 2FA is a policy setting (enforcement may be configured separately).',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextFormField(
                                  controller: _currencyCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Currency (optional)',
                                    hintText: 'e.g. EUR, GBP, CZK',
                                  ),
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                TextFormField(
                                  controller: _terminologyCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Terminology (optional)',
                                    hintText: 'e.g. patient, client',
                                  ),
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                TextFormField(
                                  controller: _replyToEmailCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Reply-to email (optional)',
                                    helperText: 'Used as reply-to for outgoing emails.',
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (v) {
                                    final value = (v ?? '').trim();
                                    if (value.isEmpty) return null;
                                    if (!value.contains('@') || !value.contains('.')) return 'Enter a valid email.';
                                    if (value.length > 254) return 'Max 254 characters.';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: GeneralSettingsSectionCard.fieldGap),
                                SwitchListTile(
                                  title: const Text('Require 2FA'),
                                  subtitle: const Text(
                                    'Policy setting for two-factor authentication. Enforcement may be configured separately.',
                                  ),
                                  value: _require2FA,
                                  onChanged: (v) => setState(() {
                                    _require2FA = v;
                                    _markDirty();
                                  }),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 96),
                        ],
                      ),
                    ),
                  ),
                ),
                if (showSaveBar)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _DirtySaveBar(
                      isDirty: _dirty,
                      isSaving: _saving,
                      showSavedFeedback: _showSavedFeedback,
                      onCancel: () => setState(() => _dirty = false),
                      onSave: () => _save(repo),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UploadButton extends StatelessWidget {
  const _UploadButton({
    required this.busy,
    required this.uploading,
    required this.onUpload,
  });

  final bool busy;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onUpload,
      icon: uploading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload, size: 20),
      label: const Text('Upload'),
    );
  }
}

class _DirtySaveBar extends StatelessWidget {
  const _DirtySaveBar({
    required this.isDirty,
    required this.isSaving,
    required this.showSavedFeedback,
    required this.onCancel,
    required this.onSave,
  });

  final bool isDirty;
  final bool isSaving;
  final bool showSavedFeedback;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: AppShadows.saveBarTop,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (showSavedFeedback) ...[
              Icon(Icons.check_circle_outline, size: 20, color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                'Saved',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ] else ...[
              Text(
                'Unsaved changes',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: isSaving ? null : onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (!isDirty || isSaving) ? null : onSave,
                icon: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 20),
                label: const Text('Save'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
