import { Router } from 'express';
import { authenticate, requireAuth, requirePermission, resolveBusinessId } from '../../middleware/authenticate';
import { PERMISSIONS, ROLE_SLUGS } from '../auth/auth.types';
import { query } from '../../database/pool';
import { ok } from '../../utils/apiResponse';

export const reportsRouter = Router();
reportsRouter.use(authenticate);
reportsRouter.use(requirePermission(PERMISSIONS.REPORTS_VIEW));

function dateRange(req: { query: Record<string, unknown> }): { from: string; to: string } {
  const from = typeof req.query.from === 'string' ? req.query.from : new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10);
  const to = typeof req.query.to === 'string' ? req.query.to : new Date().toISOString().slice(0, 10);
  return { from: `${from} 00:00:00`, to: `${to} 23:59:59.999` };
}

function scopedBranch(req: { query: Record<string, unknown>; auth?: { roleSlug: string; branchId: string | null } }): string | null {
  if (req.auth?.roleSlug === ROLE_SLUGS.CASHIER || req.auth?.roleSlug === ROLE_SLUGS.BRANCH_MANAGER) {
    return req.auth.branchId;
  }
  return typeof req.query.branchId === 'string' ? req.query.branchId : null;
}

reportsRouter.get('/reports/sales', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const { from, to } = dateRange(req);
    const branchId = scopedBranch(req);
    const params: unknown[] = [businessId, from, to];
    let sql = `SELECT DATE(created_at) AS day,
                      COUNT(*) AS order_count,
                      COALESCE(SUM(subtotal), 0) AS subtotal,
                      COALESCE(SUM(discount_amount), 0) AS discount_amount,
                      COALESCE(SUM(tax_amount), 0) AS tax_amount,
                      COALESCE(SUM(total), 0) AS total
               FROM orders
               WHERE business_id = ? AND status = 'COMPLETED' AND created_at BETWEEN ? AND ?`;
    if (branchId) {
      sql += ' AND branch_id = ?';
      params.push(branchId);
    }
    sql += ' GROUP BY DATE(created_at) ORDER BY day';
    ok(res, await query(sql, params));
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/products', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const { from, to } = dateRange(req);
    const branchId = scopedBranch(req);
    const params: unknown[] = [businessId, from, to];
    let sql = `SELECT oi.product_id, oi.name_snapshot AS product_name,
                      SUM(oi.quantity) AS quantity,
                      SUM(oi.line_total) AS total
               FROM order_items oi
               INNER JOIN orders o ON o.id = oi.order_id
               WHERE o.business_id = ? AND o.status = 'COMPLETED' AND o.created_at BETWEEN ? AND ?`;
    if (branchId) {
      sql += ' AND o.branch_id = ?';
      params.push(branchId);
    }
    sql += ' GROUP BY oi.product_id, oi.name_snapshot ORDER BY total DESC';
    ok(res, await query(sql, params));
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/categories', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const { from, to } = dateRange(req);
    const branchId = scopedBranch(req);
    const params: unknown[] = [businessId, from, to];
    let sql = `SELECT c.id AS category_id, c.name AS category_name,
                      SUM(oi.quantity) AS quantity,
                      SUM(oi.line_total) AS total
               FROM order_items oi
               INNER JOIN orders o ON o.id = oi.order_id
               INNER JOIN products p ON p.id = oi.product_id
               INNER JOIN categories c ON c.id = p.category_id
               WHERE o.business_id = ? AND o.status = 'COMPLETED' AND o.created_at BETWEEN ? AND ?`;
    if (branchId) {
      sql += ' AND o.branch_id = ?';
      params.push(branchId);
    }
    sql += ' GROUP BY c.id, c.name ORDER BY total DESC';
    ok(res, await query(sql, params));
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/payments', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const { from, to } = dateRange(req);
    const branchId = scopedBranch(req);
    const params: unknown[] = [businessId, from, to];
    let sql = `SELECT p.method, COUNT(*) AS payment_count, SUM(p.amount) AS total
               FROM payments p
               INNER JOIN orders o ON o.id = p.order_id
               WHERE p.business_id = ? AND p.status = 'COMPLETED' AND p.created_at BETWEEN ? AND ?`;
    if (branchId) {
      sql += ' AND o.branch_id = ?';
      params.push(branchId);
    }
    sql += ' GROUP BY p.method ORDER BY total DESC';
    ok(res, await query(sql, params));
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/employees', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const { from, to } = dateRange(req);
    const branchId = scopedBranch(req);
    const params: unknown[] = [businessId, from, to];
    let sql = `SELECT u.id AS cashier_id, u.name AS cashier_name,
                      COUNT(*) AS order_count, SUM(o.total) AS total
               FROM orders o
               INNER JOIN users u ON u.id = o.cashier_id
               WHERE o.business_id = ? AND o.status = 'COMPLETED' AND o.created_at BETWEEN ? AND ?`;
    if (branchId) {
      sql += ' AND o.branch_id = ?';
      params.push(branchId);
    }
    sql += ' GROUP BY u.id, u.name ORDER BY total DESC';
    ok(res, await query(sql, params));
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/inventory', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const branchId = scopedBranch(req) ?? requireAuth(req).branchId;
    const params: unknown[] = [businessId];
    let sql = `SELECT i.ingredient_id, ing.name, i.quantity_base, i.reorder_level, i.quantity_base <= i.reorder_level AS is_low
               FROM inventory i
               INNER JOIN ingredients ing ON ing.id = i.ingredient_id
               WHERE i.business_id = ?`;
    if (branchId) {
      sql += ' AND i.branch_id = ?';
      params.push(branchId);
    }
    sql += ' ORDER BY is_low DESC, ing.name';
    ok(res, await query(sql, params));
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/low-stock', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const branchId = scopedBranch(req) ?? requireAuth(req).branchId;
    const params: unknown[] = [businessId];
    let sql = `SELECT i.ingredient_id, ing.name, i.quantity_base, i.reorder_level
               FROM inventory i
               INNER JOIN ingredients ing ON ing.id = i.ingredient_id
               WHERE i.business_id = ? AND i.quantity_base <= i.reorder_level`;
    if (branchId) {
      sql += ' AND i.branch_id = ?';
      params.push(branchId);
    }
    sql += ' ORDER BY ing.name';
    ok(res, await query(sql, params));
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/cancellations', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const { from, to } = dateRange(req);
    const rows = await query(
      `SELECT id, order_number, total, cashier_id, created_at, status
       FROM orders
       WHERE business_id = ? AND status IN ('CANCELLED', 'REFUNDED', 'PARTIALLY_REFUNDED')
         AND created_at BETWEEN ? AND ?
       ORDER BY created_at DESC`,
      [businessId, from, to],
    );
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

reportsRouter.get('/reports/dashboard', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const today = new Date().toISOString().slice(0, 10);
    const branchId = scopedBranch(req);
    const params: unknown[] = [businessId, `${today} 00:00:00`, `${today} 23:59:59.999`];
    let where = `business_id = ? AND status = 'COMPLETED' AND created_at BETWEEN ? AND ?`;
    if (branchId) {
      where += ' AND branch_id = ?';
      params.push(branchId);
    }
    const summary = await query(
      `SELECT COUNT(*) AS order_count, COALESCE(SUM(total), 0) AS total, COALESCE(SUM(discount_amount), 0) AS discount_amount
       FROM orders WHERE ${where}`,
      params,
    );
    const lowStock = await query(
      `SELECT COUNT(*) AS low_stock_count
       FROM inventory
       WHERE business_id = ? AND quantity_base <= reorder_level${branchId ? ' AND branch_id = ?' : ''}`,
      branchId ? [businessId, branchId] : [businessId],
    );
    ok(res, {
      today: summary[0],
      lowStockCount: lowStock[0]?.low_stock_count ?? 0,
    });
  } catch (error) {
    next(error);
  }
});
