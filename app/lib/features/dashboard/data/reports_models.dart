import 'package:decimal/decimal.dart';
import '../../../core/utils/order_totals.dart';

class PeriodMetric {
  const PeriodMetric({
    required this.label,
    required this.current,
    required this.previous,
  });

  final String label;
  final Decimal current;
  final Decimal previous;

  Decimal get delta => current - previous;

  double get percentChange {
    if (previous == Decimal.zero) {
      return current == Decimal.zero ? 0 : 100;
    }
    return ((current - previous) / previous).toDouble() * 100;
  }

  bool get isUp => percentChange >= 0;
}

class NamedAmount {
  const NamedAmount({
    required this.id,
    required this.name,
    required this.amount,
    this.count = 0,
    this.units = 0,
    this.share = 0,
  });

  final String id;
  final String name;
  final Decimal amount;
  final int count;
  final double units;
  final double share;
}

class DayBucket {
  const DayBucket({
    required this.date,
    required this.sales,
    required this.orders,
    required this.items,
  });

  final DateTime date;
  final Decimal sales;
  final int orders;
  final double items;

  Decimal get aov => orders == 0
      ? Decimal.zero
      : (sales / Decimal.fromInt(orders)).toDecimal(scaleOnInfinitePrecision: 2);
}

class WeekBucket {
  const WeekBucket({
    required this.weekStart,
    required this.label,
    required this.sales,
    required this.orders,
    this.growthPercent = 0,
  });

  final DateTime weekStart;
  final String label;
  final Decimal sales;
  final int orders;
  final double growthPercent;

  Decimal get aov => orders == 0
      ? Decimal.zero
      : (sales / Decimal.fromInt(orders)).toDecimal(scaleOnInfinitePrecision: 2);
}

class MonthBucket {
  const MonthBucket({
    required this.year,
    required this.month,
    required this.label,
    required this.sales,
    required this.orders,
    this.growthPercent = 0,
  });

  final int year;
  final int month;
  final String label;
  final Decimal sales;
  final int orders;
  final double growthPercent;

  Decimal get aov => orders == 0
      ? Decimal.zero
      : (sales / Decimal.fromInt(orders)).toDecimal(scaleOnInfinitePrecision: 2);
}

class WeekdayTrend {
  const WeekdayTrend({
    required this.weekday,
    required this.label,
    required this.avgSales,
    required this.avgOrders,
    required this.avgItems,
    required this.sampleDays,
  });

  /// DateTime.monday = 1 … sunday = 7
  final int weekday;
  final String label;
  final Decimal avgSales;
  final double avgOrders;
  final double avgItems;
  final int sampleDays;

  Decimal get avgAov => avgOrders == 0
      ? Decimal.zero
      : (avgSales / Decimal.parse(avgOrders.toString())).toDecimal(scaleOnInfinitePrecision: 2);
}

class HourBucket {
  const HourBucket({
    required this.hour,
    required this.sales,
    required this.orders,
  });

  final int hour;
  final Decimal sales;
  final int orders;

  String get label {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12 ? 'AM' : 'PM';
    return '$h $suffix';
  }
}

class ProductSalesRow {
  const ProductSalesRow({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.units,
    required this.revenue,
    required this.share,
  });

  final String productId;
  final String name;
  final String categoryId;
  final String categoryName;
  final double units;
  final Decimal revenue;
  final double share;
}

class BranchPerfRow {
  const BranchPerfRow({
    required this.branchId,
    required this.name,
    required this.sales,
    required this.orders,
    required this.items,
    required this.growthPercent,
  });

  final String branchId;
  final String name;
  final Decimal sales;
  final int orders;
  final double items;
  final double growthPercent;

  Decimal get aov => orders == 0
      ? Decimal.zero
      : (sales / Decimal.fromInt(orders)).toDecimal(scaleOnInfinitePrecision: 2);
}

class EmployeePerfRow {
  const EmployeePerfRow({
    required this.key,
    required this.name,
    required this.sales,
    required this.orders,
    required this.items,
    required this.discounts,
    required this.cancellations,
  });

  final String key;
  final String name;
  final Decimal sales;
  final int orders;
  final double items;
  final Decimal discounts;
  final int cancellations;

  Decimal get aov => orders == 0
      ? Decimal.zero
      : (sales / Decimal.fromInt(orders)).toDecimal(scaleOnInfinitePrecision: 2);
}

class DiscountRefundStats {
  const DiscountRefundStats({
    required this.discountTotal,
    required this.discountedOrders,
    required this.discountPercentOfSales,
    required this.refundTotal,
    required this.refundCount,
    required this.cancelledCount,
    required this.cancelledValue,
    required this.cancelledPercentOfOrders,
  });

  final Decimal discountTotal;
  final int discountedOrders;
  final double discountPercentOfSales;
  final Decimal refundTotal;
  final int refundCount;
  final int cancelledCount;
  final Decimal cancelledValue;
  final double cancelledPercentOfOrders;
}

class SalesComparison {
  const SalesComparison({
    required this.label,
    required this.currentLabel,
    required this.previousLabel,
    required this.current,
    required this.previous,
  });

  final String label;
  final String currentLabel;
  final String previousLabel;
  final Decimal current;
  final Decimal previous;

  Decimal get delta => current - previous;

  double get percentChange {
    if (previous == Decimal.zero) {
      return current == Decimal.zero ? 0 : 100;
    }
    return ((current - previous) / previous).toDouble() * 100;
  }

  bool get isUp => percentChange >= 0;
}

class ProductTrendPoint {
  const ProductTrendPoint({
    required this.date,
    required this.units,
    required this.revenue,
  });

  final DateTime date;
  final double units;
  final Decimal revenue;
}

/// Full analytics payload for the Reports dashboard.
class BusinessAnalytics {
  const BusinessAnalytics({
    required this.from,
    required this.to,
    required this.totalSales,
    required this.netSales,
    required this.totalOrders,
    required this.totalItems,
    required this.totalDiscounts,
    required this.totalTax,
    required this.refunds,
    required this.cancelledOrders,
    required this.cancelledValue,
    required this.kpiTrends,
    required this.topProductName,
    required this.topProductUnits,
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.weekdayTrends,
    required this.hourly,
    required this.topProducts,
    required this.leastProducts,
    required this.categories,
    required this.branches,
    required this.employees,
    required this.payments,
    required this.discountRefunds,
    required this.comparisons,
    required this.productCatalog,
    required this.productTrends,
  });

  final DateTime from;
  final DateTime to;
  final Decimal totalSales;
  final Decimal netSales;
  final int totalOrders;
  final double totalItems;
  final Decimal totalDiscounts;
  final Decimal totalTax;
  final Decimal refunds;
  final int cancelledOrders;
  final Decimal cancelledValue;
  final Map<String, PeriodMetric> kpiTrends;
  final String topProductName;
  final double topProductUnits;
  final List<DayBucket> daily;
  final List<WeekBucket> weekly;
  final List<MonthBucket> monthly;
  final List<WeekdayTrend> weekdayTrends;
  final List<HourBucket> hourly;
  final List<ProductSalesRow> topProducts;
  final List<ProductSalesRow> leastProducts;
  final List<NamedAmount> categories;
  final List<BranchPerfRow> branches;
  final List<EmployeePerfRow> employees;
  final List<NamedAmount> payments;
  final DiscountRefundStats discountRefunds;
  final List<SalesComparison> comparisons;
  final List<NamedAmount> productCatalog;
  final Map<String, List<ProductTrendPoint>> productTrends;

  Decimal get averageOrderValue => totalOrders == 0
      ? Decimal.zero
      : (totalSales / Decimal.fromInt(totalOrders)).toDecimal(scaleOnInfinitePrecision: 2);

  static BusinessAnalytics empty(DateTime from, DateTime to) {
    return BusinessAnalytics(
      from: from,
      to: to,
      totalSales: Decimal.zero,
      netSales: Decimal.zero,
      totalOrders: 0,
      totalItems: 0,
      totalDiscounts: Decimal.zero,
      totalTax: Decimal.zero,
      refunds: Decimal.zero,
      cancelledOrders: 0,
      cancelledValue: Decimal.zero,
      kpiTrends: const {},
      topProductName: '—',
      topProductUnits: 0,
      daily: const [],
      weekly: const [],
      monthly: const [],
      weekdayTrends: const [],
      hourly: const [],
      topProducts: const [],
      leastProducts: const [],
      categories: const [],
      branches: const [],
      employees: const [],
      payments: const [],
      discountRefunds: DiscountRefundStats(
        discountTotal: Decimal.zero,
        discountedOrders: 0,
        discountPercentOfSales: 0,
        refundTotal: Decimal.zero,
        refundCount: 0,
        cancelledCount: 0,
        cancelledValue: Decimal.zero,
        cancelledPercentOfOrders: 0,
      ),
      comparisons: const [],
      productCatalog: const [],
      productTrends: const {},
    );
  }
}

String formatRs(Decimal value, {String symbol = 'Rs.'}) {
  final fixed = moneyString(value);
  final parts = fixed.split('.');
  var whole = parts[0];
  final negative = whole.startsWith('-');
  if (negative) whole = whole.substring(1);
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    final fromEnd = whole.length - i;
    buf.write(whole[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  final decimals = parts.length > 1 ? parts[1] : '00';
  return '$symbol ${negative ? '-' : ''}${buf.toString()}.$decimals';
}

String formatPct(double value, {int decimals = 1}) {
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(decimals)}%';
}

String paymentLabel(String method) {
  switch (method.toUpperCase()) {
    case 'CASH':
      return 'Cash';
    case 'CARD':
      return 'Card';
    case 'BANK_TRANSFER':
      return 'Bank Transfer';
    case 'EASYPAISA':
      return 'Easypaisa';
    case 'JAZZCASH':
      return 'JazzCash';
    default:
      return method.isEmpty ? 'Other' : method;
  }
}
