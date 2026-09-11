import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import '../../../core/firebase/firestore_host.dart';
import '../../../core/firebase/tenant_context.dart';
import '../../../core/utils/json_read.dart';
import '../../../core/utils/order_totals.dart';
import '../../auth/domain/entities/session.dart';
import 'home_dashboard_models.dart';
import 'reports_models.dart';

class ReportFilters {
  const ReportFilters({
    this.categoryId,
    this.productId,
    this.employeeKey,
    this.paymentMethod,
  });

  final String? categoryId;
  final String? productId;
  final String? employeeKey;
  final String? paymentMethod;

  bool get hasAny =>
      (categoryId != null && categoryId!.isNotEmpty) ||
      (productId != null && productId!.isNotEmpty) ||
      (employeeKey != null && employeeKey!.isNotEmpty) ||
      (paymentMethod != null && paymentMethod!.isNotEmpty);
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.orderCount,
    required this.total,
    required this.lowStockCount,
    required this.averageTicket,
    required this.takeawayCount,
    required this.dineInCount,
    required this.deliveryCount,
    required this.paymentMix,
    required this.recentOrders,
  });

  final String orderCount;
  final String total;
  final String lowStockCount;
  final String averageTicket;
  final String takeawayCount;
  final String dineInCount;
  final String deliveryCount;
  final List<Map<String, String>> paymentMix;
  final List<Map<String, String>> recentOrders;

  factory DashboardSnapshot.fromHome(HomeDashboardSnapshot home) {
    return DashboardSnapshot(
      orderCount: home.orderCount.toString(),
      total: moneyString(home.total),
      lowStockCount: home.lowStockCount.toString(),
      averageTicket: moneyString(home.averageTicket),
      takeawayCount: home.takeawayCount.toString(),
      dineInCount: home.dineInCount.toString(),
      deliveryCount: home.deliveryCount.toString(),
      paymentMix: home.paymentMix,
      recentOrders: home.recentOrdersLegacy,
    );
  }
}

class SalesReport {
  const SalesReport({
    required this.orderCount,
    required this.total,
    required this.byProduct,
    required this.byMethod,
    required this.byType,
  });

  final String orderCount;
  final String total;
  final List<Map<String, String>> byProduct;
  final List<Map<String, String>> byMethod;
  final List<Map<String, String>> byType;
}

class DashboardRepository {
  DashboardRepository(this._firestore, this._tenant);

  final FirestoreHost _firestore;
  final TenantContext _tenant;

  DateTime? _createdAt(Object? created) {
    if (created is Timestamp) return created.toDate();
    if (created is DateTime) return created;
    if (created != null) return DateTime.tryParse(created.toString());
    return null;
  }

  Query<Map<String, dynamic>> _scoped(CollectionReference<Map<String, dynamic>> col, String field) {
    if (_tenant.selectedBranchId != null) {
      return col.where(field, isEqualTo: _tenant.selectedBranchId);
    }
    if (!_tenant.allowAllBranches) {
      final ids = _tenant.allowedBranchIds;
      if (ids.isEmpty) {
        return col.where(field, isEqualTo: '__none__');
      }
      return ids.length == 1
          ? col.where(field, isEqualTo: ids.first)
          : col.where(field, whereIn: ids.take(30).toList());
    }
    return col;
  }

  Future<HomeDashboardSnapshot> homeToday() async {
    try {
      final db = _firestore.requireDb();
      final businessId = _tenant.requireBusinessId();
      final business = db.collection('businesses').doc(businessId);
      final ordersCol = business.collection('orders');

      QuerySnapshot<Map<String, dynamic>> ordersSnap;
      try {
        ordersSnap = await _scoped(ordersCol, 'branch_id')
            .orderBy('created_at', descending: true)
            .limit(800)
            .get();
      } catch (_) {
        ordersSnap = await _scoped(ordersCol, 'branch_id').limit(800).get();
      }

      final productsSnap = await business.collection('products').get();
      final categoriesSnap = await business.collection('categories').get();
      final productCategory = <String, String>{
        for (final doc in productsSnap.docs)
          doc.id: readString(asStringKeyMap(doc.data()), ['category_id', 'categoryId']),
      };
      final categoryNames = <String, String>{
        for (final doc in categoriesSnap.docs)
          doc.id: readString(asStringKeyMap(doc.data()), ['name'], doc.id),
      };

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));

      var todayCount = 0;
      var yesterdayCount = 0;
      var takeaway = 0;
      var dineIn = 0;
      var delivery = 0;
      var todaySales = money('0');
      var yesterdaySales = money('0');
      var todayItems = 0.0;
      var yesterdayItems = 0.0;
      final methods = <String, Decimal>{};
      final todayRows = <Map<String, dynamic>>[];
      final customers = <String>{};
      final productUnits = <String, double>{};
      final productRevenue = <String, Decimal>{};
      final productNames = <String, String>{};
      final categorySales = <String, Decimal>{};
      final hourSales = List<Decimal>.filled(24, Decimal.zero);
      final hourOrders = List<int>.filled(24, 0);

      for (final doc in ordersSnap.docs) {
        final data = asStringKeyMap(doc.data());
        data['id'] = doc.id;
        if (readString(data, ['status'], 'COMPLETED') == 'CANCELLED') continue;
        if (readString(data, ['status'], 'COMPLETED') == 'REFUNDED') continue;
        if (!_tenant.matchesBranch(readString(data, ['branch_id', 'branchId']))) continue;
        final at = _createdAt(data['created_at']);
        if (at == null) continue;

        final isToday = !at.isBefore(todayStart);
        final isYesterday = !at.isBefore(yesterdayStart) && at.isBefore(todayStart);
        if (!isToday && !isYesterday) continue;

        final total = money(readString(data, ['total'], '0'));
        final refundTotal = money(readString(data, ['refund_total'], '0'));
        final netTotal = total - refundTotal;
        final salesAmount = netTotal < Decimal.zero ? Decimal.zero : netTotal;
        var lineCount = 0;
        for (final raw in readList(data, ['items'])) {
          final item = asStringKeyMap(raw);
          final qty = double.tryParse(readString(item, ['quantity'], '0')) ?? 0;
          lineCount += qty.round();
          if (!isToday) continue;
          final productId = readString(item, ['productId', 'product_id']);
          final name = readString(item, ['productName', 'product_name'], productId);
          productNames[productId] = name;
          productUnits[productId] = (productUnits[productId] ?? 0) + qty;
          final lineTotal = money(readString(item, ['lineTotal', 'line_total'], '0'));
          productRevenue[productId] = (productRevenue[productId] ?? Decimal.zero) + lineTotal;
          final catId = productCategory[productId] ?? 'uncategorized';
          categorySales[catId] = (categorySales[catId] ?? Decimal.zero) + lineTotal;
        }

        if (isToday) {
          todayCount += 1;
          todaySales += salesAmount;
          todayItems += lineCount;
          final type = readString(data, ['order_type', 'orderType'], 'TAKEAWAY');
          if (type == 'DINE_IN') {
            dineIn += 1;
          } else if (type == 'DELIVERY') {
            delivery += 1;
          } else {
            takeaway += 1;
          }
          for (final raw in readList(data, ['payments'])) {
            final payment = asStringKeyMap(raw);
            final method = readString(payment, ['method'], 'OTHER');
            methods[method] = (methods[method] ?? Decimal.zero) + money(readString(payment, ['amount'], '0'));
          }
          final customerKey = readString(data, ['customer_phone', 'customerPhone']);
          if (customerKey.isNotEmpty) {
            customers.add(customerKey);
          } else {
            customers.add(readString(data, ['customer_name', 'customerName'], 'Walk-in'));
          }
          hourSales[at.hour] += salesAmount;
          hourOrders[at.hour] += 1;
          todayRows.add(data);
        } else {
          yesterdayCount += 1;
          yesterdaySales += salesAmount;
          yesterdayItems += lineCount;
        }
      }

      todayRows.sort((a, b) {
        final aAt = _createdAt(a['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bAt = _createdAt(b['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bAt.compareTo(aAt);
      });

      final inventorySnap = await _scoped(business.collection('inventory'), 'branch_id').get();
      final lowStockItems = <LowStockItem>[];
      for (final doc in inventorySnap.docs) {
        final data = asStringKeyMap(doc.data());
        if (!_tenant.matchesBranch(readString(data, ['branch_id', 'branchId']))) continue;
        final qty = money(readString(data, ['quantity_base', 'quantityBase'], '0'));
        final reorder = money(readString(data, ['reorder_level', 'reorderLevel'], '0'));
        if (qty <= reorder) {
          lowStockItems.add(
            LowStockItem(
              name: readString(data, ['ingredient_name', 'ingredientName'], doc.id),
              current: moneyString(qty),
              reorder: moneyString(reorder),
            ),
          );
        }
      }
      lowStockItems.sort((a, b) => money(a.current).compareTo(money(b.current)));

      final average = todayCount == 0
          ? money('0')
          : (todaySales / Decimal.fromInt(todayCount)).toDecimal(scaleOnInfinitePrecision: 2);
      final yesterdayAov = yesterdayCount == 0
          ? Decimal.zero
          : (yesterdaySales / Decimal.fromInt(yesterdayCount)).toDecimal(scaleOnInfinitePrecision: 2);

      double shareOf(Decimal amount) {
        if (todaySales == Decimal.zero) return 0;
        return (amount / todaySales).toDouble() * 100;
      }

      final topProducts = [
        for (final id in productRevenue.keys)
          ProductSalesRow(
            productId: id,
            name: productNames[id] ?? id,
            categoryId: productCategory[id] ?? '',
            categoryName: categoryNames[productCategory[id] ?? ''] ?? 'Uncategorized',
            units: productUnits[id] ?? 0,
            revenue: productRevenue[id] ?? Decimal.zero,
            share: shareOf(productRevenue[id] ?? Decimal.zero),
          ),
      ]..sort((a, b) => b.revenue.compareTo(a.revenue));

      final categoriesToday = [
        for (final e in (categorySales.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          NamedAmount(
            id: e.key,
            name: e.key == 'uncategorized' ? 'Uncategorized' : (categoryNames[e.key] ?? e.key),
            amount: e.value,
            share: shareOf(e.value),
          ),
      ];

      final mixEntries = methods.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final paymentMix = [
        for (final entry in mixEntries) {'label': entry.key, 'total': moneyString(entry.value)},
      ];
      final paymentSlices = [
        for (final entry in mixEntries)
          NamedAmount(
            id: entry.key,
            name: paymentLabel(entry.key),
            amount: entry.value,
            share: shareOf(entry.value),
          ),
      ];

      final hourlyToday = <HourBucket>[
        for (var h = 0; h < 24; h++)
          if (h >= 8 && h <= 22 || hourOrders[h] > 0)
            HourBucket(hour: h, sales: hourSales[h], orders: hourOrders[h]),
      ];

      final recentOrderRows = <DashboardRecentOrder>[
        for (final row in todayRows.take(8))
          DashboardRecentOrder(
            orderNumber: readString(row, ['order_number', 'orderNumber']),
            timeLabel: DateFormat.jm().format(_createdAt(row['created_at']) ?? now),
            customer: readString(row, ['customer_name', 'customerName'], 'Walk-in'),
            itemCount: readList(row, ['items']).length,
            total: formatRs(money(readString(row, ['total'], '0'))),
            status: readString(row, ['status'], 'COMPLETED'),
          ),
      ];

      return HomeDashboardSnapshot(
        orderCount: todayCount,
        total: todaySales,
        lowStockCount: lowStockItems.length,
        averageTicket: average,
        takeawayCount: takeaway,
        dineInCount: dineIn,
        deliveryCount: delivery,
        paymentMix: paymentMix,
        recentOrdersLegacy: [
          for (final row in todayRows.take(8))
            {
              'order_number': readString(row, ['order_number', 'orderNumber']),
              'total': readString(row, ['total'], '0'),
              'type': readString(row, ['order_type', 'orderType'], 'TAKEAWAY'),
              'customer': readString(row, ['customer_name', 'customerName'], 'Walk-in'),
            },
        ],
        itemsSold: todayItems,
        customersToday: customers.length,
        salesVsYesterdayPct: pctChange(todaySales.toDouble(), yesterdaySales.toDouble()),
        ordersVsYesterdayPct: pctChange(todayCount, yesterdayCount),
        aovVsYesterdayPct: pctChange(average.toDouble(), yesterdayAov.toDouble()),
        itemsVsYesterdayPct: pctChange(todayItems, yesterdayItems),
        yesterdaySales: yesterdaySales,
        hourlyToday: hourlyToday,
        categoriesToday: categoriesToday,
        topProducts: topProducts.take(5).toList(),
        lowStockItems: lowStockItems.take(6).toList(),
        paymentSlices: paymentSlices,
        recentOrderRows: recentOrderRows,
      );
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<DashboardSnapshot> today() async {
    final home = await homeToday();
    return DashboardSnapshot.fromHome(home);
  }

  Future<SalesReport> range({required DateTime from, required DateTime to}) async {
    final analytics = await analyticsRange(from: from, to: to);
    return SalesReport(
      orderCount: analytics.totalOrders.toString(),
      total: moneyString(analytics.totalSales),
      byProduct: [
        for (final row in analytics.topProducts)
          {'label': row.name, 'total': moneyString(row.revenue)},
      ],
      byMethod: [
        for (final row in analytics.payments)
          {'label': row.name, 'total': moneyString(row.amount)},
      ],
      byType: const [],
    );
  }

  Future<BusinessAnalytics> analyticsRange({
    required DateTime from,
    required DateTime to,
    ReportFilters filters = const ReportFilters(),
    List<BranchProfile> branches = const [],
  }) async {
    try {
      final rangeStart = DateTime(from.year, from.month, from.day);
      final rangeEnd = DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
      final duration = rangeEnd.difference(rangeStart);
      final prevStart = rangeStart.subtract(duration);
      final prevEnd = rangeStart;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      final thisWeekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1));
      final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
      final thisMonthStart = DateTime(now.year, now.month, 1);
      final lastMonthStart = DateTime(now.year, now.month - 1, 1);
      final lastMonthEnd = thisMonthStart;
      final ytdStart = DateTime(now.year, 1, 1);

      var fetchStart = rangeStart;
      for (final d in [prevStart, yesterdayStart, lastWeekStart, lastMonthStart, ytdStart]) {
        if (d.isBefore(fetchStart)) fetchStart = d;
      }

      final db = _firestore.requireDb();
      final businessId = _tenant.requireBusinessId();
      final business = db.collection('businesses').doc(businessId);
      final ordersCol = business.collection('orders');

      // Prefer newest orders so "Today" is reliable (unordered limit can miss today's docs).
      QuerySnapshot<Map<String, dynamic>> ordersSnap;
      try {
        ordersSnap = await _scoped(ordersCol, 'branch_id')
            .orderBy('created_at', descending: true)
            .limit(2500)
            .get();
      } catch (_) {
        ordersSnap = await _scoped(ordersCol, 'branch_id').limit(2500).get();
      }
      final productsSnap = await business.collection('products').get();
      final categoriesSnap = await business.collection('categories').get();

      final categoryNames = <String, String>{};
      for (final doc in categoriesSnap.docs) {
        final data = asStringKeyMap(doc.data());
        categoryNames[doc.id] = readString(data, ['name'], doc.id);
      }
      final productMeta = <String, ({String name, String categoryId})>{};
      for (final doc in productsSnap.docs) {
        final data = asStringKeyMap(doc.data());
        productMeta[doc.id] = (
          name: readString(data, ['name'], doc.id),
          categoryId: readString(data, ['category_id', 'categoryId']),
        );
      }

      final branchNames = <String, String>{
        for (final b in branches) b.id: b.name,
      };

      final allOrders = <_OrderRow>[];
      for (final doc in ordersSnap.docs) {
        final data = asStringKeyMap(doc.data());
        final branchId = readString(data, ['branch_id', 'branchId']);
        if (!_tenant.matchesBranch(branchId)) continue;
        final at = _createdAt(data['created_at']);
        if (at == null || at.isBefore(fetchStart)) continue;

        final status = readString(data, ['status'], 'COMPLETED');
        final refundTotal = money(readString(data, ['refund_total'], '0'));
        final items = <_LineRow>[];
        for (final raw in readList(data, ['items'])) {
          final item = asStringKeyMap(raw);
          final productId = readString(item, ['productId', 'product_id']);
          if (productId.isEmpty) continue;
          final qty = double.tryParse(readString(item, ['quantity'], '0')) ?? 0;
          items.add(
            _LineRow(
              productId: productId,
              name: readString(item, ['productName', 'product_name'], productMeta[productId]?.name ?? productId),
              categoryId: productMeta[productId]?.categoryId ?? '',
              quantity: qty,
              lineTotal: money(readString(item, ['lineTotal', 'line_total'], '0')),
            ),
          );
        }
        final payments = <_PayRow>[];
        for (final raw in readList(data, ['payments'])) {
          final payment = asStringKeyMap(raw);
          payments.add(
            _PayRow(
              method: readString(payment, ['method'], 'OTHER'),
              amount: money(readString(payment, ['amount'], '0')),
            ),
          );
        }
        final cashier = readString(data, ['cashier_name', 'cashierName'], 'Unknown');
        final createdBy = readString(data, ['created_by', 'createdBy']);
        allOrders.add(
          _OrderRow(
            at: at,
            branchId: branchId,
            status: status,
            total: money(readString(data, ['total'], '0')),
            refundTotal: refundTotal,
            tax: money(readString(data, ['tax', 'taxAmount'], '0')),
            discount: money(readString(data, ['discount', 'discountAmount'], '0')),
            cashierName: cashier.isEmpty ? 'Unknown' : cashier,
            employeeKey: createdBy.isNotEmpty ? createdBy : cashier,
            items: items,
            payments: payments,
          ),
        );
      }

      var refundsInRange = Decimal.zero;
      var refundsInRangeCount = 0;
      for (final doc in ordersSnap.docs) {
        final data = asStringKeyMap(doc.data());
        if (!_tenant.matchesBranch(readString(data, ['branch_id', 'branchId']))) continue;
        for (final raw in readList(data, ['refunds'])) {
          final refund = asStringKeyMap(raw);
          final refundedAt = _createdAt(refund['created_at']);
          if (refundedAt == null ||
              refundedAt.isBefore(rangeStart) ||
              !refundedAt.isBefore(rangeEnd)) {
            continue;
          }
          refundsInRange += money(readString(refund, ['amount'], '0'));
          refundsInRangeCount += 1;
        }
      }

      bool passFilters(_OrderRow order) {
        if (!filters.hasAny) return true;
        if (filters.employeeKey != null &&
            filters.employeeKey!.isNotEmpty &&
            order.employeeKey != filters.employeeKey &&
            order.cashierName != filters.employeeKey) {
          return false;
        }
        if (filters.paymentMethod != null && filters.paymentMethod!.isNotEmpty) {
          final has = order.payments.any((p) => p.method.toUpperCase() == filters.paymentMethod!.toUpperCase());
          if (!has) return false;
        }
        if (filters.productId != null && filters.productId!.isNotEmpty) {
          if (!order.items.any((i) => i.productId == filters.productId)) return false;
        }
        if (filters.categoryId != null && filters.categoryId!.isNotEmpty) {
          if (!order.items.any((i) => i.categoryId == filters.categoryId)) return false;
        }
        return true;
      }

      List<_OrderRow> inWindow(DateTime start, DateTime endExclusive, {bool includeCancelled = false}) {
        return [
          for (final o in allOrders)
            if (!o.at.isBefore(start) && o.at.isBefore(endExclusive))
              if (includeCancelled || (o.status != 'CANCELLED' && o.status != 'REFUNDED'))
                if (passFilters(o)) o,
        ];
      }

      final current = inWindow(rangeStart, rangeEnd);
      final previous = inWindow(prevStart, prevEnd);
      final cancelled = [
        for (final o in allOrders)
          if (!o.at.isBefore(rangeStart) && o.at.isBefore(rangeEnd) && o.status == 'CANCELLED')
            if (passFilters(o)) o,
      ];

      Decimal sumSales(List<_OrderRow> rows) =>
          rows.fold(Decimal.zero, (s, o) => s + o.netTotal);
      Decimal sumTax(List<_OrderRow> rows) => rows.fold(Decimal.zero, (s, o) => s + o.tax);
      Decimal sumDiscount(List<_OrderRow> rows) => rows.fold(Decimal.zero, (s, o) => s + o.discount);
      double sumItems(List<_OrderRow> rows) {
        var n = 0.0;
        for (final o in rows) {
          for (final i in o.items) {
            n += i.quantity;
          }
        }
        return n;
      }

      final totalSales = sumSales(current);
      final totalTax = sumTax(current);
      final totalDiscounts = sumDiscount(current);
      final totalItems = sumItems(current);
      final netSales = totalSales - totalTax;
      final cancelledValue = sumSales(cancelled);

      PeriodMetric metric(String key, Decimal cur, Decimal prev) =>
          PeriodMetric(label: key, current: cur, previous: prev);

      final kpiTrends = <String, PeriodMetric>{
        'sales': metric('sales', totalSales, sumSales(previous)),
        'orders': metric('orders', Decimal.fromInt(current.length), Decimal.fromInt(previous.length)),
        'aov': metric(
          'aov',
          current.isEmpty
              ? Decimal.zero
              : (totalSales / Decimal.fromInt(current.length)).toDecimal(scaleOnInfinitePrecision: 2),
          previous.isEmpty
              ? Decimal.zero
              : (sumSales(previous) / Decimal.fromInt(previous.length)).toDecimal(scaleOnInfinitePrecision: 2),
        ),
        'items': metric('items', Decimal.parse(totalItems.toString()), Decimal.parse(sumItems(previous).toString())),
        'discounts': metric('discounts', totalDiscounts, sumDiscount(previous)),
        'tax': metric('tax', totalTax, sumTax(previous)),
        'net': metric('net', netSales, sumSales(previous) - sumTax(previous)),
        'cancelled': metric('cancelled', Decimal.fromInt(cancelled.length), Decimal.fromInt([
          for (final o in allOrders)
            if (!o.at.isBefore(prevStart) && o.at.isBefore(prevEnd) && o.status == 'CANCELLED') o,
        ].length)),
      };

      // Product aggregates
      final productUnits = <String, double>{};
      final productRevenue = <String, Decimal>{};
      final productNames = <String, String>{};
      final categorySales = <String, Decimal>{};
      final categoryItems = <String, double>{};
      final methodSales = <String, Decimal>{};
      final methodCount = <String, int>{};
      final branchSales = <String, Decimal>{};
      final branchOrders = <String, int>{};
      final branchItems = <String, double>{};
      final branchPrevSales = <String, Decimal>{};
      final empSales = <String, Decimal>{};
      final empOrders = <String, int>{};
      final empItems = <String, double>{};
      final empDiscounts = <String, Decimal>{};
      final empNames = <String, String>{};
      final empCancel = <String, int>{};
      final dailyMap = <String, DayBucket>{};
      final hourSales = List<Decimal>.filled(24, Decimal.zero);
      final hourOrders = List<int>.filled(24, 0);
      final weekdaySales = List<Decimal>.filled(8, Decimal.zero);
      final weekdayOrders = List<double>.filled(8, 0);
      final weekdayItems = List<double>.filled(8, 0);
      final weekdaySamples = <int, Set<String>>{for (var i = 1; i <= 7; i++) i: <String>{}};
      final productDayTrend = <String, Map<String, ProductTrendPoint>>{};

      String dayKey(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      void touchDay(DateTime at, Decimal sale, int orders, double items) {
        final key = dayKey(at);
        final date = DateTime(at.year, at.month, at.day);
        final existing = dailyMap[key];
        if (existing == null) {
          dailyMap[key] = DayBucket(date: date, sales: sale, orders: orders, items: items);
        } else {
          dailyMap[key] = DayBucket(
            date: date,
            sales: existing.sales + sale,
            orders: existing.orders + orders,
            items: existing.items + items,
          );
        }
      }

      for (final o in current) {
        final itemQty = o.items.fold<double>(0, (s, i) => s + i.quantity);
        touchDay(o.at, o.netTotal, 1, itemQty);
        hourSales[o.at.hour] += o.netTotal;
        hourOrders[o.at.hour] += 1;
        final wd = o.at.weekday;
        weekdaySales[wd] += o.netTotal;
        weekdayOrders[wd] += 1;
        weekdayItems[wd] += itemQty;
        weekdaySamples[wd]!.add(dayKey(o.at));

        branchSales[o.branchId] = (branchSales[o.branchId] ?? Decimal.zero) + o.netTotal;
        branchOrders[o.branchId] = (branchOrders[o.branchId] ?? 0) + 1;
        branchItems[o.branchId] = (branchItems[o.branchId] ?? 0) + itemQty;

        empSales[o.employeeKey] = (empSales[o.employeeKey] ?? Decimal.zero) + o.netTotal;
        empOrders[o.employeeKey] = (empOrders[o.employeeKey] ?? 0) + 1;
        empItems[o.employeeKey] = (empItems[o.employeeKey] ?? 0) + itemQty;
        empDiscounts[o.employeeKey] = (empDiscounts[o.employeeKey] ?? Decimal.zero) + o.discount;
        empNames[o.employeeKey] = o.cashierName;

        for (final p in o.payments) {
          methodSales[p.method] = (methodSales[p.method] ?? Decimal.zero) + p.amount;
          methodCount[p.method] = (methodCount[p.method] ?? 0) + 1;
        }

        for (final line in o.items) {
          if (filters.productId != null &&
              filters.productId!.isNotEmpty &&
              line.productId != filters.productId) {
            continue;
          }
          if (filters.categoryId != null &&
              filters.categoryId!.isNotEmpty &&
              line.categoryId != filters.categoryId) {
            continue;
          }
          productUnits[line.productId] = (productUnits[line.productId] ?? 0) + line.quantity;
          productRevenue[line.productId] = (productRevenue[line.productId] ?? Decimal.zero) + line.lineTotal;
          productNames[line.productId] = line.name;
          final catId = line.categoryId.isEmpty ? 'uncategorized' : line.categoryId;
          categorySales[catId] = (categorySales[catId] ?? Decimal.zero) + line.lineTotal;
          categoryItems[catId] = (categoryItems[catId] ?? 0) + line.quantity;

          final dk = dayKey(o.at);
          productDayTrend.putIfAbsent(line.productId, () => {});
          final existing = productDayTrend[line.productId]![dk];
          if (existing == null) {
            productDayTrend[line.productId]![dk] = ProductTrendPoint(
              date: DateTime(o.at.year, o.at.month, o.at.day),
              units: line.quantity,
              revenue: line.lineTotal,
            );
          } else {
            productDayTrend[line.productId]![dk] = ProductTrendPoint(
              date: existing.date,
              units: existing.units + line.quantity,
              revenue: existing.revenue + line.lineTotal,
            );
          }
        }
      }

      for (final o in previous) {
        branchPrevSales[o.branchId] = (branchPrevSales[o.branchId] ?? Decimal.zero) + o.netTotal;
      }
      for (final o in cancelled) {
        empCancel[o.employeeKey] = (empCancel[o.employeeKey] ?? 0) + 1;
        empNames[o.employeeKey] = o.cashierName;
      }

      // Fill empty days in range for continuous chart
      final daily = <DayBucket>[];
      for (var d = rangeStart; d.isBefore(rangeEnd); d = d.add(const Duration(days: 1))) {
        final key = dayKey(d);
        daily.add(dailyMap[key] ?? DayBucket(date: d, sales: Decimal.zero, orders: 0, items: 0));
      }

      // Weekly buckets
      final weekMap = <String, ({DateTime start, Decimal sales, int orders})>{};
      for (final day in daily) {
        final weekStart = day.date.subtract(Duration(days: day.date.weekday - 1));
        final key = dayKey(weekStart);
        final existing = weekMap[key];
        if (existing == null) {
          weekMap[key] = (start: weekStart, sales: day.sales, orders: day.orders);
        } else {
          weekMap[key] = (
            start: weekStart,
            sales: existing.sales + day.sales,
            orders: existing.orders + day.orders,
          );
        }
      }
      final weekEntries = weekMap.values.toList()..sort((a, b) => a.start.compareTo(b.start));
      final weekly = <WeekBucket>[];
      for (var i = 0; i < weekEntries.length; i++) {
        final cur = weekEntries[i];
        final prevSales = i == 0 ? Decimal.zero : weekEntries[i - 1].sales;
        final growth = prevSales == Decimal.zero
            ? (cur.sales == Decimal.zero ? 0.0 : 100.0)
            : ((cur.sales - prevSales) / prevSales).toDouble() * 100;
        weekly.add(
          WeekBucket(
            weekStart: cur.start,
            label: 'W${DateFormat('w').format(cur.start)} · ${DateFormat('MMM d').format(cur.start)}',
            sales: cur.sales,
            orders: cur.orders,
            growthPercent: growth,
          ),
        );
      }

      // Monthly buckets
      final monthMap = <String, ({int y, int m, Decimal sales, int orders})>{};
      for (final day in daily) {
        final key = '${day.date.year}-${day.date.month}';
        final existing = monthMap[key];
        if (existing == null) {
          monthMap[key] = (y: day.date.year, m: day.date.month, sales: day.sales, orders: day.orders);
        } else {
          monthMap[key] = (
            y: day.date.year,
            m: day.date.month,
            sales: existing.sales + day.sales,
            orders: existing.orders + day.orders,
          );
        }
      }
      final monthEntries = monthMap.values.toList()
        ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.m.compareTo(b.m));
      final monthly = <MonthBucket>[];
      for (var i = 0; i < monthEntries.length; i++) {
        final cur = monthEntries[i];
        final prevSales = i == 0 ? Decimal.zero : monthEntries[i - 1].sales;
        final growth = prevSales == Decimal.zero
            ? (cur.sales == Decimal.zero ? 0.0 : 100.0)
            : ((cur.sales - prevSales) / prevSales).toDouble() * 100;
        monthly.add(
          MonthBucket(
            year: cur.y,
            month: cur.m,
            label: DateFormat('MMM yyyy').format(DateTime(cur.y, cur.m)),
            sales: cur.sales,
            orders: cur.orders,
            growthPercent: growth,
          ),
        );
      }

      const weekdayLabels = {
        1: 'Mon',
        2: 'Tue',
        3: 'Wed',
        4: 'Thu',
        5: 'Fri',
        6: 'Sat',
        7: 'Sun',
      };
      final weekdayTrends = <WeekdayTrend>[
        for (var wd = 1; wd <= 7; wd++)
          WeekdayTrend(
            weekday: wd,
            label: weekdayLabels[wd]!,
            avgSales: weekdaySamples[wd]!.isEmpty
                ? Decimal.zero
                : (weekdaySales[wd] / Decimal.fromInt(weekdaySamples[wd]!.length))
                    .toDecimal(scaleOnInfinitePrecision: 2),
            avgOrders: weekdaySamples[wd]!.isEmpty
                ? 0
                : weekdayOrders[wd] / weekdaySamples[wd]!.length,
            avgItems: weekdaySamples[wd]!.isEmpty
                ? 0
                : weekdayItems[wd] / weekdaySamples[wd]!.length,
            sampleDays: weekdaySamples[wd]!.length,
          ),
      ];

      // Hourly: business hours 8–22 plus any hours with activity
      final hourly = <HourBucket>[
        for (var h = 0; h < 24; h++)
          if (h >= 8 && h <= 22 || hourOrders[h] > 0)
            HourBucket(hour: h, sales: hourSales[h], orders: hourOrders[h]),
      ];

      double shareOf(Decimal amount) {
        if (totalSales == Decimal.zero) return 0;
        return (amount / totalSales).toDouble() * 100;
      }

      final productRows = <ProductSalesRow>[
        for (final id in productRevenue.keys)
          ProductSalesRow(
            productId: id,
            name: productNames[id] ?? productMeta[id]?.name ?? id,
            categoryId: productMeta[id]?.categoryId ?? '',
            categoryName: categoryNames[productMeta[id]?.categoryId ?? ''] ?? 'Uncategorized',
            units: productUnits[id] ?? 0,
            revenue: productRevenue[id] ?? Decimal.zero,
            share: shareOf(productRevenue[id] ?? Decimal.zero),
          ),
      ]..sort((a, b) => b.units.compareTo(a.units));

      final topProducts = productRows.take(10).toList();
      String topName = '—';
      double topUnits = 0;
      if (topProducts.isNotEmpty) {
        topName = topProducts.first.name;
        topUnits = topProducts.first.units;
      }

      // Least selling: catalog products ranked by units (incl. zero)
      final leastCandidates = <ProductSalesRow>[
        for (final entry in productMeta.entries)
          ProductSalesRow(
            productId: entry.key,
            name: entry.value.name,
            categoryId: entry.value.categoryId,
            categoryName: categoryNames[entry.value.categoryId] ?? 'Uncategorized',
            units: productUnits[entry.key] ?? 0,
            revenue: productRevenue[entry.key] ?? Decimal.zero,
            share: shareOf(productRevenue[entry.key] ?? Decimal.zero),
          ),
      ]..sort((a, b) {
          final byUnits = a.units.compareTo(b.units);
          if (byUnits != 0) return byUnits;
          return a.revenue.compareTo(b.revenue);
        });
      final leastProducts = leastCandidates.take(10).toList();

      final categories = [
        for (final e in (categorySales.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          NamedAmount(
            id: e.key,
            name: e.key == 'uncategorized' ? 'Uncategorized' : (categoryNames[e.key] ?? e.key),
            amount: e.value,
            units: categoryItems[e.key] ?? 0,
            share: shareOf(e.value),
          ),
      ];

      final payments = [
        for (final e in (methodSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
          NamedAmount(
            id: e.key,
            name: paymentLabel(e.key),
            amount: e.value,
            count: methodCount[e.key] ?? 0,
            share: shareOf(e.value),
          ),
      ];

      double growth(Decimal cur, Decimal prev) {
        if (prev == Decimal.zero) return cur == Decimal.zero ? 0 : 100;
        return ((cur - prev) / prev).toDouble() * 100;
      }

      final branchRows = [
        for (final id in {...branchSales.keys, ...branchNames.keys})
          BranchPerfRow(
            branchId: id,
            name: branchNames[id] ?? (id.isEmpty ? 'Unknown' : id),
            sales: branchSales[id] ?? Decimal.zero,
            orders: branchOrders[id] ?? 0,
            items: branchItems[id] ?? 0,
            growthPercent: growth(branchSales[id] ?? Decimal.zero, branchPrevSales[id] ?? Decimal.zero),
          ),
      ]..sort((a, b) => b.sales.compareTo(a.sales));

      final employees = [
        for (final key in empSales.keys)
          EmployeePerfRow(
            key: key,
            name: empNames[key] ?? key,
            sales: empSales[key] ?? Decimal.zero,
            orders: empOrders[key] ?? 0,
            items: empItems[key] ?? 0,
            discounts: empDiscounts[key] ?? Decimal.zero,
            cancellations: empCancel[key] ?? 0,
          ),
      ]..sort((a, b) => b.sales.compareTo(a.sales));

      final discountedOrders = current.where((o) => o.discount > Decimal.zero).length;
      final discountPct = totalSales == Decimal.zero
          ? 0.0
          : (totalDiscounts / totalSales).toDouble() * 100;
      final cancelPct = (current.length + cancelled.length) == 0
          ? 0.0
          : cancelled.length / (current.length + cancelled.length) * 100;

      // Refund KPIs use refund transaction timestamps in the selected range.
      final discountRefunds = DiscountRefundStats(
        discountTotal: totalDiscounts,
        discountedOrders: discountedOrders,
        discountPercentOfSales: discountPct,
        refundTotal: refundsInRange,
        refundCount: refundsInRangeCount,
        cancelledCount: cancelled.length,
        cancelledValue: cancelledValue,
        cancelledPercentOfOrders: cancelPct,
      );

      Decimal salesBetween(DateTime start, DateTime end) => sumSales(inWindow(start, end));

      final comparisons = [
        SalesComparison(
          label: 'Today vs Yesterday',
          currentLabel: 'Today',
          previousLabel: 'Yesterday',
          current: salesBetween(todayStart, todayStart.add(const Duration(days: 1))),
          previous: salesBetween(yesterdayStart, todayStart),
        ),
        SalesComparison(
          label: 'This Week vs Last Week',
          currentLabel: 'This Week',
          previousLabel: 'Last Week',
          current: salesBetween(thisWeekStart, todayStart.add(const Duration(days: 1))),
          previous: salesBetween(lastWeekStart, thisWeekStart),
        ),
        SalesComparison(
          label: 'This Month vs Last Month',
          currentLabel: 'This Month',
          previousLabel: 'Last Month',
          current: salesBetween(thisMonthStart, todayStart.add(const Duration(days: 1))),
          previous: salesBetween(lastMonthStart, lastMonthEnd),
        ),
        SalesComparison(
          label: 'Year to Date',
          currentLabel: 'YTD ${now.year}',
          previousLabel: 'YTD ${now.year - 1}',
          current: salesBetween(ytdStart, todayStart.add(const Duration(days: 1))),
          previous: salesBetween(DateTime(now.year - 1, 1, 1), DateTime(now.year - 1, now.month, now.day).add(const Duration(days: 1))),
        ),
      ];

      final productCatalog = [
        for (final e in productMeta.entries)
          NamedAmount(id: e.key, name: e.value.name, amount: productRevenue[e.key] ?? Decimal.zero),
      ]..sort((a, b) => a.name.compareTo(b.name));

      final productTrends = <String, List<ProductTrendPoint>>{
        for (final e in productDayTrend.entries)
          e.key: (e.value.values.toList()..sort((a, b) => a.date.compareTo(b.date))),
      };

      return BusinessAnalytics(
        from: rangeStart,
        to: DateTime(to.year, to.month, to.day),
        totalSales: totalSales,
        netSales: netSales,
        totalOrders: current.length,
        totalItems: totalItems,
        totalDiscounts: totalDiscounts,
        totalTax: totalTax,
        refunds: refundsInRange,
        cancelledOrders: cancelled.length,
        cancelledValue: cancelledValue,
        kpiTrends: kpiTrends,
        topProductName: topName,
        topProductUnits: topUnits,
        daily: daily,
        weekly: weekly,
        monthly: monthly,
        weekdayTrends: weekdayTrends,
        hourly: hourly,
        topProducts: topProducts,
        leastProducts: leastProducts,
        categories: categories,
        branches: branchRows,
        employees: employees,
        payments: payments,
        discountRefunds: discountRefunds,
        comparisons: comparisons,
        productCatalog: productCatalog,
        productTrends: productTrends,
      );
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }
}

class _LineRow {
  const _LineRow({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.quantity,
    required this.lineTotal,
  });

  final String productId;
  final String name;
  final String categoryId;
  final double quantity;
  final Decimal lineTotal;
}

class _PayRow {
  const _PayRow({required this.method, required this.amount});
  final String method;
  final Decimal amount;
}

class _OrderRow {
  const _OrderRow({
    required this.at,
    required this.branchId,
    required this.status,
    required this.total,
    required this.refundTotal,
    required this.tax,
    required this.discount,
    required this.cashierName,
    required this.employeeKey,
    required this.items,
    required this.payments,
  });

  final DateTime at;
  final String branchId;
  final String status;
  final Decimal total;
  final Decimal refundTotal;
  final Decimal tax;
  final Decimal discount;
  final String cashierName;
  final String employeeKey;
  final List<_LineRow> items;
  final List<_PayRow> payments;

  Decimal get netTotal {
    if (status == 'REFUNDED') return Decimal.zero;
    final net = total - refundTotal;
    return net < Decimal.zero ? Decimal.zero : net;
  }
}
