import 'package:equatable/equatable.dart';
import '../../../../core/utils/json_read.dart';

class CatalogCategory extends Equatable {
  const CatalogCategory({required this.id, required this.name, required this.sortOrder});

  final String id;
  final String name;
  final int sortOrder;

  factory CatalogCategory.fromJson(Map<String, dynamic> json) {
    return CatalogCategory(
      id: readString(json, ['id']),
      name: readString(json, ['name']),
      sortOrder: readInt(json, ['sort_order', 'sortOrder']),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'sort_order': sortOrder};

  @override
  List<Object?> get props => [id];
}

class ProductOption extends Equatable {
  const ProductOption({required this.id, required this.name, required this.extraPrice});

  final String id;
  final String name;
  final String extraPrice;

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    return ProductOption(
      id: readString(json, ['id']),
      name: readString(json, ['name']),
      extraPrice: readString(json, ['extra_price', 'extraPrice'], '0'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'extra_price': extraPrice};

  @override
  List<Object?> get props => [id];
}

class ProductVariant extends Equatable {
  const ProductVariant({
    required this.id,
    required this.name,
    required this.price,
    required this.isDefault,
  });

  final String id;
  final String name;
  final String price;
  final bool isDefault;

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: readString(json, ['id']),
      name: readString(json, ['name']),
      price: readString(json, ['price'], '0'),
      isDefault: readBool(json, ['is_default', 'isDefault']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'is_default': isDefault,
      };

  @override
  List<Object?> get props => [id];
}

class CatalogProduct extends Equatable {
  const CatalogProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.productType,
    required this.variants,
    required this.options,
    this.sku,
    this.active = true,
  });

  final String id;
  final String categoryId;
  final String name;
  final String productType;
  final String? sku;
  final bool active;
  final List<ProductVariant> variants;
  final List<ProductOption> options;

  ProductVariant get defaultVariant => variants.isEmpty
      ? const ProductVariant(id: '', name: 'Regular', price: '0', isDefault: true)
      : variants.firstWhere((item) => item.isDefault, orElse: () => variants.first);

  factory CatalogProduct.fromJson(Map<String, dynamic> json) {
    return CatalogProduct(
      id: readString(json, ['id']),
      categoryId: readString(json, ['category_id', 'categoryId']),
      name: readString(json, ['name']),
      productType: readString(json, ['product_type', 'productType'], 'SIMPLE'),
      sku: pick(json, ['sku'])?.toString(),
      active: json.containsKey('active') ? readBool(json, ['active']) : true,
      variants: readList(json, ['variants'])
          .map((item) => ProductVariant.fromJson(asStringKeyMap(item)))
          .toList(),
      options: readList(json, ['options'])
          .map((item) => ProductOption.fromJson(asStringKeyMap(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'product_type': productType,
        'sku': sku,
        'active': active,
        'variants': variants.map((item) => item.toJson()).toList(),
        'options': options.map((item) => item.toJson()).toList(),
      };

  @override
  List<Object?> get props => [id];
}

class PosCatalog extends Equatable {
  const PosCatalog({required this.categories, required this.products});

  final List<CatalogCategory> categories;
  final List<CatalogProduct> products;

  factory PosCatalog.fromJson(Map<String, dynamic> json) {
    return PosCatalog(
      categories: readList(json, ['categories'])
          .map((item) => CatalogCategory.fromJson(asStringKeyMap(item)))
          .toList(),
      products: readList(json, ['products'])
          .map((item) => CatalogProduct.fromJson(asStringKeyMap(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'categories': categories.map((item) => item.toJson()).toList(),
        'products': products.map((item) => item.toJson()).toList(),
      };

  @override
  List<Object?> get props => [categories, products];
}
