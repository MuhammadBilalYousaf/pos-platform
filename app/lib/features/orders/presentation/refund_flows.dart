import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../config/dependency_injection/injection.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/json_read.dart';
import '../../../core/utils/order_totals.dart';
import '../../../core/utils/safe_async.dart';
import '../../../core/widgets/admin_ui_kit.dart';
import '../../../core/widgets/password_field.dart';
import '../../admin/data/admin_repository.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../data/repositories/order_repository.dart';

/// Opens the POS refund picker (F5 / Ctrl+R): searchable refundable orders,
/// then amount or item refund for the selected ticket.
Future<void> openPosRefundPicker(BuildContext context) async {
  final auth = context.read<AuthBloc>().state;
  if (auth is! AuthAuthenticated) return;
  final canRefund = auth.session.user.can(PosPermissions.ordersRefund) ||
      auth.session.user.can(PosPermissions.orderRefund);
  if (!canRefund) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You do not have permission to refund orders.')),
    );
    return;
  }

  await showSafeDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => const _RefundOrderPickerDialog(),
  );
}

Decimal refundRemaining(Map<String, dynamic> row) {
  final total = money(readString(row, ['total'], '0'));
  final refunded = money(readString(row, ['refund_total'], '0'));
  final remaining = total - refunded;
  return remaining < Decimal.zero ? Decimal.zero : remaining;
}

bool isRefundableStatus(String status) {
  final s = status.toUpperCase();
  return s == 'COMPLETED' || s == 'PARTIALLY_REFUNDED';
}

String orderItemsSummary(Map<String, dynamic> row) {
  final names = <String>[];
  for (final raw in readList(row, ['items'])) {
    final item = asStringKeyMap(raw);
    final name = readString(item, ['productName', 'product_name']);
    if (name.isEmpty) continue;
    final qty = readString(item, ['quantity'], '1');
    names.add('$qty× $name');
  }
  if (names.isEmpty) return 'No items';
  return names.join(' · ');
}

String orderPaymentMethod(Map<String, dynamic> row) {
  final payments = readList(row, ['payments']);
  if (payments.isEmpty) return '-';
  return readString(asStringKeyMap(payments.first), ['method'], '-');
}

bool orderMatchesQuery(Map<String, dynamic> row, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final parts = <String>[
    readString(row, ['order_number', 'orderNumber']),
    readString(row, ['customer_name', 'customerName']),
    readString(row, ['cashier_name', 'cashierName', 'created_by']),
    readString(row, ['order_type', 'orderType']),
    readString(row, ['status']),
    readString(row, ['total']),
    readString(row, ['refund_total'], '0'),
    orderPaymentMethod(row),
    orderItemsSummary(row),
  ];
  for (final raw in readList(row, ['items'])) {
    final item = asStringKeyMap(raw);
    parts.add(readString(item, ['productName', 'product_name']));
    parts.add(readString(item, ['productId', 'product_id']));
  }
  return parts.join(' ').toLowerCase().contains(q);
}

class _RefundOrderPickerDialog extends StatefulWidget {
  const _RefundOrderPickerDialog();

  @override
  State<_RefundOrderPickerDialog> createState() => _RefundOrderPickerDialogState();
}

class _RefundOrderPickerDialogState extends State<_RefundOrderPickerDialog> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await sl<OrderRepository>().listOrders();
      final refundable = rows.where((row) {
        if (!isRefundableStatus(readString(row, ['status'], 'COMPLETED'))) return false;
        return refundRemaining(row) > Decimal.zero || _hasRefundableItems(row);
      }).toList();
      if (!mounted) return;
      setState(() {
        _orders = refundable;
        _loading = false;
      });
    } on Failure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  bool _hasRefundableItems(Map<String, dynamic> row) {
    for (final raw in readList(row, ['items'])) {
      final item = asStringKeyMap(raw);
      final ordered = moneyOrZero(readString(item, ['quantity'], '1'));
      final refunded = moneyOrZero(readString(item, ['refunded_quantity', 'refundedQuantity'], '0'));
      if (ordered - refunded > Decimal.zero) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.text;
    return _orders.where((row) => orderMatchesQuery(row, q)).toList();
  }

  Future<void> _onSelect(Map<String, dynamic> row) async {
    final choice = await showSafeDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text('Refund ${readString(row, ['order_number'])}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(orderItemsSummary(row), style: const TextStyle(fontSize: 13, color: kAdminMuted)),
              const SizedBox(height: 8),
              Text(
                'Total Rs. ${readString(row, ['total'])}'
                '${moneyOrZero(readString(row, ['refund_total'], '0')) > Decimal.zero ? ' · Already refunded Rs. ${readString(row, ['refund_total'])}' : ''}'
                ' · Remaining Rs. ${moneyString(refundRemaining(row))}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text('Choose refund type:'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          if (refundRemaining(row) > Decimal.zero)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'amount'),
              child: const Text('Refund amount'),
            ),
          FilledButton(
            style: adminPrimaryButtonStyle,
            onPressed: () => Navigator.pop(ctx, 'items'),
            child: const Text('Refund / return items'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'amount') {
      await _runAmountRefund(row);
    } else if (choice == 'items') {
      await _runItemRefund(row);
    }
    if (!mounted) return;
    await _load();
  }

  Future<String?> _askCancellationPassword() async {
    final password = TextEditingController();
    try {
      final ok = await showSafeDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Authorization required'),
          content: PasswordField(
            controller: password,
            autofocus: true,
            label: 'Order cancellation password',
            helperText: 'Configured by Business Admin in Settings',
            autofillHints: const [],
            onSubmitted: (_) => Navigator.pop(dialogContext, true),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true) return null;
      final value = password.text;
      if (value.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter the cancellation password.')),
          );
        }
        return null;
      }
      try {
        await sl<AdminRepository>().verifyOrderCancellationPassword(value);
      } on Failure catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
        }
        return null;
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        }
        return null;
      }
      return value;
    } finally {
      password.dispose();
    }
  }

  Future<void> _runAmountRefund(Map<String, dynamic> row) async {
    final remaining = refundRemaining(row);
    if (remaining <= Decimal.zero) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing left to refund on this order.')),
      );
      return;
    }
    const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER'];
    final amount = TextEditingController(text: moneyString(remaining));
    final reason = TextEditingController();
    var method = readList(row, ['payments']).isEmpty
        ? 'CASH'
        : readString(asStringKeyMap(readList(row, ['payments']).first), ['method'], 'CASH');
    var restoreStock = true;

    try {
      final ok = await showSafeDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setLocal) {
              final parsed = moneyOrZero(amount.text);
              final isFull = parsed >= remaining;
              return AlertDialog(
                title: Text('Refund ${readString(row, ['order_number'])}'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Order total: Rs. ${readString(row, ['total'])}'),
                      if (moneyOrZero(readString(row, ['refund_total'], '0')) > Decimal.zero)
                        Text('Already refunded: Rs. ${readString(row, ['refund_total'])}'),
                      Text(
                        'Remaining: Rs. ${moneyString(remaining)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Refund amount'),
                        onChanged: (_) => setLocal(() {}),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: methods.contains(method) ? method : 'CASH',
                        decoration: const InputDecoration(labelText: 'Refund method'),
                        items: [for (final m in methods) DropdownMenuItem(value: m, child: Text(m))],
                        onChanged: (value) {
                          if (value != null) setLocal(() => method = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reason,
                        decoration: const InputDecoration(labelText: 'Reason (optional)'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Restore recipe stock'),
                        subtitle: Text(
                          isFull
                              ? 'Returns ingredients to inventory on full refund'
                              : 'Only applies when refund clears the remaining balance',
                        ),
                        value: restoreStock && isFull,
                        onChanged: isFull ? (value) => setLocal(() => restoreStock = value) : null,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
                  FilledButton(
                    style: adminPrimaryButtonStyle,
                    onPressed: parsed <= Decimal.zero || parsed > remaining
                        ? null
                        : () => Navigator.pop(ctx, true),
                    child: const Text('Process refund'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (ok != true || !mounted) return;

      final parsedAmount = parseMoneyInputOrThrow(amount.text, label: 'Refund amount');
      final isFull = parsedAmount >= remaining;
      final result = await sl<OrderRepository>().refundOrder(
        orderId: readString(row, ['id']),
        amount: moneyString(parsedAmount),
        method: method,
        reason: reason.text.trim(),
        restoreStock: isFull && restoreStock,
      );
      if (!mounted) return;
      final lastRefund = result['last_refund'];
      final note = lastRefund is Map ? readString(asStringKeyMap(lastRefund), ['stock_note']) : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(note.isEmpty ? 'Refund recorded.' : 'Refund recorded. $note')),
      );
    } on Failure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      amount.dispose();
      reason.dispose();
    }
  }

  Future<void> _runItemRefund(Map<String, dynamic> row) async {
    final password = await _askCancellationPassword();
    if (password == null || !mounted) return;

    final items = readList(row, ['items']).map(asStringKeyMap).toList();
    final selectedQty = <int, TextEditingController>{};
    for (var i = 0; i < items.length; i++) {
      final ordered = moneyOrZero(readString(items[i], ['quantity'], '1'));
      final refunded = moneyOrZero(readString(items[i], ['refunded_quantity', 'refundedQuantity'], '0'));
      final remaining = ordered - refunded;
      if (remaining > Decimal.zero) {
        selectedQty[i] = TextEditingController(text: '0');
      }
    }
    if (selectedQty.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items left to refund or return.')),
      );
      return;
    }

    var refundMoney = true;
    var returnStock = false;
    final reason = TextEditingController();
    var method = 'CASH';
    const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER'];

    try {
      final ok = await showSafeDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setLocal) {
              return AlertDialog(
                title: Text('Item refund · ${readString(row, ['order_number'])}'),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in selectedQty.entries)
                          Builder(
                            builder: (context) {
                              final item = items[entry.key];
                              final ordered = moneyOrZero(readString(item, ['quantity'], '1'));
                              final refunded =
                                  moneyOrZero(readString(item, ['refunded_quantity', 'refundedQuantity'], '0'));
                              final returned =
                                  moneyOrZero(readString(item, ['returned_quantity', 'returnedQuantity'], '0'));
                              final remainingQty = ordered - refunded;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        '${readString(item, ['productName', 'product_name'])}\n'
                                        'Ordered ${moneyString(ordered)} · refunded ${moneyString(refunded)} · returned ${moneyString(returned)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 90,
                                      child: TextField(
                                        controller: entry.value,
                                        decoration: InputDecoration(
                                          labelText: 'Qty',
                                          helperText: 'max ${moneyString(remainingQty)}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Refund money for selected qty'),
                          value: refundMoney,
                          onChanged: (value) => setLocal(() => refundMoney = value ?? true),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Return stock for selected qty'),
                          value: returnStock,
                          onChanged: (value) => setLocal(() => returnStock = value ?? false),
                        ),
                        if (refundMoney)
                          DropdownButtonFormField<String>(
                            initialValue: method,
                            decoration: const InputDecoration(labelText: 'Refund method'),
                            items: [for (final m in methods) DropdownMenuItem(value: m, child: Text(m))],
                            onChanged: (value) {
                              if (value != null) setLocal(() => method = value);
                            },
                          ),
                        TextField(
                          controller: reason,
                          decoration: const InputDecoration(labelText: 'Reason (optional)'),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Process')),
                ],
              );
            },
          );
        },
      );
      if (ok != true || !mounted) return;

      final selections = <Map<String, dynamic>>[];
      for (final entry in selectedQty.entries) {
        final qty = money(entry.value.text.trim().isEmpty ? '0' : entry.value.text.trim());
        if (qty > Decimal.zero) {
          selections.add({'index': entry.key, 'quantity': moneyString(qty)});
        }
      }
      if (selections.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a quantity for at least one item.')),
        );
        return;
      }
      if (!refundMoney && !returnStock) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Choose refund money and/or return stock.')),
        );
        return;
      }

      final result = await sl<OrderRepository>().refundOrderItems(
        orderId: readString(row, ['id']),
        cancellationPassword: password,
        selections: selections,
        method: method,
        reason: reason.text.trim(),
        refundMoney: refundMoney,
        returnStock: returnStock,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item action recorded. Status: ${result['status']}.')),
      );
    } on Failure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      for (final c in selectedQty.values) {
        c.dispose();
      }
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Refund an order')),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: adminInputDecoration(
                'Search by order #, item, cashier, customer, type, payment…',
                icon: Icons.search,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              _loading
                  ? 'Loading refundable orders…'
                  : '${visible.length} of ${_orders.length} refundable order${_orders.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: kAdminMuted),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
                  : _error != null
                      ? Center(child: Text(_error!, textAlign: TextAlign.center))
                      : visible.isEmpty
                          ? const Center(
                              child: Text(
                                'No refundable orders match your search.\nCompleted or partially refunded sales with remaining balance appear here.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
                              itemBuilder: (context, index) {
                                final row = visible[index];
                                return _RefundOrderTile(
                                  row: row,
                                  onTap: () => _onSelect(row),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _RefundOrderTile extends StatelessWidget {
  const _RefundOrderTile({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = readString(row, ['status'], 'COMPLETED');
    final created = row['created_at'];
    var timeLabel = '—';
    if (created is Timestamp) {
      timeLabel = DateFormat('MMM d, h:mm a').format(created.toDate());
    }
    final remaining = refundRemaining(row);
    final refunded = moneyOrZero(readString(row, ['refund_total'], '0'));
    final statusLabel = status.toUpperCase() == 'PARTIALLY_REFUNDED' ? 'Partial refund' : status;
    final tone = status.toUpperCase() == 'PARTIALLY_REFUNDED'
        ? AdminStatusTone.warning
        : AdminStatusTone.success;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${readString(row, ['order_number'])}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                AdminStatusPill(label: statusLabel, tone: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$timeLabel · ${readString(row, ['order_type', 'orderType'], '-').replaceAll('_', ' ')}'
              ' · ${readString(row, ['cashier_name', 'cashierName', 'created_by'], '-')}'
              ' · ${orderPaymentMethod(row)}'
              ' · ${readString(row, ['customer_name', 'customerName'], 'Walk-in')}',
              style: const TextStyle(fontSize: 12, color: kAdminMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              orderItemsSummary(row),
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Total Rs. ${readString(row, ['total'])}'
              '${refunded > Decimal.zero ? ' · Refunded Rs. ${readString(row, ['refund_total'])}' : ''}'
              ' · Left Rs. ${moneyString(remaining)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
