import { env } from '../config/env';
import { logger } from '../config/logger';
import { execute, query, closePool } from './pool';
import { newId } from '../utils/ids';
import { PERMISSIONS, ROLE_SLUGS } from '../modules/auth/auth.types';

const ALL_PERMISSIONS: Array<{ code: string; name: string }> = [
  { code: PERMISSIONS.PLATFORM_MANAGE, name: 'Manage platform' },
  { code: PERMISSIONS.BUSINESS_MANAGE, name: 'Manage business' },
  { code: PERMISSIONS.BRANCH_MANAGE, name: 'Manage branches' },
  { code: PERMISSIONS.USERS_MANAGE, name: 'Manage users' },
  { code: PERMISSIONS.CATALOG_READ, name: 'Read catalog' },
  { code: PERMISSIONS.CATALOG_WRITE, name: 'Write catalog' },
  { code: PERMISSIONS.INVENTORY_READ, name: 'Read inventory' },
  { code: PERMISSIONS.INVENTORY_ADJUST, name: 'Adjust inventory' },
  { code: PERMISSIONS.RECIPES_WRITE, name: 'Manage recipes' },
  { code: PERMISSIONS.ORDERS_CREATE, name: 'Create orders' },
  { code: PERMISSIONS.ORDERS_READ, name: 'Read orders' },
  { code: PERMISSIONS.ORDERS_REFUND, name: 'Refund or cancel orders' },
  { code: PERMISSIONS.PAYMENTS_CREATE, name: 'Take payments' },
  { code: PERMISSIONS.REPORTS_VIEW, name: 'View reports' },
  { code: PERMISSIONS.SETTINGS_MANAGE, name: 'Manage settings' },
  { code: PERMISSIONS.SYNC_APPLY, name: 'Sync offline orders' },
];

async function idOrCreate(table: string, whereSql: string, params: unknown[], insert: () => Promise<string>): Promise<string> {
  const rows = await query<{ id: string }>(`SELECT id FROM ${table} WHERE ${whereSql} LIMIT 1`, params);
  if (rows[0]) {
    return rows[0].id;
  }
  return insert();
}

async function ensurePermission(code: string, name: string): Promise<string> {
  return idOrCreate('permissions', 'code = ?', [code], async () => {
    const id = newId();
    await execute('INSERT INTO permissions (id, code, name) VALUES (?, ?, ?)', [id, code, name]);
    return id;
  });
}

async function ensureRole(slug: string, name: string): Promise<string> {
  return idOrCreate('roles', 'slug = ? AND business_id IS NULL', [slug], async () => {
    const id = newId();
    await execute(
      'INSERT INTO roles (id, business_id, name, slug, is_system) VALUES (?, NULL, ?, ?, 1)',
      [id, name, slug],
    );
    return id;
  });
}

async function grant(roleId: string, permissionIds: string[]): Promise<void> {
  for (const permissionId of permissionIds) {
    await execute('INSERT IGNORE INTO role_permissions (role_id, permission_id) VALUES (?, ?)', [roleId, permissionId]);
  }
}

async function ensureUnit(code: string, name: string, dimension: string, conversion: string): Promise<string> {
  return idOrCreate('units', 'code = ? AND business_id IS NULL', [code], async () => {
    const id = newId();
    await execute(
      'INSERT INTO units (id, business_id, code, name, dimension, conversion_to_base) VALUES (?, NULL, ?, ?, ?, ?)',
      [id, code, name, dimension, conversion],
    );
    return id;
  });
}

interface SeedProduct {
  category: string;
  name: string;
  sku: string;
  type: 'SIMPLE' | 'RECIPE';
  price: string;
}

const CATEGORIES = [
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

const PRODUCTS: SeedProduct[] = [
  { category: 'Turkish Ice Cream', name: 'Vanilla Turkish Ice Cream', sku: 'TIC-VAN', type: 'SIMPLE', price: '350.00' },
  { category: 'Turkish Ice Cream', name: 'Chocolate Turkish Ice Cream', sku: 'TIC-CHO', type: 'SIMPLE', price: '350.00' },
  { category: 'Turkish Ice Cream', name: 'Pistachio Turkish Ice Cream', sku: 'TIC-PIS', type: 'SIMPLE', price: '450.00' },
  { category: 'Turkish Ice Cream', name: 'Mango Turkish Ice Cream', sku: 'TIC-MAN', type: 'SIMPLE', price: '400.00' },
  { category: 'Turkish Ice Cream', name: 'Strawberry Turkish Ice Cream', sku: 'TIC-STR', type: 'SIMPLE', price: '400.00' },
  { category: 'Soft Ice Cream', name: 'Vanilla Soft Serve', sku: 'SIC-VAN', type: 'SIMPLE', price: '250.00' },
  { category: 'Soft Ice Cream', name: 'Chocolate Soft Serve', sku: 'SIC-CHO', type: 'SIMPLE', price: '250.00' },
  { category: 'Soft Ice Cream', name: 'Twist Soft Serve', sku: 'SIC-TWI', type: 'SIMPLE', price: '280.00' },
  { category: 'Sundae', name: 'Chocolate Sundae', sku: 'SUN-CHO', type: 'SIMPLE', price: '450.00' },
  { category: 'Sundae', name: 'Caramel Sundae', sku: 'SUN-CAR', type: 'SIMPLE', price: '450.00' },
  { category: 'Sundae', name: 'Strawberry Sundae', sku: 'SUN-STR', type: 'SIMPLE', price: '450.00' },
  { category: 'Fresh Mint', name: 'Fresh Mint Cooler', sku: 'MNT-CLR', type: 'RECIPE', price: '280.00' },
  { category: 'Lemonade', name: 'Classic Lemonade', sku: 'LMN-CLS', type: 'RECIPE', price: '250.00' },
  { category: 'Lemonade', name: 'Mint Lemonade', sku: 'LMN-MNT', type: 'RECIPE', price: '280.00' },
  { category: 'Water', name: 'Mineral Water', sku: 'WTR-MIN', type: 'RECIPE', price: '80.00' },
  { category: 'Kids Cup', name: 'Kids Vanilla Cup', sku: 'KID-VAN', type: 'SIMPLE', price: '200.00' },
  { category: 'Kids Cup', name: 'Kids Chocolate Cup', sku: 'KID-CHO', type: 'SIMPLE', price: '200.00' },
  { category: 'Boba Cup', name: 'Brown Sugar Boba', sku: 'BOB-BRN', type: 'RECIPE', price: '550.00' },
  { category: 'Boba Cup', name: 'Taro Boba', sku: 'BOB-TAR', type: 'RECIPE', price: '550.00' },
  { category: 'Cold Coffee', name: 'Iced Latte', sku: 'COF-LAT', type: 'RECIPE', price: '450.00' },
  { category: 'Cold Coffee', name: 'Classic Cold Coffee', sku: 'COF-CLS', type: 'RECIPE', price: '420.00' },
  { category: 'Cold Coffee', name: 'Mocha Cold Coffee', sku: 'COF-MOC', type: 'RECIPE', price: '480.00' },
  { category: 'Shake', name: 'Mango Shake', sku: 'SHK-MAN', type: 'RECIPE', price: '450.00' },
  { category: 'Shake', name: 'Chocolate Shake', sku: 'SHK-CHO', type: 'RECIPE', price: '450.00' },
  { category: 'Shake', name: 'Strawberry Shake', sku: 'SHK-STR', type: 'RECIPE', price: '450.00' },
  { category: 'Shake', name: 'Oreo Shake', sku: 'SHK-ORE', type: 'RECIPE', price: '480.00' },
  { category: 'Shake', name: 'Vanilla Shake', sku: 'SHK-VAN', type: 'RECIPE', price: '420.00' },
  { category: 'Brownie', name: 'Chocolate Brownie', sku: 'BRW-CHO', type: 'SIMPLE', price: '300.00' },
  { category: 'Brownie', name: 'Walnut Brownie', sku: 'BRW-WAL', type: 'SIMPLE', price: '350.00' },
  { category: 'Molten Lawa', name: 'Molten Lava Cake', sku: 'MLT-LAV', type: 'SIMPLE', price: '400.00' },
];

export async function seed(): Promise<void> {
  const permissionIds = new Map<string, string>();
  for (const permission of ALL_PERMISSIONS) {
    permissionIds.set(permission.code, await ensurePermission(permission.code, permission.name));
  }
  const ids = [...permissionIds.values()];
  const exceptPlatform = ids.filter((id) => id !== permissionIds.get(PERMISSIONS.PLATFORM_MANAGE));

  const superAdminRole = await ensureRole(ROLE_SLUGS.PLATFORM_SUPER_ADMIN, 'Platform Super Admin');
  const businessAdminRole = await ensureRole(ROLE_SLUGS.BUSINESS_ADMIN, 'Business Admin');
  const branchManagerRole = await ensureRole(ROLE_SLUGS.BRANCH_MANAGER, 'Branch Manager');
  const cashierRole = await ensureRole(ROLE_SLUGS.CASHIER, 'Employee / Cashier');

  await grant(superAdminRole, ids);
  await grant(businessAdminRole, exceptPlatform);
  await grant(branchManagerRole, [
    PERMISSIONS.CATALOG_READ,
    PERMISSIONS.INVENTORY_READ,
    PERMISSIONS.INVENTORY_ADJUST,
    PERMISSIONS.ORDERS_CREATE,
    PERMISSIONS.ORDERS_READ,
    PERMISSIONS.ORDERS_REFUND,
    PERMISSIONS.PAYMENTS_CREATE,
    PERMISSIONS.REPORTS_VIEW,
    PERMISSIONS.USERS_MANAGE,
    PERMISSIONS.SYNC_APPLY,
  ].map((code) => permissionIds.get(code)!));
  await grant(cashierRole, [
    PERMISSIONS.CATALOG_READ,
    PERMISSIONS.ORDERS_CREATE,
    PERMISSIONS.ORDERS_READ,
    PERMISSIONS.PAYMENTS_CREATE,
    PERMISSIONS.SYNC_APPLY,
  ].map((code) => permissionIds.get(code)!));

  const unitG = await ensureUnit('G', 'Gram', 'MASS', '1');
  const unitKg = await ensureUnit('KG', 'Kilogram', 'MASS', '1000');
  const unitMl = await ensureUnit('ML', 'Milliliter', 'VOLUME', '1');
  const unitL = await ensureUnit('L', 'Liter', 'VOLUME', '1000');
  const unitPcs = await ensureUnit('PCS', 'Piece', 'COUNT', '1');
  await ensureUnit('DOZEN', 'Dozen', 'COUNT', '12');
  await ensureUnit('BOX', 'Box', 'COUNT', '1');
  await ensureUnit('PACK', 'Pack', 'COUNT', '1');
  void unitKg;
  void unitL;

  const businessId = await idOrCreate('businesses', 'slug = ?', ['turknroll'], async () => {
    const id = newId();
    await execute(
      `INSERT INTO businesses
        (id, name, slug, primary_color, secondary_color, currency_code, tax_rate, address, phone, receipt_header, receipt_footer)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        id,
        'TurknRoll',
        'turknroll',
        '#C62828',
        '#FFF8E7',
        'PKR',
        '0.0000',
        'TurknRoll Flagship',
        '0300-0000000',
        'TurknRoll',
        'Thank you for visiting. Ice cream made to roll.',
      ],
    );
    return id;
  });

  const branchId = await idOrCreate('branches', 'business_id = ? AND code = ?', [businessId, 'MAIN'], async () => {
    const id = newId();
    await execute(
      `INSERT INTO branches (id, business_id, name, code, address, phone, timezone)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, businessId, 'Main Branch', 'MAIN', 'TurknRoll Flagship', '0300-0000000', 'Asia/Karachi'],
    );
    return id;
  });

  const adminUid = env.SEED_ADMIN_FIREBASE_UID || 'seed-admin-turknroll';
  const cashierUid = env.SEED_CASHIER_FIREBASE_UID || 'seed-cashier-turknroll';

  await idOrCreate('users', 'email = ?', ['admin@turknroll.local'], async () => {
    const id = newId();
    await execute(
      `INSERT INTO users (id, firebase_uid, business_id, branch_id, role_id, name, email)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, adminUid, businessId, branchId, businessAdminRole, 'TurknRoll Admin', 'admin@turknroll.local'],
    );
    return id;
  });

  await idOrCreate('users', 'email = ?', ['cashier@turknroll.local'], async () => {
    const id = newId();
    await execute(
      `INSERT INTO users (id, firebase_uid, business_id, branch_id, role_id, name, email)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, cashierUid, businessId, branchId, cashierRole, 'Front Counter', 'cashier@turknroll.local'],
    );
    return id;
  });

  const categoryIds = new Map<string, string>();
  for (const [index, name] of CATEGORIES.entries()) {
    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    const id = await idOrCreate('categories', 'business_id = ? AND slug = ?', [businessId, slug], async () => {
      const created = newId();
      await execute(
        `INSERT INTO categories (id, business_id, name, slug, sort_order) VALUES (?, ?, ?, ?, ?)`,
        [created, businessId, name, slug, index],
      );
      return created;
    });
    categoryIds.set(name, id);
  }

  const productIds = new Map<string, string>();
  for (const product of PRODUCTS) {
    const id = await idOrCreate('products', 'business_id = ? AND sku = ?', [businessId, product.sku], async () => {
      const created = newId();
      await execute(
        `INSERT INTO products (id, business_id, category_id, name, sku, product_type, tracks_inventory)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [created, businessId, categoryIds.get(product.category), product.name, product.sku, product.type, product.type === 'RECIPE' ? 1 : 0],
      );
      await execute(
        `INSERT INTO product_variants (id, business_id, product_id, name, sku, price, is_default)
         VALUES (?, ?, ?, ?, ?, ?, 1)`,
        [newId(), businessId, created, 'Regular', `${product.sku}-REG`, product.price],
      );
      return created;
    });
    productIds.set(product.sku, id);
  }

  async function ensureIngredient(name: string, sku: string, unitId: string): Promise<string> {
    return idOrCreate('ingredients', 'business_id = ? AND sku = ?', [businessId, sku], async () => {
      const id = newId();
      await execute(
        'INSERT INTO ingredients (id, business_id, name, sku, unit_id) VALUES (?, ?, ?, ?, ?)',
        [id, businessId, name, sku, unitId],
      );
      return id;
    });
  }

  const milk = await ensureIngredient('Milk', 'ING-MILK', unitMl);
  const mango = await ensureIngredient('Mango', 'ING-MANGO', unitG);
  const iceCream = await ensureIngredient('Ice Cream Base', 'ING-ICECREAM', unitG);
  const sugar = await ensureIngredient('Sugar', 'ING-SUGAR', unitG);
  const cup = await ensureIngredient('Cup', 'ING-CUP', unitPcs);
  const straw = await ensureIngredient('Straw', 'ING-STRAW', unitPcs);
  const waterBottle = await ensureIngredient('Water Bottle', 'ING-WATER', unitPcs);
  const mint = await ensureIngredient('Fresh Mint', 'ING-MINT', unitG);
  const lemon = await ensureIngredient('Lemon', 'ING-LEMON', unitG);
  const coffee = await ensureIngredient('Coffee', 'ING-COFFEE', unitG);
  const boba = await ensureIngredient('Boba Pearls', 'ING-BOBA', unitG);

  const opening: Array<[string, string, string]> = [
    [milk, '20000', '2000'],
    [mango, '8000', '500'],
    [iceCream, '15000', '1000'],
    [sugar, '10000', '500'],
    [cup, '500', '50'],
    [straw, '500', '50'],
    [waterBottle, '200', '20'],
    [mint, '2000', '200'],
    [lemon, '5000', '400'],
    [coffee, '3000', '300'],
    [boba, '4000', '400'],
  ];
  for (const [ingredientId, qty, reorder] of opening) {
    await idOrCreate('inventory', 'branch_id = ? AND ingredient_id = ?', [branchId, ingredientId], async () => {
      const id = newId();
      await execute(
        `INSERT INTO inventory (id, business_id, branch_id, ingredient_id, quantity_base, reorder_level)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [id, businessId, branchId, ingredientId, qty, reorder],
      );
      return id;
    });
  }

  const mangoShakeId = productIds.get('SHK-MAN');
  if (mangoShakeId) {
    const recipeId = await idOrCreate('recipes', 'business_id = ? AND product_id = ? AND variant_id IS NULL', [businessId, mangoShakeId], async () => {
      const id = newId();
      await execute(
        `INSERT INTO recipes (id, business_id, product_id, variant_id, name, yield_qty)
         VALUES (?, ?, ?, NULL, ?, 1)`,
        [id, businessId, mangoShakeId, 'Mango Shake'],
      );
      const items: Array<[string, string]> = [
        [milk, '250.0000'],
        [mango, '80.0000'],
        [iceCream, '100.0000'],
        [sugar, '20.0000'],
        [cup, '1.0000'],
        [straw, '1.0000'],
      ];
      for (const [ingredientId, qty] of items) {
        await execute(
          'INSERT INTO recipe_items (id, recipe_id, ingredient_id, quantity_base) VALUES (?, ?, ?, ?)',
          [newId(), id, ingredientId, qty],
        );
      }
      return id;
    });
    void recipeId;
  }

  const waterId = productIds.get('WTR-MIN');
  if (waterId) {
    await idOrCreate('recipes', 'business_id = ? AND product_id = ? AND variant_id IS NULL', [businessId, waterId], async () => {
      const id = newId();
      await execute(
        `INSERT INTO recipes (id, business_id, product_id, variant_id, name, yield_qty)
         VALUES (?, ?, ?, NULL, ?, 1)`,
        [id, businessId, waterId, 'Mineral Water'],
      );
      await execute(
        'INSERT INTO recipe_items (id, recipe_id, ingredient_id, quantity_base) VALUES (?, ?, ?, ?)',
        [newId(), id, waterBottle, '1.0000'],
      );
      return id;
    });
  }

  async function ensureSimpleRecipe(sku: string, name: string, items: Array<[string, string]>): Promise<void> {
    const productId = productIds.get(sku);
    if (!productId) {
      return;
    }
    await idOrCreate('recipes', 'business_id = ? AND product_id = ? AND variant_id IS NULL', [businessId, productId], async () => {
      const id = newId();
      await execute(
        `INSERT INTO recipes (id, business_id, product_id, variant_id, name, yield_qty)
         VALUES (?, ?, ?, NULL, ?, 1)`,
        [id, businessId, productId, name],
      );
      for (const [ingredientId, qty] of items) {
        await execute(
          'INSERT INTO recipe_items (id, recipe_id, ingredient_id, quantity_base) VALUES (?, ?, ?, ?)',
          [newId(), id, ingredientId, qty],
        );
      }
      return id;
    });
  }

  await ensureSimpleRecipe('LMN-CLS', 'Classic Lemonade', [
    [lemon, '40.0000'],
    [sugar, '20.0000'],
    [cup, '1.0000'],
  ]);
  await ensureSimpleRecipe('LMN-MNT', 'Mint Lemonade', [
    [lemon, '40.0000'],
    [mint, '10.0000'],
    [sugar, '20.0000'],
    [cup, '1.0000'],
  ]);
  await ensureSimpleRecipe('MNT-CLR', 'Fresh Mint Cooler', [
    [mint, '15.0000'],
    [sugar, '15.0000'],
    [cup, '1.0000'],
  ]);
  await ensureSimpleRecipe('COF-LAT', 'Iced Latte', [
    [coffee, '18.0000'],
    [milk, '200.0000'],
    [cup, '1.0000'],
  ]);
  await ensureSimpleRecipe('COF-CLS', 'Classic Cold Coffee', [
    [coffee, '18.0000'],
    [milk, '180.0000'],
    [sugar, '15.0000'],
    [cup, '1.0000'],
  ]);
  await ensureSimpleRecipe('COF-MOC', 'Mocha Cold Coffee', [
    [coffee, '18.0000'],
    [milk, '180.0000'],
    [sugar, '20.0000'],
    [cup, '1.0000'],
  ]);
  await ensureSimpleRecipe('BOB-BRN', 'Brown Sugar Boba', [
    [boba, '50.0000'],
    [milk, '200.0000'],
    [sugar, '25.0000'],
    [cup, '1.0000'],
    [straw, '1.0000'],
  ]);
  await ensureSimpleRecipe('BOB-TAR', 'Taro Boba', [
    [boba, '50.0000'],
    [milk, '200.0000'],
    [sugar, '25.0000'],
    [cup, '1.0000'],
    [straw, '1.0000'],
  ]);
  await ensureSimpleRecipe('SHK-CHO', 'Chocolate Shake', [
    [milk, '250.0000'],
    [iceCream, '100.0000'],
    [sugar, '20.0000'],
    [cup, '1.0000'],
    [straw, '1.0000'],
  ]);


  await idOrCreate('printers', 'business_id = ? AND branch_id = ? AND name = ?', [businessId, branchId, 'Counter 80mm'], async () => {
    const id = newId();
    await execute(
      `INSERT INTO printers (id, business_id, branch_id, name, printer_type, paper_width_mm, connection_type, is_default)
       VALUES (?, ?, ?, ?, 'ESC_POS', 80, 'NETWORK', 1)`,
      [id, businessId, branchId, 'Counter 80mm'],
    );
    return id;
  });

  logger.info({ businessId, branchId }, 'Seed complete. TurknRoll catalog is database data, not app hard-coding.');
}

if (require.main === module) {
  seed()
    .then(async () => {
      await closePool();
      process.exit(0);
    })
    .catch(async (error: unknown) => {
      logger.error({ err: error }, 'Seed failed');
      await closePool();
      process.exit(1);
    });
}
