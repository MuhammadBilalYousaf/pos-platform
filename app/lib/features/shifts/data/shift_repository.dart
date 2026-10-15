import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../../../core/errors/failures.dart';
import '../../../core/firebase/firestore_host.dart';
import '../../../core/firebase/tenant_context.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../core/utils/json_read.dart';
import '../../../core/utils/order_totals.dart';

class PosShift {
  const PosShift({
    required this.id,
    required this.branchId,
    required this.businessDay,
    required this.startedAt,
    required this.startedBy,
    this.endedAt,
    this.endedBy,
    this.status = 'OPEN',
    this.openingNote,
    this.closingNote,
    this.openingCash,
    this.closingCash,
  });

  final String id;
  final String branchId;
  /// Calendar date of shift open (YYYY-MM-DD). Midnight-crossing sales stay on this day.
  final String businessDay;
  final DateTime startedAt;
  final String? startedBy;
  final DateTime? endedAt;
  final String? endedBy;
  final String status;
  final String? openingNote;
  final String? closingNote;
  final String? openingCash;
  final String? closingCash;

  bool get isOpen => status == 'OPEN' && endedAt == null;

  Map<String, dynamic> toCache() => {
        'id': id,
        'branchId': branchId,
        'businessDay': businessDay,
        'startedAt': startedAt.toIso8601String(),
        'startedBy': startedBy,
        'endedAt': endedAt?.toIso8601String(),
        'endedBy': endedBy,
        'status': status,
        'openingNote': openingNote,
        'closingNote': closingNote,
        'openingCash': openingCash,
        'closingCash': closingCash,
      };

  factory PosShift.fromJson(Map<String, dynamic> data, {String? id}) {
    final started = data['started_at'] ?? data['startedAt'];
    final ended = data['ended_at'] ?? data['endedAt'];
    return PosShift(
      id: id ?? readString(data, ['id']),
      branchId: readString(data, ['branch_id', 'branchId']),
      businessDay: readString(data, ['business_day', 'businessDay']),
      startedAt: started is Timestamp
          ? started.toDate()
          : DateTime.tryParse(started?.toString() ?? '') ?? DateTime.now(),
      startedBy: pick(data, ['started_by', 'startedBy'])?.toString(),
      endedAt: ended is Timestamp
          ? ended.toDate()
          : ended == null
              ? null
              : DateTime.tryParse(ended.toString()),
      endedBy: pick(data, ['ended_by', 'endedBy'])?.toString(),
      status: readString(data, ['status'], 'OPEN').toUpperCase(),
      openingNote: pick(data, ['opening_note', 'openingNote'])?.toString(),
      closingNote: pick(data, ['closing_note', 'closingNote'])?.toString(),
      openingCash: pick(data, ['opening_cash', 'openingCash'])?.toString(),
      closingCash: pick(data, ['closing_cash', 'closingCash'])?.toString(),
    );
  }
}

class ShiftSummary {
  const ShiftSummary({
    required this.shift,
    required this.orderCount,
    required this.salesTotal,
    required this.refundTotal,
    required this.cancelCount,
  });

  final PosShift shift;
  final int orderCount;
  final String salesTotal;
  final String refundTotal;
  final int cancelCount;
}

class ShiftRepository {
  ShiftRepository(this._firestore, this._tenant, this._cache);

  final FirestoreHost _firestore;
  final TenantContext _tenant;
  final Box<dynamic> _cache;

  String _cacheKey(String branchId) => 'active_shift_${_tenant.businessId}_$branchId';

  static String businessDayFor(DateTime at) {
    final local = at.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<PosShift?> getActiveShift({String? branchId}) async {
    final resolved = branchId ?? _tenant.requireBranchId();
    final cached = _readCache(resolved);
    try {
      final businessId = _tenant.requireBusinessId();
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .requireDb()
            .collection('businesses')
            .doc(businessId)
            .collection('shifts')
            .where('branch_id', isEqualTo: resolved)
            .where('status', isEqualTo: 'OPEN')
            .limit(5)
            .get();
      } catch (_) {
        // Fallback when the composite index is not ready yet.
        snap = await _firestore
            .requireDb()
            .collection('businesses')
            .doc(businessId)
            .collection('shifts')
            .where('branch_id', isEqualTo: resolved)
            .limit(40)
            .get();
      }
      final shifts = snap.docs
          .map((doc) {
            final data = asStringKeyMap(doc.data());
            data['id'] = doc.id;
            return PosShift.fromJson(data, id: doc.id);
          })
          .where((shift) => shift.isOpen)
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      if (shifts.isEmpty) {
        await _cache.delete(_cacheKey(resolved));
        return null;
      }
      final active = shifts.first;
      await _cache.put(_cacheKey(resolved), active.toCache());
      return active;
    } catch (error) {
      if (cached != null) return cached;
      throw mapFirebaseFailure(error);
    }
  }

  PosShift? _readCache(String branchId) {
    final raw = _cache.get(_cacheKey(branchId));
    if (raw is! Map) return null;
    return PosShift.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<PosShift> startShift({
    String? openingCash,
    String? openingNote,
    String? branchId,
  }) async {
    final resolved = branchId ?? _tenant.requireBranchId();
    final existing = await getActiveShift(branchId: resolved);
    if (existing != null) {
      throw const Failure('A shift is already open for this branch. End it before starting another.');
    }
    final businessId = _tenant.requireBusinessId();
    final now = DateTime.now();
    final ref = _firestore.requireDb().collection('businesses').doc(businessId).collection('shifts').doc();
    final shift = PosShift(
      id: ref.id,
      branchId: resolved,
      businessDay: businessDayFor(now),
      startedAt: now,
      startedBy: _tenant.userId,
      status: 'OPEN',
      openingCash: openingCash,
      openingNote: openingNote,
    );
    await ref.set({
      'id': ref.id,
      'business_id': businessId,
      'branch_id': resolved,
      'business_day': shift.businessDay,
      'started_at': Timestamp.fromDate(now.toUtc()),
      'started_by': _tenant.userId,
      'status': 'OPEN',
      if (openingCash != null && openingCash.isNotEmpty) 'opening_cash': openingCash,
      if (openingNote != null && openingNote.isNotEmpty) 'opening_note': openingNote,
    });
    await _cache.put(_cacheKey(resolved), shift.toCache());
    return shift;
  }

  Future<PosShift> endShift({
    required String shiftId,
    String? closingCash,
    String? closingNote,
  }) async {
    final businessId = _tenant.requireBusinessId();
    final ref = _firestore.requireDb().collection('businesses').doc(businessId).collection('shifts').doc(shiftId);
    final snap = await ref.get();
    if (!snap.exists) throw const Failure('Shift was not found.');
    final data = asStringKeyMap(snap.data());
    final branchId = readString(data, ['branch_id', 'branchId']);
    if (!_tenant.canAccessBranch(branchId)) {
      throw const Failure('You cannot end a shift for that branch.');
    }
    if (readString(data, ['status'], 'OPEN').toUpperCase() != 'OPEN') {
      throw const Failure('This shift is already closed.');
    }
    final now = DateTime.now();
    await ref.set({
      'status': 'CLOSED',
      'ended_at': Timestamp.fromDate(now.toUtc()),
      'ended_by': _tenant.userId,
      if (closingCash != null && closingCash.isNotEmpty) 'closing_cash': closingCash,
      if (closingNote != null && closingNote.isNotEmpty) 'closing_note': closingNote,
    }, SetOptions(merge: true));
    await _cache.delete(_cacheKey(branchId));
    final updated = asStringKeyMap(snap.data());
    updated['id'] = shiftId;
    updated['status'] = 'CLOSED';
    updated['ended_at'] = Timestamp.fromDate(now.toUtc());
    updated['ended_by'] = _tenant.userId;
    if (closingCash != null) updated['closing_cash'] = closingCash;
    if (closingNote != null) updated['closing_note'] = closingNote;
    return PosShift.fromJson(updated, id: shiftId);
  }

  Future<List<PosShift>> listShifts({int limit = 50}) async {
    final businessId = _tenant.requireBusinessId();
    final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('shifts').limit(limit).get();
    final rows = snap.docs.map((doc) {
      final data = asStringKeyMap(doc.data());
      data['id'] = doc.id;
      return PosShift.fromJson(data, id: doc.id);
    }).where((shift) => _tenant.matchesBranch(shift.branchId)).toList();
    rows.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return rows;
  }

  Future<ShiftSummary> summarizeShift(PosShift shift) async {
    final businessId = _tenant.requireBusinessId();
    final orders = await _firestore.requireDb().collection('businesses').doc(businessId).collection('orders').where('shift_id', isEqualTo: shift.id).get();
    var sales = money('0');
    var refunds = money('0');
    var cancels = 0;
    var count = 0;
    for (final doc in orders.docs) {
      final data = asStringKeyMap(doc.data());
      final status = readString(data, ['status'], 'COMPLETED').toUpperCase();
      if (status == 'CANCELLED') {
        cancels += 1;
        continue;
      }
      count += 1;
      sales += money(readString(data, ['total'], '0'));
      refunds += money(readString(data, ['refund_total'], '0'));
    }
    return ShiftSummary(
      shift: shift,
      orderCount: count,
      salesTotal: moneyString(sales),
      refundTotal: moneyString(refunds),
      cancelCount: cancels,
    );
  }
}

Box<dynamic> openShiftCacheBox() => Hive.box(HiveBoxes.session);
