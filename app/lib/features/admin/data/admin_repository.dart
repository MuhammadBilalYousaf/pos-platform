import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/errors/failures.dart';
import '../../../core/firebase/firestore_host.dart';
import '../../../core/firebase/tenant_context.dart';
import '../../../core/utils/json_read.dart';
import '../../../core/utils/order_totals.dart';
import '../../auth/data/datasources/firebase_auth_datasource.dart';
import '../../auth/data/seed/turknroll_seed.dart';
import '../../auth/domain/entities/session.dart';
import '../../auth/domain/permissions.dart';
import '../../products/domain/entities/catalog.dart';

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.branchId,
    this.branchIds = const [],
    this.active = true,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? branchId;
  final List<String> branchIds;
  final bool active;
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.reorderLevel,
    this.sku,
    this.unit,
  });

  final String id;
  final String name;
  final String quantity;
  final String reorderLevel;
  final String? sku;
  final String? unit;
}

class InventoryTransaction {
  const InventoryTransaction({
    required this.id,
    required this.type,
    required this.quantity,
    required this.createdAt,
    this.inventoryId,
    this.ingredientId,
    this.branchId,
    this.reason,
    this.orderId,
    this.createdBy,
  });

  final String id;
  final String type;
  final String quantity;
  final DateTime createdAt;
  final String? inventoryId;
  final String? ingredientId;
  final String? branchId;
  final String? reason;
  final String? orderId;
  final String? createdBy;
}

class RecipeLine {
  const RecipeLine({required this.ingredientId, required this.quantity});
  final String ingredientId;
  final String quantity;
}

class ProductRecipe {
  const ProductRecipe({
    required this.id,
    required this.productId,
    required this.name,
    required this.items,
  });

  final String id;
  final String productId;
  final String name;
  final List<RecipeLine> items;
}

class IngredientOption {
  const IngredientOption({required this.id, required this.name});
  final String id;
  final String name;
}

class PosCustomer {
  const PosCustomer({
    required this.id,
    required this.name,
    this.phone,
    this.note,
  });

  final String id;
  final String name;
  final String? phone;
  final String? note;
}

class CreateBusinessRequest {
  const CreateBusinessRequest({
    required this.businessName,
    required this.slug,
    required this.currencyCode,
    required this.taxRate,
    required this.primaryColor,
    required this.secondaryColor,
    required this.branchName,
    required this.branchCode,
    required this.adminName,
    required this.adminEmail,
    required this.adminPassword,
    this.address,
    this.phone,
    this.receiptHeader,
    this.receiptFooter,
    this.seedSampleCatalog = false,
  });

  final String businessName;
  final String slug;
  final String currencyCode;
  final String taxRate;
  final String primaryColor;
  final String secondaryColor;
  final String? address;
  final String? phone;
  final String? receiptHeader;
  final String? receiptFooter;
  final String branchName;
  final String branchCode;
  final String adminName;
  final String adminEmail;
  final String adminPassword;
  final bool seedSampleCatalog;
}

class AdminRepository {
  AdminRepository(this._firestore, this._tenant, this._auth);

  final FirestoreHost _firestore;
  final TenantContext _tenant;
  final FirebaseAuthDataSource _auth;

  Future<List<BusinessProfile>> listBusinesses() async {
    try {
      final snap = await _firestore.requireDb().collection('businesses').get();
      return snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        data['id'] = doc.id;
        return BusinessProfile.fromJson(data);
      }).toList();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> createBusiness(CreateBusinessRequest request) async {
    try {
      final db = _firestore.requireDb();
      final businessId = _slug(request.slug.isEmpty ? request.businessName : request.slug);
      if (businessId.isEmpty) {
        throw const Failure('Enter a business name or slug.');
      }
      final existing = await db.collection('businesses').doc(businessId).get();
      if (existing.exists) {
        throw const Failure('A business with that slug already exists.');
      }
      final branchId = _slug(request.branchCode.isEmpty ? request.branchName : request.branchCode);
      await db.collection('businesses').doc(businessId).set({
        'id': businessId,
        'name': request.businessName,
        'slug': businessId,
        'primary_color': request.primaryColor,
        'secondary_color': request.secondaryColor,
        'currency_code': request.currencyCode,
        'tax_rate': request.taxRate,
        'address': request.address,
        'phone': request.phone,
        'receipt_header': request.receiptHeader ?? request.businessName,
        'receipt_footer': request.receiptFooter ?? 'Thank you',
        'orderSeq': 1000,
        'status': 'active',
      });
      await db.collection('businesses').doc(businessId).collection('branches').doc(branchId).set({
        'id': branchId,
        'name': request.branchName,
        'code': request.branchCode.toUpperCase(),
        'address': request.address,
        'phone': request.phone,
        'timezone': 'Asia/Karachi',
        'active': true,
      });
      final adminUid = await _auth.createUserWithoutSwitching(
        email: request.adminEmail,
        password: request.adminPassword,
      );
      await db.collection('users').doc(adminUid).set({
        'id': adminUid,
        'email': request.adminEmail,
        'name': request.adminName,
        'role': PosRole.businessAdmin,
        'permissions': PosRole.permissionsFor(PosRole.businessAdmin),
        'businessId': businessId,
        'branchId': branchId,
        'branchIds': [branchId],
        'active': true,
      });
      if (request.seedSampleCatalog) {
        await TurknRollFirestoreSeed(db).seedSampleMenu(businessId: businessId, branchId: branchId);
      }
      await writeAudit(action: 'business.create', detail: request.businessName, businessId: businessId);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<StaffMember>> listStaff({String? businessId, String? branchId}) async {
    try {
      final biz = businessId ?? _tenant.requireBusinessId();
      final selected = branchId ?? (_tenant.isAllBranches ? null : _tenant.effectiveBranchId);
      Query<Map<String, dynamic>> query = _firestore.requireDb().collection('users').where('businessId', isEqualTo: biz);
      if (selected != null) {
        query = query.where('branchId', isEqualTo: selected);
      } else if (_tenant.role != PosRole.businessAdmin && _tenant.role != PosRole.platformSuperAdmin) {
        final ids = _tenant.allowedBranchIds;
        if (ids.isEmpty) return [];
        query = ids.length == 1 ? query.where('branchId', isEqualTo: ids.first) : query.where('branchId', whereIn: ids.take(30).toList());
      }
      final snap = await query.get();
      return snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        final memberBranch = pick(data, ['branchId', 'branch_id'])?.toString();
        final memberBranches = readList(data, ['branchIds', 'branch_ids']).map((item) => item.toString()).toList();
        return StaffMember(
          id: doc.id,
          name: readString(data, ['name']),
          email: readString(data, ['email']),
          role: readString(data, ['role']),
          branchId: memberBranch,
          branchIds: memberBranches.isEmpty && memberBranch != null ? [memberBranch] : memberBranches,
          active: data.containsKey('active') ? readBool(data, ['active']) : true,
        );
      }).where((row) {
        if (selected == null) return true;
        return row.branchId == selected || row.branchIds.contains(selected);
      }).toList();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> inviteStaff({
    required String name,
    required String email,
    required String password,
    required String role,
    String? branchId,
    List<String> extraBranchIds = const [],
  }) async {
    try {
      if (!PosRole.invitableBy(_tenant.role ?? '').contains(role)) {
        throw const Failure('You cannot create that role.');
      }
      if (role == PosRole.platformSuperAdmin) {
        throw const Failure('Staff cannot be promoted to Super Admin.');
      }
      final businessId = _tenant.requireBusinessId();
      final assigned = branchId ?? _tenant.effectiveBranchId ?? _tenant.branchId;
      if (assigned == null || assigned.isEmpty) {
        throw const Failure('Assign the person to a branch.');
      }
      if (!_tenant.canAccessBranch(assigned)) {
        throw const Failure('You cannot assign staff to that branch.');
      }
      final uid = await _auth.createUserWithoutSwitching(email: email, password: password);
      await _firestore.requireDb().collection('users').doc(uid).set({
        'id': uid,
        'email': email,
        'name': name,
        'role': role,
        'permissions': PosRole.permissionsFor(role),
        'businessId': businessId,
        'branchId': assigned,
        'branchIds': extraBranchIds.isEmpty ? [assigned] : extraBranchIds,
        'active': true,
      });
      await writeAudit(action: 'staff.create', detail: '$name ($role)');
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<BranchProfile>> listBranches({String? businessId}) async {
    try {
      final biz = businessId ?? _tenant.requireBusinessId();
      final col = _firestore.requireDb().collection('businesses').doc(biz).collection('branches');
      if (businessId != null || _tenant.allowAllBranches || _tenant.role == PosRole.platformSuperAdmin) {
        final snap = await col.get();
        return snap.docs.map((doc) {
          final data = asStringKeyMap(doc.data());
          data['id'] = doc.id;
          return BranchProfile.fromJson(data);
        }).toList();
      }
      final rows = <BranchProfile>[];
      for (final id in _tenant.allowedBranchIds) {
        final snap = await col.doc(id).get();
        if (!snap.exists) continue;
        final data = asStringKeyMap(snap.data());
        data['id'] = snap.id;
        rows.add(BranchProfile.fromJson(data));
      }
      return rows;
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> createBranch({
    required String name,
    required String code,
    String? address,
    String? phone,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final id = _slug(code.isEmpty ? name : code);
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('branches').doc(id).set({
        'id': id,
        'name': name,
        'code': code.toUpperCase(),
        'address': address,
        'phone': phone,
        'timezone': 'Asia/Karachi',
        'active': true,
      });
      await writeAudit(action: 'branch.create', detail: name);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> saveBusiness({
    required String name,
    required String currencyCode,
    required String taxRate,
    required String primaryColor,
    required String secondaryColor,
    String? address,
    String? phone,
    String? receiptHeader,
    String? receiptFooter,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      await _firestore.requireDb().collection('businesses').doc(businessId).set({
        'name': name,
        'currency_code': currencyCode,
        'tax_rate': taxRate,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        'address': address,
        'phone': phone,
        if (receiptHeader != null) 'receipt_header': receiptHeader,
        if (receiptFooter != null) 'receipt_footer': receiptFooter,
      }, SetOptions(merge: true));
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> saveReceipt({
    required String receiptHeader,
    required String receiptFooter,
    required int paperWidthMm,
    required bool showAddress,
    required bool showPhone,
    String? address,
    String? phone,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      await _firestore.requireDb().collection('businesses').doc(businessId).set({
        'receipt_header': receiptHeader,
        'receipt_footer': receiptFooter,
        'receipt_paper_width': paperWidthMm <= 58 ? 58 : 80,
        'receipt_show_address': showAddress,
        'receipt_show_phone': showPhone,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
      }, SetOptions(merge: true));
      await writeAudit(action: 'receipt.update', detail: 'Receipt layout saved');
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> saveCategory(CatalogCategory category) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final id = category.id.isEmpty ? _slug(category.name) : category.id;
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('categories').doc(id).set({
        'id': id,
        'name': category.name,
        'slug': id,
        'sort_order': category.sortOrder,
      });
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      final businessId = _tenant.requireBusinessId();
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('categories').doc(id).delete();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> saveProduct({
    required String name,
    required String sku,
    required String categoryId,
    required String price,
    required String productType,
    String? id,
    bool active = true,
    List<ProductVariant> variants = const [],
    List<ProductOption> options = const [],
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final productId = (id != null && id.isNotEmpty) ? id : (sku.isEmpty ? _slug(name) : sku);
      final savedVariants = variants.isNotEmpty
          ? variants
          : [
              ProductVariant(
                id: '$productId-REG',
                name: 'Regular',
                price: price,
                isDefault: true,
              ),
            ];
      final hasDefault = savedVariants.any((item) => item.isDefault);
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('products').doc(productId).set({
        'id': productId,
        'category_id': categoryId,
        'name': name,
        'sku': sku.isEmpty ? productId : sku,
        'product_type': productType,
        'tracks_inventory': productType == 'RECIPE',
        'active': active,
        'variants': [
          for (var index = 0; index < savedVariants.length; index++)
            {
              'id': savedVariants[index].id.isEmpty ? '$productId-${index + 1}' : savedVariants[index].id,
              'name': savedVariants[index].name,
              'sku': '${sku.isEmpty ? productId : sku}-${index + 1}',
              'price': savedVariants[index].price,
              'is_default': hasDefault ? savedVariants[index].isDefault : index == 0,
            },
        ],
        'options': [
          for (var index = 0; index < options.length; index++)
            {
              'id': options[index].id.isEmpty ? '$productId-opt-${index + 1}' : options[index].id,
              'name': options[index].name,
              'extra_price': options[index].extraPrice,
            },
        ],
      }, SetOptions(merge: true));
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      final businessId = _tenant.requireBusinessId();
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('products').doc(id).delete();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<InventoryItem>> listInventory() async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('inventory').get();
      return snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        return InventoryItem(
          id: doc.id,
          name: readString(data, ['ingredient_name', 'ingredientName', 'name']),
          quantity: readString(data, ['quantity_base', 'quantityBase'], '0'),
          reorderLevel: readString(data, ['reorder_level', 'reorderLevel'], '0'),
          sku: pick(data, ['ingredient_id', 'sku'])?.toString(),
        );
      }).where((item) {
        final parts = item.id.split('_');
        final branchId = parts.isEmpty ? '' : parts.first;
        return _tenant.matchesBranch(branchId);
      }).toList();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> upsertIngredient({
    required String name,
    required String quantity,
    required String reorderLevel,
    String? sku,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final branchId = _tenant.requireBranchId();
      final ingredientId = _slug(sku == null || sku.isEmpty ? name : sku).toUpperCase();
      final db = _firestore.requireDb();
      final business = db.collection('businesses').doc(businessId);
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('ingredients').doc(ingredientId).set({
        'id': ingredientId,
        'business_id': businessId,
        'name': name,
        'sku': ingredientId,
        'unit': 'PCS',
      }, SetOptions(merge: true));
      final inventoryId = '${branchId}_$ingredientId';
      await business.collection('inventory').doc(inventoryId).set({
        'id': inventoryId,
        'business_id': businessId,
        'branch_id': branchId,
        'ingredient_id': ingredientId,
        'ingredient_name': name,
        'quantity_base': quantity,
        'reorder_level': reorderLevel,
      }, SetOptions(merge: true));
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<InventoryTransaction>> listInventoryTransactions({String? inventoryId}) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('inventory_transactions').limit(200).get();
      final rows = snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        final created = data['created_at'];
        final branchId = readString(data, ['branch_id', 'branchId'], doc.id.split('_').first);
        return InventoryTransaction(
          id: doc.id,
          type: readString(data, ['type'], 'ADJUST'),
          quantity: readString(data, ['quantity_base', 'quantityBase'], '0'),
          inventoryId: pick(data, ['inventory_id', 'inventoryId'])?.toString(),
          ingredientId: pick(data, ['ingredient_id', 'ingredientId'])?.toString(),
          branchId: branchId,
          reason: pick(data, ['reason'])?.toString(),
          orderId: pick(data, ['order_id', 'orderId'])?.toString(),
          createdBy: pick(data, ['created_by', 'createdBy'])?.toString(),
          createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
        );
      }).where((row) {
        if (inventoryId != null && row.inventoryId != inventoryId) return false;
        final branch = row.branchId ?? row.inventoryId?.split('_').first;
        return _tenant.matchesBranch(branch);
      }).toList();
      rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rows;
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<PosCustomer>> listCustomers() async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('customers').get();
      final rows = snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        return PosCustomer(
          id: doc.id,
          name: readString(data, ['name']),
          phone: pick(data, ['phone'])?.toString(),
          note: pick(data, ['note'])?.toString(),
        );
      }).toList();
      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return rows;
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<PosCustomer> saveCustomer({
    required String name,
    String? phone,
    String? note,
    String? id,
  }) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const Failure('Enter a customer name.');
      }
      final businessId = _tenant.requireBusinessId();
      final customerId = (id != null && id.isNotEmpty) ? id : _slug('$trimmed ${phone ?? ''} ${DateTime.now().millisecondsSinceEpoch}');
      final record = {
        'id': customerId,
        'name': trimmed,
        'phone': phone?.trim(),
        'note': note?.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('customers').doc(customerId).set(record, SetOptions(merge: true));
      return PosCustomer(id: customerId, name: trimmed, phone: phone?.trim(), note: note?.trim());
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> adjustStock({
    required String inventoryId,
    required String delta,
    required String reason,
  }) async {
    Failure? localFailure;
    try {
      final change = parseMoneyInputOrThrow(delta, label: 'Stock change');
      final businessId = _tenant.requireBusinessId();
      final db = _firestore.requireDb();
      final ref = db.collection('businesses').doc(businessId).collection('inventory').doc(inventoryId);
      await db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          localFailure = const Failure('Inventory item was not found.');
          throw localFailure!;
        }
        final data = asStringKeyMap(snap.data());
        final branchId = readString(data, ['branch_id', 'branchId'], inventoryId.split('_').first);
        final next = money(readString(data, ['quantity_base', 'quantityBase'], '0')) + change;
        if (next < money('0')) {
          localFailure = const Failure('Stock cannot go below zero.');
          throw localFailure!;
        }
        tx.update(ref, {'quantity_base': moneyString(next)});
        tx.set(db.collection('businesses').doc(businessId).collection('inventory_transactions').doc(), {
          'type': 'ADJUST',
          'branch_id': branchId,
          'quantity_base': moneyString(change),
          'reason': reason,
          'inventory_id': inventoryId,
          'created_at': FieldValue.serverTimestamp(),
          'created_by': _tenant.userId,
        });
      });
    } catch (error) {
      if (localFailure != null) throw localFailure!;
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> updateStaff({
    required String id,
    required String name,
    required String role,
    required String branchId,
    List<String> branchIds = const [],
    bool active = true,
  }) async {
    try {
      if (role == PosRole.platformSuperAdmin) {
        throw const Failure('Staff cannot be promoted to Super Admin.');
      }
      if (!PosRole.invitableBy(_tenant.role ?? '').contains(role) && role != PosRole.cashier) {
        throw const Failure('You cannot assign that role.');
      }
      if (!_tenant.canAccessBranch(branchId)) {
        throw const Failure('You cannot assign staff to that branch.');
      }
      final ids = branchIds.isEmpty ? [branchId] : branchIds;
      await _firestore.requireDb().collection('users').doc(id).set({
        'name': name,
        'role': role,
        'permissions': PosRole.permissionsFor(role),
        'branchId': branchId,
        'branchIds': ids,
        'active': active,
      }, SetOptions(merge: true));
      await writeAudit(action: active ? 'staff.edit' : 'staff.deactivate', detail: name);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> updateBranch({
    required String id,
    required String name,
    required String code,
    String? address,
    String? phone,
    bool active = true,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('branches').doc(id).set({
        'name': name,
        'code': code.toUpperCase(),
        'address': address,
        'phone': phone,
        'active': active,
      }, SetOptions(merge: true));
      await writeAudit(action: active ? 'branch.edit' : 'branch.deactivate', detail: name);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> setBusinessStatus({required String businessId, required String status}) async {
    try {
      await _firestore.requireDb().collection('businesses').doc(businessId).set({'status': status}, SetOptions(merge: true));
      await writeAudit(action: 'business.status', detail: '$businessId:$status', businessId: businessId, platform: true);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> saveBusinessProfile(CreateBusinessRequest request, {required String businessId}) async {
    try {
      await _firestore.requireDb().collection('businesses').doc(businessId).set({
        'name': request.businessName,
        'currency_code': request.currencyCode,
        'tax_rate': request.taxRate,
        'primary_color': request.primaryColor,
        'secondary_color': request.secondaryColor,
        'address': request.address,
        'phone': request.phone,
        'receipt_header': request.receiptHeader,
        'receipt_footer': request.receiptFooter,
      }, SetOptions(merge: true));
      await writeAudit(action: 'business.edit', detail: request.businessName, businessId: businessId, platform: true);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> writeAudit({
    required String action,
    String? detail,
    String? businessId,
    bool platform = false,
  }) async {
    try {
      final payload = {
        'action': action,
        'detail': detail,
        'actor_id': _tenant.userId,
        'created_at': FieldValue.serverTimestamp(),
      };
      if (platform) {
        await _firestore.requireDb().collection('platform_audit').add(payload);
        return;
      }
      final biz = businessId ?? _tenant.businessId;
      if (biz == null) return;
      await _firestore.requireDb().collection('businesses').doc(biz).collection('audit_logs').add(payload);
    } catch (_) {}
  }

  Future<List<Map<String, String>>> listAudit({bool platform = false}) async {
    try {
      if (platform) {
        final snap = await _firestore.requireDb().collection('platform_audit').limit(100).get();
        return snap.docs.map((doc) {
          final data = asStringKeyMap(doc.data());
          return {
            'action': readString(data, ['action']),
            'detail': readString(data, ['detail']),
            'at': data['created_at'] is Timestamp ? (data['created_at'] as Timestamp).toDate().toLocal().toString() : '',
          };
        }).toList();
      }
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('audit_logs').limit(100).get();
      return snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        return {
          'action': readString(data, ['action']),
          'detail': readString(data, ['detail']),
          'at': data['created_at'] is Timestamp ? (data['created_at'] as Timestamp).toDate().toLocal().toString() : '',
        };
      }).toList();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<IngredientOption>> listIngredients() async {
    try {
      final businessId = _tenant.requireBusinessId();
      final business = _firestore.requireDb().collection('businesses').doc(businessId);
      final snap = await business.collection('ingredients').get();
      final byId = <String, IngredientOption>{
        for (final doc in snap.docs)
          doc.id: IngredientOption(id: doc.id, name: readString(asStringKeyMap(doc.data()), ['name'], doc.id)),
      };
      final inventorySnap = await business.collection('inventory').get();
      for (final doc in inventorySnap.docs) {
        final data = asStringKeyMap(doc.data());
        final id = readString(data, ['ingredient_id', 'ingredientId']);
        if (id.isEmpty || byId.containsKey(id)) continue;
        byId[id] = IngredientOption(id: id, name: readString(data, ['ingredient_name', 'ingredientName', 'name'], id));
      }
      final rows = byId.values.toList();
      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return rows;
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<ProductRecipe>> listRecipes() async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('recipes').get();
      return snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        return ProductRecipe(
          id: doc.id,
          productId: readString(data, ['product_id', 'productId'], doc.id),
          name: readString(data, ['name'], doc.id),
          items: [
            for (final raw in readList(data, ['items']))
              RecipeLine(
                ingredientId: readString(asStringKeyMap(raw), ['ingredient_id', 'ingredientId']),
                quantity: readString(asStringKeyMap(raw), ['quantity_base', 'quantityBase'], '1'),
              ),
          ],
        );
      }).toList();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> saveRecipe({
    required String productId,
    required String productName,
    required List<RecipeLine> items,
  }) async {
    try {
      if (productId.isEmpty) {
        throw const Failure('Choose the POS product this recipe makes.');
      }
      final lines = items.where((item) => item.ingredientId.isNotEmpty).toList();
      if (lines.isEmpty) {
        throw const Failure('Add at least one ingredient.');
      }
      final businessId = _tenant.requireBusinessId();
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('recipes').doc(productId).set({
        'id': productId,
        'business_id': businessId,
        'product_id': productId,
        'name': productName,
        'yield_qty': '1',
        'items': [
          for (final line in lines) {'ingredient_id': line.ingredientId, 'quantity_base': line.quantity},
        ],
      });
      await writeAudit(action: 'recipe.save', detail: productName);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> deleteRecipe(String productId) async {
    try {
      final businessId = _tenant.requireBusinessId();
      await _firestore.requireDb().collection('businesses').doc(businessId).collection('recipes').doc(productId).delete();
      await writeAudit(action: 'recipe.delete', detail: productId);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<Map<String, String>>> listNamed(String collection) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final col = _firestore.requireDb().collection('businesses').doc(businessId).collection(collection);
      Query<Map<String, dynamic>> query = col;
      if (collection == 'purchases' || collection == 'waste') {
        if (_tenant.selectedBranchId != null) {
          query = col.where('branch_id', isEqualTo: _tenant.selectedBranchId);
        } else if (_tenant.role != PosRole.businessAdmin && _tenant.role != PosRole.platformSuperAdmin) {
          final ids = _tenant.allowedBranchIds;
          if (ids.isEmpty) return [];
          query = ids.length == 1 ? col.where('branch_id', isEqualTo: ids.first) : col.where('branch_id', whereIn: ids.take(30).toList());
        }
      }
      final snap = await query.get();
      return snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        data['id'] = doc.id;
        return {
          'id': doc.id,
          'name': readString(data, ['name']),
          'subtitle': readString(data, ['phone', 'code', 'sku', 'detail', 'branch_id'], ''),
        };
      }).toList();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> saveNamed({
    required String collection,
    required String name,
    Map<String, dynamic> extra = const {},
    String? id,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final docId = (id != null && id.isNotEmpty) ? id : _slug(name);
      final branchId = _tenant.effectiveBranchId;
      await _firestore.requireDb().collection('businesses').doc(businessId).collection(collection).doc(docId).set({
        'id': docId,
        'business_id': businessId,
        'name': name,
        if (branchId != null &&
            branchId.isNotEmpty &&
            !extra.containsKey('branch_id') &&
            !extra.containsKey('branchId') &&
            _collectionUsesBranch(collection))
          'branch_id': branchId,
        ...extra,
        'updated_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await writeAudit(action: '$collection.save', detail: name);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  bool _collectionUsesBranch(String collection) {
    return collection == 'purchases' ||
        collection == 'waste' ||
        collection == 'held_tickets';
  }

  Future<void> recordWaste({required String ingredientId, required String quantity, required String reason}) async {
    try {
      final branchId = _tenant.requireBranchId();
      await saveNamed(
        collection: 'waste',
        name: ingredientId,
        extra: {
          'ingredient_id': ingredientId,
          'quantity_base': quantity,
          'reason': reason,
          'branch_id': branchId,
        },
      );
      await adjustStock(inventoryId: '${branchId}_$ingredientId', delta: '-$quantity', reason: reason);
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> transferStock({
    required String ingredientId,
    required String fromBranchId,
    required String toBranchId,
    required String quantity,
  }) async {
    try {
      if (!_tenant.canAccessBranch(fromBranchId) || !_tenant.canAccessBranch(toBranchId)) {
        throw const Failure('You can only transfer between branches you manage.');
      }
      await adjustStock(inventoryId: '${fromBranchId}_$ingredientId', delta: '-$quantity', reason: 'Transfer out');
      final toId = '${toBranchId}_$ingredientId';
      final businessId = _tenant.requireBusinessId();
      final ref = _firestore.requireDb().collection('businesses').doc(businessId).collection('inventory').doc(toId);
      final snap = await ref.get();
      if (snap.exists) {
        await adjustStock(inventoryId: toId, delta: quantity, reason: 'Transfer in');
      } else {
        await ref.set({
          'id': toId,
          'branch_id': toBranchId,
          'ingredient_id': ingredientId,
          'ingredient_name': ingredientId,
          'quantity_base': quantity,
          'reorder_level': '0',
        });
      }
      await saveNamed(
        collection: 'stock_transfers',
        name: '$ingredientId $fromBranchId→$toBranchId',
        extra: {
          'ingredient_id': ingredientId,
          'from_branch_id': fromBranchId,
          'to_branch_id': toBranchId,
          'quantity_base': quantity,
        },
      );
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  String _slug(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
