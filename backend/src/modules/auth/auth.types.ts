export interface AuthContext {
  firebaseUid: string;
  userId: string;
  businessId: string | null;
  branchId: string | null;
  roleId: string;
  roleSlug: string;
  permissions: string[];
  name: string;
  email: string;
}

export const PERMISSIONS = {
  PLATFORM_MANAGE: 'platform.manage',
  BUSINESS_MANAGE: 'business.manage',
  BRANCH_MANAGE: 'branch.manage',
  USERS_MANAGE: 'users.manage',
  CATALOG_READ: 'catalog.read',
  CATALOG_WRITE: 'catalog.write',
  INVENTORY_READ: 'inventory.read',
  INVENTORY_ADJUST: 'inventory.adjust',
  RECIPES_WRITE: 'recipes.write',
  ORDERS_CREATE: 'orders.create',
  ORDERS_READ: 'orders.read',
  ORDERS_REFUND: 'orders.refund',
  PAYMENTS_CREATE: 'payments.create',
  REPORTS_VIEW: 'reports.view',
  SETTINGS_MANAGE: 'settings.manage',
  SYNC_APPLY: 'sync.apply',
} as const;

export type PermissionCode = (typeof PERMISSIONS)[keyof typeof PERMISSIONS];

export const ROLE_SLUGS = {
  PLATFORM_SUPER_ADMIN: 'platform_super_admin',
  BUSINESS_ADMIN: 'business_admin',
  BRANCH_MANAGER: 'branch_manager',
  CASHIER: 'cashier',
} as const;
