import 'package:equatable/equatable.dart';
import '../../../../core/utils/json_read.dart';
import '../permissions.dart';

class PosUser extends Equatable {
  const PosUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.permissions,
    this.active = true,
    this.primaryBranchId,
    this.branchIds = const [],
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final List<String> permissions;
  final bool active;
  final String? primaryBranchId;
  final List<String> branchIds;

  bool can(String permission) {
    if (permission == PosPermissions.platformManage && role != PosRole.platformSuperAdmin) {
      return false;
    }
    return PosRole.permissionsFor(role).contains(permission);
  }

  bool get isPlatformAdmin => role == PosRole.platformSuperAdmin;
  bool get isBusinessAdmin => role == PosRole.businessAdmin;
  bool get isBranchManager => role == PosRole.branchManager;
  bool get isCashier => role == PosRole.cashier;
  bool get canRunPos => can(PosPermissions.ordersCreate);
  bool get canManageStaff => can(PosPermissions.staffCreate) || can(PosPermissions.usersManage);
  bool get canManageCatalog => can(PosPermissions.catalogWrite);
  bool get canManageInventory => can(PosPermissions.inventoryAdjust);
  bool get canViewReports => can(PosPermissions.reportsView);
  bool get canManageSettings => can(PosPermissions.settingsManage);
  bool get canManageBranches => can(PosPermissions.branchCreate) || can(PosPermissions.branchEdit);

  List<String> resolvedBranchIds({List<String> fallback = const []}) {
    if (isBusinessAdmin || isPlatformAdmin) {
      return fallback;
    }
    final ids = <String>{
      ...branchIds.where((item) => item.isNotEmpty),
      if (primaryBranchId != null && primaryBranchId!.isNotEmpty) primaryBranchId!,
    };
    return ids.toList();
  }

  factory PosUser.fromJson(Map<String, dynamic> json) {
    final branchId = pick(json, ['branchId', 'branch_id'])?.toString();
    final fromList = readList(json, ['branchIds', 'branch_ids']).map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
    return PosUser(
      id: readString(json, ['id']),
      name: readString(json, ['name']),
      email: readString(json, ['email']),
      role: readString(json, ['role']),
      permissions: readList(json, ['permissions']).map((item) => item.toString()).toList(),
      active: json.containsKey('active') ? readBool(json, ['active']) : true,
      primaryBranchId: branchId,
      branchIds: fromList.isEmpty && branchId != null && branchId.isNotEmpty ? [branchId] : fromList,
    );
  }

  @override
  List<Object?> get props => [id, email, role, active, primaryBranchId, branchIds];
}

class BusinessProfile extends Equatable {
  const BusinessProfile({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.currencyCode,
    required this.taxRate,
    this.logoUrl,
    this.address,
    this.phone,
    this.receiptHeader,
    this.receiptFooter,
    this.receiptPaperWidthMm = 80,
    this.receiptShowAddress = true,
    this.receiptShowPhone = true,
    this.status = 'active',
  });

  final String id;
  final String name;
  final String primaryColor;
  final String secondaryColor;
  final String currencyCode;
  final String taxRate;
  final String? logoUrl;
  final String? address;
  final String? phone;
  final String? receiptHeader;
  final String? receiptFooter;
  final int receiptPaperWidthMm;
  final bool receiptShowAddress;
  final bool receiptShowPhone;
  final String status;

  bool get isActive => status == 'active' || status.isEmpty;
  bool get isSuspended => status == 'suspended';

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: readString(json, ['id']),
      name: readString(json, ['name']),
      primaryColor: readString(json, ['primary_color', 'primaryColor'], '#1F6F4A'),
      secondaryColor: readString(json, ['secondary_color', 'secondaryColor'], '#F4EFE6'),
      currencyCode: readString(json, ['currency_code', 'currencyCode'], 'PKR'),
      taxRate: readString(json, ['tax_rate', 'taxRate'], '0'),
      logoUrl: pick(json, ['logo_url', 'logoUrl'])?.toString(),
      address: pick(json, ['address'])?.toString(),
      phone: pick(json, ['phone'])?.toString(),
      receiptHeader: pick(json, ['receipt_header', 'receiptHeader'])?.toString(),
      receiptFooter: pick(json, ['receipt_footer', 'receiptFooter'])?.toString(),
      receiptPaperWidthMm: _paperWidth(json),
      receiptShowAddress: pick(json, ['receipt_show_address', 'receiptShowAddress']) == null
          ? true
          : readBool(json, ['receipt_show_address', 'receiptShowAddress']),
      receiptShowPhone: pick(json, ['receipt_show_phone', 'receiptShowPhone']) == null
          ? true
          : readBool(json, ['receipt_show_phone', 'receiptShowPhone']),
      status: readString(json, ['status'], 'active'),
    );
  }

  static int _paperWidth(Map<String, dynamic> json) {
    final value = readInt(json, ['receipt_paper_width', 'receiptPaperWidthMm', 'receipt_paper_width_mm'], 80);
    return value <= 58 ? 58 : 80;
  }

  @override
  List<Object?> get props => [
        id,
        name,
        status,
        address,
        phone,
        receiptHeader,
        receiptFooter,
        receiptPaperWidthMm,
        receiptShowAddress,
        receiptShowPhone,
      ];
}

class BranchProfile extends Equatable {
  const BranchProfile({
    required this.id,
    required this.name,
    required this.code,
    this.address,
    this.phone,
    this.active = true,
  });

  final String id;
  final String name;
  final String code;
  final String? address;
  final String? phone;
  final bool active;

  factory BranchProfile.fromJson(Map<String, dynamic> json) {
    return BranchProfile(
      id: readString(json, ['id']),
      name: readString(json, ['name']),
      code: readString(json, ['code']),
      address: pick(json, ['address'])?.toString(),
      phone: pick(json, ['phone'])?.toString(),
      active: json.containsKey('active') ? readBool(json, ['active']) : true,
    );
  }

  @override
  List<Object?> get props => [id, code, active];
}

class Session extends Equatable {
  const Session({
    required this.user,
    this.business,
    this.branch,
    this.branches = const [],
  });

  final PosUser user;
  final BusinessProfile? business;
  final BranchProfile? branch;
  final List<BranchProfile> branches;

  List<BranchProfile> get accessibleBranches {
    if (user.isBusinessAdmin || user.isPlatformAdmin) {
      return branches;
    }
    final allowed = user.resolvedBranchIds(fallback: branches.map((item) => item.id).toList());
    return branches.where((item) => allowed.contains(item.id)).toList();
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      user: PosUser.fromJson(asStringKeyMap(json['user'])),
      business: json['business'] == null
          ? null
          : BusinessProfile.fromJson(asStringKeyMap(json['business'])),
      branch: json['branch'] == null
          ? null
          : BranchProfile.fromJson(asStringKeyMap(json['branch'])),
      branches: readList(json, ['branches'])
          .map((item) => BranchProfile.fromJson(asStringKeyMap(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'user': {
          'id': user.id,
          'name': user.name,
          'email': user.email,
          'role': user.role,
          'permissions': user.permissions,
          'active': user.active,
          'branchId': user.primaryBranchId,
          'branchIds': user.branchIds,
        },
        if (business != null)
          'business': {
            'id': business!.id,
            'name': business!.name,
            'primary_color': business!.primaryColor,
            'secondary_color': business!.secondaryColor,
            'currency_code': business!.currencyCode,
            'tax_rate': business!.taxRate,
            'logo_url': business!.logoUrl,
            'address': business!.address,
            'phone': business!.phone,
            'receipt_header': business!.receiptHeader,
            'receipt_footer': business!.receiptFooter,
            'receipt_paper_width': business!.receiptPaperWidthMm,
            'receipt_show_address': business!.receiptShowAddress,
            'receipt_show_phone': business!.receiptShowPhone,
            'status': business!.status,
          },
        if (branch != null)
          'branch': {
            'id': branch!.id,
            'name': branch!.name,
            'code': branch!.code,
            'address': branch!.address,
            'phone': branch!.phone,
            'active': branch!.active,
          },
        'branches': branches
            .map(
              (item) => {
                'id': item.id,
                'name': item.name,
                'code': item.code,
                'address': item.address,
                'phone': item.phone,
                'active': item.active,
              },
            )
            .toList(),
      };

  @override
  List<Object?> get props => [user, business, branch, branches];
}
