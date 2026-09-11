import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/utils/json_read.dart';
import '../../../../core/widgets/workbench.dart';
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

class _OrdersPageState extends State<OrdersPage> {
  List<Map<String, dynamic>> _rows = const [];
  String _query = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
      if (_query.isEmpty) return true;
      final hay = '${row['order_number']} ${row['customer_name']} ${row['total']} ${row['order_type']} ${row['cashier_name']}'.toLowerCase();
      return hay.contains(_query.toLowerCase());
    }).toList();
    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) => _load(),
      child: PageFrame(
      title: 'Orders',
      subtitle: 'Completed tickets for this business. Open one to reprint the receipt preview.',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search order, customer, type'),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: visible.isEmpty
                          ? const Center(child: Text('No orders yet.'))
                          : ListView.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final row = visible[index];
                                return Card(
                                  child: ListTile(
                                    title: Text(readString(row, ['order_number'])),
                                    subtitle: Text(
                                      '${readString(row, ['order_type'], 'TAKEAWAY')} · ${readString(row, ['customer_name'], 'Walk-in')} · ${readString(row, ['status'])}',
                                    ),
                                    trailing: Text(readString(row, ['total'])),
                                    onTap: () => _open(row),
                                  ),
                                );
                              },
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
