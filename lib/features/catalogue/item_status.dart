import 'package:flutter/material.dart';

enum ItemStatus {
  available('Available'),
  low('Low in stock'),
  out('Out of stock'),
  expired('Expired'),
  discontinued('Discontinued');

  const ItemStatus(this.label);
  final String label;
}

/// Status is worked out, never typed in. Highest rule wins:
/// discontinued > expired > out of stock > low in stock > available.
ItemStatus computeStatus({
  required int quantity,
  required int lowStockLevel,
  required bool discontinued,
  String? expiryDate,
  DateTime? now,
}) {
  if (discontinued) return ItemStatus.discontinued;
  if (expiryDate != null && expiryDate.isNotEmpty) {
    final expiry = DateTime.tryParse(expiryDate);
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    if (expiry != null && expiry.isBefore(today)) return ItemStatus.expired;
  }
  if (quantity <= 0) return ItemStatus.out;
  if (quantity <= lowStockLevel) return ItemStatus.low;
  return ItemStatus.available;
}

/// Days until expiry, or null when there is no expiry date.
int? daysToExpiry(String? expiryDate, {DateTime? now}) {
  if (expiryDate == null || expiryDate.isEmpty) return null;
  final expiry = DateTime.tryParse(expiryDate);
  if (expiry == null) return null;
  final t = now ?? DateTime.now();
  return expiry.difference(DateTime(t.year, t.month, t.day)).inDays;
}

Color statusColor(ItemStatus s, ColorScheme scheme) => switch (s) {
      ItemStatus.available => const Color(0xFF2E7D32),
      ItemStatus.low => const Color(0xFFE65100),
      ItemStatus.out => scheme.error,
      ItemStatus.expired => const Color(0xFF8E24AA),
      ItemStatus.discontinued => scheme.outline,
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final ItemStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
