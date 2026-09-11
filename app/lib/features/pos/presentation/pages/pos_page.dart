import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../admin/data/admin_repository.dart';
import '../../../products/domain/entities/catalog.dart';
import '../../../products/presentation/bloc/catalog_cubit.dart';
import '../../../sync/presentation/bloc/sync_cubit.dart';
import '../bloc/cart_cubit.dart';
import '../bloc/order_cubit.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/utils/order_totals.dart';
import '../../../../core/widgets/admin_ui_kit.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
      final auth = context.read<AuthBloc>().state;
      if (auth is AuthAuthenticated) {
        context.read<CartCubit>().setTaxRate(auth.session.business?.taxRate ?? '0');
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<OrderCubit, OrderState>(
      listener: (context, state) async {
        if (state is OrderCompleted) {
          context.read<CartCubit>().clear();
          context.read<SyncCubit>().refreshQueue();
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(state.message),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: SelectableText(state.receipt.toPreviewText(), style: const TextStyle(fontFamily: 'Consolas', fontSize: 13)),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            ),
          );
          if (context.mounted) context.read<OrderCubit>().acknowledge();
        } else if (state is OrderFailure) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          context.read<OrderCubit>().acknowledge();
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1100;
          if (desktop) {
            return Row(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: kAdminPageBg,
                    child: _ProductPane(search: _search, searchFocus: _searchFocus),
                  ),
                ),
                SizedBox(
                  width: 420,
                  child: _CartPane(),
                ),
              ],
            );
          }
          return ColoredBox(
            color: kAdminPageBg,
            child: Column(
              children: [
                const _VerticalCategories(),
                _SearchBar(controller: _search, focusNode: _searchFocus),
                const Expanded(child: _ProductGrid()),
                const SizedBox(height: 280, child: _CartPane(compact: true)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.focusNode});
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: adminInputDecoration('Search name or SKU (all categories)', icon: Icons.search),
              onChanged: context.read<CatalogCubit>().search,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: adminOutlinedButtonStyle,
            onPressed: () {},
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('Scan'),
          ),
        ],
      ),
    );
  }
}

class _VerticalCategories extends StatelessWidget {
  const _VerticalCategories();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        final categories = state.catalog?.categories ?? [];
        if (categories.isEmpty && state.status != CatalogStatus.ready) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView(
              shrinkWrap: true,
              children: [
                _PosCategoryButton(
                  label: 'All',
                  selected: state.selectedCategoryId == null,
                  onTap: () => context.read<CatalogCubit>().selectCategory(null),
                ),
                for (final category in categories)
                  _PosCategoryButton(
                    label: category.name,
                    selected: state.selectedCategoryId == category.id,
                    onTap: () => context.read<CatalogCubit>().selectCategory(category.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PosCategoryButton extends StatefulWidget {
  const _PosCategoryButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PosCategoryButton> createState() => _PosCategoryButtonState();
}

class _PosCategoryButtonState extends State<_PosCategoryButton> with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1, end: 0.97).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.selected ? kAdminAccent : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected ? kAdminAccent : kAdminBorder,
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: kAdminAccent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              onHighlightChanged: (down) {
                if (down) {
                  _pressController.forward();
                } else {
                  _pressController.reverse();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      width: 4,
                      height: widget.selected ? 22 : 0,
                      margin: EdgeInsets.only(right: widget.selected ? 10 : 0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: TextStyle(
                          color: widget.selected ? Colors.white : const Color(0xFF1E293B),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        child: Text(widget.label),
                      ),
                    ),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 280),
                      turns: widget.selected ? 0 : -0.02,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: widget.selected ? Colors.white.withValues(alpha: 0.9) : kAdminMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPane extends StatelessWidget {
  const _ProductPane({required this.search, required this.searchFocus});
  final TextEditingController search;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _VerticalCategories(),
        _SearchBar(controller: search, focusNode: searchFocus),
        const Expanded(child: _ProductGrid()),
      ],
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        if (state.status == CatalogStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == CatalogStatus.failure) {
          return Center(child: Text(state.message ?? 'Unable to load products.'));
        }
        final products = state.visibleProducts;
        if (products.isEmpty) {
          final q = state.query.trim();
          return Center(
            child: Text(
              q.isNotEmpty
                  ? 'No products match "$q" across categories.'
                  : 'No products in this category.',
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            final variant = product.defaultVariant;
            return InkWell(
              onTap: () => _add(context, product),
              child: Ink(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kAdminBorder),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: kAdminAccentSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.icecream_outlined, color: kAdminAccent, size: 32),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (product.sku != null) Text(product.sku!, style: const TextStyle(color: kAdminMuted, fontSize: 11)),
                      Text('Rs. ${variant.price}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kAdminAccent)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _add(BuildContext context, CatalogProduct product) async {
    if (product.variants.length <= 1 && product.options.isEmpty) {
      context.read<CartCubit>().addProduct(product);
      return;
    }
    var variant = product.defaultVariant;
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(product.name),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: variant.id,
                      decoration: const InputDecoration(labelText: 'Size / variant'),
                      items: [
                        for (final item in product.variants)
                          DropdownMenuItem(value: item.id, child: Text('${item.name} · ${item.price}')),
                      ],
                      onChanged: (value) {
                        variant = product.variants.firstWhere((item) => item.id == value);
                        setLocal(() {});
                      },
                    ),
                    if (product.options.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: Text('Add-ons', style: Theme.of(context).textTheme.titleSmall)),
                      for (final option in product.options)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(option.id),
                          title: Text('${option.name} (+${option.extraPrice})'),
                          onChanged: (value) {
                            setLocal(() {
                              if (value == true) {
                                selected.add(option.id);
                              } else {
                                selected.remove(option.id);
                              }
                            });
                          },
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
              ],
            );
          },
        );
      },
    );
    if (ok == true && context.mounted) {
      context.read<CartCubit>().addProduct(
            product,
            variant: variant,
            options: product.options.where((item) => selected.contains(item.id)).toList(),
          );
    }
  }
}

class _CartPane extends StatelessWidget {
  const _CartPane({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: kAdminBorder)),
        ),
        child: BlocBuilder<CartCubit, CartState>(
        builder: (context, cart) {
          final totals = cart.totals;
          return Column(
            children: [
              ListTile(
                title: const Text('Current Order', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${cart.orderType}${cart.customerName == null || cart.customerName!.isEmpty ? '' : ' · ${cart.customerName}'}'),
                trailing: TextButton(onPressed: () => _ticketMeta(context, cart), child: const Text('Details')),
              ),
              Expanded(
                child: cart.isEmpty
                    ? const Center(child: Text('Tap a product to add it.'))
                    : ListView.builder(
                        itemCount: cart.lines.length,
                        itemBuilder: (context, index) {
                          final line = cart.lines[index];
                          return ListTile(
                            dense: compact,
                            title: Text(line.displayName),
                            subtitle: Text('${line.quantity} × ${line.variant.price}${line.lineDiscount == '0' || line.lineDiscount.isEmpty ? '' : ' − ${line.lineDiscount}'}'),
                            onTap: () => _lineDiscount(context, line),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(onPressed: () => context.read<CartCubit>().decrement(line.key), icon: const Icon(Icons.remove)),
                                IconButton(onPressed: () => context.read<CartCubit>().increment(line.key), icon: const Icon(Icons.add)),
                                IconButton(onPressed: () => context.read<CartCubit>().remove(line.key), icon: const Icon(Icons.close)),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    _totalRow('Subtotal', totals.subtotal),
                    _totalRow('Discount', totals.discountAmount),
                    _totalRow('Tax', totals.taxAmount),
                    _totalRow('Total', totals.total, emphasize: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: adminOutlinedButtonStyle,
                            onPressed: cart.isEmpty ? null : () => context.read<CartCubit>().holdTicket(),
                            child: const Text('Hold'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: adminOutlinedButtonStyle,
                            onPressed: () => _recall(context),
                            child: Text('Recall (${context.read<CartCubit>().heldTickets.length})'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: adminPrimaryButtonStyle,
                        onPressed: cart.isEmpty ? null : () => payCurrentSale(context),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Proceed to Payment'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: emphasize ? const TextStyle(fontWeight: FontWeight.bold) : null)),
          Text(value, style: emphasize ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 20) : null),
        ],
      ),
    );
  }

  Future<void> _lineDiscount(BuildContext context, CartLine line) async {
    final amount = TextEditingController(text: line.lineDiscount == '0' ? '' : line.lineDiscount);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Discount · ${line.displayName}'),
        content: TextField(controller: amount, decoration: const InputDecoration(labelText: 'Line discount amount')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    context.read<CartCubit>().setLineDiscount(line.key, amount.text.trim().isEmpty ? '0' : amount.text.trim());
  }

  Future<void> _ticketMeta(BuildContext context, CartState cart) async {
    final customer = TextEditingController(text: cart.customerName ?? '');
    final phone = TextEditingController(text: cart.customerPhone ?? '');
    final table = TextEditingController(text: cart.tableNo ?? '');
    final note = TextEditingController(text: cart.note ?? '');
    final discount = TextEditingController(text: cart.orderDiscount);
    var type = cart.orderType;
    var guests = const <PosCustomer>[];
    try {
      guests = await sl<AdminRepository>().listCustomers();
    } catch (_) {}
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Ticket details'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: 'Order type'),
                        items: const [
                          DropdownMenuItem(value: 'DINE_IN', child: Text('Dine in')),
                          DropdownMenuItem(value: 'TAKEAWAY', child: Text('Takeaway')),
                          DropdownMenuItem(value: 'DELIVERY', child: Text('Delivery')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            type = value;
                            setLocal(() {});
                          }
                        },
                      ),
                      if (guests.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: '',
                          decoration: const InputDecoration(labelText: 'Saved customer'),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('Walk-in / new')),
                            for (final guest in guests)
                              DropdownMenuItem(value: guest.id, child: Text('${guest.name}${guest.phone == null || guest.phone!.isEmpty ? '' : ' · ${guest.phone}'}')),
                          ],
                          onChanged: (value) {
                            if (value == null || value.isEmpty) return;
                            final guest = guests.firstWhere((item) => item.id == value);
                            customer.text = guest.name;
                            phone.text = guest.phone ?? '';
                            setLocal(() {});
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(controller: customer, decoration: const InputDecoration(labelText: 'Customer name')),
                      const SizedBox(height: 12),
                      TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                      const SizedBox(height: 12),
                      TextField(controller: table, decoration: const InputDecoration(labelText: 'Table / token')),
                      const SizedBox(height: 12),
                      TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
                      const SizedBox(height: 12),
                      TextField(controller: discount, decoration: const InputDecoration(labelText: 'Order discount')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !context.mounted) return;
    context.read<CartCubit>().setOrderType(type);
    context.read<CartCubit>().setCustomer(name: customer.text.trim(), phone: phone.text.trim());
    context.read<CartCubit>().setTicketMeta(tableNo: table.text.trim(), note: note.text.trim(), discount: discount.text.trim());
    final name = customer.text.trim();
    if (name.isEmpty) return;
    final already = guests.any(
      (guest) => guest.name.toLowerCase() == name.toLowerCase() && (guest.phone ?? '') == phone.text.trim(),
    );
    if (!already) {
      try {
        await sl<AdminRepository>().saveCustomer(name: name, phone: phone.text.trim());
      } catch (_) {}
    }
  }

  Future<void> _recall(BuildContext context) async {
    final tickets = context.read<CartCubit>().heldTickets;
    if (tickets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No held tickets.')));
      return;
    }
    final id = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Recall ticket'),
          children: [
            for (final ticket in tickets)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, ticket.id),
                child: Text('${ticket.label} · ${ticket.cart.totals.total}'),
              ),
          ],
        );
      },
    );
    if (id != null && context.mounted) {
      await context.read<CartCubit>().recallTicket(id);
    }
  }
}

Future<void> payCurrentSale(BuildContext context) async {
  final cart = context.read<CartCubit>().state;
  if (cart.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add items before taking payment.')));
    return;
  }
  const methods = ['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER'];
  final total = money(cart.totals.total);
  final tendered = TextEditingController(text: cart.totals.total);
  final reference = TextEditingController();
  var method = 'CASH';
  Decimal parseTendered() {
    try {
      return money(tendered.text.trim().isEmpty ? '0' : tendered.text.trim());
    } catch (_) {
      return money('0');
    }
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          final paid = parseTendered();
          final change = paid - total;
          return AlertDialog(
            title: Text('Pay ${cart.totals.total}'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Method'),
                    items: [for (final item in methods) DropdownMenuItem(value: item, child: Text(item))],
                    onChanged: (value) {
                      if (value != null) {
                        method = value;
                        setLocal(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tendered,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount tendered'),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: reference, decoration: const InputDecoration(labelText: 'Reference (card / wallet)')),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(change >= money('0') ? 'Change: ${moneyString(change)}' : 'Short: ${moneyString(change.abs())}'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: change < money('0') ? null : () => Navigator.pop(context, true),
                child: const Text('Complete sale'),
              ),
            ],
          );
        },
      );
    },
  );
  if (confirmed != true || !context.mounted) return;
  final auth = context.read<AuthBloc>().state;
  if (auth is! AuthAuthenticated) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in again to complete this sale.')));
    return;
  }
  final session = auth.session;
  String? branchId;
  try {
    branchId = sl<TenantContext>().effectiveBranchId ?? session.branch?.id;
  } catch (_) {
    branchId = session.branch?.id;
  }
  if (branchId == null || branchId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a branch before taking payment.')));
    return;
  }
  final paid = parseTendered();
  await context.read<OrderCubit>().complete(
        CompleteSale(
          branchId: branchId,
          cart: context.read<CartCubit>().state,
          paymentMethod: method,
          referenceNo: reference.text.trim().isEmpty ? null : reference.text.trim(),
          tendered: moneyString(paid),
          change: moneyString(paid - total),
          businessName: session.business?.name,
          branchName: session.branch?.name,
          address: session.branch?.address ?? session.business?.address,
          phone: session.branch?.phone ?? session.business?.phone,
          cashierName: session.user.name,
          header: session.business?.receiptHeader,
          footer: session.business?.receiptFooter,
          paperWidthMm: session.business?.receiptPaperWidthMm ?? 80,
          showAddress: session.business?.receiptShowAddress ?? true,
          showPhone: session.business?.receiptShowPhone ?? true,
          online: context.read<SyncCubit>().state.online,
        ),
      );
}

class PosShortcuts extends StatelessWidget {
  const PosShortcuts({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => context.read<CartCubit>().clear(),
        const SingleActivator(LogicalKeyboardKey.f3): () => context.read<CartCubit>().holdTicket(),
        const SingleActivator(LogicalKeyboardKey.f4): () => payCurrentSale(context),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
