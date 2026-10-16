import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/utils/order_totals.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../../admin/data/admin_repository.dart';
import '../../../admin/domain/named_discount.dart';

class DiscountEditResult {
  const DiscountEditResult({required this.value, required this.isPercent});
  final String value;
  final bool isPercent;
}

/// Shared Rs / % discount editor with optional named discounts from Settings.
Future<DiscountEditResult?> showDiscountEditor({
  required BuildContext context,
  required String title,
  required String initialValue,
  required bool initialIsPercent,
  required String baseAmountLabel,
  required Decimal baseAmount,
}) async {
  final value = TextEditingController(
    text: initialValue == '0' || initialValue == '0.00' ? '' : initialValue,
  );
  var isPercent = initialIsPercent;
  var presets = const <NamedDiscount>[];
  try {
    presets = await sl<AdminRepository>().listDiscounts();
  } catch (_) {}
  if (!context.mounted) {
    value.dispose();
    return null;
  }

  final result = await showDialog<DiscountEditResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          final preview = resolveDiscount(
            baseAmount: baseAmount,
            value: value.text.trim().isEmpty ? '0' : value.text.trim(),
            isPercent: isPercent,
          );
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(baseAmountLabel, style: const TextStyle(fontSize: 13, color: kAdminMuted)),
                  const SizedBox(height: 12),
                  if (presets.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: '',
                      decoration: const InputDecoration(
                        labelText: 'Saved discount (Catalog helpers)',
                        helperText: 'Pick a named discount, or enter a custom value below',
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Custom / none')),
                        for (final item in presets)
                          DropdownMenuItem(value: item.id, child: Text(item.label)),
                      ],
                      onChanged: (id) {
                        if (id == null || id.isEmpty) return;
                        final matches = presets.where((item) => item.id == id);
                        if (matches.isEmpty) return;
                        final match = matches.first;
                        value.text = match.value;
                        isPercent = match.isPercent;
                        setLocal(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Rs'), icon: Icon(Icons.payments_outlined, size: 16)),
                      ButtonSegment(value: true, label: Text('%'), icon: Icon(Icons.percent, size: 16)),
                    ],
                    selected: {isPercent},
                    onSelectionChanged: (next) {
                      setLocal(() => isPercent = next.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: isPercent ? 'Discount percent' : 'Discount amount (Rs)',
                      suffixText: isPercent ? '%' : 'Rs',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Applies as Rs. ${moneyString(preview)} off',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  const DiscountEditResult(value: '0', isPercent: false),
                ),
                child: const Text('Clear'),
              ),
              FilledButton(
                style: adminPrimaryButtonStyle,
                onPressed: () => Navigator.pop(
                  dialogContext,
                  DiscountEditResult(
                    value: value.text.trim().isEmpty ? '0' : value.text.trim(),
                    isPercent: isPercent,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );
  value.dispose();
  return result;
}
