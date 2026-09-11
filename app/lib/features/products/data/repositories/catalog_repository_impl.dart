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

  @override
  Future<PosCatalog> load({bool forceRefresh = false}) async {
    final cached = _box.get('pos_catalog');
    if (!forceRefresh && cached is Map) {
      try {
        return PosCatalog.fromJson(asStringKeyMap(cached));
      } catch (_) {}
    }
    try {
      final db = _firestore.requireDb();
      final businessId = _tenant.requireBusinessId();
      final business = db.collection('businesses').doc(businessId);
      final categoriesSnap = await business.collection('categories').orderBy('sort_order').get();
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
      await _box.put('pos_catalog', catalog.toJson());
      return catalog;
    } catch (error) {
      if (cached is Map) {
        return PosCatalog.fromJson(asStringKeyMap(cached));
      }
      throw mapFirebaseFailure(error);
    }
  }
}

Box<dynamic> openCatalogBox() => Hive.box(HiveBoxes.catalog);
