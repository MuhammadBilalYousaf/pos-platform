import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/utils/json_read.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import 'package:intl/intl.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/domain/permissions.dart';
import '../../../orders/data/repositories/order_repository.dart';
import '../../../pos/presentation/bloc/order_cubit.dart';
import '../../../printing/domain/printer_service.dart';
import '../../../admin/presentation/bloc/branch_context_cubit.dart';

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
      if (_statusFilter == 'REFUNDED' && status != 'REFUNDED') return false;
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
                                            'PENDING' || 'OPEN' || 'HELD' || 'ON_HOLD' => AdminStatusTone.warning,
                                            _ => AdminStatusTone.neutral,
                                          };
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
                                                  Expanded(child: AdminStatusPill(label: status, tone: tone)),
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

  Future<void> _open(Map<String, dynamic> row) async {
    final auth = context.read<AuthBloc>().state;
    final business = auth is AuthAuthenticated ? auth.session.business : null;
    final branch = auth is AuthAuthenticated ? auth.session.branch : null;
    final receipt = receiptFromOrder(
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
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(receipt.orderNumber),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: SelectableText(receipt.toPreviewText(), style: const TextStyle(fontFamily: 'Consolas'))),
        ),
        actions: [
          if (auth is AuthAuthenticated &&
              auth.session.user.can(PosPermissions.orderCancel) &&
              readString(row, ['status']) != 'CANCELLED')
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await sl<OrderRepository>().cancelOrder(readString(row, ['id']));
                  await _load();
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
              child: const Text('Cancel order'),
            ),
          TextButton(
            onPressed: () {
              context.read<OrderCubit>().reprint(receipt);
              Navigator.pop(context);
            },
            child: const Text('Reprint preview'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
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
    lines: [
      for (final item in items)
        ReceiptLine(
          name: readString(item, ['productName', 'product_name']),
          quantity: readString(item, ['quantity']),
          unitPrice: readString(item, ['unitPrice', 'unit_price']),
          lineTotal: readString(item, ['lineTotal', 'line_total']),
        ),
    ],
    subtotal: readString(row, ['subtotal']),
    discount: readString(row, ['discount']),
    tax: readString(row, ['tax']),
    total: readString(row, ['total']),
    paymentMethod: readString(payment, ['method'], '-'),
    orderType: readString(row, ['order_type', 'orderType']),
    customerName: readString(row, ['customer_name', 'customerName']),
    tableNo: readString(row, ['table_no', 'tableNo']),
    tendered: pick(payment, ['tendered'])?.toString(),
    change: pick(payment, ['change'])?.toString(),
  );
}
