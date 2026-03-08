import 'package:flutter/material.dart';

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
    return Wrap(
      spacing: 8,
      children: [
        if (phone != null && phone!.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.phone, size: 16),
            label: Text(phone!),
            onPressed: () {},
          ),
        if (email != null && email!.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.email, size: 16),
            label: Text(email!),
            onPressed: () {},
          ),
      ],
    );
  }
}
