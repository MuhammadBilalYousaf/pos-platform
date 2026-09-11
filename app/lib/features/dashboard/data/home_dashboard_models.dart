import 'package:decimal/decimal.dart';
import 'reports_models.dart';

class LowStockItem {
  const LowStockItem({
    required this.name,
    required this.current,
    required this.reorder,
  });

  final String name;
  final String current;
  final String reorder;
}

class DashboardRecentOrder {
  const DashboardRecentOrder({
    required this.orderNumber,
    required this.timeLabel,
    required this.customer,
    required this.itemCount,
    required this.total,
    required this.status,
  });

  final String orderNumber;
  final String timeLabel;
  final String customer;
  final int itemCount;
  final String total;
  final String status;
}

class HomeDashboardSnapshot {
  const HomeDashboardSnapshot({
    required this.orderCount,
    required this.total,
    required this.lowStockCount,
    required this.averageTicket,
    required this.takeawayCount,
    required this.dineInCount,
    required this.deliveryCount,
    required this.paymentMix,
    required this.recentOrdersLegacy,
    required this.itemsSold,
    required this.customersToday,
    required this.salesVsYesterdayPct,
    required this.ordersVsYesterdayPct,
    required this.aovVsYesterdayPct,
    required this.itemsVsYesterdayPct,
    required this.yesterdaySales,
    required this.hourlyToday,
    required this.categoriesToday,
    required this.topProducts,
    required this.lowStockItems,
    required this.paymentSlices,
    required this.recentOrderRows,
  });

  final int orderCount;
  final Decimal total;
  final int lowStockCount;
  final Decimal averageTicket;
  final int takeawayCount;
  final int dineInCount;
  final int deliveryCount;
  final List<Map<String, String>> paymentMix;
  final List<Map<String, String>> recentOrdersLegacy;
  final double itemsSold;
  final int customersToday;
  final double salesVsYesterdayPct;
  final double ordersVsYesterdayPct;
  final double aovVsYesterdayPct;
  final double itemsVsYesterdayPct;
  final Decimal yesterdaySales;
  final List<HourBucket> hourlyToday;
  final List<NamedAmount> categoriesToday;
  final List<ProductSalesRow> topProducts;
  final List<LowStockItem> lowStockItems;
  final List<NamedAmount> paymentSlices;
  final List<DashboardRecentOrder> recentOrderRows;
}

double pctChange(num current, num previous) {
  if (previous == 0) return current == 0 ? 0 : 100;
  return ((current - previous) / previous) * 100;
}
