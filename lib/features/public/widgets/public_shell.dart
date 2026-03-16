import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/public_booking_mirror_repository.dart';

class PublicShell extends StatelessWidget {
  const PublicShell({
    super.key,
    required this.child,
    this.maxWidth = 960,
    this.title,
    this.subtitle,
    this.showBack = false,
    this.topRight,
    this.scrollableCard = false,
    this.showPoweredBy = false,
    this.clinicId,
  });

  final Widget child;
  final double maxWidth;
  final String? title;
  final String? subtitle;
  final bool showBack;
  final Widget? topRight;
  final bool scrollableCard;
  final bool showPoweredBy;
  /// When set, app bar shows clinic logo and name from the public mirror when available.
  final String? clinicId;

  @override
  Widget build(BuildContext context) {
    final showAppBar = title != null || showBack || clinicId != null;
    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              automaticallyImplyLeading: showBack,
              title: _buildTitle(context),
              actions: topRight != null ? [topRight!] : null,
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
      bottomNavigationBar: showPoweredBy
          ? const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Powered by KineticDx',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            )
          : null,
    );
  }

  Widget? _buildTitle(BuildContext context) {
    if (title != null && (clinicId == null || clinicId!.trim().isEmpty)) {
      return Text(title!);
    }
    if (clinicId != null && clinicId!.trim().isNotEmpty) {
      final repo = context.read<PublicBookingMirrorRepository>();
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: repo.streamFullMirrorDoc(clinicId!.trim()),
        builder: (context, snap) {
          final doc = snap.data;
          final data = doc != null && doc.exists
              ? (doc.data() ?? <String, dynamic>{})
              : <String, dynamic>{};
          return _titleFromData(context, data);
        },
      );
    }
    return title != null ? Text(title!) : null;
  }

  Widget _titleFromData(BuildContext context, Map<String, dynamic> data) {
    final logoUrl = (data['logoUrl'] as String? ?? '').trim();
    final clinicName = (data['clinicName'] as String? ?? '').trim();
    final contact = data['contact'] is Map ? data['contact'] as Map<String, dynamic> : null;
    final address = (contact != null ? (contact['address'] as String? ?? '').toString().trim() : (data['address'] as String? ?? '').toString().trim());
    if (clinicName.isEmpty && logoUrl.isEmpty) {
      return title != null ? Text(title!) : const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logoUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  logoUrl,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 32, height: 32),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                clinicName.isNotEmpty ? clinicName : (title ?? 'Booking'),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            address,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
