import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/repositories/public_booking_mirror_repository.dart';

/// Contact strip for public booking (website, email, WhatsApp, phone).
/// When [clinicId] is set, loads contact from the public booking mirror and
/// shows the same actions as the intro screen. When [phone]/[email]/[website]
/// are passed directly, uses those instead (no mirror).
class PublicContactActions extends StatelessWidget {
  const PublicContactActions({
    super.key,
    this.phone,
    this.email,
    this.website,
    this.clinicId,
    this.debugWhenEmpty = false,
  });

  final String? phone;
  final String? email;
  final String? website;
  final String? clinicId;
  final bool debugWhenEmpty;

  @override
  Widget build(BuildContext context) {
    if (clinicId != null && clinicId!.trim().isNotEmpty) {
      return _PublicContactActionsFromMirror(
        clinicId: clinicId!.trim(),
        debugWhenEmpty: debugWhenEmpty,
      );
    }
    return _PublicContactActionsStatic(
      phone: phone,
      email: email,
      website: website,
      debugWhenEmpty: debugWhenEmpty,
    );
  }
}

class _PublicContactActionsFromMirror extends StatelessWidget {
  const _PublicContactActionsFromMirror({
    required this.clinicId,
    this.debugWhenEmpty = false,
  });

  final String clinicId;
  final bool debugWhenEmpty;

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static void _extractContact(Map<String, dynamic> data, Map<String, String> out) {
    final contact = data['contact'] is Map ? data['contact'] as Map<String, dynamic> : null;
    String fromContact(String k) => contact != null ? _s(contact[k]) : _s(data[k]);
    out['landingUrl'] = fromContact('landingUrl');
    out['websiteUrl'] = fromContact('websiteUrl');
    out['email'] = fromContact('email');
    out['whatsapp'] = fromContact('whatsapp');
    out['phone'] = fromContact('phone');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PublicBookingMirrorRepository>();
    return StreamBuilder<dynamic>(
      stream: repo.streamFullMirrorDoc(clinicId),
      builder: (context, snap) {
        final doc = snap.data as DocumentSnapshot<Map<String, dynamic>>?;
        final data = doc != null && doc.exists
            ? (doc.data() ?? const <String, dynamic>{})
            : const <String, dynamic>{};
        final contact = <String, String>{};
        _extractContact(data, contact);
        final landingUrl = contact['landingUrl'] ?? '';
        final websiteUrl = contact['websiteUrl'] ?? '';
        final email = contact['email'] ?? '';
        final whatsapp = contact['whatsapp'] ?? '';
        final phone = contact['phone'] ?? '';
        final hasAny = landingUrl.isNotEmpty ||
            websiteUrl.isNotEmpty ||
            email.isNotEmpty ||
            whatsapp.isNotEmpty ||
            phone.isNotEmpty;
        if (!hasAny && !debugWhenEmpty) return const SizedBox.shrink();
        return _PublicContactActionIcons(
          landingUrl: landingUrl.isEmpty ? null : landingUrl,
          websiteUrl: websiteUrl.isEmpty ? null : websiteUrl,
          email: email.isEmpty ? null : email,
          whatsapp: whatsapp.isEmpty ? null : whatsapp,
          phone: phone.isEmpty ? null : phone,
          compact: true,
        );
      },
    );
  }
}

class _PublicContactActionsStatic extends StatelessWidget {
  const _PublicContactActionsStatic({
    this.phone,
    this.email,
    this.website,
    this.debugWhenEmpty = false,
  });

  final String? phone;
  final String? email;
  final String? website;
  final bool debugWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final hasAny = (phone ?? '').trim().isNotEmpty ||
        (email ?? '').trim().isNotEmpty ||
        (website ?? '').trim().isNotEmpty;
    if (!hasAny && !debugWhenEmpty) return const SizedBox.shrink();
    return _PublicContactActionIcons(
      websiteUrl: (website ?? '').trim().isEmpty ? null : (website ?? '').trim(),
      email: (email ?? '').trim().isEmpty ? null : (email ?? '').trim(),
      phone: (phone ?? '').trim().isEmpty ? null : (phone ?? '').trim(),
      compact: true,
    );
  }
}

/// Shared icon strip with url_launcher. [compact] uses smaller padding for app bar.
class _PublicContactActionIcons extends StatelessWidget {
  const _PublicContactActionIcons({
    this.landingUrl,
    this.websiteUrl,
    this.email,
    this.whatsapp,
    this.phone,
    this.compact = false,
  });

  final String? landingUrl;
  final String? websiteUrl;
  final String? email;
  final String? whatsapp;
  final String? phone;
  final bool compact;

  bool _hasValue(String? v) => v != null && v.trim().isNotEmpty;

  String get _bestWebUrl {
    final l = (landingUrl ?? '').trim();
    if (l.isNotEmpty) return l;
    return (websiteUrl ?? '').trim();
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _openUrl(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: $uri')),
      );
    }
  }

  Uri _safeParseWeb(String raw) {
    final s = raw.trim();
    if (s.toLowerCase().startsWith('http://') ||
        s.toLowerCase().startsWith('https://')) {
      return Uri.parse(s);
    }
    return Uri.parse('https://$s');
  }

  Uri _whatsappUri(String raw) {
    final s = raw.trim();
    final lower = s.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return Uri.parse(s);
    }
    if (lower.startsWith('wa.me/')) {
      return Uri.parse('https://$s');
    }
    final digits = _digitsOnly(s);
    return Uri.parse('https://wa.me/$digits');
  }

  Uri _telUri(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    return Uri(scheme: 'tel', path: cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    final web = _bestWebUrl;
    if (_hasValue(web)) {
      buttons.add(
        IconButton(
          tooltip: 'Website',
          icon: const Icon(Icons.public, size: 20),
          onPressed: () => _openUrl(context, _safeParseWeb(web)),
        ),
      );
    }

    if (_hasValue(email)) {
      buttons.add(
        IconButton(
          tooltip: 'Email',
          icon: const Icon(Icons.email_outlined, size: 20),
          onPressed: () => _openUrl(
            context,
            Uri(scheme: 'mailto', path: email!.trim()),
          ),
        ),
      );
    }

    if (_hasValue(whatsapp)) {
      final digits = _digitsOnly(whatsapp!);
      if (digits.isNotEmpty) {
        buttons.add(
          IconButton(
            tooltip: 'WhatsApp',
            icon: const Icon(Icons.chat_bubble_outline, size: 20),
            onPressed: () => _openUrl(context, _whatsappUri(whatsapp!)),
          ),
        );
      }
    }

    if (_hasValue(phone)) {
      buttons.add(
        IconButton(
          tooltip: 'Call',
          icon: const Icon(Icons.call_outlined, size: 20),
          onPressed: () => _openUrl(context, _telUri(phone!)),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    if (compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: buttons);
    }
    return Material(
      color: Colors.white.withValues(alpha: 0.90),
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }
}
