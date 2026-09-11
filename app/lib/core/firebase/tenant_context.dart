import '../errors/failures.dart';
import '../../features/auth/domain/entities/session.dart';
import '../../features/auth/domain/permissions.dart';

class TenantContext {
  String? userId;
  String? role;
  String? businessId;
  String? branchId;
  String? selectedBranchId;
  List<String> allowedBranchIds = const [];
  List<String> permissions = const [];
  bool allowAllBranches = false;

  void apply(Session session) {
    userId = session.user.id;
    role = session.user.role;
    businessId = session.business?.id;
    branchId = session.user.primaryBranchId ?? session.branch?.id;
    permissions = PosRole.permissionsFor(session.user.role);
    allowedBranchIds = session.user.resolvedBranchIds(
      fallback: session.branches.map((item) => item.id).toList(),
    );
    if (session.user.isBusinessAdmin || session.user.isPlatformAdmin) {
      allowAllBranches = session.user.isBusinessAdmin;
      allowedBranchIds = session.branches.map((item) => item.id).toList();
      selectedBranchId = null;
    } else if (session.user.isBranchManager) {
      allowAllBranches = allowedBranchIds.length > 1;
      selectedBranchId = allowedBranchIds.length == 1 ? allowedBranchIds.first : null;
      if (selectedBranchId == null && allowedBranchIds.length > 1) {
        selectedBranchId = null;
      }
      if (allowedBranchIds.length == 1) {
        selectedBranchId = allowedBranchIds.first;
      }
    } else {
      allowAllBranches = false;
      selectedBranchId = branchId ?? (allowedBranchIds.isEmpty ? null : allowedBranchIds.first);
    }
  }

  void selectBranch(String? id) {
    if (id == null) {
      if (!allowAllBranches) {
        return;
      }
      selectedBranchId = null;
      return;
    }
    if (allowAllBranches || allowedBranchIds.contains(id)) {
      selectedBranchId = id;
    }
  }

  void clear() {
    userId = null;
    role = null;
    businessId = null;
    branchId = null;
    selectedBranchId = null;
    allowedBranchIds = const [];
    permissions = const [];
    allowAllBranches = false;
  }

  String requireBusinessId() {
    final id = businessId;
    if (id == null || id.isEmpty) {
      throw const Failure('No business is assigned to this account.');
    }
    return id;
  }

  String requireBranchId() {
    final id = effectiveBranchId;
    if (id == null || id.isEmpty) {
      throw const Failure('Select a branch first.');
    }
    return id;
  }

  String? get effectiveBranchId => selectedBranchId ?? branchId;

  bool get isAllBranches => selectedBranchId == null && allowAllBranches;

  bool canAccessBranch(String? id) {
    if (id == null || id.isEmpty) {
      return allowAllBranches;
    }
    if (allowAllBranches) {
      return true;
    }
    return allowedBranchIds.contains(id);
  }

  bool matchesBranch(String? documentBranchId) {
    if (documentBranchId == null || documentBranchId.isEmpty) {
      return allowAllBranches;
    }
    if (!canAccessBranch(documentBranchId)) {
      return false;
    }
    if (selectedBranchId == null) {
      return true;
    }
    return documentBranchId == selectedBranchId;
  }
}
