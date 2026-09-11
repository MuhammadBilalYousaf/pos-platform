import { Router } from 'express';
import { z } from 'zod';
import { Decimal } from 'decimal.js';
import { authenticate, requireAuth, requirePermission, resolveBranchId, resolveBusinessId } from '../../middleware/authenticate';
import { PERMISSIONS } from '../auth/auth.types';
import { validate } from '../../middleware/validate';
import { auditAction } from '../../middleware/audit';
import { query, withTransaction } from '../../database/pool';
import { ok, created } from '../../utils/apiResponse';
import { newId } from '../../utils/ids';
import { moneyString } from '../../utils/money';
import { applyInventoryMove } from './inventory.service';
import { assertBranchOfBusiness } from '../org/tenant';
import { AppError } from '../../utils/appError';

export const inventoryRouter = Router();
inventoryRouter.use(authenticate);

inventoryRouter.get('/inventory', requirePermission(PERMISSIONS.INVENTORY_READ, PERMISSIONS.REPORTS_VIEW), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const branchId = resolveBranchId(req, typeof req.query.branchId === 'string' ? req.query.branchId : undefined);
    await assertBranchOfBusiness(businessId, branchId);
    const rows = await query(
      `SELECT i.id, i.ingredient_id, ing.name AS ingredient_name, u.code AS unit_code,
              i.quantity_base, i.reorder_level, i.updated_at
       FROM inventory i
       INNER JOIN ingredients ing ON ing.id = i.ingredient_id
       INNER JOIN units u ON u.id = ing.unit_id
       WHERE i.business_id = ? AND i.branch_id = ?
       ORDER BY ing.name`,
      [businessId, branchId],
    );
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

inventoryRouter.get('/inventory/movements', requirePermission(PERMISSIONS.INVENTORY_READ, PERMISSIONS.REPORTS_VIEW), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const branchId = resolveBranchId(req, typeof req.query.branchId === 'string' ? req.query.branchId : undefined);
    await assertBranchOfBusiness(businessId, branchId);
    const rows = await query(
      `SELECT t.*, ing.name AS ingredient_name, u.name AS user_name
       FROM inventory_transactions t
       INNER JOIN ingredients ing ON ing.id = t.ingredient_id
       LEFT JOIN users u ON u.id = t.user_id
       WHERE t.business_id = ? AND t.branch_id = ?
       ORDER BY t.created_at DESC
       LIMIT 200`,
      [businessId, branchId],
    );
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

const adjustmentBody = z.object({
  branchId: z.string().uuid().optional(),
  reason: z.string().min(1).max(255),
  items: z
    .array(
      z.object({
        ingredientId: z.string().uuid(),
        quantityBase: z.string().regex(/^-?\d+(\.\d{1,4})?$/),
      }),
    )
    .min(1),
});

inventoryRouter.post(
  '/inventory/adjustments',
  requirePermission(PERMISSIONS.INVENTORY_ADJUST),
  validate(adjustmentBody),
  auditAction('inventory.adjust', 'stock_adjustment'),
  async (req, res, next) => {
    try {
      const auth = requireAuth(req);
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof adjustmentBody>;
      const branchId = resolveBranchId(req, body.branchId);
      await assertBranchOfBusiness(businessId, branchId);
      const adjustmentId = newId();

      await withTransaction(async (conn) => {
        await conn.execute(
          `INSERT INTO stock_adjustments (id, business_id, branch_id, user_id, reason)
           VALUES (?, ?, ?, ?, ?)`,
          [adjustmentId, businessId, branchId, auth.userId, body.reason],
        );
        for (const item of body.items) {
          const qty = new Decimal(item.quantityBase);
          if (qty.eq(0)) {
            throw new AppError(400, 'INVALID_QUANTITY', 'Adjustment quantity cannot be zero.');
          }
          await conn.execute(
            `INSERT INTO stock_adjustment_items (id, adjustment_id, ingredient_id, quantity_base)
             VALUES (?, ?, ?, ?)`,
            [newId(), adjustmentId, item.ingredientId, item.quantityBase],
          );
          await applyInventoryMove(conn, {
            businessId,
            branchId,
            ingredientId: item.ingredientId,
            delta: qty,
            type: qty.gt(0) ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
            referenceType: 'stock_adjustment',
            referenceId: adjustmentId,
            userId: auth.userId,
            notes: body.reason,
          });
        }
      });

      created(res, { id: adjustmentId });
    } catch (error) {
      next(error);
    }
  },
);

const purchaseBody = z.object({
  branchId: z.string().uuid().optional(),
  supplierId: z.string().uuid().optional(),
  invoiceNo: z.string().max(64).optional(),
  items: z
    .array(
      z.object({
        ingredientId: z.string().uuid(),
        quantityBase: z.string().regex(/^\d+(\.\d{1,4})?$/),
        unitCost: z.string().regex(/^\d+(\.\d{1,2})?$/),
      }),
    )
    .min(1),
});

inventoryRouter.post(
  '/purchases',
  requirePermission(PERMISSIONS.INVENTORY_ADJUST),
  validate(purchaseBody),
  auditAction('purchase.create', 'purchase'),
  async (req, res, next) => {
    try {
      const auth = requireAuth(req);
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof purchaseBody>;
      const branchId = resolveBranchId(req, body.branchId);
      await assertBranchOfBusiness(businessId, branchId);
      const purchaseId = newId();
      let total = new Decimal(0);

      await withTransaction(async (conn) => {
        for (const item of body.items) {
          const lineTotal = new Decimal(item.unitCost).times(item.quantityBase);
          total = total.plus(lineTotal);
        }
        await conn.execute(
          `INSERT INTO purchases (id, business_id, branch_id, supplier_id, user_id, invoice_no, total)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [purchaseId, businessId, branchId, body.supplierId ?? null, auth.userId, body.invoiceNo ?? null, moneyString(total)],
        );
        for (const item of body.items) {
          const lineTotal = new Decimal(item.unitCost).times(item.quantityBase);
          await conn.execute(
            `INSERT INTO purchase_items (id, purchase_id, ingredient_id, quantity_base, unit_cost, line_total)
             VALUES (?, ?, ?, ?, ?, ?)`,
            [newId(), purchaseId, item.ingredientId, item.quantityBase, moneyString(item.unitCost), moneyString(lineTotal)],
          );
          await applyInventoryMove(conn, {
            businessId,
            branchId,
            ingredientId: item.ingredientId,
            delta: new Decimal(item.quantityBase),
            type: 'PURCHASE',
            referenceType: 'purchase',
            referenceId: purchaseId,
            userId: auth.userId,
          });
        }
      });

      created(res, { id: purchaseId, total: moneyString(total) });
    } catch (error) {
      next(error);
    }
  },
);
