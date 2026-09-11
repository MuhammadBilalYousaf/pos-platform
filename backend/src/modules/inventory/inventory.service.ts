import type { PoolConnection, RowDataPacket } from 'mysql2/promise';
import { Decimal } from 'decimal.js';
import { AppError } from '../../utils/appError';
import { newId } from '../../utils/ids';
import { money, qtyString } from '../../utils/money';

export interface InventoryMoveInput {
  businessId: string;
  branchId: string;
  ingredientId: string;
  delta: Decimal;
  type: 'PURCHASE' | 'SALE' | 'SALE_REVERSAL' | 'TRANSFER_IN' | 'TRANSFER_OUT' | 'ADJUSTMENT_IN' | 'ADJUSTMENT_OUT' | 'WASTE' | 'RETURN';
  referenceType: string;
  referenceId: string;
  userId: string;
  notes?: string;
}

export async function applyInventoryMove(conn: PoolConnection, input: InventoryMoveInput): Promise<void> {
  const [rows] = await conn.query<RowDataPacket[]>(
    `SELECT id, quantity_base
     FROM inventory
     WHERE branch_id = ? AND ingredient_id = ?
     LIMIT 1
     FOR UPDATE`,
    [input.branchId, input.ingredientId],
  );

  let inventoryId: string;
  let previous = money(0);
  const existing = rows[0];
  if (!existing) {
    inventoryId = newId();
    await conn.execute(
      `INSERT INTO inventory (id, business_id, branch_id, ingredient_id, quantity_base)
       VALUES (?, ?, ?, ?, 0)`,
      [inventoryId, input.businessId, input.branchId, input.ingredientId],
    );
  } else {
    inventoryId = String(existing.id);
    previous = money(existing.quantity_base);
  }

  const next = previous.plus(input.delta);
  if (next.lt(0)) {
    throw new AppError(409, 'INSUFFICIENT_STOCK', 'Insufficient stock for this item.');
  }

  await conn.execute('UPDATE inventory SET quantity_base = ? WHERE id = ?', [qtyString(next), inventoryId]);
  await conn.execute(
    `INSERT INTO inventory_transactions
      (id, business_id, branch_id, ingredient_id, transaction_type, quantity_base, previous_qty, new_qty, reference_type, reference_id, user_id, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      newId(),
      input.businessId,
      input.branchId,
      input.ingredientId,
      input.type,
      qtyString(input.delta),
      qtyString(previous),
      qtyString(next),
      input.referenceType,
      input.referenceId,
      input.userId,
      input.notes ?? null,
    ],
  );
}

export async function explodeRecipe(
  conn: PoolConnection,
  businessId: string,
  productId: string,
  variantId: string | null,
  quantity: Decimal,
): Promise<Array<{ ingredientId: string; quantityBase: Decimal }>> {
  let recipeId: string | undefined;
  if (variantId) {
    const [variantRecipes] = await conn.query<RowDataPacket[]>(
      `SELECT id FROM recipes WHERE business_id = ? AND product_id = ? AND variant_id = ? LIMIT 1`,
      [businessId, productId, variantId],
    );
    recipeId = variantRecipes[0] ? String(variantRecipes[0].id) : undefined;
  }
  if (!recipeId) {
    const [productRecipes] = await conn.query<RowDataPacket[]>(
      `SELECT id FROM recipes WHERE business_id = ? AND product_id = ? AND variant_id IS NULL LIMIT 1`,
      [businessId, productId],
    );
    recipeId = productRecipes[0] ? String(productRecipes[0].id) : undefined;
  }
  if (!recipeId) {
    return [];
  }
  const [items] = await conn.query<RowDataPacket[]>(
    'SELECT ingredient_id, quantity_base FROM recipe_items WHERE recipe_id = ?',
    [recipeId],
  );
  return items.map((item) => ({
    ingredientId: String(item.ingredient_id),
    quantityBase: money(item.quantity_base).times(quantity),
  }));
}
