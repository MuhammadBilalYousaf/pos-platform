import '../../../core/utils/json_read.dart';
import '../../../core/utils/order_totals.dart';

class NamedDiscount {
  const NamedDiscount({
    required this.id,
    required this.name,
    required this.value,
    required this.isPercent,
  });

  final String id;
  final String name;
  final String value;
  final bool isPercent;

  String get label => '$name · ${formatDiscountLabel(value: value, isPercent: isPercent)}';

  factory NamedDiscount.fromJson(Map<String, dynamic> json) {
    final type = readString(json, ['type', 'discount_type', 'discountType'], 'AMOUNT').toUpperCase();
    final isPercent = type == 'PERCENT' || type == 'PERCENTAGE' || type == '%';
    final value = readString(json, ['amount', 'value'], '0');
    return NamedDiscount(
      id: readString(json, ['id']),
      name: readString(json, ['name']),
      value: value.isEmpty ? '0' : value,
      isPercent: isPercent,
    );
  }
}
