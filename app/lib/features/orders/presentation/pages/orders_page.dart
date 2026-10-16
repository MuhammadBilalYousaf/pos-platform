import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import 'package:decimal/decimal.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/json_read.dart';
import '../../../../core/utils/order_totals.dart';
import '../../../../core/utils/safe_async.dart';
import '../../../../core/widgets/password_field.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import 'package:intl/intl.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/domain/permissions.dart';
import '../../../orders/data/repositories/order_repository.dart';
import '../../../pos/presentation/bloc/order_cubit.dart';
import '../../../printing/domain/printer_service.dart';
import '../../../admin/data/admin_repository.dart';
import '../../../admin/presentation/bloc/branch_context_cubit.dart';

class _CancelChoice {
  const _CancelChoice({
    required this.returnStock,
    required this.refundMoney,
    required this.method,
  });

  final bool returnStock;
  final bool refundMoney;
  final String method;
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _rows = const [];
  String _query = '';
  String _statusFilter = 'ALL';
  String? _error;
  bool _loading = true;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() {
          _statusFilter = switch (_tabs.index) {
            1 => 'COMPLETED',
            2 => 'PENDING',
            3 => 'HELD',
            4 => 'CANCELLED',
            5 => 'REFUNDED',
            _ => 'ALL',
          };
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await sl<OrderRepository>().listOrders();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rows.where((row) {
      final status = readString(row, ['status'], 'COMPLETED').toUpperCase();
      if (_statusFilter == 'COMPLETED' && status != 'COMPLETED') return false;
      if (_statusFilter == 'CANCELLED' && status != 'CANCELLED') return false;
      if (_statusFilter == 'PENDING' && status != 'PENDING' && status != 'OPEN') return false;
      if (_statusFilter == 'HELD' && status != 'HELD' && status != 'ON_HOLD') return false;
      if (_statusFilter == 'REFUNDED' && status != 'REFUNDED' && status != 'PARTIALLY_REFUNDED') return false;
      if (_query.isEmpty) return true;
      final hay = '${row['order_number']} ${row['customer_name']} ${row['total']} ${row['order_type']} ${row['cashier_name']}'.toLowerCase();
      return hay.contains(_query.toLowerCase());
    }).toList();

    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) => _load(),
      child: PageFrame(
        title: 'Orders',
        subtitle: 'Manage and track all orders across your branches.',
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
            : _error != null
                ? Center(child: Text(_error!))
                : Column(
                    children: [
                      TabBar(
                        controller: _tabs,
                        isScrollable: true,
                        labelColor: kAdminAccent,
                        unselectedLabelColor: kAdminMuted,
                        indicatorColor: kAdminAccent,
                        tabs: const [
                          Tab(text: 'All Orders'),
                          Tab(text: 'Completed'),
                          Tab(text: 'Pending'),
                          Tab(text: 'Held'),
                          Tab(text: 'Cancelled'),
                          Tab(text: 'Refunded'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: adminInputDecoration('Search order, customer, type', icon: Icons.search),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: AdminSurfaceCard(
                          padding: EdgeInsets.zero,
                          child: visible.isEmpty
                              ? const Center(child: Text('No orders in this view.'))
                              : Column(
                                  children: [
                                    const AdminTableHeader(columns: ['Order', 'Date & Time', 'Customer', 'Branch', 'Total', 'Status', '']),
                                    Expanded(
                                      child: ListView.separated(
                                        itemCount: visible.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
                                        itemBuilder: (context, index) {
                                          final row = visible[index];
                                          final status = readString(row, ['status'], 'COMPLETED');
                                          final created = row['created_at'];
                                          var timeLabel = '—';
                                          if (created is Timestamp) {
                                            timeLabel = DateFormat('MMM d, h:mm a').format(created.toDate());
                                          }
                                          final tone = switch (status.toUpperCase()) {
                                            'COMPLETED' => AdminStatusTone.success,
                                            'CANCELLED' || 'REFUNDED' => AdminStatusTone.danger,
                                            'PARTIALLY_REFUNDED' => AdminStatusTone.warning,
                                            'PENDING' || 'OPEN' || 'HELD' || 'ON_HOLD' => AdminStatusTone.warning,
                                            _ => AdminStatusTone.neutral,
                                          };
                                          final statusLabel = status.toUpperCase() == 'PARTIALLY_REFUNDED' ? 'Partial refund' : status;
                                          return InkWell(
                                            onTap: () => _open(row),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text('#${readString(row, ['order_number'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                                  ),
                                                  Expanded(child: Text(timeLabel, style: const TextStyle(fontSize: 12))),
                                                  Expanded(child: Text(readString(row, ['customer_name'], 'Walk-in'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                  Expanded(child: Text(readString(row, ['branch_id', 'branchId']), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                  Expanded(child: Text('Rs. ${readString(row, ['total'])}', style: const TextStyle(fontWeight: FontWeight.w600))),
                                                  Expanded(child: AdminStatusPill(label: statusLabel, tone: tone)),
                                                  Expanded(
                                                    child: Align(
                                                      alignment: Alignment.centerRight,
                                                      child: IconButton(onPressed: () => _open(row), icon: const Icon(Icons.visibility_outlined, size: 20)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Map<String, dynamic> _latestOrder(Map<String, dynamic> row) {
    final id = readString(row, ['id']);
    if (id.isEmpty) return row;
    for (final item in _rows) {
      if (readString(item, ['id']) == id) return item;
    }
    return row;
  }

  ReceiptData _receiptFor(Map<String, dynamic> row) {
    final auth = context.read<AuthBloc>().state;
    final business = auth is AuthAuthenticated ? auth.session.business : null;
    final branch = auth is AuthAuthenticated ? auth.session.branch : null;
    return receiptFromOrder(
      row,
      businessName: business?.name ?? 'POS',
      branchName: branch?.name ?? readString(row, ['branch_id']),
      address: branch?.address ?? business?.address,
      phone: branch?.phone ?? business?.phone,
      footer: business?.receiptFooter,
      header: business?.receiptHeader,
      paperWidthMm: business?.receiptPaperWidthMm ?? 80,
      showAddress: business?.receiptShowAddress ?? true,
      showPhone: business?.receiptShowPhone ?? true,
    );
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final latest = _latestOrder(row);
    final auth = context.read<AuthBloc>().state;
    final receipt = _receiptFor(latest);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(receipt.orderNumber),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (latest['cancel_audit'] is Map) ...[
                  Text(
                    'Cancelled by ${readString(asStringKeyMap(latest['cancel_audit']), ['by'])}'
                    ' · stock ${readBool(asStringKeyMap(latest['cancel_audit']), ['stock_returned']) ? 'returned' : 'not returned'}'
                    ' · refund ${readBool(asStringKeyMap(latest['cancel_audit']), ['refund_money']) ? readString(asStringKeyMap(latest['cancel_audit']), ['refund_amount']) : 'none'}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                  ),
                  const SizedBox(height: 8),
                ],
                if (moneyOrZero(readString(latest, ['refund_total'], '0')) > Decimal.zero)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Refunded so far: Rs. ${readString(latest, ['refund_total'])} · Status: ${readString(latest, ['status'])}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                    ),
                  ),
                SelectableText(receipt.toPreviewText(), style: const TextStyle(fontFamily: 'Consolas')),
              ],
            ),
          ),
        ),
        actions: [
          if (auth is AuthAuthenticated &&
              (auth.session.user.can(PosPermissions.ordersRefund) ||
                  auth.session.user.can(PosPermissions.orderRefund)) &&
              _canRefund(readString(latest, ['status'], 'COMPLETED')) &&
              _refundRemaining(latest) > Decimal.zero)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                runAfterDialogClosed(this, () => _refund(latest));
              },
              child: const Text('Refund amount'),
            ),
          if (auth is AuthAuthenticated &&
              (auth.session.user.can(PosPermissions.ordersRefund) ||
                  auth.session.user.can(PosPermissions.orderRefund)) &&
              _canRefund(readString(latest, ['status'], 'COMPLETED')))
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                runAfterDialogClosed(this, () => _itemRefund(latest));
              },
              child: const Text('Refund / return items'),
            ),
          if (auth is AuthAuthenticated &&
              (auth.session.user.can(PosPermissions.orderCancel) ||
                  auth.session.user.can(PosPermissions.ordersRefund)) &&
              _canCancelAuthorized(readString(latest, ['status'], 'COMPLETED')))
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                runAfterDialogClosed(this, () => _cancelAuthorized(latest));
              },
              child: const Text('Cancel order'),
            ),
          TextButton(
            onPressed: () {
              showDialog<void>(
                context: dialogContext,
                builder: (context) => AlertDialog(
                  title: const Text('Cancel vs waste'),
                  content: const Text(
                    'Cancel order: ticket was not completed. Stock stays as it is.\n\n'
                    'Cancel completed sale: ticket was paid by mistake and stock should come back. Money is not refunded.\n\n'
                    'Refund: money goes back. Full refund can also restore stock.\n\n'
                    'Waste (Inventory): food or ingredients were thrown away, including a partial quantity. Stock goes down.',
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ),
              );
            },
            child: const Text('When to use each'),
          ),
          TextButton(
            onPressed: () async {
              final choice = await showDialog<String>(
                context: dialogContext,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reprint'),
                  content: const Text(
                    'Kitchen ticket has items only (no prices) and cuts separately.\n'
                    'Customer receipt includes totals.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, 'kitchen'), child: const Text('Kitchen')),
                    TextButton(onPressed: () => Navigator.pop(ctx, 'customer'), child: const Text('Customer')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, 'both'), child: const Text('Both')),
                  ],
                ),
              );
              if (choice == null || !mounted) return;
              try {
                final fresh = _receiptFor(_latestOrder(latest));
                final cubit = context.read<OrderCubit>();
                if (choice == 'kitchen') {
                  await cubit.reprintKitchen(fresh);
                } else if (choice == 'customer') {
                  await cubit.reprintCustomer(fresh);
                } else {
                  await cubit.reprintBoth(fresh);
                }
                if (!mounted) return;
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      choice == 'kitchen'
                          ? 'Kitchen ticket sent.'
                          : choice == 'customer'
                              ? 'Customer receipt sent.'
                              : 'Kitchen + customer receipts sent.',
                    ),
                  ),
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
              }
            },
            child: const Text('Reprint…'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  bool _canRefund(String status) {
    final s = status.toUpperCase();
    return s == 'COMPLETED' || s == 'PARTIALLY_REFUNDED';
  }

  bool _canCancelAuthorized(String status) {
    final s = status.toUpperCase();
    return s != 'CANCELLED' && s != 'REFUNDED';
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the cancellation password.')));
        }
        return null;
      }
      // Validate immediately so a wrong password fails before the next step.
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

  Future<void> _cancelAuthorized(Map<String, dynamic> row) async {
    final password = await _askCancellationPassword();
    if (password == null || !mounted) return;

    final reason = TextEditingController();
    try {
      final choice = await showSafeDialog<_CancelChoice>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) {
          var returnStock = false;
          var refundMoney = false;
          var method = 'CASH';
          const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER'];
          return StatefulBuilder(
            builder: (context, setLocal) {
              return AlertDialog(
                title: Text('Cancel ${readString(row, ['order_number'])}'),
                content: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Choose what should happen with this cancelled order:'),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Return stock'),
                        subtitle: const Text('Restore consumed inventory'),
                        value: returnStock,
                        onChanged: (value) => setLocal(() => returnStock = value ?? false),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Refund money'),
                        subtitle: const Text('Refund the remaining payment'),
                        value: refundMoney,
                        onChanged: (value) => setLocal(() => refundMoney = value ?? false),
                      ),
                      Text(
                        !returnStock && !refundMoney
                            ? 'Neither — cancel only, no stock or money movement.'
                            : returnStock && refundMoney
                                ? 'Both stock return and money refund.'
                                : returnStock
                                    ? 'Stock only.'
                                    : 'Refund only.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (refundMoney) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: method,
                          decoration: const InputDecoration(labelText: 'Refund method'),
                          items: [for (final m in methods) DropdownMenuItem(value: m, child: Text(m))],
                          onChanged: (value) {
                            if (value != null) setLocal(() => method = value);
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Back')),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      dialogContext,
                      _CancelChoice(returnStock: returnStock, refundMoney: refundMoney, method: method),
                    ),
                    child: const Text('Review confirmation'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (choice == null || !mounted) return;

      final confirmed = await showSafeDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm cancellation'),
          content: Text(
            'Order ${readString(row, ['order_number'])}\n'
            'Return stock: ${choice.returnStock ? 'Yes' : 'No'}\n'
            'Refund money: ${choice.refundMoney ? 'Yes' : 'No'}\n'
            '${reason.text.trim().isEmpty ? '' : 'Reason: ${reason.text.trim()}\n'}'
            '\nThis cannot be undone from this screen.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel order')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      try {
        final result = await sl<OrderRepository>().cancelOrderAuthorized(
          orderId: readString(row, ['id']),
          cancellationPassword: password,
          returnStock: choice.returnStock,
          refundMoney: choice.refundMoney,
          reason: reason.text.trim(),
          refundMethod: choice.method,
        );
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cancelled. Stock returned: ${result['stock_returned'] == true ? 'yes' : 'no'}. '
              'Money refunded: ${result['money_refunded'] == true ? 'Rs. ${result['refund_amount']}' : 'no'}.',
            ),
          ),
        );
      } on Failure catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      reason.dispose();
    }
  }

  Future<void> _itemRefund(Map<String, dynamic> row) async {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No items left to refund or return.')));
      return;
    }

    var refundMoney = true;
    var returnStock = false;
    final reason = TextEditingController();
    var method = 'CASH';
    const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER'];

    final ok = await showSafeDialog<bool>(
      context: context,
      builder: (context) {
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
                            final refunded = moneyOrZero(readString(item, ['refunded_quantity', 'refundedQuantity'], '0'));
                            final returned = moneyOrZero(readString(item, ['returned_quantity', 'returnedQuantity'], '0'));
                            final remaining = ordered - refunded;
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
                                        helperText: 'max ${moneyString(remaining)}',
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
                      TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Process')),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a quantity for at least one item.')));
      return;
    }
    if (!refundMoney && !returnStock) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose refund money and/or return stock.')));
      return;
    }

    try {
      final result = await sl<OrderRepository>().refundOrderItems(
        orderId: readString(row, ['id']),
        cancellationPassword: password,
        selections: selections,
        method: method,
        reason: reason.text.trim(),
        refundMoney: refundMoney,
        returnStock: returnStock,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item action recorded. Status: ${result['status']}.')),
      );
      // Re-open order so the receipt shows RETURNED lines and net totals.
      final updated = _latestOrder(row);
      runAfterDialogClosed(this, () => _open(updated));
    } on Failure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Decimal _refundRemaining(Map<String, dynamic> row) {
    final total = money(readString(row, ['total'], '0'));
    final refunded = money(readString(row, ['refund_total'], '0'));
    final remaining = total - refunded;
    return remaining < Decimal.zero ? Decimal.zero : remaining;
  }

  Future<void> _refund(Map<String, dynamic> row) async {
    final remaining = _refundRemaining(row);
    if (remaining <= Decimal.zero) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing left to refund on this order.')));
      return;
    }
    const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER'];
    final amount = TextEditingController(text: moneyString(remaining));
    final reason = TextEditingController();
    var method = readList(row, ['payments']).isEmpty
        ? 'CASH'
        : readString(asStringKeyMap(readList(row, ['payments']).first), ['method'], 'CASH');
    var restoreStock = true;

    final ok = await showSafeDialog<bool>(
      context: context,
      builder: (context) {
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
                    Text('Remaining: Rs. ${moneyString(remaining)}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Restore recipe stock'),
                      subtitle: Text(isFull ? 'Returns ingredients to inventory on full refund' : 'Only applies when refund clears the remaining balance'),
                      value: restoreStock && isFull,
                      onChanged: isFull ? (value) => setLocal(() => restoreStock = value) : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
                FilledButton(
                  style: adminPrimaryButtonStyle,
                  onPressed: parsed <= Decimal.zero || parsed > remaining
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('Process refund'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      final parsedAmount = parseMoneyInputOrThrow(amount.text, label: 'Refund amount');
      final isFull = parsedAmount >= remaining;
      final result = await sl<OrderRepository>().refundOrder(
        orderId: readString(row, ['id']),
        amount: moneyString(parsedAmount),
        method: method,
        reason: reason.text.trim(),
        restoreStock: isFull && restoreStock,
      );
      await _load();
      if (!mounted) return;
      final lastRefund = result['last_refund'];
      final note = lastRefund is Map ? readString(asStringKeyMap(lastRefund), ['stock_note']) : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(note.isEmpty ? 'Refund recorded.' : 'Refund recorded. $note'),
        ),
      );
      final updated = _latestOrder(row);
      runAfterDialogClosed(this, () => _open(updated));
    } on Failure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

ReceiptData receiptFromOrder(
  Map<String, dynamic> row, {
  required String businessName,
  required String branchName,
  String? address,
  String? phone,
  String? footer,
  String? header,
  int paperWidthMm = 80,
  bool showAddress = true,
  bool showPhone = true,
}) {
  final items = readList(row, ['items']).map(asStringKeyMap).toList();
  final payments = readList(row, ['payments']).map(asStringKeyMap).toList();
  final created = row['created_at'];
  DateTime at = DateTime.now();
  if (created is Timestamp) at = created.toDate();
  final payment = payments.isEmpty ? <String, dynamic>{} : payments.first;

  final lines = <ReceiptLine>[];
  var netGoods = Decimal.zero;
  var refundedGoods = Decimal.zero;

  for (final item in items) {
    final name = readString(item, ['productName', 'product_name'], 'Item');
    final unitPrice = readString(item, ['unitPrice', 'unit_price'], '0');
    final ordered = moneyOrZero(readString(item, ['quantity'], '0'));
    final refundedQty = moneyOrZero(readString(item, ['refunded_quantity', 'refundedQuantity'], '0'));
    final returnedQty = moneyOrZero(readString(item, ['returned_quantity', 'returnedQuantity'], '0'));
    final lineTotal = moneyOrZero(readString(item, ['lineTotal', 'line_total'], '0'));
    if (ordered <= Decimal.zero) continue;

    final unitShare = (lineTotal / ordered).toDecimal(scaleOnInfinitePrecision: 4);
    var kept = ordered - refundedQty;
    if (kept < Decimal.zero) kept = Decimal.zero;

    if (kept > Decimal.zero) {
      final keptTotal = unitShare * kept;
      netGoods += keptTotal;
      lines.add(
        ReceiptLine(
          name: name,
          quantity: moneyString(kept),
          unitPrice: unitPrice,
          lineTotal: moneyString(keptTotal),
        ),
      );
    }

    if (refundedQty > Decimal.zero) {
      final refundLine = unitShare * refundedQty;
      refundedGoods += refundLine;
      final stockReturned = returnedQty > Decimal.zero;
      lines.add(
        ReceiptLine(
          name: name,
          quantity: moneyString(refundedQty),
          unitPrice: unitPrice,
          lineTotal: '-${moneyString(refundLine)}',
          isReturned: true,
          note: stockReturned ? 'RETURNED' : 'REFUNDED',
        ),
      );
    }
  }

  final originalTotal = moneyOrZero(readString(row, ['total'], '0'));
  final refundMoney = moneyOrZero(readString(row, ['refund_total'], '0'));
  // Prefer order refund_total when money was refunded; otherwise goods returned value.
  final effectiveRefund = refundMoney > Decimal.zero ? refundMoney : refundedGoods;
  var netTotal = originalTotal - effectiveRefund;
  if (netTotal < Decimal.zero) netTotal = Decimal.zero;

  // Net subtotal from kept lines; fall back to original - refunded goods.
  final originalSubtotal = moneyOrZero(readString(row, ['subtotal'], '0'));
  final netSubtotal = netGoods > Decimal.zero
      ? netGoods
      : (originalSubtotal - refundedGoods < Decimal.zero ? Decimal.zero : originalSubtotal - refundedGoods);

  // Scale tax/discount with remaining goods when there was an item refund.
  final scale = originalSubtotal > Decimal.zero
      ? (netSubtotal / originalSubtotal).toDecimal(scaleOnInfinitePrecision: 6)
      : Decimal.one;
  final originalTax = moneyOrZero(readString(row, ['tax'], '0'));
  final originalDiscount = moneyOrZero(readString(row, ['discount'], '0'));
  final netTax = effectiveRefund > Decimal.zero ? (originalTax * scale) : originalTax;
  final netDiscount = effectiveRefund > Decimal.zero ? (originalDiscount * scale) : originalDiscount;

  return ReceiptData(
    businessName: businessName,
    branchName: branchName,
    address: address,
    phone: phone,
    footer: footer,
    header: header,
    paperWidthMm: paperWidthMm,
    showAddress: showAddress,
    showPhone: showPhone,
    orderNumber: readString(row, ['order_number', 'orderNumber']),
    cashierName: readString(row, ['cashier_name', 'cashierName', 'created_by']),
    createdAt: at,
    lines: lines,
    subtotal: moneyString(effectiveRefund > Decimal.zero ? netSubtotal : originalSubtotal),
    discount: moneyString(netDiscount),
    tax: moneyString(netTax),
    total: moneyString(effectiveRefund > Decimal.zero ? netTotal : originalTotal),
    paymentMethod: readString(payment, ['method'], '-'),
    orderType: readString(row, ['order_type', 'orderType']),
    customerName: readString(row, ['customer_name', 'customerName']),
    tableNo: readString(row, ['table_no', 'tableNo']),
    tendered: pick(payment, ['tendered'])?.toString(),
    change: pick(payment, ['change'])?.toString(),
    refundTotal: effectiveRefund > Decimal.zero ? moneyString(effectiveRefund) : null,
    originalTotal: effectiveRefund > Decimal.zero ? moneyString(originalTotal) : null,
  );
}
