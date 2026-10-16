import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'order_totals.dart';

enum StockLevel { ok, low, veryLow, out }

class StockStatus {
  const StockStatus({
    required this.level,
    required this.quantity,
    required this.reorderLevel,
  });

  final StockLevel level;
  final Decimal quantity;
  final Decimal reorderLevel;

  String get label => switch (level) {
        StockLevel.out => 'Out of stock',
        StockLevel.veryLow => 'Very low',
        StockLevel.low => 'Low stock',
        StockLevel.ok => 'In stock',
      };

  Color get color => switch (level) {
        StockLevel.out => const Color(0xFFB91C1C),
        StockLevel.veryLow => const Color(0xFFC2410C),
        StockLevel.low => const Color(0xFFB45309),
        StockLevel.ok => const Color(0xFF15803D),
      };

  Color get background => switch (level) {
        StockLevel.out => const Color(0xFFFEE2E2),
        StockLevel.veryLow => const Color(0xFFFFEDD5),
        StockLevel.low => const Color(0xFFFEF3C7),
        StockLevel.ok => const Color(0xFFDCFCE7),
      };

  bool get isWarning => level != StockLevel.ok;

  static StockStatus fromQuantity({
    required String quantity,
    required String reorderLevel,
  }) {
    final qty = moneyOrZero(quantity);
    final reorder = moneyOrZero(reorderLevel);
    if (qty <= Decimal.zero) {
      return StockStatus(level: StockLevel.out, quantity: qty, reorderLevel: reorder);
    }
    if (reorder > Decimal.zero) {
      final veryLowCut = (reorder / Decimal.fromInt(2)).toDecimal(scaleOnInfinitePrecision: 4);
      if (qty <= veryLowCut) {
        return StockStatus(level: StockLevel.veryLow, quantity: qty, reorderLevel: reorder);
      }
      if (qty <= reorder) {
        return StockStatus(level: StockLevel.low, quantity: qty, reorderLevel: reorder);
      }
    }
    return StockStatus(level: StockLevel.ok, quantity: qty, reorderLevel: reorder);
  }
}

class StockStatusChip extends StatelessWidget {
  const StockStatusChip({super.key, required this.status, this.compact = false});

  final StockStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!status.isWarning && compact) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
