import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/permissions.dart';
import '../../domain/demo_accounts.dart';

class _SeedProduct {
  const _SeedProduct(this.category, this.name, this.sku, this.type, this.price);
  final String category;
  final String name;
  final String sku;
  final String type;
  final String price;
}

const _categories = [
  'Turkish Ice Cream',
  'Soft Ice Cream',
  'Sundae',
  'Fresh Mint',
  'Lemonade',
  'Water',
  'Kids Cup',
  'Boba Cup',
  'Cold Coffee',
  'Shake',
  'Brownie',
  'Molten Lawa',
];

const _products = [
  _SeedProduct('Turkish Ice Cream', 'Vanilla Turkish Ice Cream', 'TIC-VAN', 'SIMPLE', '350.00'),
  _SeedProduct('Turkish Ice Cream', 'Chocolate Turkish Ice Cream', 'TIC-CHO', 'SIMPLE', '350.00'),
  _SeedProduct('Turkish Ice Cream', 'Pistachio Turkish Ice Cream', 'TIC-PIS', 'SIMPLE', '450.00'),
  _SeedProduct('Turkish Ice Cream', 'Mango Turkish Ice Cream', 'TIC-MAN', 'SIMPLE', '400.00'),
  _SeedProduct('Turkish Ice Cream', 'Strawberry Turkish Ice Cream', 'TIC-STR', 'SIMPLE', '400.00'),
  _SeedProduct('Soft Ice Cream', 'Vanilla Soft Serve', 'SIC-VAN', 'SIMPLE', '250.00'),
  _SeedProduct('Soft Ice Cream', 'Chocolate Soft Serve', 'SIC-CHO', 'SIMPLE', '250.00'),
  _SeedProduct('Soft Ice Cream', 'Twist Soft Serve', 'SIC-TWI', 'SIMPLE', '280.00'),
  _SeedProduct('Sundae', 'Chocolate Sundae', 'SUN-CHO', 'SIMPLE', '450.00'),
  _SeedProduct('Sundae', 'Caramel Sundae', 'SUN-CAR', 'SIMPLE', '450.00'),
  _SeedProduct('Sundae', 'Strawberry Sundae', 'SUN-STR', 'SIMPLE', '450.00'),
  _SeedProduct('Fresh Mint', 'Fresh Mint Cooler', 'MNT-CLR', 'RECIPE', '280.00'),
  _SeedProduct('Lemonade', 'Classic Lemonade', 'LMN-CLS', 'RECIPE', '250.00'),
  _SeedProduct('Lemonade', 'Mint Lemonade', 'LMN-MNT', 'RECIPE', '280.00'),
  _SeedProduct('Water', 'Mineral Water', 'WTR-MIN', 'RECIPE', '80.00'),
  _SeedProduct('Kids Cup', 'Kids Vanilla Cup', 'KID-VAN', 'SIMPLE', '200.00'),
  _SeedProduct('Kids Cup', 'Kids Chocolate Cup', 'KID-CHO', 'SIMPLE', '200.00'),
  _SeedProduct('Boba Cup', 'Brown Sugar Boba', 'BOB-BRN', 'RECIPE', '550.00'),
  _SeedProduct('Boba Cup', 'Taro Boba', 'BOB-TAR', 'RECIPE', '550.00'),
  _SeedProduct('Cold Coffee', 'Iced Latte', 'COF-LAT', 'RECIPE', '450.00'),
  _SeedProduct('Cold Coffee', 'Classic Cold Coffee', 'COF-CLS', 'RECIPE', '420.00'),
  _SeedProduct('Cold Coffee', 'Mocha Cold Coffee', 'COF-MOC', 'RECIPE', '480.00'),
  _SeedProduct('Shake', 'Mango Shake', 'SHK-MAN', 'RECIPE', '450.00'),
  _SeedProduct('Shake', 'Chocolate Shake', 'SHK-CHO', 'RECIPE', '450.00'),
  _SeedProduct('Shake', 'Strawberry Shake', 'SHK-STR', 'RECIPE', '450.00'),
  _SeedProduct('Shake', 'Oreo Shake', 'SHK-ORE', 'RECIPE', '480.00'),
  _SeedProduct('Shake', 'Vanilla Shake', 'SHK-VAN', 'RECIPE', '420.00'),
  _SeedProduct('Brownie', 'Chocolate Brownie', 'BRW-CHO', 'SIMPLE', '300.00'),
  _SeedProduct('Brownie', 'Walnut Brownie', 'BRW-WAL', 'SIMPLE', '350.00'),
  _SeedProduct('Molten Lawa', 'Molten Lava Cake', 'MLT-LAV', 'SIMPLE', '400.00'),
];

class TurknRollFirestoreSeed {
  TurknRollFirestoreSeed(this._db);
  final FirebaseFirestore _db;

  Future<void> ensureStore({required String uid, required String email}) async {
    final businessRef = _db.collection('businesses').doc(DemoAccounts.businessId);
    final existing = await businessRef.get();
    if (!existing.exists) {
      await _writeCatalog(businessRef);
    }
    await _db.collection('users').doc(uid).set({
      'id': uid,
      'email': email,
      'name': 'TurknRoll Admin',
      'role': 'business_admin',
      'permissions': PosPermissions.admin,
      'businessId': DemoAccounts.businessId,
      'branchId': DemoAccounts.branchId,
    }, SetOptions(merge: true));
  }

  Future<void> seedSampleMenu({
    required String businessId,
    required String branchId,
  }) async {
    final businessRef = _db.collection('businesses').doc(businessId);
    await _writeSampleMenu(businessRef, branchId);
  }

  Future<void> _writeCatalog(DocumentReference<Map<String, dynamic>> businessRef) async {
    final batch = _db.batch();
    batch.set(businessRef, {
      'id': DemoAccounts.businessId,
      'name': 'TurknRoll',
      'slug': 'turknroll',
      'primary_color': '#C62828',
      'secondary_color': '#FFF8E7',
      'currency_code': 'PKR',
      'tax_rate': '0.0000',
      'address': 'TurknRoll Flagship',
      'phone': '0300-0000000',
      'receipt_header': 'TurknRoll',
      'receipt_footer': 'Thank you for visiting. Ice cream made to roll.',
      'orderSeq': 1000,
    });
    batch.set(businessRef.collection('branches').doc(DemoAccounts.branchId), {
      'id': DemoAccounts.branchId,
      'name': 'Main Branch',
      'code': 'MAIN',
      'address': 'TurknRoll Flagship',
      'phone': '0300-0000000',
      'timezone': 'Asia/Karachi',
    });
    await batch.commit();
    await _writeSampleMenu(businessRef, DemoAccounts.branchId);
  }
  Future<void> _writeSampleMenu(
    DocumentReference<Map<String, dynamic>> businessRef,
    String branchId,
  ) async {
    final batch = _db.batch();
    String slug(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final categoryIds = <String, String>{};
    for (var index = 0; index < _categories.length; index++) {
      final name = _categories[index];
      final id = slug(name);
      categoryIds[name] = id;
      batch.set(businessRef.collection('categories').doc(id), {
        'id': id,
        'name': name,
        'slug': id,
        'sort_order': index,
      });
    }

    for (final product in _products) {
      final categoryId = categoryIds[product.category]!;
      batch.set(businessRef.collection('products').doc(product.sku), {
        'id': product.sku,
        'category_id': categoryId,
        'name': product.name,
        'sku': product.sku,
        'product_type': product.type,
        'tracks_inventory': product.type == 'RECIPE',
        'variants': [
          {
            'id': '${product.sku}-REG',
            'name': 'Regular',
            'sku': '${product.sku}-REG',
            'price': product.price,
            'is_default': true,
          },
        ],
        'options': <Map<String, dynamic>>[],
      });
    }

    const ingredients = <Map<String, String>>[
      {'id': 'ING-MILK', 'name': 'Milk', 'sku': 'ING-MILK', 'unit': 'ML'},
      {'id': 'ING-MANGO', 'name': 'Mango', 'sku': 'ING-MANGO', 'unit': 'G'},
      {'id': 'ING-ICECREAM', 'name': 'Ice Cream Base', 'sku': 'ING-ICECREAM', 'unit': 'G'},
      {'id': 'ING-SUGAR', 'name': 'Sugar', 'sku': 'ING-SUGAR', 'unit': 'G'},
      {'id': 'ING-CUP', 'name': 'Cup', 'sku': 'ING-CUP', 'unit': 'PCS'},
      {'id': 'ING-STRAW', 'name': 'Straw', 'sku': 'ING-STRAW', 'unit': 'PCS'},
      {'id': 'ING-WATER', 'name': 'Water Bottle', 'sku': 'ING-WATER', 'unit': 'PCS'},
      {'id': 'ING-MINT', 'name': 'Fresh Mint', 'sku': 'ING-MINT', 'unit': 'G'},
      {'id': 'ING-LEMON', 'name': 'Lemon', 'sku': 'ING-LEMON', 'unit': 'G'},
      {'id': 'ING-COFFEE', 'name': 'Coffee', 'sku': 'ING-COFFEE', 'unit': 'G'},
      {'id': 'ING-BOBA', 'name': 'Boba Pearls', 'sku': 'ING-BOBA', 'unit': 'G'},
    ];
    for (final ingredient in ingredients) {
      batch.set(businessRef.collection('ingredients').doc(ingredient['id']), ingredient);
    }

    const opening = <List<String>>[
      ['ING-MILK', '20000', '2000'],
      ['ING-MANGO', '8000', '500'],
      ['ING-ICECREAM', '15000', '1000'],
      ['ING-SUGAR', '10000', '500'],
      ['ING-CUP', '500', '50'],
      ['ING-STRAW', '500', '50'],
      ['ING-WATER', '200', '20'],
      ['ING-MINT', '2000', '200'],
      ['ING-LEMON', '5000', '400'],
      ['ING-COFFEE', '3000', '300'],
      ['ING-BOBA', '4000', '400'],
    ];
    final names = {for (final item in ingredients) item['id']!: item['name']!};
    for (final row in opening) {
      final inventoryId = '${branchId}_${row[0]}';
      batch.set(businessRef.collection('inventory').doc(inventoryId), {
        'id': inventoryId,
        'branch_id': branchId,
        'ingredient_id': row[0],
        'ingredient_name': names[row[0]],
        'quantity_base': row[1],
        'reorder_level': row[2],
      });
    }

    void recipe(String sku, String name, List<List<String>> items) {
      batch.set(businessRef.collection('recipes').doc(sku), {
        'id': sku,
        'product_id': sku,
        'name': name,
        'yield_qty': '1',
        'items': items
            .map((item) => {'ingredient_id': item[0], 'quantity_base': item[1]})
            .toList(),
      });
    }

    recipe('SHK-MAN', 'Mango Shake', [
      ['ING-MILK', '250.0000'],
      ['ING-MANGO', '80.0000'],
      ['ING-ICECREAM', '100.0000'],
      ['ING-SUGAR', '20.0000'],
      ['ING-CUP', '1.0000'],
      ['ING-STRAW', '1.0000'],
    ]);
    recipe('WTR-MIN', 'Mineral Water', [
      ['ING-WATER', '1.0000'],
    ]);
    recipe('LMN-CLS', 'Classic Lemonade', [
      ['ING-LEMON', '40.0000'],
      ['ING-SUGAR', '20.0000'],
      ['ING-CUP', '1.0000'],
    ]);
    recipe('LMN-MNT', 'Mint Lemonade', [
      ['ING-LEMON', '40.0000'],
      ['ING-MINT', '10.0000'],
      ['ING-SUGAR', '20.0000'],
      ['ING-CUP', '1.0000'],
    ]);
    recipe('MNT-CLR', 'Fresh Mint Cooler', [
      ['ING-MINT', '15.0000'],
      ['ING-SUGAR', '15.0000'],
      ['ING-CUP', '1.0000'],
    ]);
    recipe('COF-LAT', 'Iced Latte', [
      ['ING-COFFEE', '18.0000'],
      ['ING-MILK', '200.0000'],
      ['ING-CUP', '1.0000'],
    ]);
    recipe('COF-CLS', 'Classic Cold Coffee', [
      ['ING-COFFEE', '18.0000'],
      ['ING-MILK', '180.0000'],
      ['ING-SUGAR', '15.0000'],
      ['ING-CUP', '1.0000'],
    ]);
    recipe('COF-MOC', 'Mocha Cold Coffee', [
      ['ING-COFFEE', '18.0000'],
      ['ING-MILK', '180.0000'],
      ['ING-SUGAR', '20.0000'],
      ['ING-CUP', '1.0000'],
    ]);
    recipe('BOB-BRN', 'Brown Sugar Boba', [
      ['ING-BOBA', '50.0000'],
      ['ING-MILK', '200.0000'],
      ['ING-SUGAR', '25.0000'],
      ['ING-CUP', '1.0000'],
      ['ING-STRAW', '1.0000'],
    ]);
    recipe('BOB-TAR', 'Taro Boba', [
      ['ING-BOBA', '50.0000'],
      ['ING-MILK', '200.0000'],
      ['ING-SUGAR', '25.0000'],
      ['ING-CUP', '1.0000'],
      ['ING-STRAW', '1.0000'],
    ]);
    recipe('SHK-CHO', 'Chocolate Shake', [
      ['ING-MILK', '250.0000'],
      ['ING-ICECREAM', '100.0000'],
      ['ING-SUGAR', '20.0000'],
      ['ING-CUP', '1.0000'],
      ['ING-STRAW', '1.0000'],
    ]);

    await batch.commit();
  }
}
