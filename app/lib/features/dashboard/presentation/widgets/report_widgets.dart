import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/reports_models.dart';

/// Reports accent matching the analytics mock (purple).
const Color kReportAccent = Color(0xFF7C3AED);
const Color kReportAccentSoft = Color(0xFFF3E8FF);
const Color kReportSuccess = Color(0xFF16A34A);
const Color kReportDanger = Color(0xFFDC2626);
const Color kReportCardBorder = Color(0xFFE5E7EB);
const Color kReportMuted = Color(0xFF6B7280);

class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.height,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kReportCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class ReportKpiCard extends StatelessWidget {
  const ReportKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.trendPercent,
    this.subtitle,
    this.iconColor = kReportAccent,
  });

  final String label;
  final String value;
  final IconData icon;
  final double? trendPercent;
  final String? subtitle;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final trend = trendPercent;
    final up = trend == null || trend >= 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kReportCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const Spacer(),
              if (trend != null)
                Text(
                  formatPct(trend),
                  style: TextStyle(
                    color: up ? kReportSuccess : kReportDanger,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: kReportMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: const TextStyle(color: kReportMuted, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class ReportSalesLineChart extends StatelessWidget {
  const ReportSalesLineChart({super.key, required this.days});

  final List<DayBucket> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Center(child: Text('No sales in this range'));
    final maxY = days.fold<double>(0, (m, d) => d.sales.toDouble() > m ? d.sales.toDouble() : m);
    final spots = <FlSpot>[
      for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), days[i].sales.toDouble()),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, _) => Text(
                _shortMoney(v),
                style: const TextStyle(fontSize: 10, color: kReportMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (days.length / 6).clamp(1, 999).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.round();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('d MMM').format(days[i].date),
                    style: const TextStyle(fontSize: 10, color: kReportMuted),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => [
              for (final t in touched)
                LineTooltipItem(
                  '${DateFormat('MMM d').format(days[t.x.toInt()].date)}\n${formatRs(Decimal.parse(t.y.toString()))}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: kReportAccent,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  kReportAccent.withValues(alpha: 0.28),
                  kReportAccent.withValues(alpha: 0.02),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReportBarChart extends StatelessWidget {
  const ReportBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.highlightMax = true,
  });

  final List<double> values;
  final List<String> labels;
  final bool highlightMax;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const Center(child: Text('No data'));
    final maxY = values.fold<double>(0, (m, v) => v > m ? v : m);
    final peak = maxY;
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text(
                _shortMoney(v),
                style: const TextStyle(fontSize: 10, color: kReportMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i], style: const TextStyle(fontSize: 10, color: kReportMuted)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  color: highlightMax && values[i] == peak && peak > 0
                      ? kReportAccent
                      : kReportAccent.withValues(alpha: 0.45),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class ReportDonutChart extends StatelessWidget {
  const ReportDonutChart({
    super.key,
    required this.slices,
    required this.centerLabel,
    required this.centerValue,
  });

  final List<NamedAmount> slices;
  final String centerLabel;
  final String centerValue;

  static const _palette = [
    Color(0xFF7C3AED),
    Color(0xFF2563EB),
    Color(0xFF06B6D4),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return const Center(child: Text('No data'));
    }
    final total = slices.fold<double>(0, (s, e) => s + e.amount.toDouble());
    return Row(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 48,
                  sections: [
                    for (var i = 0; i < slices.length; i++)
                      PieChartSectionData(
                        value: slices[i].amount.toDouble() <= 0 ? 0.01 : slices[i].amount.toDouble(),
                        color: _palette[i % _palette.length],
                        radius: 28,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerLabel, style: const TextStyle(fontSize: 11, color: kReportMuted)),
                  Text(
                    centerValue,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < slices.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          slices[i].name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        '${(total == 0 ? 0 : slices[i].amount.toDouble() / total * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReportProductTable extends StatelessWidget {
  const ReportProductTable({
    super.key,
    required this.rows,
    this.sortByUnits = true,
  });

  final List<ProductSalesRow> rows;
  final bool sortByUnits;

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]
      ..sort((a, b) => sortByUnits ? b.units.compareTo(a.units) : b.revenue.compareTo(a.revenue));
    if (sorted.isEmpty) return const Center(child: Text('No product sales'));
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text('Product', style: TextStyle(color: kReportMuted, fontSize: 12))),
              Expanded(child: Text('Units', textAlign: TextAlign.right, style: TextStyle(color: kReportMuted, fontSize: 12))),
              Expanded(flex: 2, child: Text('Revenue', textAlign: TextAlign.right, style: TextStyle(color: kReportMuted, fontSize: 12))),
              Expanded(flex: 2, child: Text('% Sales', textAlign: TextAlign.right, style: TextStyle(color: kReportMuted, fontSize: 12))),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = sorted[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: Text(row.units.toStringAsFixed(row.units % 1 == 0 ? 0 : 1), textAlign: TextAlign.right),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(formatRs(row.revenue), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${row.share.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (row.share / 100).clamp(0, 1),
                              minHeight: 5,
                              backgroundColor: kReportAccentSoft,
                              color: kReportAccent,
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

class ReportComparisonCard extends StatelessWidget {
  const ReportComparisonCard({super.key, required this.item});

  final SalesComparison item;

  @override
  Widget build(BuildContext context) {
    final up = item.isUp;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kReportCardBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            formatPct(item.percentChange),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: up ? kReportSuccess : kReportDanger,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatRs(item.current)} vs ${formatRs(item.previous)}',
            style: const TextStyle(color: kReportMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _shortMoney(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}
