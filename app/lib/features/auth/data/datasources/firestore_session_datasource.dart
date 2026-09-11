import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/firebase/firestore_host.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/utils/json_read.dart';
import '../../domain/entities/session.dart';
import '../../domain/permissions.dart';

class FirestoreSessionDataSource {
  FirestoreSessionDataSource({
    required FirestoreHost firestore,
    required TenantContext tenant,
    required Box<dynamic> sessionBox,
  })  : _firestore = firestore,
        _tenant = tenant,
        _sessionBox = sessionBox;

  final FirestoreHost _firestore;
  final TenantContext _tenant;
  final Box<dynamic> _sessionBox;

  Future<Session> load({required String uid, required String email}) async {
    try {
      final db = _firestore.requireDb();
      final userSnap = await db.collection('users').doc(uid).get();
      if (!userSnap.exists) {
        throw const Failure('No POS profile is linked to this Firebase account yet.');
      }
      final userData = asStringKeyMap(userSnap.data());
      userData['id'] = uid;
      if (userData['email'] == null) {
        userData['email'] = email;
      }
      final user = PosUser.fromJson(userData);
      if (!user.active) {
        throw const Failure('This account has been deactivated.');
      }
      if (user.isPlatformAdmin) {
        final session = Session(user: user);
        _tenant.apply(session);
        await _sessionBox.put('session', session.toCacheJson());
        return session;
      }
      final businessId = readString(userData, ['businessId', 'business_id']);
      if (businessId.isEmpty) {
        throw const Failure('No business is assigned to this account.');
      }
      final businessSnap = await db.collection('businesses').doc(businessId).get();
      if (!businessSnap.exists) {
        throw const Failure('The assigned business was not found.');
      }
      final businessData = asStringKeyMap(businessSnap.data());
      businessData['id'] = businessId;
      final business = BusinessProfile.fromJson(businessData);
      if (!business.isActive) {
        throw Failure(
          business.isSuspended
              ? 'This business is suspended. Contact the Super Admin.'
              : 'This business is inactive. Contact the Super Admin.',
        );
      }

      final branchesSnap = await db.collection('businesses').doc(businessId).collection('branches').get();
      final allBranches = branchesSnap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        data['id'] = doc.id;
        return BranchProfile.fromJson(data);
      }).toList();
      final allowedIds = user.resolvedBranchIds(fallback: allBranches.map((item) => item.id).toList());
      final branches = user.isBusinessAdmin
          ? allBranches
          : allBranches.where((item) => allowedIds.contains(item.id)).toList();

      BranchProfile? branch;
      for (final item in branches) {
        if (item.id == user.primaryBranchId) {
          branch = item;
          break;
        }
      }
      branch ??= branches.isEmpty ? null : branches.first;
      if (branch != null && !branch.active && !user.isBusinessAdmin) {
        throw const Failure('The assigned branch is inactive.');
      }

      final session = Session(
        user: user,
        business: business,
        branch: branch,
        branches: branches,
      );
      _tenant.apply(session);
      await _sessionBox.put('session', session.toCacheJson());
      return session;
    } catch (error) {
      final mapped = error is Failure ? error : mapFirebaseFailure(error);
      if (mapped.code == 'OFFLINE') {
        final cached = _sessionBox.get('session');
        if (cached is Map) {
          final session = Session.fromJson(asStringKeyMap(cached));
          if (session.user.id == uid) {
            _tenant.apply(session);
            return session;
          }
        }
      }
      throw mapped;
    }
  }

  Future<bool> isPlatformInitialized() async {
    try {
      final snap = await _firestore.requireDb().collection('platform').doc('state').get();
      return snap.exists;
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<Session> bootstrapPlatform({
    required String uid,
    required String name,
    required String email,
    required String ownerCode,
  }) async {
    try {
      final db = _firestore.requireDb();
      await db.collection('owner_unlocks').doc(uid).set({
        'code': ownerCode,
        'created_at': FieldValue.serverTimestamp(),
      });
      await db.collection('users').doc(uid).set({
        'id': uid,
        'email': email,
        'name': name,
        'role': PosRole.platformSuperAdmin,
        'permissions': PosRole.permissionsFor(PosRole.platformSuperAdmin),
        'active': true,
      });
      final stateRef = db.collection('platform').doc('state');
      final stateSnap = await stateRef.get();
      if (!stateSnap.exists) {
        await stateRef.set({
          'initialized': true,
          'ownerUid': uid,
          'ownerEmail': email,
          'ownerUids': [uid],
        });
      } else {
        await stateRef.set({
          'ownerUids': FieldValue.arrayUnion([uid]),
          'lastOwnerUid': uid,
          'lastOwnerEmail': email,
        }, SetOptions(merge: true));
      }
      try {
        await db.collection('owner_unlocks').doc(uid).delete();
      } catch (_) {}
      return await load(uid: uid, email: email);
    } catch (error) {
      final mapped = mapFirebaseFailure(error);
      if (mapped.message.toLowerCase().contains('permission')) {
        throw const Failure(
          'Super Admin secret code was rejected, or rules are not published. Publish firestore.rules, and set platform/owner_gate with field code (string).',
        );
      }
      throw mapped;
    }
  }

  Future<void> clear() async {
    _tenant.clear();
    await _sessionBox.delete('session');
  }
}
