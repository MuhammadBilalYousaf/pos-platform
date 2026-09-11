import { Router } from 'express';
import { z } from 'zod';
import { authenticate, requirePermission, resolveBusinessId } from '../../middleware/authenticate';
import { PERMISSIONS } from '../auth/auth.types';
import { validate } from '../../middleware/validate';
import { auditAction } from '../../middleware/audit';
import { execute, query } from '../../database/pool';
import { ok, created } from '../../utils/apiResponse';
import { AppError } from '../../utils/appError';
import { newId } from '../../utils/ids';
import { moneyString } from '../../utils/money';

export const catalogRouter = Router();
catalogRouter.use(authenticate);

const categoryBody = z.object({
  name: z.string().min(1).max(191),
  slug: z.string().min(1).max(64).optional(),
  sortOrder: z.number().int().optional(),
  isActive: z.boolean().optional(),
});

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 64);
}

catalogRouter.get('/categories', requirePermission(PERMISSIONS.CATALOG_READ, PERMISSIONS.ORDERS_CREATE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const rows = await query(
      'SELECT * FROM categories WHERE business_id = ? ORDER BY sort_order, name',
      [businessId],
    );
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

catalogRouter.post(
  '/categories',
  requirePermission(PERMISSIONS.CATALOG_WRITE),
  validate(categoryBody),
  auditAction('category.create', 'category'),
  async (req, res, next) => {
    try {
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof categoryBody>;
      const id = newId();
      await execute(
        `INSERT INTO categories (id, business_id, name, slug, sort_order, is_active)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [id, businessId, body.name, body.slug ?? slugify(body.name), body.sortOrder ?? 0, body.isActive === false ? 0 : 1],
      );
      const rows = await query('SELECT * FROM categories WHERE id = ?', [id]);
      created(res, rows[0]);
    } catch (error) {
      next(error);
    }
  },
);

catalogRouter.get('/products', requirePermission(PERMISSIONS.CATALOG_READ, PERMISSIONS.ORDERS_CREATE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const products = await query(
      `SELECT p.*, c.name AS category_name
       FROM products p
       INNER JOIN categories c ON c.id = p.category_id
       WHERE p.business_id = ?
       ORDER BY c.sort_order, p.name`,
      [businessId],
    );
    const variants = await query(
      'SELECT * FROM product_variants WHERE business_id = ? AND is_active = 1',
      [businessId],
    );
    const options = await query(
      'SELECT * FROM product_options WHERE business_id = ? AND is_active = 1',
      [businessId],
    );
    const data = products.map((product) => ({
      ...product,
      variants: variants.filter((variant) => variant.product_id === product.id),
      options: options.filter((option) => option.product_id === product.id),
    }));
    ok(res, data);
  } catch (error) {
    next(error);
  }
});

const productBody = z.object({
  categoryId: z.string().uuid(),
  name: z.string().min(1).max(191),
  sku: z.string().max(64).optional(),
  description: z.string().max(512).optional(),
  productType: z.enum(['SIMPLE', 'RECIPE', 'BUNDLE']).optional(),
  tracksInventory: z.boolean().optional(),
  variants: z
    .array(
      z.object({
        name: z.string().min(1).max(128),
        sku: z.string().max(64).optional(),
        price: z.string().regex(/^\d+(\.\d{1,2})?$/),
        cost: z.string().regex(/^\d+(\.\d{1,2})?$/).optional(),
        isDefault: z.boolean().optional(),
      }),
    )
    .min(1),
});

catalogRouter.post(
  '/products',
  requirePermission(PERMISSIONS.CATALOG_WRITE),
  validate(productBody),
  auditAction('product.create', 'product'),
  async (req, res, next) => {
    try {
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof productBody>;
      const categories = await query(
        'SELECT id FROM categories WHERE id = ? AND business_id = ?',
        [body.categoryId, businessId],
      );
      if (!categories[0]) {
        throw new AppError(400, 'INVALID_CATEGORY', 'Category was not found for this business.');
      }
      const productId = newId();
      await execute(
        `INSERT INTO products (id, business_id, category_id, name, sku, description, product_type, tracks_inventory)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          productId,
          businessId,
          body.categoryId,
          body.name,
          body.sku ?? null,
          body.description ?? null,
          body.productType ?? 'SIMPLE',
          body.tracksInventory ? 1 : 0,
        ],
      );
      for (const [index, variant] of body.variants.entries()) {
        await execute(
          `INSERT INTO product_variants (id, business_id, product_id, name, sku, price, cost, is_default)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            newId(),
            businessId,
            productId,
            variant.name,
            variant.sku ?? null,
            moneyString(variant.price),
            variant.cost ? moneyString(variant.cost) : null,
            variant.isDefault || index === 0 ? 1 : 0,
          ],
        );
      }
      const createdProduct = await query('SELECT * FROM products WHERE id = ?', [productId]);
      created(res, createdProduct[0]);
    } catch (error) {
      next(error);
    }
  },
);

catalogRouter.get('/pos/catalog', requirePermission(PERMISSIONS.ORDERS_CREATE, PERMISSIONS.CATALOG_READ), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const categories = await query(
      'SELECT id, name, slug, sort_order FROM categories WHERE business_id = ? AND is_active = 1 ORDER BY sort_order, name',
      [businessId],
    );
    const products = await query(
      `SELECT id, category_id, name, sku, product_type, tracks_inventory
       FROM products
       WHERE business_id = ? AND is_active = 1
       ORDER BY name`,
      [businessId],
    );
    const variants = await query(
      `SELECT id, product_id, name, sku, price, is_default
       FROM product_variants
       WHERE business_id = ? AND is_active = 1`,
      [businessId],
    );
    const options = await query(
      `SELECT id, product_id, name, extra_price
       FROM product_options
       WHERE business_id = ? AND is_active = 1`,
      [businessId],
    );
    ok(res, {
      categories,
      products: products.map((product) => ({
        ...product,
        variants: variants.filter((variant) => variant.product_id === product.id),
        options: options.filter((option) => option.product_id === product.id),
      })),
    });
  } catch (error) {
    next(error);
  }
});
