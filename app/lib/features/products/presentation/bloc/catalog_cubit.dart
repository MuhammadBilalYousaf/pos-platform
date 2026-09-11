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
    return items.where((product) {
      final matchesCategory = selectedCategoryId == null || product.categoryId == selectedCategoryId;
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query.toLowerCase()) ||
          (product.sku ?? '').toLowerCase().contains(query.toLowerCase());
      return product.active && matchesCategory && matchesQuery && product.variants.isNotEmpty;
    }).toList();
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
