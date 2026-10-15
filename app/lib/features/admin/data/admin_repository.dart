import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import '../../../core/errors/failures.dart';
import '../../../core/firebase/firestore_host.dart';
import '../../../core/firebase/tenant_context.dart';
import '../../../core/utils/json_read.dart';
import '../../../core/utils/order_totals.dart';
import '../../../core/utils/password_hash.dart';
import '../../../core/utils/stock_units.dart';
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
    this.unit = 'PCS',
    this.kind = 'INGREDIENT',
    this.unitCost = '0',
    this.unitCostPerBase = '0',
  });

  final String id;
  final String name;
  final String quantity;
  final String reorderLevel;
  final String? sku;
  final String unit;
  final String kind;
  /// Cost in money for one display [unit] (e.g. Rs per KG).
  final String unitCost;
  /// Cost per stored base unit (G / ML / PCS).
  final String unitCostPerBase;
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
  const RecipeLine({
    required this.ingredientId,
    required this.quantity,
    this.optionId,
    this.unit = 'PCS',
    this.variantQuantities = const {},
  });

  final String ingredientId;
  final String quantity;

  /// When set, this line is consumed only if the order includes that add-on/preparation.
  final String? optionId;

  /// Copied from the stock item. The recipe does not choose a different unit.
  final String unit;

  /// Amount of this ingredient used by each product size, in [unit].
  final Map<String, String> variantQuantities;
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
  const IngredientOption({
    required this.id,
    required this.name,
    this.unit = 'PCS',
    this.kind = 'INGREDIENT',
    this.unitCostPerBase = '0',
    this.onHandBase = '0',
    this.reorderLevel = '0',
  });

  final String id;
  final String name;
  final String unit;
  final String kind;
  /// Average / last purchase cost per base unit (G/ML/PCS).
  final String unitCostPerBase;
  final String onHandBase;
  final String reorderLevel;
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
      final actorRole = _tenant.role ?? '';
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
        if (!PosRole.canViewStaffRole(actorRole, row.role)) return false;
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
      if (!PosRole.canAssignRole(_tenant.role ?? '', role)) {
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

  /// Sets or changes the order-cancellation password (Business Admin only).
  /// Stores a one-way hash — plaintext is never written to Firestore.
  Future<void> setOrderCancellationPassword(String password) async {
    try {
      if (_tenant.role != PosRole.businessAdmin && _tenant.role != PosRole.platformSuperAdmin) {
        throw const Failure('Only a Business Admin can set the cancellation password.');
      }
      final trimmed = password.trim();
      if (trimmed.length < 4) {
        throw const Failure('Cancellation password must be at least 4 characters.');
      }
      final businessId = _tenant.requireBusinessId();
      final hash = hashBusinessSecret(trimmed, businessId: businessId);
      await _firestore.requireDb().collection('businesses').doc(businessId).set({
        'order_cancel_password_hash': hash,
        'order_cancel_password_updated_at': FieldValue.serverTimestamp(),
        'order_cancel_password_updated_by': _tenant.userId,
      }, SetOptions(merge: true));
      await writeAudit(action: 'settings.cancel_password', detail: 'updated');
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  Future<bool> hasOrderCancellationPassword() async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).get();
      final data = asStringKeyMap(snap.data());
      return readString(data, ['order_cancel_password_hash']).isNotEmpty;
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  /// Validates the cancellation password against the stored hash.
  /// Does not return the hash or plaintext to callers.
  Future<void> verifyOrderCancellationPassword(String password) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).get();
      final data = asStringKeyMap(snap.data());
      final stored = readString(data, ['order_cancel_password_hash']);
      if (stored.isEmpty) {
        throw const Failure('No cancellation password is configured. Ask a Business Admin to set one in Settings.');
      }
      if (!matchesBusinessSecret(input: password, storedHash: stored, businessId: businessId)) {
        throw const Failure('Incorrect cancellation password.');
      }
    } catch (error) {
      if (error is Failure) rethrow;
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
        'parent_id': category.parentId,
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
              'recipe_multiplier': savedVariants[index].recipeMultiplier.isEmpty ? '1' : savedVariants[index].recipeMultiplier,
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

  /// Converts a display-unit purchase cost (Rs per KG/L/PCS/…) into cost per base unit.
  static Decimal unitCostToBase(String unitCost, String unit) {
    final cost = money(unitCost.isEmpty ? '0' : unitCost);
    switch (StockUnits.normalize(unit)) {
      case 'KG':
      case 'L':
        return (cost / Decimal.fromInt(1000)).toDecimal(scaleOnInfinitePrecision: 6);
      default:
        return cost;
    }
  }

  static String unitCostFromBase(String unitCostPerBase, String unit) {
    final cost = money(unitCostPerBase.isEmpty ? '0' : unitCostPerBase);
    switch (StockUnits.normalize(unit)) {
      case 'KG':
      case 'L':
        return moneyString(cost * Decimal.fromInt(1000));
      default:
        return moneyString(cost);
    }
  }

  Future<List<InventoryItem>> listInventory() async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('inventory').get();
      return snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        final unit = readString(data, ['unit'], 'PCS');
        final perBase = readString(data, ['unit_cost_per_base', 'unitCostPerBase'], '0');
        return InventoryItem(
          id: doc.id,
          name: readString(data, ['ingredient_name', 'ingredientName', 'name']),
          quantity: StockUnits.fromBase(money(readString(data, ['quantity_base', 'quantityBase'], '0')), unit),
          reorderLevel: readString(data, ['reorder_level', 'reorderLevel'], '0'),
          sku: pick(data, ['ingredient_id', 'sku'])?.toString(),
          unit: unit,
          kind: readString(data, ['kind'], 'INGREDIENT'),
          unitCostPerBase: perBase,
          unitCost: unitCostFromBase(perBase, unit),
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

  Future<void> updateInventoryItem({
    required InventoryItem item,
    required String name,
    required String unit,
    required String kind,
    required String quantity,
    required String reorderLevel,
    String? unitCost,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final ingredientId = (item.sku ?? '').trim().toUpperCase();
      if (ingredientId.isEmpty) {
        throw const Failure('This stock item has no SKU.');
      }
      final normalizedUnit = StockUnits.normalize(unit);
      final storedQty = moneyString(StockUnits.toBase(quantity.isEmpty ? '0' : quantity, normalizedUnit));
      final costPerBase = unitCost == null || unitCost.trim().isEmpty
          ? money(item.unitCostPerBase.isEmpty ? '0' : item.unitCostPerBase)
          : unitCostToBase(unitCost.trim(), normalizedUnit);
      if (costPerBase < Decimal.zero) {
        throw const Failure('Unit cost cannot be negative.');
      }
      final db = _firestore.requireDb().collection('businesses').doc(businessId);
      await db.collection('ingredients').doc(ingredientId).set({
        'name': name,
        'unit': normalizedUnit,
        'kind': kind,
        'unit_cost_per_base': moneyString(costPerBase),
      }, SetOptions(merge: true));
      await db.collection('inventory').doc(item.id).set({
        'ingredient_name': name,
        'unit': normalizedUnit,
        'kind': kind,
        'quantity_base': storedQty,
        'reorder_level': reorderLevel.isEmpty ? '0' : reorderLevel,
        'unit_cost_per_base': moneyString(costPerBase),
      }, SetOptions(merge: true));
      await writeAudit(action: 'inventory.update', detail: name);
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  /// Adds a received purchase onto current stock. Does not replace the quantity already on hand.
  /// Optional [unitCost] is the purchase cost for the entered quantity (updates weighted average cost).
  Future<void> receivePurchase({
    required String ingredientId,
    required String quantity,
    String? unitCost,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final branchId = _tenant.requireBranchId();
      final id = ingredientId.trim().toUpperCase();
      final db = _firestore.requireDb().collection('businesses').doc(businessId);
      final ingredientSnap = await db.collection('ingredients').doc(id).get();
      if (!ingredientSnap.exists) {
        throw Failure('No stock item with SKU $id. Add it in Inventory first.');
      }
      final ingredient = asStringKeyMap(ingredientSnap.data());
      final unit = readString(ingredient, ['unit'], 'PCS');
      final received = StockUnits.toBase(quantity, unit);
      if (received <= Decimal.zero) {
        throw const Failure('Purchase quantity must be greater than zero.');
      }
      final inventoryId = '${branchId}_$id';
      final inventoryRef = db.collection('inventory').doc(inventoryId);
      final existingSnap = await inventoryRef.get();
      if (!existingSnap.exists) {
        await inventoryRef.set({
          'id': inventoryId,
          'business_id': businessId,
          'branch_id': branchId,
          'ingredient_id': id,
          'ingredient_name': readString(ingredient, ['name'], id),
          'quantity_base': '0',
          'unit': unit,
          'kind': readString(ingredient, ['kind'], 'INGREDIENT'),
          'reorder_level': '0',
          'unit_cost_per_base': '0',
        });
      }
      Decimal? avgCost;
      Decimal? newCostPerBase;
      if (unitCost != null && unitCost.trim().isNotEmpty) {
        final totalPaid = parseMoneyInputOrThrow(unitCost, label: 'Purchase cost');
        if (totalPaid < Decimal.zero) {
          throw const Failure('Purchase cost cannot be negative.');
        }
        final stock = asStringKeyMap((await inventoryRef.get()).data());
        final currentQty = money(readString(stock, ['quantity_base', 'quantityBase'], '0'));
        final currentCost = money(readString(stock, ['unit_cost_per_base', 'unitCostPerBase'], '0'));
        newCostPerBase = received > Decimal.zero
            ? (totalPaid / received).toDecimal(scaleOnInfinitePrecision: 6)
            : Decimal.zero;
        final combinedQty = currentQty + received;
        final numerator = (currentCost * currentQty) + (newCostPerBase * received);
        avgCost = combinedQty > Decimal.zero
            ? (numerator / combinedQty).toDecimal(scaleOnInfinitePrecision: 6)
            : newCostPerBase;
        await inventoryRef.set({'unit_cost_per_base': moneyString(avgCost)}, SetOptions(merge: true));
        await db.collection('ingredients').doc(id).set({
          'unit_cost_per_base': moneyString(avgCost),
          'last_purchase_cost_per_base': moneyString(newCostPerBase),
        }, SetOptions(merge: true));
      }
      await adjustStock(inventoryId: inventoryId, delta: moneyString(received), reason: 'Purchase');
      // Re-apply cost after adjust in case adjust overwrote merge fields on some paths.
      if (avgCost != null && newCostPerBase != null) {
        await inventoryRef.set({'unit_cost_per_base': moneyString(avgCost)}, SetOptions(merge: true));
      }
      await saveNamed(
        collection: 'purchases',
        name: readString(ingredient, ['name'], id),
        extra: {
          'ingredient_id': id,
          'quantity': quantity,
          'unit': StockUnits.normalize(unit),
          'quantity_base': moneyString(received),
          if (unitCost != null && unitCost.trim().isNotEmpty) 'purchase_cost': unitCost.trim(),
          'branch_id': branchId,
          'status': 'Received',
          'created_by': _tenant.userId,
        },
      );
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> upsertIngredient({
    required String name,
    required String quantity,
    required String reorderLevel,
    String? sku,
    String unit = 'PCS',
    String kind = 'INGREDIENT',
    String? unitCost,
  }) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final branchId = _tenant.requireBranchId();
      final ingredientId = _slug(sku == null || sku.isEmpty ? name : sku).toUpperCase();
      final normalizedUnit = StockUnits.normalize(unit);
      final costPerBase = unitCost == null || unitCost.trim().isEmpty
          ? Decimal.zero
          : unitCostToBase(unitCost.trim(), normalizedUnit);
      if (costPerBase < Decimal.zero) {
        throw const Failure('Unit cost cannot be negative.');
      }
      final db = _firestore.requireDb();
      final business = db.collection('businesses').doc(businessId);
      await business.collection('ingredients').doc(ingredientId).set({
        'id': ingredientId,
        'business_id': businessId,
        'name': name,
        'sku': ingredientId,
        'unit': normalizedUnit,
        'kind': kind,
        'unit_cost_per_base': moneyString(costPerBase),
      }, SetOptions(merge: true));
      final inventoryId = '${branchId}_$ingredientId';
      final storedQty = moneyString(StockUnits.toBase(quantity.isEmpty ? '0' : quantity, normalizedUnit));
      await business.collection('inventory').doc(inventoryId).set({
        'id': inventoryId,
        'business_id': businessId,
        'branch_id': branchId,
        'ingredient_id': ingredientId,
        'ingredient_name': name,
        'quantity_base': storedQty,
        'unit': normalizedUnit,
        'kind': kind,
        'reorder_level': reorderLevel,
        'unit_cost_per_base': moneyString(costPerBase),
      }, SetOptions(merge: true));
    } catch (error) {
      if (error is Failure) rethrow;
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

  /// Updates staff profile. Returns an optional Auth warning (e.g. password reset email sent).
  Future<String?> updateStaff({
    required String id,
    required String name,
    required String role,
    required String branchId,
    required String email,
    List<String> branchIds = const [],
    bool active = true,
    String? newPassword,
    String? previousEmail,
  }) async {
    try {
      final actorRole = _tenant.role ?? '';
      if (id == _tenant.userId) {
        throw const Failure('You cannot edit your own staff record here.');
      }
      if (role == PosRole.platformSuperAdmin) {
        throw const Failure('Staff cannot be promoted to Super Admin.');
      }
      if (!PosRole.canAssignRole(actorRole, role)) {
        throw const Failure('You cannot assign that role.');
      }
      if (!_tenant.canAccessBranch(branchId)) {
        throw const Failure('You cannot assign staff to that branch.');
      }

      final existingSnap = await _firestore.requireDb().collection('users').doc(id).get();
      if (!existingSnap.exists) {
        throw const Failure('Staff member not found.');
      }
      final existing = asStringKeyMap(existingSnap.data());
      final currentRole = readString(existing, ['role']);
      if (!PosRole.canEditStaffRole(actorRole, currentRole)) {
        throw Failure(
          'You cannot edit a ${PosRole.label(currentRole)}. '
          'Only staff below your role are editable.',
        );
      }

      final trimmedEmail = email.trim();
      if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
        throw const Failure('Enter a valid email address.');
      }
      final password = newPassword?.trim() ?? '';
      if (password.isNotEmpty && password.length < 6) {
        throw const Failure('Password must be at least 6 characters.');
      }
      final ids = branchIds.isEmpty ? [branchId] : branchIds;
      await _firestore.requireDb().collection('users').doc(id).set({
        'name': name.trim(),
        'email': trimmedEmail,
        'role': role,
        'permissions': PosRole.permissionsFor(role),
        'branchId': branchId,
        'branchIds': ids,
        'active': active,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': _tenant.userId,
      }, SetOptions(merge: true));
      await writeAudit(action: active ? 'staff.edit' : 'staff.deactivate', detail: '$name <$trimmedEmail>');

      String? authWarning;
      final loginEmail = (previousEmail != null && previousEmail.trim().isNotEmpty) ? previousEmail.trim() : trimmedEmail;
      if (password.isNotEmpty || loginEmail.toLowerCase() != trimmedEmail.toLowerCase()) {
        try {
          await _auth.updateUserAuthWithoutSwitching(
            email: loginEmail,
            newEmail: trimmedEmail,
            newPassword: password.isEmpty ? null : password,
          );
        } on Failure catch (error) {
          // Profile is already saved; surface Auth follow-up as a warning.
          authWarning = error.message;
        }
      }
      return authWarning;
    } catch (error) {
      if (error is Failure) rethrow;
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
          doc.id: IngredientOption(
            id: doc.id,
            name: readString(asStringKeyMap(doc.data()), ['name'], doc.id),
            unit: readString(asStringKeyMap(doc.data()), ['unit'], 'PCS'),
            kind: readString(asStringKeyMap(doc.data()), ['kind'], 'INGREDIENT'),
            unitCostPerBase: readString(asStringKeyMap(doc.data()), ['unit_cost_per_base', 'unitCostPerBase'], '0'),
          ),
      };
      final inventorySnap = await business.collection('inventory').get();
      for (final doc in inventorySnap.docs) {
        final data = asStringKeyMap(doc.data());
        final parts = doc.id.split('_');
        final branchId = parts.isEmpty ? '' : parts.first;
        if (!_tenant.matchesBranch(branchId)) continue;
        final id = readString(data, ['ingredient_id', 'ingredientId']);
        if (id.isEmpty) continue;
        final onHand = readString(data, ['quantity_base', 'quantityBase'], '0');
        final reorder = readString(data, ['reorder_level', 'reorderLevel'], '0');
        final unitCost = readString(data, ['unit_cost_per_base', 'unitCostPerBase'], '0');
        final existing = byId[id];
        if (existing == null) {
          byId[id] = IngredientOption(
            id: id,
            name: readString(data, ['ingredient_name', 'ingredientName', 'name'], id),
            unit: readString(data, ['unit'], 'PCS'),
            kind: readString(data, ['kind'], 'INGREDIENT'),
            unitCostPerBase: unitCost,
            onHandBase: onHand,
            reorderLevel: reorder,
          );
        } else {
          byId[id] = IngredientOption(
            id: existing.id,
            name: existing.name,
            unit: existing.unit,
            kind: existing.kind,
            unitCostPerBase: existing.unitCostPerBase != '0' ? existing.unitCostPerBase : unitCost,
            onHandBase: onHand,
            reorderLevel: reorder,
          );
        }
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
                optionId: () {
                  final id = readString(asStringKeyMap(raw), ['option_id', 'optionId']);
                  return id.isEmpty ? null : id;
                }(),
                unit: readString(asStringKeyMap(raw), ['unit'], 'PCS'),
                variantQuantities: _stringMap(asStringKeyMap(raw)['variant_quantities']),
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
          for (final line in lines)
            {
              'ingredient_id': line.ingredientId,
              'quantity_base': line.quantity,
              'unit': line.unit,
              if (line.optionId != null && line.optionId!.isNotEmpty) 'option_id': line.optionId,
              if (line.variantQuantities.isNotEmpty) 'variant_quantities': line.variantQuantities,
            },
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
          'subtitle': [
            readString(data, ['quantity', 'quantity_base']),
            readString(data, ['unit']),
            readString(data, ['reason']),
            readString(data, ['phone', 'code', 'sku', 'detail', 'branch_id']),
          ].where((part) => part.isNotEmpty).join(' · '),
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

  Future<void> recordWaste({
    required String ingredientId,
    required String quantity,
    required String reason,
    String unit = 'PCS',
    String? notes,
  }) async {
    try {
      final branchId = _tenant.requireBranchId();
      final base = StockUnits.toBase(quantity, unit);
      if (base <= Decimal.zero) {
        throw const Failure('Waste quantity must be greater than zero.');
      }
      final baseText = moneyString(base);
      await saveNamed(
        collection: 'waste',
        name: ingredientId,
        extra: {
          'ingredient_id': ingredientId,
          'quantity': quantity,
          'unit': StockUnits.normalize(unit),
          'quantity_base': baseText,
          'reason': reason,
          'notes': notes,
          'branch_id': branchId,
          'created_by': _tenant.userId,
        },
      );
      await adjustStock(inventoryId: '${branchId}_$ingredientId', delta: '-$baseText', reason: 'WASTE: $reason');
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  /// Deducts component ingredients and adds the prepared mixture to stock.
  /// Selling a product later consumes the mixture only, so ingredients are not deducted twice.
  Future<void> produceMixture({
    required String mixtureId,
    required String yieldQuantity,
    required String yieldUnit,
    required List<RecipeLine> components,
  }) async {
    try {
      final branchId = _tenant.requireBranchId();
      final businessId = _tenant.requireBusinessId();
      final yieldBase = StockUnits.toBase(yieldQuantity, yieldUnit);
      if (yieldBase <= Decimal.zero) {
        throw const Failure('Yield must be greater than zero.');
      }
      final lines = components.where((line) => line.ingredientId.trim().isNotEmpty).toList();
      if (lines.isEmpty) {
        throw const Failure('Add at least one ingredient to produce this mixture.');
      }
      final seen = <String>{};
      final needs = <String, Decimal>{};
      final labels = <String, String>{};
      for (final line in lines) {
        final ingredientId = line.ingredientId.trim().toUpperCase();
        if (!seen.add(ingredientId)) {
          throw Failure('Ingredient $ingredientId is listed more than once. Combine quantities into one row.');
        }
        final used = StockUnits.toBase(line.quantity, line.unit);
        if (used <= Decimal.zero) {
          throw Failure('Quantity for $ingredientId must be greater than zero.');
        }
        needs['${branchId}_$ingredientId'] = used;
        labels['${branchId}_$ingredientId'] = ingredientId;
      }

      final db = _firestore.requireDb();
      final inventory = db.collection('businesses').doc(businessId).collection('inventory');
      // Validate all stock first so we never partially deduct on failure.
      for (final entry in needs.entries) {
        final snap = await inventory.doc(entry.key).get();
        if (!snap.exists) {
          throw Failure(
            'Stock for ${labels[entry.key]} was not found in this branch. Add it under Inventory first.',
          );
        }
        final data = asStringKeyMap(snap.data());
        final current = money(readString(data, ['quantity_base', 'quantityBase'], '0'));
        if (current < entry.value) {
          final name = readString(data, ['ingredient_name', 'ingredientName'], labels[entry.key] ?? entry.key);
          final unit = readString(data, ['unit'], 'PCS');
          throw Failure(
            'Insufficient stock for $name. Need ${StockUnits.fromBase(entry.value, unit)} $unit, available ${StockUnits.fromBase(current, unit)} $unit.',
          );
        }
      }

      var mixtureCost = Decimal.zero;
      for (final entry in needs.entries) {
        final snap = await inventory.doc(entry.key).get();
        final data = asStringKeyMap(snap.data());
        final unitCost = money(readString(data, ['unit_cost_per_base', 'unitCostPerBase'], '0'));
        mixtureCost += unitCost * entry.value;
        await adjustStock(
          inventoryId: entry.key,
          delta: '-${moneyString(entry.value)}',
          reason: 'Produce $mixtureId',
        );
      }

      final mixId = '${branchId}_$mixtureId';
      final ref = inventory.doc(mixId);
      final snap = await ref.get();
      final mixtureName = mixtureId;
      if (!snap.exists) {
        final ingredientSnap =
            await db.collection('businesses').doc(businessId).collection('ingredients').doc(mixtureId).get();
        final ingredientName = ingredientSnap.exists
            ? readString(asStringKeyMap(ingredientSnap.data()), ['name'], mixtureId)
            : mixtureName;
        await ref.set({
          'id': mixId,
          'branch_id': branchId,
          'ingredient_id': mixtureId,
          'ingredient_name': ingredientName,
          'quantity_base': '0',
          'unit': StockUnits.normalize(yieldUnit),
          'kind': 'MIXTURE',
          'reorder_level': '0',
          'unit_cost_per_base': '0',
        });
      }
      final costPerBase = yieldBase > Decimal.zero
          ? (mixtureCost / yieldBase).toDecimal(scaleOnInfinitePrecision: 6)
          : Decimal.zero;
      await adjustStock(inventoryId: mixId, delta: moneyString(yieldBase), reason: 'Mixture produced');
      await ref.set({
        'unit_cost_per_base': moneyString(costPerBase),
        'kind': 'MIXTURE',
        'last_produced_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await db.collection('businesses').doc(businessId).collection('ingredients').doc(mixtureId).set({
        'unit_cost_per_base': moneyString(costPerBase),
        'kind': 'MIXTURE',
      }, SetOptions(merge: true));

      await saveNamed(
        collection: 'productions',
        name: mixtureId,
        extra: {
          'mixture_id': mixtureId,
          'yield_quantity_base': moneyString(yieldBase),
          'unit': StockUnits.baseOf(yieldUnit),
          'branch_id': branchId,
          'created_by': _tenant.userId,
          'total_component_cost': moneyString(mixtureCost),
          'unit_cost_per_base': moneyString(costPerBase),
          'components': [
            for (final line in lines)
              {
                'ingredient_id': line.ingredientId.trim().toUpperCase(),
                'quantity_base': moneyString(StockUnits.toBase(line.quantity, line.unit)),
                'unit': StockUnits.normalize(line.unit),
              },
          ],
        },
      );
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  Future<int> applyBulkPrice({
    required List<String> productIds,
    String? price,
    bool variantsOnlyDefault = false,
  }) async {
    if (productIds.isEmpty) {
      throw const Failure('Select at least one product.');
    }
    final nextPrice = parseMoneyInputOrThrow(price ?? '0', label: 'Price');
    if (nextPrice < Decimal.zero) {
      throw const Failure('Price cannot be negative.');
    }
    final businessId = _tenant.requireBusinessId();
    final col = _firestore.requireDb().collection('businesses').doc(businessId).collection('products');
    var updated = 0;
    for (final id in productIds) {
      final ref = col.doc(id);
      final snap = await ref.get();
      if (!snap.exists) continue;
      final data = asStringKeyMap(snap.data());
      final variants = readList(data, ['variants']).map(asStringKeyMap).toList();
      final nextVariants = [
        for (final variant in variants)
          {
            ...variant,
            if (!variantsOnlyDefault || readBool(variant, ['is_default', 'isDefault']))
              'price': moneyString(nextPrice),
          },
      ];
      await ref.set({
        'variants': nextVariants,
        'bulk_price_updated_at': FieldValue.serverTimestamp(),
        'bulk_price_updated_by': _tenant.userId,
      }, SetOptions(merge: true));
      updated++;
    }
    await writeAudit(
      action: 'catalog.bulk_price',
      detail: '$updated products set to ${moneyString(nextPrice)}',
    );
    return updated;
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

  Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key.toString().isNotEmpty) entry.key.toString(): entry.value.toString(),
    };
  }

  String _slug(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
