import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/catalog.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../../../core/errors/failures.dart';

class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._repository) : super(const CatalogState());

  final CatalogRepository _repository;

  Future<void> load({bool forceRefresh = false}) async {
    emit(state.copyWith(status: CatalogStatus.loading));
    try {
      final catalog = await _repository.load(forceRefresh: forceRefresh);
      emit(state.copyWith(
        status: CatalogStatus.ready,
        catalog: catalog,
      ));
    } on Failure catch (error) {
      emit(state.copyWith(status: CatalogStatus.failure, message: error.message));
    } catch (_) {
      emit(state.copyWith(status: CatalogStatus.failure, message: 'Unable to load products.'));
    }
  }

  void selectCategory(String? id) {
    emit(state.copyWith(selectedCategoryId: id, clearCategory: id == null));
  }

  void search(String query) {
    emit(state.copyWith(query: query));
  }

  /// Exact barcode / SKU match for scanner input (product SKU, id, or variant SKU/id).
  BarcodeMatch? findByBarcode(String raw) => state.findByBarcode(raw);
}

class BarcodeMatch {
  const BarcodeMatch({required this.product, this.variant});
  final CatalogProduct product;
  final ProductVariant? variant;
}

bool _categoryMatches(PosCatalog? catalog, String productCategoryId, String? selectedId) {
  if (selectedId == null || productCategoryId == selectedId) return selectedId == null || productCategoryId == selectedId;
  final categories = catalog?.categories ?? const <CatalogCategory>[];
  final childIds = categories.where((item) => item.parentId == selectedId).map((item) => item.id).toSet();
  return childIds.contains(productCategoryId);
}

enum CatalogStatus { initial, loading, ready, failure }

class CatalogState extends Equatable {
  const CatalogState({
    this.status = CatalogStatus.initial,
    this.catalog,
    this.selectedCategoryId,
    this.query = '',
    this.message,
  });

  final CatalogStatus status;
  final PosCatalog? catalog;
  final String? selectedCategoryId;
  final String query;
  final String? message;

  List<CatalogProduct> get visibleProducts {
    final items = catalog?.products ?? const <CatalogProduct>[];
    final q = query.trim().toLowerCase();
    final searchActive = q.isNotEmpty;
    return items.where((product) {
      final matchesQuery = !searchActive ||
          product.name.toLowerCase().contains(q) ||
          (product.sku ?? '').toLowerCase().contains(q);
      final matchesCategory = searchActive ||
          selectedCategoryId == null ||
          _categoryMatches(catalog, product.categoryId, selectedCategoryId);
      return product.active && matchesCategory && matchesQuery && product.variants.isNotEmpty;
    }).toList();
  }

  BarcodeMatch? findByBarcode(String raw) {
    final code = raw.trim().toLowerCase();
    if (code.isEmpty) return null;
    for (final product in catalog?.products ?? const <CatalogProduct>[]) {
      if (!product.active || product.variants.isEmpty) continue;
      if ((product.sku ?? '').trim().toLowerCase() == code || product.id.toLowerCase() == code) {
        return BarcodeMatch(product: product);
      }
      for (final variant in product.variants) {
        final variantSku = (variant.sku ?? '').trim().toLowerCase();
        if (variantSku == code || variant.id.toLowerCase() == code) {
          return BarcodeMatch(product: product, variant: variant);
        }
      }
    }
    return null;
  }

  CatalogState copyWith({
    CatalogStatus? status,
    PosCatalog? catalog,
    String? selectedCategoryId,
    bool clearCategory = false,
    String? query,
    String? message,
  }) {
    return CatalogState(
      status: status ?? this.status,
      catalog: catalog ?? this.catalog,
      selectedCategoryId: clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
      query: query ?? this.query,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, catalog, selectedCategoryId, query, message];
}
