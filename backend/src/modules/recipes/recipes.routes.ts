import { Router } from 'express';
import { z } from 'zod';
import { authenticate, requirePermission, resolveBusinessId } from '../../middleware/authenticate';
import { PERMISSIONS } from '../auth/auth.types';
import { validate } from '../../middleware/validate';
import { auditAction } from '../../middleware/audit';
import { execute, query, withTransaction } from '../../database/pool';
import { ok, created } from '../../utils/apiResponse';
import { AppError } from '../../utils/appError';
import { newId } from '../../utils/ids';
import { qtyString } from '../../utils/money';

export const recipesRouter = Router();
recipesRouter.use(authenticate);

recipesRouter.get('/recipes', requirePermission(PERMISSIONS.CATALOG_READ, PERMISSIONS.RECIPES_WRITE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const recipes = await query(
      `SELECT r.*, p.name AS product_name
       FROM recipes r
       INNER JOIN products p ON p.id = r.product_id
       WHERE r.business_id = ?
       ORDER BY p.name`,
      [businessId],
    );
    const items = await query(
      `SELECT ri.*, ing.name AS ingredient_name
       FROM recipe_items ri
       INNER JOIN recipes r ON r.id = ri.recipe_id
       INNER JOIN ingredients ing ON ing.id = ri.ingredient_id
       WHERE r.business_id = ?`,
      [businessId],
    );
    ok(
      res,
      recipes.map((recipe) => ({
        ...recipe,
        items: items.filter((item) => item.recipe_id === recipe.id),
      })),
    );
  } catch (error) {
    next(error);
  }
});

const recipeBody = z.object({
  productId: z.string().uuid(),
  variantId: z.string().uuid().optional(),
  name: z.string().min(1).max(191),
  yieldQty: z.string().regex(/^\d+(\.\d{1,4})?$/).optional(),
  items: z
    .array(
      z.object({
        ingredientId: z.string().uuid(),
        quantityBase: z.string().regex(/^\d+(\.\d{1,4})?$/),
      }),
    )
    .min(1),
});

recipesRouter.post(
  '/recipes',
  requirePermission(PERMISSIONS.RECIPES_WRITE),
  validate(recipeBody),
  auditAction('recipe.create', 'recipe'),
  async (req, res, next) => {
    try {
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof recipeBody>;
      const products = await query(
        'SELECT id FROM products WHERE id = ? AND business_id = ?',
        [body.productId, businessId],
      );
      if (!products[0]) {
        throw new AppError(400, 'INVALID_PRODUCT', 'Product was not found for this business.');
      }
      const recipeId = newId();
      await withTransaction(async (conn) => {
        await conn.execute(
          `INSERT INTO recipes (id, business_id, product_id, variant_id, name, yield_qty)
           VALUES (?, ?, ?, ?, ?, ?)`,
          [recipeId, businessId, body.productId, body.variantId ?? null, body.name, body.yieldQty ?? '1.0000'],
        );
        for (const item of body.items) {
          await conn.execute(
            `INSERT INTO recipe_items (id, recipe_id, ingredient_id, quantity_base)
             VALUES (?, ?, ?, ?)`,
            [newId(), recipeId, item.ingredientId, qtyString(item.quantityBase)],
          );
        }
        await conn.execute('UPDATE products SET product_type = ? WHERE id = ? AND business_id = ?', [
          'RECIPE',
          body.productId,
          businessId,
        ]);
      });
      created(res, { id: recipeId });
    } catch (error) {
      next(error);
    }
  },
);

recipesRouter.get('/ingredients', requirePermission(PERMISSIONS.INVENTORY_READ, PERMISSIONS.RECIPES_WRITE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const rows = await query(
      `SELECT i.*, u.code AS unit_code, u.name AS unit_name
       FROM ingredients i
       INNER JOIN units u ON u.id = i.unit_id
       WHERE i.business_id = ?
       ORDER BY i.name`,
      [businessId],
    );
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

const ingredientBody = z.object({
  name: z.string().min(1).max(191),
  sku: z.string().max(64).optional(),
  unitId: z.string().uuid(),
});

recipesRouter.post(
  '/ingredients',
  requirePermission(PERMISSIONS.RECIPES_WRITE),
  validate(ingredientBody),
  auditAction('ingredient.create', 'ingredient'),
  async (req, res, next) => {
    try {
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof ingredientBody>;
      const id = newId();
      await execute(
        `INSERT INTO ingredients (id, business_id, name, sku, unit_id)
         VALUES (?, ?, ?, ?, ?)`,
        [id, businessId, body.name, body.sku ?? null, body.unitId],
      );
      created(res, { id });
    } catch (error) {
      next(error);
    }
  },
);
