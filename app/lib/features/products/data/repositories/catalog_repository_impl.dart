import 'package:hive/hive.dart';
import '../../../../core/firebase/firestore_host.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../../../../core/utils/json_read.dart';
import '../../domain/entities/catalog.dart';

abstract class CatalogRepository {
  Future<PosCatalog> load({bool forceRefresh = false});
}

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._firestore, this._tenant, this._box);

  final FirestoreHost _firestore;
  final TenantContext _tenant;
  final Box<dynamic> _box;

  String _cacheKey(String businessId) => 'pos_catalog_$businessId';

  PosCatalog? _catalogForBusiness(Object? raw, String businessId) {
    if (raw is! Map) {
      return null;
    }
    final stored = asStringKeyMap(raw);
    if (readString(stored, ['businessId', 'business_id']) != businessId) {
      return null;
    }
    final body = stored['catalog'];
    if (body is! Map) {
      return null;
    }
    try {
      return PosCatalog.fromJson(asStringKeyMap(body));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PosCatalog> load({bool forceRefresh = false}) async {
    final businessId = _tenant.requireBusinessId();
    final key = _cacheKey(businessId);
    final cached = _box.get(key);
    // Drop the old shared cache. It showed one business's menu inside another.
    await _box.delete('pos_catalog');
    if (!forceRefresh) {
      final cachedCatalog = _catalogForBusiness(cached, businessId);
      if (cachedCatalog != null) {
        return cachedCatalog;
      }
    }
    try {
      final db = _firestore.requireDb();
      final business = db.collection('businesses').doc(businessId);
      final categoriesSnap = await () async {
        try {
          return await business.collection('categories').orderBy('sort_order').get();
        } catch (_) {
          return business.collection('categories').get();
        }
      }();
      final productsSnap = await business.collection('products').get();
      final catalog = PosCatalog(
        categories: categoriesSnap.docs.map((doc) {
          final data = asStringKeyMap(doc.data());
          data['id'] = doc.id;
          return CatalogCategory.fromJson(data);
        }).toList(),
        products: productsSnap.docs.map((doc) {
          final data = asStringKeyMap(doc.data());
          data['id'] = doc.id;
          return CatalogProduct.fromJson(data);
        }).toList(),
      );
      await _box.put(key, {
        'businessId': businessId,
        'catalog': catalog.toJson(),
      });
      return catalog;
    } catch (error) {
      final cachedCatalog = _catalogForBusiness(cached, businessId);
      if (cachedCatalog != null) {
        return cachedCatalog;
      }
      throw mapFirebaseFailure(error);
    }
  }
}

Box<dynamic> openCatalogBox() => Hive.box(HiveBoxes.catalog);
