-- Multi-tenant POS schema. MySQL 8.0+.
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS businesses (
  id CHAR(36) NOT NULL,
  name VARCHAR(191) NOT NULL,
  slug VARCHAR(64) NOT NULL,
  logo_url VARCHAR(512) NULL,
  primary_color VARCHAR(16) NOT NULL DEFAULT '#1F6F4A',
  secondary_color VARCHAR(16) NOT NULL DEFAULT '#F4EFE6',
  currency_code CHAR(3) NOT NULL DEFAULT 'PKR',
  tax_rate DECIMAL(6, 4) NOT NULL DEFAULT 0.0000,
  address VARCHAR(255) NULL,
  phone VARCHAR(32) NULL,
  receipt_header VARCHAR(255) NULL,
  receipt_footer VARCHAR(255) NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_businesses_slug (slug),
  CONSTRAINT chk_businesses_status CHECK (status IN ('ACTIVE', 'SUSPENDED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS branches (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  name VARCHAR(191) NOT NULL,
  code VARCHAR(32) NOT NULL,
  address VARCHAR(255) NULL,
  phone VARCHAR(32) NULL,
  timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Karachi',
  status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_branches_business_code (business_id, code),
  KEY idx_branches_business (business_id),
  CONSTRAINT fk_branches_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT chk_branches_status CHECK (status IN ('ACTIVE', 'INACTIVE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS roles (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NULL,
  name VARCHAR(64) NOT NULL,
  slug VARCHAR(64) NOT NULL,
  is_system TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_roles_business_slug (business_id, slug),
  KEY idx_roles_business (business_id),
  CONSTRAINT fk_roles_business FOREIGN KEY (business_id) REFERENCES businesses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS permissions (
  id CHAR(36) NOT NULL,
  code VARCHAR(64) NOT NULL,
  name VARCHAR(128) NOT NULL,
  description VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_permissions_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id CHAR(36) NOT NULL,
  permission_id CHAR(36) NOT NULL,
  PRIMARY KEY (role_id, permission_id),
  CONSTRAINT fk_rp_role FOREIGN KEY (role_id) REFERENCES roles (id) ON DELETE CASCADE,
  CONSTRAINT fk_rp_permission FOREIGN KEY (permission_id) REFERENCES permissions (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS users (
  id CHAR(36) NOT NULL,
  firebase_uid VARCHAR(128) NOT NULL,
  business_id CHAR(36) NULL,
  branch_id CHAR(36) NULL,
  role_id CHAR(36) NOT NULL,
  name VARCHAR(191) NOT NULL,
  email VARCHAR(191) NOT NULL,
  phone VARCHAR(32) NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_firebase_uid (firebase_uid),
  UNIQUE KEY uq_users_email (email),
  KEY idx_users_business (business_id),
  KEY idx_users_branch (branch_id),
  KEY idx_users_role (role_id),
  CONSTRAINT fk_users_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_users_branch FOREIGN KEY (branch_id) REFERENCES branches (id),
  CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles (id),
  CONSTRAINT chk_users_status CHECK (status IN ('ACTIVE', 'DISABLED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_roles (
  user_id CHAR(36) NOT NULL,
  role_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NULL,
  PRIMARY KEY (user_id, role_id),
  KEY idx_user_roles_branch (branch_id),
  CONSTRAINT fk_ur_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_ur_role FOREIGN KEY (role_id) REFERENCES roles (id),
  CONSTRAINT fk_ur_branch FOREIGN KEY (branch_id) REFERENCES branches (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS units (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NULL,
  code VARCHAR(16) NOT NULL,
  name VARCHAR(64) NOT NULL,
  dimension VARCHAR(16) NOT NULL,
  conversion_to_base DECIMAL(18, 6) NOT NULL DEFAULT 1.000000,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_units_business_code (business_id, code),
  CONSTRAINT fk_units_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT chk_units_dimension CHECK (dimension IN ('MASS', 'VOLUME', 'COUNT'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS categories (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  name VARCHAR(191) NOT NULL,
  slug VARCHAR(64) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_categories_business_slug (business_id, slug),
  KEY idx_categories_business_sort (business_id, sort_order),
  CONSTRAINT fk_categories_business FOREIGN KEY (business_id) REFERENCES businesses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS products (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  category_id CHAR(36) NOT NULL,
  name VARCHAR(191) NOT NULL,
  sku VARCHAR(64) NULL,
  description VARCHAR(512) NULL,
  product_type VARCHAR(24) NOT NULL DEFAULT 'SIMPLE',
  tracks_inventory TINYINT(1) NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_products_business_sku (business_id, sku),
  KEY idx_products_business_category (business_id, category_id, is_active),
  CONSTRAINT fk_products_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories (id),
  CONSTRAINT chk_products_type CHECK (product_type IN ('SIMPLE', 'RECIPE', 'BUNDLE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS product_variants (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  product_id CHAR(36) NOT NULL,
  name VARCHAR(128) NOT NULL,
  sku VARCHAR(64) NULL,
  price DECIMAL(12, 2) NOT NULL,
  cost DECIMAL(12, 2) NULL,
  is_default TINYINT(1) NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_variants_product (product_id),
  KEY idx_variants_business (business_id),
  CONSTRAINT fk_variants_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_variants_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS product_options (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  product_id CHAR(36) NOT NULL,
  name VARCHAR(128) NOT NULL,
  extra_price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  KEY idx_options_product (product_id),
  CONSTRAINT fk_options_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_options_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS ingredients (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  name VARCHAR(191) NOT NULL,
  sku VARCHAR(64) NULL,
  unit_id CHAR(36) NOT NULL,
  track_inventory TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_ingredients_business_sku (business_id, sku),
  KEY idx_ingredients_business (business_id),
  CONSTRAINT fk_ingredients_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_ingredients_unit FOREIGN KEY (unit_id) REFERENCES units (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS recipes (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  product_id CHAR(36) NOT NULL,
  variant_id CHAR(36) NULL,
  name VARCHAR(191) NOT NULL,
  yield_qty DECIMAL(12, 4) NOT NULL DEFAULT 1.0000,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_recipes_product (business_id, product_id, variant_id),
  CONSTRAINT fk_recipes_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_recipes_product FOREIGN KEY (product_id) REFERENCES products (id),
  CONSTRAINT fk_recipes_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS recipe_items (
  id CHAR(36) NOT NULL,
  recipe_id CHAR(36) NOT NULL,
  ingredient_id CHAR(36) NOT NULL,
  quantity_base DECIMAL(18, 4) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_recipe_items (recipe_id, ingredient_id),
  CONSTRAINT fk_recipe_items_recipe FOREIGN KEY (recipe_id) REFERENCES recipes (id) ON DELETE CASCADE,
  CONSTRAINT fk_recipe_items_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS inventory (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NOT NULL,
  ingredient_id CHAR(36) NOT NULL,
  quantity_base DECIMAL(18, 4) NOT NULL DEFAULT 0.0000,
  reorder_level DECIMAL(18, 4) NOT NULL DEFAULT 0.0000,
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_inventory_branch_ingredient (branch_id, ingredient_id),
  KEY idx_inventory_business_branch (business_id, branch_id),
  CONSTRAINT fk_inventory_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_inventory_branch FOREIGN KEY (branch_id) REFERENCES branches (id),
  CONSTRAINT fk_inventory_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS inventory_transactions (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NOT NULL,
  ingredient_id CHAR(36) NOT NULL,
  transaction_type VARCHAR(32) NOT NULL,
  quantity_base DECIMAL(18, 4) NOT NULL,
  previous_qty DECIMAL(18, 4) NOT NULL,
  new_qty DECIMAL(18, 4) NOT NULL,
  reference_type VARCHAR(32) NULL,
  reference_id CHAR(36) NULL,
  user_id CHAR(36) NULL,
  notes VARCHAR(255) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_inv_tx_branch_created (branch_id, created_at),
  KEY idx_inv_tx_ingredient (ingredient_id, created_at),
  KEY idx_inv_tx_reference (reference_type, reference_id),
  CONSTRAINT fk_inv_tx_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_inv_tx_branch FOREIGN KEY (branch_id) REFERENCES branches (id),
  CONSTRAINT fk_inv_tx_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients (id),
  CONSTRAINT fk_inv_tx_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT chk_inv_tx_type CHECK (
    transaction_type IN (
      'PURCHASE', 'SALE', 'SALE_REVERSAL', 'TRANSFER_IN', 'TRANSFER_OUT',
      'ADJUSTMENT_IN', 'ADJUSTMENT_OUT', 'WASTE', 'RETURN'
    )
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS stock_adjustments (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  reason VARCHAR(255) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_adjustments_branch (business_id, branch_id),
  CONSTRAINT fk_adj_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_adj_branch FOREIGN KEY (branch_id) REFERENCES branches (id),
  CONSTRAINT fk_adj_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS stock_adjustment_items (
  id CHAR(36) NOT NULL,
  adjustment_id CHAR(36) NOT NULL,
  ingredient_id CHAR(36) NOT NULL,
  quantity_base DECIMAL(18, 4) NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_adj_items_adj FOREIGN KEY (adjustment_id) REFERENCES stock_adjustments (id) ON DELETE CASCADE,
  CONSTRAINT fk_adj_items_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS stock_transfers (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  from_branch_id CHAR(36) NOT NULL,
  to_branch_id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'COMPLETED',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_transfers_business (business_id, created_at),
  CONSTRAINT fk_tr_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_tr_from FOREIGN KEY (from_branch_id) REFERENCES branches (id),
  CONSTRAINT fk_tr_to FOREIGN KEY (to_branch_id) REFERENCES branches (id),
  CONSTRAINT fk_tr_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT chk_transfers_status CHECK (status IN ('DRAFT', 'COMPLETED', 'CANCELLED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id CHAR(36) NOT NULL,
  transfer_id CHAR(36) NOT NULL,
  ingredient_id CHAR(36) NOT NULL,
  quantity_base DECIMAL(18, 4) NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_tr_items_transfer FOREIGN KEY (transfer_id) REFERENCES stock_transfers (id) ON DELETE CASCADE,
  CONSTRAINT fk_tr_items_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS suppliers (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  name VARCHAR(191) NOT NULL,
  phone VARCHAR(32) NULL,
  email VARCHAR(191) NULL,
  address VARCHAR(255) NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_suppliers_business (business_id),
  CONSTRAINT fk_suppliers_business FOREIGN KEY (business_id) REFERENCES businesses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS purchases (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NOT NULL,
  supplier_id CHAR(36) NULL,
  user_id CHAR(36) NOT NULL,
  invoice_no VARCHAR(64) NULL,
  total DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  purchased_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_purchases_branch (business_id, branch_id, purchased_at),
  CONSTRAINT fk_purchases_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_purchases_branch FOREIGN KEY (branch_id) REFERENCES branches (id),
  CONSTRAINT fk_purchases_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers (id),
  CONSTRAINT fk_purchases_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS purchase_items (
  id CHAR(36) NOT NULL,
  purchase_id CHAR(36) NOT NULL,
  ingredient_id CHAR(36) NOT NULL,
  quantity_base DECIMAL(18, 4) NOT NULL,
  unit_cost DECIMAL(12, 2) NOT NULL,
  line_total DECIMAL(12, 2) NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_purchase_items_purchase FOREIGN KEY (purchase_id) REFERENCES purchases (id) ON DELETE CASCADE,
  CONSTRAINT fk_purchase_items_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS discounts (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  name VARCHAR(128) NOT NULL,
  discount_type VARCHAR(16) NOT NULL,
  value DECIMAL(12, 2) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_discounts_business (business_id),
  CONSTRAINT fk_discounts_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT chk_discounts_type CHECK (discount_type IN ('PERCENT', 'FIXED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS orders (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NOT NULL,
  cashier_id CHAR(36) NOT NULL,
  order_number VARCHAR(48) NOT NULL,
  idempotency_key CHAR(36) NOT NULL,
  status VARCHAR(32) NOT NULL,
  subtotal DECIMAL(12, 2) NOT NULL,
  discount_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  tax_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  total DECIMAL(12, 2) NOT NULL,
  notes VARCHAR(255) NULL,
  sync_status VARCHAR(24) NOT NULL DEFAULT 'SYNCED',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_orders_idempotency (business_id, idempotency_key),
  UNIQUE KEY uq_orders_number (business_id, branch_id, order_number),
  KEY idx_orders_branch_created (business_id, branch_id, created_at),
  KEY idx_orders_cashier (cashier_id, created_at),
  KEY idx_orders_status (status, created_at),
  CONSTRAINT fk_orders_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_orders_branch FOREIGN KEY (branch_id) REFERENCES branches (id),
  CONSTRAINT fk_orders_cashier FOREIGN KEY (cashier_id) REFERENCES users (id),
  CONSTRAINT chk_orders_status CHECK (
    status IN ('DRAFT', 'HELD', 'COMPLETED', 'CANCELLED', 'REFUNDED', 'PARTIALLY_REFUNDED')
  ),
  CONSTRAINT chk_orders_sync CHECK (
    sync_status IN ('PENDING_SYNC', 'SYNCING', 'SYNCED', 'SYNC_FAILED')
  )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS order_items (
  id CHAR(36) NOT NULL,
  order_id CHAR(36) NOT NULL,
  product_id CHAR(36) NOT NULL,
  variant_id CHAR(36) NULL,
  name_snapshot VARCHAR(191) NOT NULL,
  quantity DECIMAL(12, 3) NOT NULL,
  unit_price DECIMAL(12, 2) NOT NULL,
  discount_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  line_total DECIMAL(12, 2) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_order_items_order (order_id),
  KEY idx_order_items_product (product_id),
  CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES products (id),
  CONSTRAINT fk_order_items_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS order_item_options (
  id CHAR(36) NOT NULL,
  order_item_id CHAR(36) NOT NULL,
  option_id CHAR(36) NULL,
  name_snapshot VARCHAR(128) NOT NULL,
  extra_price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
  PRIMARY KEY (id),
  KEY idx_oio_item (order_item_id),
  CONSTRAINT fk_oio_item FOREIGN KEY (order_item_id) REFERENCES order_items (id) ON DELETE CASCADE,
  CONSTRAINT fk_oio_option FOREIGN KEY (option_id) REFERENCES product_options (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS payments (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  order_id CHAR(36) NOT NULL,
  cashier_id CHAR(36) NOT NULL,
  method VARCHAR(32) NOT NULL,
  amount DECIMAL(12, 2) NOT NULL,
  reference_no VARCHAR(64) NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'COMPLETED',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_payments_order (order_id),
  KEY idx_payments_business_created (business_id, created_at),
  CONSTRAINT fk_payments_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_payments_cashier FOREIGN KEY (cashier_id) REFERENCES users (id),
  CONSTRAINT chk_payments_method CHECK (
    method IN ('CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER')
  ),
  CONSTRAINT chk_payments_status CHECK (status IN ('COMPLETED', 'FAILED', 'REFUNDED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS printers (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NOT NULL,
  name VARCHAR(128) NOT NULL,
  printer_type VARCHAR(32) NOT NULL DEFAULT 'ESC_POS',
  paper_width_mm SMALLINT NOT NULL DEFAULT 80,
  connection_type VARCHAR(24) NOT NULL DEFAULT 'NETWORK',
  connection_target VARCHAR(191) NULL,
  is_default TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_printers_branch (business_id, branch_id),
  CONSTRAINT fk_printers_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_printers_branch FOREIGN KEY (branch_id) REFERENCES branches (id),
  CONSTRAINT chk_printers_width CHECK (paper_width_mm IN (58, 80))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS settings (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NOT NULL,
  branch_id CHAR(36) NULL,
  setting_key VARCHAR(64) NOT NULL,
  setting_value JSON NOT NULL,
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_settings_scope (business_id, branch_id, setting_key),
  CONSTRAINT fk_settings_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_settings_branch FOREIGN KEY (branch_id) REFERENCES branches (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS audit_logs (
  id CHAR(36) NOT NULL,
  business_id CHAR(36) NULL,
  user_id CHAR(36) NULL,
  action VARCHAR(64) NOT NULL,
  entity_type VARCHAR(64) NOT NULL,
  entity_id CHAR(36) NULL,
  metadata JSON NULL,
  ip_address VARCHAR(64) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_audit_business_created (business_id, created_at),
  KEY idx_audit_entity (entity_type, entity_id),
  CONSTRAINT fk_audit_business FOREIGN KEY (business_id) REFERENCES businesses (id),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
