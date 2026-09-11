import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../admin/presentation/bloc/branch_context_cubit.dart';
import '../../../sync/presentation/bloc/sync_cubit.dart';
import '../../data/dashboard_repository.dart';
import '../../data/home_dashboard_models.dart';
import '../../data/reports_models.dart';
import '../widgets/business_shell.dart';
import '../widgets/report_widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  HomeDashboardSnapshot? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await sl<DashboardRepository>().homeToday();
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) {
        setState(() => _loading = true);
        _load();
      },
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: kShellAccent))
          : _error != null
              ? Center(child: Text(_error!))
              : _DashboardBody(data: _data!, onRefresh: _load),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data, required this.onRefresh});
  final HomeDashboardSnapshot data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncCubit>().state;
    final topProduct = data.topProducts.isEmpty ? null : data.topProducts.first;
    final salesUp = data.salesVsYesterdayPct >= 0;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dashboard',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1200
                  ? 4
                  : c.maxWidth >= 800
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: cols == 1 ? 2.4 : 1.65,
                children: [
                  _DashKpi(
                    label: 'Total Sales',
                    value: formatRs(data.total),
                    trend: data.salesVsYesterdayPct,
                    icon: Icons.payments_rounded,
                    color: const Color(0xFF16A34A),
                  ),
                  _DashKpi(
                    label: 'Total Orders',
                    value: '${data.orderCount}',
                    trend: data.ordersVsYesterdayPct,
                    icon: Icons.receipt_long_rounded,
                    color: const Color(0xFF2563EB),
                  ),
                  _DashKpi(
                    label: 'Average Order Value',
                    value: formatRs(data.averageTicket),
                    trend: data.aovVsYesterdayPct,
                    icon: Icons.shopping_bag_outlined,
                    color: kShellAccent,
                  ),
                  _DashKpi(
                    label: 'Items Sold',
                    value: data.itemsSold.toStringAsFixed(data.itemsSold % 1 == 0 ? 0 : 1),
                    trend: data.itemsVsYesterdayPct,
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFFEA580C),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 1000) {
                return Column(
                  children: [
                    _chartCard('Today\'s Sales', _TodaySalesChart(hourly: data.hourlyToday)),
                    const SizedBox(height: 12),
                    _chartCard(
                      'Sales by Category',
                      ReportDonutChart(
                        slices: data.categoriesToday,
                        centerLabel: 'Total Sales',
                        centerValue: formatRs(data.total),
                      ),
                      height: 280,
                    ),
                    const SizedBox(height: 12),
                    _chartCard(
                      'Payment Methods',
                      ReportDonutChart(
                        slices: data.paymentSlices,
                        centerLabel: 'Total Sales',
                        centerValue: formatRs(data.total),
                      ),
                      height: 280,
                    ),
                  ],
                );
              }
              return SizedBox(
                height: 300,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _chartCard('Today\'s Sales', _TodaySalesChart(hourly: data.hourlyToday)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _chartCard(
                        'Sales by Category',
                        ReportDonutChart(
                          slices: data.categoriesToday,
                          centerLabel: 'Total Sales',
                          centerValue: formatRs(data.total),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _chartCard(
                        'Payment Methods',
                        ReportDonutChart(
                          slices: data.paymentSlices,
                          centerLabel: 'Total Sales',
                          centerValue: formatRs(data.total),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 1000) {
                return Column(
                  children: [
                    _chartCard('Top Selling Products', _TopProductsTable(rows: data.topProducts), height: 320),
                    const SizedBox(height: 12),
                    _chartCard('Recent Orders', _RecentOrdersTable(rows: data.recentOrderRows), height: 320),
                    const SizedBox(height: 12),
                    _chartCard('Low Stock Items', _LowStockTable(rows: data.lowStockItems), height: 260),
                  ],
                );
              }
              return SizedBox(
                height: 340,
                child: Row(
                  children: [
                    Expanded(child: _chartCard('Top Selling Products', _TopProductsTable(rows: data.topProducts))),
                    const SizedBox(width: 12),
                    Expanded(child: _chartCard('Recent Orders', _RecentOrdersTable(rows: data.recentOrderRows))),
                    const SizedBox(width: 12),
                    Expanded(child: _chartCard('Low Stock Items', _LowStockTable(rows: data.lowStockItems))),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1000 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: cols == 4 ? 1.55 : 1.35,
                children: [
                  _MiniInsightCard(
                    title: 'Today\'s Special',
                    subtitle: topProduct?.name ?? 'No sales yet',
                    detail: topProduct == null
                        ? 'Complete a sale to highlight a product.'
                        : '${topProduct.units.toStringAsFixed(0)} sold · ${formatRs(topProduct.revenue)}',
                    icon: Icons.star_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                  _MiniInsightCard(
                    title: 'Today vs Yesterday',
                    subtitle: salesUp ? 'Sales are higher than yesterday' : 'Sales are lower than yesterday',
                    detail:
                        '${formatRs(data.total)} vs ${formatRs(data.yesterdaySales)} (${formatPct(data.salesVsYesterdayPct)})',
                    icon: salesUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                    color: salesUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                  _MiniInsightCard(
                    title: 'Total Customers Today',
                    subtitle: '${data.customersToday}',
                    detail: 'Unique customers from orders today',
                    icon: Icons.people_outline,
                    color: const Color(0xFF0EA5E9),
                  ),
                  _MiniInsightCard(
                    title: 'Pending Orders',
                    subtitle: '${sync.pendingCount}',
                    detail: sync.pendingCount == 0 ? 'All orders synced' : 'Waiting to sync when online',
                    icon: Icons.schedule_rounded,
                    color: const Color(0xFFEC4899),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _chartCard(String title, Widget child, {double? height}) {
    return Container(
      height: height ?? 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kReportCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DashKpi extends StatelessWidget {
  const _DashKpi({
    required this.label,
    required this.value,
    required this.trend,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final double trend;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final up = trend >= 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kReportCardBorder),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                formatPct(trend),
                style: TextStyle(
                  color: up ? kReportSuccess : kReportDanger,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(label, style: const TextStyle(color: kReportMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          Text('vs yesterday', style: TextStyle(color: kReportMuted.withValues(alpha: 0.8), fontSize: 11)),
        ],
      ),
    );
  }
}

class _TodaySalesChart extends StatelessWidget {
  const _TodaySalesChart({required this.hourly});
  final List<HourBucket> hourly;

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty || hourly.every((h) => h.sales == Decimal.zero)) {
      return const Center(child: Text('No sales yet today'));
    }
    return ReportBarChart(
      scrollable: true,
      barWidth: 20,
      minBarSlotWidth: 64,
      highlightMax: true,
      values: [for (final h in hourly) h.sales.toDouble()],
      labels: [for (final h in hourly) h.label],
    );
  }
}

class _TopProductsTable extends StatelessWidget {
  const _TopProductsTable({required this.rows});
  final List<ProductSalesRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No product sales today'));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: kShellAccentSoft,
            child: Text('${i + 1}', style: const TextStyle(color: kShellAccent, fontWeight: FontWeight.w800)),
          ),
          title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${row.units.toStringAsFixed(0)} sold'),
          trailing: Text(formatRs(row.revenue), style: const TextStyle(fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

class _RecentOrdersTable extends StatelessWidget {
  const _RecentOrdersTable({required this.rows});
  final List<DashboardRecentOrder> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No orders yet today'));
    return Column(
      children: [
        const Row(
          children: [
            Expanded(flex: 2, child: Text('Order', style: TextStyle(color: kReportMuted, fontSize: 11))),
            Expanded(child: Text('Time', style: TextStyle(color: kReportMuted, fontSize: 11))),
            Expanded(flex: 2, child: Text('Customer', style: TextStyle(color: kReportMuted, fontSize: 11))),
            Expanded(child: Text('Total', textAlign: TextAlign.right, style: TextStyle(color: kReportMuted, fontSize: 11))),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = rows[i];
              final completed = row.status == 'COMPLETED';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text('#${row.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(child: Text(row.timeLabel, style: const TextStyle(fontSize: 12))),
                    Expanded(flex: 2, child: Text(row.customer, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(row.total, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: completed ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              completed ? 'Completed' : row.status,
                              style: TextStyle(
                                fontSize: 10,
                                color: completed ? const Color(0xFF166534) : const Color(0xFF991B1B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LowStockTable extends StatelessWidget {
  const _LowStockTable({required this.rows});
  final List<LowStockItem> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No low stock alerts'));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('Min ${row.reorder}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(row.current, style: const TextStyle(color: kReportDanger, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              const Icon(Icons.warning_amber_rounded, color: kReportDanger, size: 18),
            ],
          ),
        );
      },
    );
  }
}

class _MiniInsightCard extends StatelessWidget {
  const _MiniInsightCard({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kReportCardBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Text(subtitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: kReportMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
