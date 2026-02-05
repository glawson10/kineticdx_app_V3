// lib/features/public/ui/price_list_screen.dart
//
// V3 logic + V2 presentation:
// - Same card layout + booking CTA as V2
// - Customisable per-clinic via READ-ONLY public branding doc (optional)
// - Safe fallback to defaults (so it looks identical today)
//
// Recommended Firestore doc (read-only):
// clinics/{clinicId}/public/branding/ui/v1
// {
//   "priceListTitle": "Price list",
//   "currency": "Kč",
//   "prices": [
//     {"title":"60 Minute Session","price":"1300 Kč","description":"Initial consultation..."},
//     {"title":"45 Minute Session","price":"1000 Kč","description":"Follow-up session..."}
//   ],
//   "infoNotes": [
//     "Home visits – please contact via email in advance to arrange logistics (2000 Kč)."
//   ],
//   "primaryCtaText": "Go to booking"
// }
//
// PUBLIC CONTACT ACTIONS (top-right icons)
// - Reads from *public booking mirror*:
//   clinics/{clinicId}/public/config/publicBooking/publicBooking
// - Supports BOTH schemas:
//   A) contact: { landingUrl, websiteUrl, email, phone, whatsapp }
//   B) flat:    { landingUrl, websiteUrl, email, phone, whatsapp }
//
// NOTE: This file does NOT depend on clinician providers.
// It will work for public boot, anonymous, and signed-in flows.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_routes.dart'; // ✅ use the correct AppRoutes import

class PriceListItem {
  final String title;
  final String price;
  final String description;

  const PriceListItem({
    required this.title,
    required this.price,
    required this.description,
  });

  static PriceListItem? fromMap(Map<String, dynamic> m) {
    final title = m['title'];
    final price = m['price'];
    final description = m['description'];
    if (title is! String || price is! String || description is! String)
      return null;
    return PriceListItem(title: title, price: price, description: description);
  }
}

class PriceListConfig {
  final String screenTitle;
  final List<PriceListItem> items;
  final List<String> infoNotes;
  final String primaryCtaText;

  const PriceListConfig({
    required this.screenTitle,
    required this.items,
    required this.infoNotes,
    required this.primaryCtaText,
  });

  static const PriceListConfig defaults = PriceListConfig(
    screenTitle: 'Price list',
    items: [
      PriceListItem(
        title: '60 Minute Session',
        price: '1300 Kč',
        description:
            'Initial consultation, mobility assessment & manual techniques',
      ),
      PriceListItem(
        title: '45 Minute Session',
        price: '1000 Kč',
        description:
            'Follow-up session focusing on movement progression & soft-tissue work',
      ),
    ],
    infoNotes: [
      'Home visits – please contact via email in advance to arrange logistics (2000 Kč).',
    ],
    primaryCtaText: 'Go to booking',
  );

  static PriceListConfig? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;

    final title = (m['priceListTitle'] as String?)?.trim();
    final cta = (m['primaryCtaText'] as String?)?.trim();

    final pricesRaw = m['prices'];
    final notesRaw = m['infoNotes'];

    final items = <PriceListItem>[];
    if (pricesRaw is List) {
      for (final x in pricesRaw) {
        if (x is Map<String, dynamic>) {
          final item = PriceListItem.fromMap(x);
          if (item != null) items.add(item);
        } else if (x is Map) {
          final item = PriceListItem.fromMap(Map<String, dynamic>.from(x));
          if (item != null) items.add(item);
        }
      }
    }

    final notes = <String>[];
    if (notesRaw is List) {
      for (final x in notesRaw) {
        if (x is String && x.trim().isNotEmpty) notes.add(x.trim());
      }
    }

    final hasMeaningful = (title != null && title.isNotEmpty) ||
        (cta != null && cta.isNotEmpty) ||
        items.isNotEmpty ||
        notes.isNotEmpty;

    if (!hasMeaningful) return null;

    return PriceListConfig(
      screenTitle: (title == null || title.isEmpty)
          ? PriceListConfig.defaults.screenTitle
          : title,
      items: items.isEmpty ? PriceListConfig.defaults.items : items,
      infoNotes: notes.isEmpty ? PriceListConfig.defaults.infoNotes : notes,
      primaryCtaText: (cta == null || cta.isEmpty)
          ? PriceListConfig.defaults.primaryCtaText
          : cta,
    );
  }

  PriceListConfig merge(PriceListConfig? other) {
    if (other == null) return this;
    return PriceListConfig(
      screenTitle: other.screenTitle,
      items: other.items,
      infoNotes: other.infoNotes,
      primaryCtaText: other.primaryCtaText,
    );
  }
}

/// ---------------------------------------------------------------------------
/// Public contact actions (top-right icons)
/// Reads from public mirror:
/// clinics/{clinicId}/public/config/publicBooking/publicBooking
///
/// Supports BOTH:
///  - contact map schema (preferred)
///  - flat keys (legacy / simpler mirror)
/// ---------------------------------------------------------------------------
class PublicContactActions extends StatelessWidget {
  final String clinicId;

  /// Optional: show a tiny debug pill on screen so you can confirm why icons hide
  final bool debug;

  const PublicContactActions({
    super.key,
    required this.clinicId,
    this.debug = false,
  });

  DocumentReference<Map<String, dynamic>> get _publicBookingDoc =>
      FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('public')
          .doc('config')
          .collection('publicBooking')
          .doc('publicBooking');

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static Uri? _tryParseUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final hasScheme = s.startsWith('http://') || s.startsWith('https://');
    final normalized = hasScheme ? s : 'https://$s';

    try {
      final u = Uri.parse(normalized);
      if (!u.hasScheme) return null;
      return u;
    } catch (_) {
      return null;
    }
  }

  static Uri? _mailto(String email) {
    final e = email.trim();
    if (e.isEmpty || !e.contains('@')) return null;
    return Uri(scheme: 'mailto', path: e);
  }

  static Uri? _tel(String phone) {
    final p = phone.trim();
    if (p.isEmpty) return null;
    return Uri(scheme: 'tel', path: p);
  }

  static Uri? _whatsapp(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // If already a URL (wa.me / https://...), just use it.
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return _tryParseUrl(s);
    }
    if (s.startsWith('wa.me/')) return _tryParseUrl('https://$s');

    // Otherwise treat as phone number -> https://wa.me/<digits>
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return Uri.parse('https://wa.me/$digits');
  }

  static Future<void> _launch(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      // best-effort silent
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _publicBookingDoc.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const <String, dynamic>{};

        // ✅ Support both schemas:
        // A) contact: {...}
        // B) flat keys {...}
        final contact = (data['contact'] is Map)
            ? Map<String, dynamic>.from(data['contact'] as Map)
            : data;

        final landingUrl = _s(contact['landingUrl']);
        final websiteUrl = _s(contact['websiteUrl']);
        final email = _s(contact['email']);
        final phone = _s(contact['phone']);
        final whatsapp = _s(contact['whatsapp']);

        final Uri? webUri =
            _tryParseUrl(landingUrl.isNotEmpty ? landingUrl : websiteUrl);
        final Uri? mailUri = _mailto(email);
        final Uri? telUri = _tel(phone);
        final Uri? waUri = _whatsapp(whatsapp);

        final actions = <Widget>[];

        if (webUri != null) {
          actions.add(
            IconButton(
              tooltip: 'Website',
              icon: const Icon(Icons.public),
              onPressed: () => _launch(webUri),
            ),
          );
        }
        if (mailUri != null) {
          actions.add(
            IconButton(
              tooltip: 'Email',
              icon: const Icon(Icons.email_outlined),
              onPressed: () => _launch(mailUri),
            ),
          );
        }
        if (telUri != null) {
          actions.add(
            IconButton(
              tooltip: 'Phone',
              icon: const Icon(Icons.call_outlined),
              onPressed: () => _launch(telUri),
            ),
          );
        }
        if (waUri != null) {
          actions.add(
            IconButton(
              tooltip: 'WhatsApp',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => _launch(waUri),
            ),
          );
        }

        if (actions.isEmpty) {
          if (!debug) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'No public links',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          );
        }

        return Row(mainAxisSize: MainAxisSize.min, children: actions);
      },
    );
  }
}

class PriceListScreen extends StatefulWidget {
  static const routeName = AppRoutes.priceList;

  /// Optional clinicId. If provided, we attempt a read-only fetch of per-clinic config.
  final String? clinicId;

  /// Carry corporate code forward (so Price list → Booking stays corporate-only)
  final String? corporateCode;

  /// Optional override (useful for testing / preview in clinician shell).
  final PriceListConfig? configOverride;

  /// Optional: show debug chip for why icons might be hidden
  final bool debugContactIcons;

  const PriceListScreen({
    super.key,
    this.clinicId,
    this.corporateCode,
    this.configOverride,
    this.debugContactIcons = false,
  });

  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  late Future<PriceListConfig> _configFuture;

  @override
  void initState() {
    super.initState();
    _configFuture = _resolveConfig();
  }

  Future<PriceListConfig> _resolveConfig() async {
    var config = PriceListConfig.defaults;

    if (widget.clinicId != null && widget.clinicId!.trim().isNotEmpty) {
      final fromDb = await _loadConfigFromFirestore(widget.clinicId!.trim());
      config = config.merge(fromDb);
    }

    config = config.merge(widget.configOverride);

    return config;
  }

  Future<PriceListConfig?> _loadConfigFromFirestore(String clinicId) async {
    try {
      // clinics/{clinicId}/public/branding/ui/v1
      final snap = await FirebaseFirestore.instance
          .collection('clinics')
          .doc(clinicId)
          .collection('public')
          .doc('branding')
          .collection('ui')
          .doc('v1')
          .get();

      return PriceListConfig.fromMap(snap.data());
    } catch (_) {
      return null; // silent fallback to defaults
    }
  }

  void _goToBooking() {
    final clinicId = widget.clinicId?.trim();
    final corp = widget.corporateCode?.trim();

    Navigator.pushNamed(
      context,
      AppRoutes.patientBookSimple,
      arguments: {
        if (clinicId != null && clinicId.isNotEmpty) 'clinicId': clinicId,
        if (corp != null && corp.isNotEmpty) 'corporateCode': corp,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cid = (widget.clinicId ?? '').trim();

    return FutureBuilder<PriceListConfig>(
      future: _configFuture,
      builder: (context, snap) {
        final config = snap.data ?? PriceListConfig.defaults;

        return Scaffold(
          appBar: AppBar(
            title: Text(config.screenTitle),
            leading: const BackButton(),
            actions: [
              if (cid.isNotEmpty)
                PublicContactActions(
                  clinicId: cid,
                  debug: widget.debugContactIcons,
                ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      for (final item in config.items) ...[
                        _PriceTile(
                          title: item.title,
                          price: item.price,
                          description: item.description,
                        ),
                        const SizedBox(height: 16),
                      ],
                      for (final note in config.infoNotes) ...[
                        _InfoTile(text: note),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _goToBooking,
                    child: Text(config.primaryCtaText),
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

class _PriceTile extends StatelessWidget {
  final String title;
  final String price;
  final String description;

  const _PriceTile({
    required this.title,
    required this.price,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  price,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String text;

  const _InfoTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
