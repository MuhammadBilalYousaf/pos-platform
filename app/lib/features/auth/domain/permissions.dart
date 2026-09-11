class PosRole {
  static const platformSuperAdmin = 'platform_super_admin';
  static const businessAdmin = 'business_admin';
  static const branchManager = 'branch_manager';
  static const cashier = 'cashier';

  static const staffRoles = [businessAdmin, branchManager, cashier];

  static String label(String role) {
    switch (role) {
      case platformSuperAdmin:
        return 'Super Admin';
      case businessAdmin:
        return 'Business Admin';
      case branchManager:
        return 'Manager';
      case cashier:
        return 'Employee';
      default:
        return role;
    }
  }

  static List<String> permissionsFor(String role) {
    switch (role) {
      case platformSuperAdmin:
        return PosPermissions.platformOwner;
      case businessAdmin:
        return PosPermissions.admin;
      case branchManager:
        return PosPermissions.manager;
      case cashier:
        return PosPermissions.cashier;
      default:
        return const [];
    }
  }

  static List<String> invitableBy(String actorRole) {
    switch (actorRole) {
      case platformSuperAdmin:
        return const [businessAdmin];
      case businessAdmin:
        return const [businessAdmin, branchManager, cashier];
      case branchManager:
        return const [cashier];
      default:
        return const [];
    }
  }
}

class PosPermissions {
  static const platformManage = 'platform.manage';
  static const businessCreate = 'business.create';
  static const businessEdit = 'business.edit';
  static const businessSuspend = 'business.suspend';
  static const businessManage = 'business.manage';
  static const branchCreate = 'branch.create';
  static const branchEdit = 'branch.edit';
  static const branchDeactivate = 'branch.deactivate';
  static const branchManage = 'branch.manage';
  static const staffCreate = 'staff.create';
  static const staffEdit = 'staff.edit';
  static const staffDeactivate = 'staff.deactivate';
  static const staffAssignBranch = 'staff.assign_branch';
  static const usersManage = 'users.manage';
  static const catalogRead = 'catalog.read';
  static const catalogWrite = 'catalog.write';
  static const productCreate = 'product.create';
  static const productEdit = 'product.edit';
  static const productDelete = 'product.delete';
  static const productPriceEdit = 'product.price_edit';
  static const inventoryRead = 'inventory.read';
  static const inventoryView = 'inventory.view';
  static const inventoryAdjust = 'inventory.adjust';
  static const inventoryTransfer = 'inventory.transfer';
  static const inventoryWaste = 'inventory.waste';
  static const recipesWrite = 'recipes.write';
  static const ordersCreate = 'orders.create';
  static const ordersRead = 'orders.read';
  static const orderView = 'order.view';
  static const orderCreate = 'order.create';
  static const orderCancel = 'order.cancel';
  static const orderRefund = 'order.refund';
  static const ordersRefund = 'orders.refund';
  static const paymentsCreate = 'payments.create';
  static const reportsView = 'reports.view';
  static const reportView = 'report.view';
  static const reportExport = 'report.export';
  static const settingsManage = 'settings.manage';
  static const settingsEdit = 'settings.edit';
  static const printerConfigure = 'printer.configure';
  static const auditView = 'audit.view';
  static const syncApply = 'sync.apply';

  static const platformOwner = <String>[
    platformManage,
    businessCreate,
    businessEdit,
    businessSuspend,
    businessManage,
    auditView,
  ];

  static const admin = <String>[
    businessManage,
    businessEdit,
    branchCreate,
    branchEdit,
    branchDeactivate,
    branchManage,
    staffCreate,
    staffEdit,
    staffDeactivate,
    staffAssignBranch,
    usersManage,
    catalogRead,
    catalogWrite,
    productCreate,
    productEdit,
    productDelete,
    productPriceEdit,
    inventoryRead,
    inventoryView,
    inventoryAdjust,
    inventoryTransfer,
    inventoryWaste,
    recipesWrite,
    ordersCreate,
    ordersRead,
    orderView,
    orderCreate,
    orderCancel,
    orderRefund,
    ordersRefund,
    paymentsCreate,
    reportsView,
    reportView,
    reportExport,
    settingsManage,
    settingsEdit,
    printerConfigure,
    auditView,
    syncApply,
  ];

  static const manager = <String>[
    staffCreate,
    staffEdit,
    usersManage,
    catalogRead,
    inventoryRead,
    inventoryView,
    inventoryAdjust,
    inventoryWaste,
    recipesWrite,
    ordersCreate,
    ordersRead,
    orderView,
    orderCreate,
    orderCancel,
    ordersRefund,
    orderRefund,
    paymentsCreate,
    reportsView,
    reportView,
    syncApply,
  ];

  static const cashier = <String>[
    catalogRead,
    ordersCreate,
    ordersRead,
    orderView,
    orderCreate,
    paymentsCreate,
    syncApply,
  ];
}
