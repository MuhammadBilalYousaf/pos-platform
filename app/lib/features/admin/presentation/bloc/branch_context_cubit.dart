import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../auth/domain/entities/session.dart';

class BranchContextState extends Equatable {
  const BranchContextState({
    this.branches = const [],
    this.selectedBranchId,
    this.allowAll = false,
    this.showSwitcher = false,
  });

  final List<BranchProfile> branches;
  final String? selectedBranchId;
  final bool allowAll;
  final bool showSwitcher;

  bool get isAll => selectedBranchId == null && allowAll;

  BranchProfile? get selected {
    if (selectedBranchId == null) return null;
    for (final branch in branches) {
      if (branch.id == selectedBranchId) return branch;
    }
    return null;
  }

  BranchContextState copyWith({
    List<BranchProfile>? branches,
    String? selectedBranchId,
    bool? allowAll,
    bool? showSwitcher,
    bool clearSelection = false,
  }) {
    return BranchContextState(
      branches: branches ?? this.branches,
      selectedBranchId: clearSelection ? null : (selectedBranchId ?? this.selectedBranchId),
      allowAll: allowAll ?? this.allowAll,
      showSwitcher: showSwitcher ?? this.showSwitcher,
    );
  }

  @override
  List<Object?> get props => [branches, selectedBranchId, allowAll, showSwitcher];
}

class BranchContextCubit extends Cubit<BranchContextState> {
  BranchContextCubit(this._tenant) : super(const BranchContextState());

  final TenantContext _tenant;

  void bind(Session session) {
    _tenant.apply(session);
    final branches = session.accessibleBranches.where((item) => item.active).toList();
    emit(
      BranchContextState(
        branches: branches,
        selectedBranchId: _tenant.selectedBranchId,
        allowAll: _tenant.allowAllBranches,
        showSwitcher: !session.user.isCashier && branches.isNotEmpty,
      ),
    );
  }

  void select(String? branchId) {
    _tenant.selectBranch(branchId);
    emit(state.copyWith(selectedBranchId: _tenant.selectedBranchId, clearSelection: _tenant.selectedBranchId == null));
  }

  void clear() {
    _tenant.clear();
    emit(const BranchContextState());
  }
}
