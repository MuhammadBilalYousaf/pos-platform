import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:decimal/decimal.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../admin/presentation/bloc/branch_context_cubit.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/domain/permissions.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/dashboard_repository.dart';
import '../../data/reports_models.dart';
import '../widgets/report_widgets.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _preset = 'This Month';
  BusinessAnalytics? _data;
  String? _error;
  bool _loading = true;
  bool _sortTopByUnits = true;
  String? _filterCategoryId;
  String? _filterProductId;
  String? _filterEmployee;
  String? _filterPayment;
  String? _trendProductId;
  String _trendGranularity = 'Daily';

  static const _presets = [
    'Today',
    'Yesterday',
    'This Week',
    'Last Week',
    'This Month',
    'Last Month',
    'Custom',
  ];

  static const _tabLabels = [
    'Overview',
    'Sales',
    'Products',
    'Categories',
    'Branches',
    'Employees',
    'Payments',
    'Discounts & Refunds',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _preset = preset;
      switch (preset) {
        case 'Today':
          _from = today;
          _to = today;
        case 'Yesterday':
          _from = today.subtract(const Duration(days: 1));
          _to = _from;
        case 'This Week':
          _from = today.subtract(Duration(days: today.weekday - 1));
          _to = today;
        case 'Last Week':
          final thisWeek = today.subtract(Duration(days: today.weekday - 1));
          _from = thisWeek.subtract(const Duration(days: 7));
          _to = thisWeek.subtract(const Duration(days: 1));
        case 'This Month':
          _from = DateTime(now.year, now.month, 1);
          _to = today;
        case 'Last Month':
          _from = DateTime(now.year, now.month - 1, 1);
          _to = DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
        default:
          break;
      }
    });
    if (preset != 'Custom') _load();
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null) return;
    setState(() {
      _preset = 'Custom';
      _from = range.start;
      _to = range.end;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthBloc>().state;
      final branches = auth is AuthAuthenticated ? auth.session.accessibleBranches : const <BranchProfile>[];
      final data = await sl<DashboardRepository>().analyticsRange(
        from: _from,
        to: _to,
        branches: branches,
        filters: ReportFilters(
          categoryId: _filterCategoryId,
          productId: _filterProductId,
          employeeKey: _filterEmployee,
          paymentMethod: _filterPayment,
        ),
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _trendProductId ??= data.productCatalog.isEmpty ? null : data.productCatalog.first.id;
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

  Future<void> _exportCsv() async {
    final data = _data;
    if (data == null) return;
    final buf = StringBuffer()
      ..writeln('Metric,Value')
      ..writeln('From,${DateFormat('yyyy-MM-dd').format(data.from)}')
      ..writeln('To,${DateFormat('yyyy-MM-dd').format(data.to)}')
      ..writeln('Total Sales,${formatRs(data.totalSales)}')
      ..writeln('Total Orders,${data.totalOrders}')
      ..writeln('Average Order Value,${formatRs(data.averageOrderValue)}')
      ..writeln('Total Items,${data.totalItems}')
      ..writeln('Total Discounts,${formatRs(data.totalDiscounts)}')
      ..writeln('Total Tax,${formatRs(data.totalTax)}')
      ..writeln('Net Sales,${formatRs(data.netSales)}')
      ..writeln('Cancelled Orders,${data.cancelledOrders}');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report summary copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final canExport = auth is AuthAuthenticated && auth.session.user.can(PosPermissions.reportExport);
    final branchState = context.watch<BranchContextCubit>().state;

    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) => _load(),
        child: ColoredBox(
          color: const Color(0xFFF8FAFC),
          child: PageFrame(
          title: 'Reports',
          subtitle: 'Analyze your business performance with detailed reports and insights.',
          actions: [
            _DateRangeButton(
              from: _from,
              to: _to,
              onTap: _pickCustomRange,
            ),
            const SizedBox(width: 8),
            if (branchState.showSwitcher) _BranchFilter(state: branchState),
            if (canExport) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kReportAccent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _data == null ? null : _exportCsv,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Export'),
              ),
            ],
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PresetChips(selected: _preset, onSelected: _applyPreset, onCustom: _pickCustomRange),
              const SizedBox(height: 8),
              _FilterBar(
                data: _data,
                categoryId: _filterCategoryId,
                productId: _filterProductId,
                employeeKey: _filterEmployee,
                paymentMethod: _filterPayment,
                onChanged: (cat, prod, emp, pay) {
                  setState(() {
                    _filterCategoryId = cat;
                    _filterProductId = prod;
                    _filterEmployee = emp;
                    _filterPayment = pay;
                  });
                  _load();
                },
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                labelColor: kReportAccent,
                unselectedLabelColor: kReportMuted,
                indicatorColor: kReportAccent,
                tabs: [for (final label in _tabLabels) Tab(text: label)],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: kReportAccent))
                    : _error != null
                        ? Center(child: Text(_error!))
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              _OverviewTab(
                                data: _data!,
                                sortTopByUnits: _sortTopByUnits,
                                onSortChanged: (v) => setState(() => _sortTopByUnits = v),
                                trendProductId: _trendProductId,
                                onTrendProduct: (id) => setState(() => _trendProductId = id),
                                trendGranularity: _trendGranularity,
                                onGranularity: (v) => setState(() => _trendGranularity = v),
                              ),
                              _SalesTab(data: _data!, granularity: _trendGranularity, onGranularity: (v) => setState(() => _trendGranularity = v)),
                              _ProductsTab(
                                data: _data!,
                                sortTopByUnits: _sortTopByUnits,
                                onSortChanged: (v) => setState(() => _sortTopByUnits = v),
                                trendProductId: _trendProductId,
                                onTrendProduct: (id) => setState(() => _trendProductId = id),
                              ),
                              _CategoriesTab(data: _data!),
                              _BranchesTab(data: _data!),
                              _EmployeesTab(data: _data!),
                              _PaymentsTab(data: _data!),
                              _DiscountsTab(data: _data!),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChips extends StatelessWidget {
  const _PresetChips({required this.selected, required this.onSelected, required this.onCustom});
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      children: [
        for (final preset in _ReportsPageState._presets)
          ChoiceChip(
            label: Text(preset, style: const TextStyle(fontSize: 12)),
            selected: selected == preset,
            selectedColor: kReportAccentSoft,
            labelStyle: TextStyle(
              color: selected == preset ? kReportAccent : kReportMuted,
              fontWeight: selected == preset ? FontWeight.w700 : FontWeight.w500,
            ),
            onSelected: (_) {
              if (preset == 'Custom') {
                onCustom();
              } else {
                onSelected(preset);
              }
            },
          ),
      ],
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({required this.from, required this.to, required this.onTap});
  final DateTime from;
  final DateTime to;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label =
        '${DateFormat('MMM d, yyyy').format(from)} - ${DateFormat('MMM d, yyyy').format(to)}';
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_month_rounded, size: 18),
      label: Text(label),
    );
  }
}

class _BranchFilter extends StatelessWidget {
  const _BranchFilter({required this.state});
  final BranchContextState state;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: kReportCardBorder),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: DropdownButton<String?>(
          value: state.selectedBranchId,
          hint: const Text('All Branches'),
          items: [
            if (state.allowAll) const DropdownMenuItem<String?>(value: null, child: Text('All Branches')),
            for (final branch in state.branches)
              DropdownMenuItem<String?>(value: branch.id, child: Text(branch.name)),
          ],
          onChanged: (value) => context.read<BranchContextCubit>().select(value),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.data,
    required this.categoryId,
    required this.productId,
    required this.employeeKey,
    required this.paymentMethod,
    required this.onChanged,
  });

  final BusinessAnalytics? data;
  final String? categoryId;
  final String? productId;
  final String? employeeKey;
  final String? paymentMethod;
  final void Function(String? cat, String? prod, String? emp, String? pay) onChanged;

  @override
  Widget build(BuildContext context) {
    final categories = data?.categories ?? const [];
    final products = data?.productCatalog ?? const [];
    final employees = data?.employees ?? const [];
    final payments = data?.payments ?? const [];
    final safeCategory =
        categories.any((c) => c.id == categoryId) ? categoryId : null;
    final safeProduct = products.any((p) => p.id == productId) ? productId : null;
    final safeEmployee = employees.any((e) => e.key == employeeKey) ? employeeKey : null;
    final safePayment = payments.any((p) => p.id == paymentMethod) ? paymentMethod : null;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _miniDropdown<String?>(
          label: 'Category',
          value: safeCategory,
          items: [
            const DropdownMenuItem(value: null, child: Text('All categories')),
            for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => onChanged(v, productId, employeeKey, paymentMethod),
        ),
        _miniDropdown<String?>(
          label: 'Product',
          value: safeProduct,
          items: [
            const DropdownMenuItem(value: null, child: Text('All products')),
            for (final p in products) DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => onChanged(categoryId, v, employeeKey, paymentMethod),
        ),
        _miniDropdown<String?>(
          label: 'Employee',
          value: safeEmployee,
          items: [
            const DropdownMenuItem(value: null, child: Text('All employees')),
            for (final e in employees) DropdownMenuItem(value: e.key, child: Text(e.name)),
          ],
          onChanged: (v) => onChanged(categoryId, productId, v, paymentMethod),
        ),
        _miniDropdown<String?>(
          label: 'Payment',
          value: safePayment,
          items: [
            const DropdownMenuItem(value: null, child: Text('All methods')),
            for (final p in payments) DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => onChanged(categoryId, productId, employeeKey, v),
        ),
      ],
    );
  }

  Widget _miniDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kReportCardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(label),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.data,
    required this.sortTopByUnits,
    required this.onSortChanged,
    required this.trendProductId,
    required this.onTrendProduct,
    required this.trendGranularity,
    required this.onGranularity,
  });

  final BusinessAnalytics data;
  final bool sortTopByUnits;
  final ValueChanged<bool> onSortChanged;
  final String? trendProductId;
  final ValueChanged<String?> onTrendProduct;
  final String trendGranularity;
  final ValueChanged<String> onGranularity;

  @override
  Widget build(BuildContext context) {
    final trends = data.kpiTrends;
    return ListView(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cols = width >= 1400
                ? 5
                : width >= 1100
                    ? 4
                    : width >= 800
                        ? 3
                        : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                ReportKpiCard(
                  label: 'Total Sales',
                  value: formatRs(data.totalSales),
                  icon: Icons.payments_rounded,
                  trendPercent: trends['sales']?.percentChange,
                ),
                ReportKpiCard(
                  label: 'Total Orders',
                  value: '${data.totalOrders}',
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFF2563EB),
                  trendPercent: trends['orders']?.percentChange,
                ),
                ReportKpiCard(
                  label: 'Average Order Value',
                  value: formatRs(data.averageOrderValue),
                  icon: Icons.shopping_bag_rounded,
                  iconColor: const Color(0xFF0891B2),
                  trendPercent: trends['aov']?.percentChange,
                ),
                ReportKpiCard(
                  label: 'Total Items Sold',
                  value: data.totalItems.toStringAsFixed(data.totalItems % 1 == 0 ? 0 : 1),
                  icon: Icons.inventory_2_rounded,
                  iconColor: const Color(0xFF059669),
                  trendPercent: trends['items']?.percentChange,
                ),
                ReportKpiCard(
                  label: 'Total Discounts',
                  value: formatRs(data.totalDiscounts),
                  icon: Icons.local_offer_rounded,
                  iconColor: const Color(0xFFD97706),
                  trendPercent: trends['discounts']?.percentChange,
                ),
                ReportKpiCard(
                  label: 'Total Tax',
                  value: formatRs(data.totalTax),
                  icon: Icons.account_balance_rounded,
                  iconColor: const Color(0xFF7C3AED),
                  trendPercent: trends['tax']?.percentChange,
                ),
                ReportKpiCard(
                  label: 'Net Sales',
                  value: formatRs(data.netSales),
                  icon: Icons.trending_up_rounded,
                  iconColor: const Color(0xFF16A34A),
                  trendPercent: trends['net']?.percentChange,
                ),
                ReportKpiCard(
                  label: 'Refunds',
                  value: formatRs(data.refunds),
                  icon: Icons.undo_rounded,
                  iconColor: const Color(0xFFDC2626),
                  subtitle: 'Not tracked in orders yet',
                ),
                ReportKpiCard(
                  label: 'Cancelled Orders',
                  value: '${data.cancelledOrders}',
                  icon: Icons.cancel_outlined,
                  iconColor: const Color(0xFFEF4444),
                  trendPercent: trends['cancelled']?.percentChange,
                  subtitle: formatRs(data.cancelledValue),
                ),
                ReportKpiCard(
                  label: 'Top Selling Product',
                  value: data.topProductName,
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  subtitle: '${data.topProductUnits.toStringAsFixed(0)} units sold',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ResponsiveChartRow(
          height: 280,
          children: [
            ReportSectionCard(
              title: data.from.year == data.to.year &&
                      data.from.month == data.to.month &&
                      data.from.day == data.to.day
                  ? 'Sales Trend (Hourly)'
                  : 'Sales Trend',
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: trendGranularity,
                  items: const [
                    DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                  ],
                  onChanged: (v) {
                    if (v != null) onGranularity(v);
                  },
                ),
              ),
              child: _TrendByGranularity(data: data, granularity: trendGranularity),
            ),
            ReportSectionCard(
              title: 'Sales by Day of Week',
              child: ReportBarChart(
                values: [for (final d in data.weekdayTrends) d.avgSales.toDouble()],
                labels: [for (final d in data.weekdayTrends) d.label],
              ),
            ),
            ReportSectionCard(
              title: 'Hourly Sales Trend',
              child: ReportBarChart(
                scrollable: true,
                barWidth: 20,
                minBarSlotWidth: 64,
                values: [for (final h in data.hourly) h.sales.toDouble()],
                labels: [for (final h in data.hourly) h.label],
              ),
            ),
          ],
          flex: const [2, 1, 1],
        ),
        const SizedBox(height: 16),
        _ResponsiveChartRow(
          height: 320,
          children: [
            ReportSectionCard(
              title: 'Top Selling Products',
              trailing: TextButton(
                onPressed: () => onSortChanged(!sortTopByUnits),
                child: Text(sortTopByUnits ? 'Sort: Units' : 'Sort: Revenue'),
              ),
              child: ReportProductTable(rows: data.topProducts, sortByUnits: sortTopByUnits),
            ),
            ReportSectionCard(
              title: 'Least Selling Products',
              child: ReportProductTable(rows: data.leastProducts, sortByUnits: true),
            ),
            ReportSectionCard(
              title: 'Category Performance',
              child: ReportDonutChart(
                slices: data.categories,
                centerLabel: 'Total Sales',
                centerValue: formatRs(data.totalSales),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ResponsiveChartRow(
          height: 280,
          children: [
            ReportSectionCard(
              title: 'Branch Performance',
              child: _BranchTable(rows: data.branches),
            ),
            ReportSectionCard(
              title: 'Employee Performance',
              child: _EmployeeTable(rows: data.employees),
            ),
            ReportSectionCard(
              title: 'Payment Methods',
              child: ReportDonutChart(
                slices: data.payments,
                centerLabel: 'Total Sales',
                centerValue: formatRs(data.totalSales),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Sales Comparison', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1100 ? 4 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: [for (final c in data.comparisons) ReportComparisonCard(item: c)],
            );
          },
        ),
        const SizedBox(height: 16),
        ReportSectionCard(
          title: 'Discounts, Refunds & Cancellations',
          height: 140,
          child: _DiscountSummary(stats: data.discountRefunds, sales: data.totalSales),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 260,
          child: ReportSectionCard(
            title: 'Product Sales Trend',
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: data.productCatalog.any((p) => p.id == trendProductId) ? trendProductId : null,
                hint: const Text('Select product'),
                items: [
                  for (final p in data.productCatalog)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: onTrendProduct,
              ),
            ),
            child: _ProductTrendChart(data: data, productId: trendProductId),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ResponsiveChartRow extends StatelessWidget {
  const _ResponsiveChartRow({
    required this.children,
    required this.height,
    this.flex = const [],
  });

  final List<Widget> children;
  final double height;
  final List<int> flex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                SizedBox(height: height, child: children[i]),
              ],
            ],
          );
        }
        return SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  flex: i < flex.length ? flex[i] : 1,
                  child: children[i],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TrendByGranularity extends StatelessWidget {
  const _TrendByGranularity({required this.data, required this.granularity});
  final BusinessAnalytics data;
  final String granularity;

  bool get _sameDay =>
      data.from.year == data.to.year && data.from.month == data.to.month && data.from.day == data.to.day;

  @override
  Widget build(BuildContext context) {
    switch (granularity) {
      case 'Weekly':
        if (data.weekly.isEmpty) return const Center(child: Text('No sales in this range'));
        return ReportBarChart(
          values: [for (final w in data.weekly) w.sales.toDouble()],
          labels: [for (final w in data.weekly) w.label.split(' · ').first],
        );
      case 'Monthly':
        if (data.monthly.isEmpty) return const Center(child: Text('No sales in this range'));
        return ReportBarChart(
          values: [for (final m in data.monthly) m.sales.toDouble()],
          labels: [for (final m in data.monthly) m.label],
        );
      default:
        // Today / Yesterday: a 1-point daily line is invisible — show hourly instead.
        if (_sameDay || data.daily.length <= 1) {
          if (data.hourly.every((h) => h.sales == Decimal.zero)) {
            return const Center(child: Text('No sales in this range'));
          }
          return ReportBarChart(
            scrollable: true,
            barWidth: 20,
            minBarSlotWidth: 64,
            values: [for (final h in data.hourly) h.sales.toDouble()],
            labels: [for (final h in data.hourly) h.label],
          );
        }
        return ReportSalesLineChart(days: data.daily);
    }
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({required this.data, required this.granularity, required this.onGranularity});
  final BusinessAnalytics data;
  final String granularity;
  final ValueChanged<String> onGranularity;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: 320,
          child: ReportSectionCard(
            title: 'Sales Trend',
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: granularity,
                items: const [
                  DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                ],
                onChanged: (v) {
                  if (v != null) onGranularity(v);
                },
              ),
            ),
            child: _TrendByGranularity(data: data, granularity: granularity),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: Row(
            children: [
              Expanded(
                child: ReportSectionCard(
                  title: 'Day-of-Week Averages',
                  child: ReportBarChart(
                    values: [for (final d in data.weekdayTrends) d.avgSales.toDouble()],
                    labels: [for (final d in data.weekdayTrends) d.label],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ReportSectionCard(
                  title: 'Peak Hours',
                  child: ReportBarChart(
                    scrollable: true,
                    barWidth: 18,
                    minBarSlotWidth: 56,
                    values: [for (final h in data.hourly) h.sales.toDouble()],
                    labels: [for (final h in data.hourly) h.label],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ReportSectionCard(
          title: 'Daily Breakdown',
          height: 360,
          child: _DailyTable(days: data.daily),
        ),
      ],
    );
  }
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({
    required this.data,
    required this.sortTopByUnits,
    required this.onSortChanged,
    required this.trendProductId,
    required this.onTrendProduct,
  });

  final BusinessAnalytics data;
  final bool sortTopByUnits;
  final ValueChanged<bool> onSortChanged;
  final String? trendProductId;
  final ValueChanged<String?> onTrendProduct;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: 360,
          child: Row(
            children: [
              Expanded(
                child: ReportSectionCard(
                  title: 'Top Selling Products',
                  trailing: TextButton(
                    onPressed: () => onSortChanged(!sortTopByUnits),
                    child: Text(sortTopByUnits ? 'Sort: Units' : 'Sort: Revenue'),
                  ),
                  child: ReportProductTable(rows: data.topProducts, sortByUnits: sortTopByUnits),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ReportSectionCard(
                  title: 'Least Selling Products',
                  child: ReportProductTable(rows: data.leastProducts, sortByUnits: true),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 280,
          child: ReportSectionCard(
            title: 'Product Sales Trend',
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: trendProductId,
                hint: const Text('Select product'),
                items: [
                  for (final p in data.productCatalog)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: onTrendProduct,
              ),
            ),
            child: _ProductTrendChart(data: data, productId: trendProductId),
          ),
        ),
      ],
    );
  }
}

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab({required this.data});
  final BusinessAnalytics data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: 320,
          child: Row(
            children: [
              Expanded(
                child: ReportSectionCard(
                  title: 'Category Mix',
                  child: ReportDonutChart(
                    slices: data.categories,
                    centerLabel: 'Total Sales',
                    centerValue: formatRs(data.totalSales),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ReportSectionCard(
                  title: 'Category Revenue',
                  child: ReportBarChart(
                    values: [for (final c in data.categories.take(8)) c.amount.toDouble()],
                    labels: [for (final c in data.categories.take(8)) c.name.split(' ').first],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ReportSectionCard(
          title: 'Category Details',
          height: 360,
          child: _NamedAmountTable(rows: data.categories),
        ),
      ],
    );
  }
}

class _BranchesTab extends StatelessWidget {
  const _BranchesTab({required this.data});
  final BusinessAnalytics data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: 300,
          child: ReportSectionCard(
            title: 'Branch Comparison',
            child: ReportBarChart(
              values: [for (final b in data.branches) b.sales.toDouble()],
              labels: [for (final b in data.branches) b.name.split(' ').take(2).join(' ')],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ReportSectionCard(
          title: 'Branch Performance',
          height: 360,
          child: _BranchTable(rows: data.branches),
        ),
      ],
    );
  }
}

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab({required this.data});
  final BusinessAnalytics data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ReportSectionCard(
          title: 'Employee / Cashier Performance',
          height: 480,
          child: _EmployeeTable(rows: data.employees, detailed: true),
        ),
      ],
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.data});
  final BusinessAnalytics data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: 320,
          child: Row(
            children: [
              Expanded(
                child: ReportSectionCard(
                  title: 'Payment Mix',
                  child: ReportDonutChart(
                    slices: data.payments,
                    centerLabel: 'Total Sales',
                    centerValue: formatRs(data.totalSales),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ReportSectionCard(
                  title: 'Payment Amounts',
                  child: ReportBarChart(
                    values: [for (final p in data.payments) p.amount.toDouble()],
                    labels: [for (final p in data.payments) p.name],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ReportSectionCard(
          title: 'Payment Details',
          height: 300,
          child: _NamedAmountTable(rows: data.payments),
        ),
      ],
    );
  }
}

class _DiscountsTab extends StatelessWidget {
  const _DiscountsTab({required this.data});
  final BusinessAnalytics data;

  @override
  Widget build(BuildContext context) {
    final s = data.discountRefunds;
    return ListView(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 900 ? 3 : 1;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                ReportKpiCard(
                  label: 'Total Discounts',
                  value: formatRs(s.discountTotal),
                  icon: Icons.local_offer_rounded,
                  subtitle: '${s.discountedOrders} discounted orders · ${s.discountPercentOfSales.toStringAsFixed(1)}% of sales',
                ),
                ReportKpiCard(
                  label: 'Refunds',
                  value: formatRs(s.refundTotal),
                  icon: Icons.undo_rounded,
                  iconColor: kReportDanger,
                  subtitle: '${s.refundCount} refunds (not stored on orders yet)',
                ),
                ReportKpiCard(
                  label: 'Cancellations',
                  value: '${s.cancelledCount}',
                  icon: Icons.cancel_outlined,
                  iconColor: kReportDanger,
                  subtitle: '${formatRs(s.cancelledValue)} · ${s.cancelledPercentOfOrders.toStringAsFixed(1)}% of tickets',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text('Period Comparisons', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1100 ? 4 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: [for (final c in data.comparisons) ReportComparisonCard(item: c)],
            );
          },
        ),
      ],
    );
  }
}

class _BranchTable extends StatelessWidget {
  const _BranchTable({required this.rows});
  final List<BranchPerfRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No branch data'));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        final up = row.growthPercent >= 0;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${row.orders} orders · AOV ${formatRs(row.aov)}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatRs(row.sales), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                formatPct(row.growthPercent),
                style: TextStyle(color: up ? kReportSuccess : kReportDanger, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmployeeTable extends StatelessWidget {
  const _EmployeeTable({required this.rows, this.detailed = false});
  final List<EmployeePerfRow> rows;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No employee sales in this range'));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: kReportAccentSoft,
            child: Text(
              row.name.isEmpty ? '?' : row.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(color: kReportAccent, fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            detailed
                ? '${row.orders} orders · ${row.items.toStringAsFixed(0)} items · discounts ${formatRs(row.discounts)} · cancels ${row.cancellations}'
                : '${row.orders} orders · AOV ${formatRs(row.aov)}',
          ),
          trailing: Text(formatRs(row.sales), style: const TextStyle(fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

class _DailyTable extends StatelessWidget {
  const _DailyTable({required this.days});
  final List<DayBucket> days;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: days.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final d = days[days.length - 1 - i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(DateFormat('EEEE, MMM d').format(d.date)),
          subtitle: Text('${d.orders} orders · ${d.items.toStringAsFixed(0)} items · AOV ${formatRs(d.aov)}'),
          trailing: Text(formatRs(d.sales), style: const TextStyle(fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

class _NamedAmountTable extends StatelessWidget {
  const _NamedAmountTable({required this.rows});
  final List<NamedAmount> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No data'));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(row.name),
          subtitle: Text('${row.share.toStringAsFixed(1)}% of sales · ${row.units.toStringAsFixed(0)} items'),
          trailing: Text(formatRs(row.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

class _DiscountSummary extends StatelessWidget {
  const _DiscountSummary({required this.stats, required this.sales});
  final DiscountRefundStats stats;
  final dynamic sales;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Discounts: ${formatRs(stats.discountTotal)} (${stats.discountPercentOfSales.toStringAsFixed(1)}% of sales) across ${stats.discountedOrders} orders',
          ),
        ),
        Expanded(
          child: Text(
            'Refunds: ${formatRs(stats.refundTotal)} (${stats.refundCount}) — refund amounts are not stored on order documents yet',
          ),
        ),
        Expanded(
          child: Text(
            'Cancellations: ${stats.cancelledCount} · ${formatRs(stats.cancelledValue)} (${stats.cancelledPercentOfOrders.toStringAsFixed(1)}% of tickets)',
          ),
        ),
      ],
    );
  }
}

class _ProductTrendChart extends StatelessWidget {
  const _ProductTrendChart({required this.data, required this.productId});
  final BusinessAnalytics data;
  final String? productId;

  @override
  Widget build(BuildContext context) {
    if (productId == null) return const Center(child: Text('Select a product'));
    final points = data.productTrends[productId] ?? const <ProductTrendPoint>[];
    if (points.isEmpty) return const Center(child: Text('No sales for this product in range'));
    final days = [
      for (final p in points)
        DayBucket(date: p.date, sales: p.revenue, orders: 0, items: p.units),
    ];
    return ReportSalesLineChart(days: days);
  }
}
