import { Router } from 'express';
import { z } from 'zod';
import { authenticate, requireAuth, requirePermission, resolveBranchId, resolveBusinessId } from '../../middleware/authenticate';
import { PERMISSIONS } from '../auth/auth.types';
import { validate } from '../../middleware/validate';
import { auditAction } from '../../middleware/audit';
import { query, withTransaction } from '../../database/pool';
import { ok, created } from '../../utils/apiResponse';
import { AppError } from '../../utils/appError';
import { completeOrder } from './orders.service';
import { applyInventoryMove, explodeRecipe } from '../inventory/inventory.service';
import { Decimal } from 'decimal.js';
import { assertBranchOfBusiness } from '../org/tenant';

export const ordersRouter = Router();
ordersRouter.use(authenticate);

const completeBody = z.object({
  branchId: z.string().uuid().optional(),
  idempotencyKey: z.string().uuid(),
  notes: z.string().max(255).optional(),
  discountAmount: z.string().regex(/^\d+(\.\d{1,2})?$/).optional(),
  items: z
    .array(
      z.object({
        productId: z.string().uuid(),
        variantId: z.string().uuid().optional(),
        quantity: z.string().regex(/^\d+(\.\d{1,3})?$/),
        optionIds: z.array(z.string().uuid()).optional(),
        discountAmount: z.string().regex(/^\d+(\.\d{1,2})?$/).optional(),
      }),
    )
    .min(1),
  payments: z
    .array(
      z.object({
        method: z.enum(['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER']),
        amount: z.string().regex(/^\d+(\.\d{1,2})?$/),
        referenceNo: z.string().max(64).optional(),
      }),
    )
    .min(1),
});

ordersRouter.post(
  '/orders',
  requirePermission(PERMISSIONS.ORDERS_CREATE, PERMISSIONS.PAYMENTS_CREATE),
  validate(completeBody),
  auditAction('order.complete', 'order'),
  async (req, res, next) => {
    try {
      const auth = requireAuth(req);
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof completeBody>;
      const branchId = resolveBranchId(req, body.branchId);
      await assertBranchOfBusiness(businessId, branchId);
      const order = await completeOrder(auth, businessId, { ...body, branchId });
      created(res, order);
    } catch (error) {
      next(error);
    }
  },
);

ordersRouter.get('/orders', requirePermission(PERMISSIONS.ORDERS_READ, PERMISSIONS.ORDERS_CREATE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const branchId =
      typeof req.query.branchId === 'string' ? resolveBranchId(req, req.query.branchId) : requireAuth(req).branchId;
    const limit = Math.min(Number(req.query.limit ?? 50), 200);
    const params: unknown[] = [businessId];
    let sql = `SELECT o.*, u.name AS cashier_name
               FROM orders o
               INNER JOIN users u ON u.id = o.cashier_id
               WHERE o.business_id = ?`;
    if (branchId) {
      sql += ' AND o.branch_id = ?';
      params.push(branchId);
    }
    sql += ' ORDER BY o.created_at DESC LIMIT ?';
    params.push(limit);
    const rows = await query(sql, params);
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

ordersRouter.get('/orders/:id', requirePermission(PERMISSIONS.ORDERS_READ, PERMISSIONS.ORDERS_CREATE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const rows = await query('SELECT * FROM orders WHERE id = ? AND business_id = ? LIMIT 1', [req.params.id, businessId]);
    const order = rows[0];
    if (!order) {
      throw new AppError(404, 'ORDER_NOT_FOUND', 'Order was not found.');
    }
    const items = await query('SELECT * FROM order_items WHERE order_id = ?', [order.id]);
    const payments = await query('SELECT * FROM payments WHERE order_id = ?', [order.id]);
    ok(res, { ...order, items, payments });
  } catch (error) {
    next(error);
  }
});

ordersRouter.post(
  '/orders/:id/cancel',
  requirePermission(PERMISSIONS.ORDERS_REFUND),
  auditAction('order.cancel', 'order'),
  async (req, res, next) => {
    try {
      const auth = requireAuth(req);
      const businessId = resolveBusinessId(req);
      await withTransaction(async (conn) => {
        const [orders] = await conn.query(
          'SELECT * FROM orders WHERE id = ? AND business_id = ? LIMIT 1 FOR UPDATE',
          [req.params.id, businessId],
        );
        const order = (orders as Array<{ id: string; status: string; branch_id: string }>)[0];
        if (!order) {
          throw new AppError(404, 'ORDER_NOT_FOUND', 'Order was not found.');
        }
        if (order.status !== 'COMPLETED') {
          throw new AppError(409, 'ORDER_NOT_CANCELLABLE', 'Only completed orders can be cancelled.');
        }
        const [items] = await conn.query(
          'SELECT product_id, variant_id, quantity FROM order_items WHERE order_id = ?',
          [order.id],
        );
        for (const item of items as Array<{ product_id: string; variant_id: string; quantity: string }>) {
          const components = await explodeRecipe(
            conn,
            businessId,
            item.product_id,
            item.variant_id,
            new Decimal(item.quantity),
          );
          for (const component of components) {
            await applyInventoryMove(conn, {
              businessId,
              branchId: order.branch_id,
              ingredientId: component.ingredientId,
              delta: component.quantityBase,
              type: 'SALE_REVERSAL',
              referenceType: 'order',
              referenceId: order.id,
              userId: auth.userId,
              notes: 'Order cancelled',
            });
          }
        }
        await conn.execute('UPDATE orders SET status = ? WHERE id = ?', ['CANCELLED', order.id]);
      });
      ok(res, { id: req.params.id, status: 'CANCELLED' });
    } catch (error) {
      next(error);
    }
  },
);
