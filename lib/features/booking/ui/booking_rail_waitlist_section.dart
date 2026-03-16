// lib/features/booking/ui/booking_rail_waitlist_section.dart
// Waitlist section in calendar tools: list entries, Book, Add to waitlist.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/waitlist_repository.dart';
import '../../../models/waitlist_entry.dart';

typedef OnBookWaitlistEntry = void Function(WaitlistEntry entry);

class BookingRailWaitlistSection extends StatelessWidget {
  final String clinicId;
  final OnBookWaitlistEntry? onBookEntry;
  final VoidCallback? onAddTap;
  /// Custom message when the waitlist is empty (e.g. for tools panel).
  final String? emptyMessage;

  const BookingRailWaitlistSection({
    super.key,
    required this.clinicId,
    this.onBookEntry,
    this.onAddTap,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.read<WaitlistRepository>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Text(
                'Waitlist',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (onAddTap != null) ...[
                const Spacer(),
                TextButton.icon(
                  onPressed: onAddTap,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ],
          ),
        ),
        StreamBuilder<List<WaitlistEntry>>(
          stream: repo.watchEntries(clinicId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final entries = snap.data ?? [];
            if (entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Text(
                  emptyMessage ?? 'No waitlist entries. Tap Add to add a patient.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final e = entries[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: ListTile(
                    title: Text(
                      e.displayLabel,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: (e.priority != 0 ||
                            (e.notes != null && e.notes!.trim().isNotEmpty))
                        ? Text(
                            [
                              if (e.priority != 0) 'Priority ${e.priority}',
                              if (e.notes != null && e.notes!.trim().isNotEmpty)
                                e.notes!.trim(),
                            ].join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : null,
                    trailing: onBookEntry != null
                        ? TextButton(
                            onPressed: () => onBookEntry!(e),
                            child: const Text('Book'),
                          )
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
