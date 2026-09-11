import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/firebase/firestore_host.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/utils/json_read.dart';
import '../../../pos/presentation/bloc/cart_cubit.dart';

/// POS held tickets under businesses/{businessId}/held_tickets.
class HeldTicketRepository {
  HeldTicketRepository(this._firestore, this._tenant);

  final FirestoreHost _firestore;
  final TenantContext _tenant;

  CollectionReference<Map<String, dynamic>> _col() {
    final businessId = _tenant.requireBusinessId();
    return _firestore.requireDb().collection('businesses').doc(businessId).collection('held_tickets');
  }

  Future<List<HeldTicket>> list() async {
    try {
      final branchId = _tenant.effectiveBranchId;
      Query<Map<String, dynamic>> query = _col().orderBy('held_at', descending: true).limit(50);
      if (branchId != null && branchId.isNotEmpty && !_tenant.isAllBranches) {
        query = _col().where('branch_id', isEqualTo: branchId).orderBy('held_at', descending: true).limit(50);
      }
      final snap = await query.get();
      return [
        for (final doc in snap.docs)
          if (_tenant.matchesBranch(readString(asStringKeyMap(doc.data()), ['branch_id', 'branchId'])))
            _fromDoc(doc.id, asStringKeyMap(doc.data())),
      ];
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> save(HeldTicket ticket) async {
    try {
      final branchId = _tenant.requireBranchId();
      final businessId = _tenant.requireBusinessId();
      await _col().doc(ticket.id).set({
        'id': ticket.id,
        'business_id': businessId,
        'branch_id': branchId,
        'label': ticket.label,
        'cart': ticket.cart.toJson(),
        'held_at': Timestamp.fromDate(ticket.heldAt.toUtc()),
        'created_by': _tenant.userId,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _col().doc(id).delete();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  HeldTicket _fromDoc(String id, Map<String, dynamic> data) {
    final heldAt = data['held_at'];
    return HeldTicket(
      id: readString(data, ['id'], id),
      label: readString(data, ['label'], 'Held'),
      heldAt: heldAt is Timestamp ? heldAt.toDate() : DateTime.tryParse(readString(data, ['held_at'])) ?? DateTime.now(),
      cart: CartState.fromJson(asStringKeyMap(data['cart'])),
    );
  }
}
