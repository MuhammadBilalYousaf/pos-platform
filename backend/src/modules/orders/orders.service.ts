import type { PoolConnection, RowDataPacket } from 'mysql2/promise';
import { Decimal } from 'decimal.js';
import { withTransaction } from '../../database/pool';
import { AppError } from '../../utils/appError';
import { newId } from '../../utils/ids';
import { money, moneyString } from '../../utils/money';
import type { AuthContext } from '../auth/auth.types';
import { applyInventoryMove, explodeRecipe } from '../inventory/inventory.service';
import { calculateOrderTotals } from './orderTotals';
import { getBusinessTaxRate } from '../org/tenant';

const PAYMENT_METHODS = new Set(['CASH', 'CARD', 'BANK_TRANSFER', 'EASYPAISA', 'JAZZCASH', 'OTHER']);

export interface CompleteOrderItemInput {
  productId: string;
  variantId?: string;
  quantity: string;
  optionIds?: string[];
  discountAmount?: string;
  nameSnapshot?: string;
}

export interface CompleteOrderInput {
  branchId: string;
  idempotencyKey: string;
  notes?: string;
  discountAmount?: string;
  items: CompleteOrderItemInput[];
  payments: Array<{
    method: string;
    amount: string;
    referenceNo?: string;
  }>;
}

interface ProductRow extends RowDataPacket {
  id: string;
  name: string;
  product_type: string;
}

interface VariantRow extends RowDataPacket {
  id: string;
  product_id: string;
  name: string;
  price: string;
}

interface OptionRow extends RowDataPacket {
  id: string;
  product_id: string;
  name: string;
  extra_price: string;
}

export async function completeOrder(auth: AuthContext, businessId: string, input: CompleteOrderInput) {
  if (!input.items.length) {
    throw new AppError(400, 'EMPTY_CART', 'Add at least one item before completing the order.');
  }
  if (!input.payments.length) {
    throw new AppError(400, 'PAYMENT_REQUIRED', 'A payment is required to complete the order.');
  }
  for (const payment of input.payments) {
    if (!PAYMENT_METHODS.has(payment.method)) {
      throw new AppError(400, 'INVALID_PAYMENT_METHOD', 'This payment method is not supported.');
    }
  }

  const taxRate = await getBusinessTaxRate(businessId);

  return withTransaction(async (conn) => {
    const [existing] = await conn.query<RowDataPacket[]>(
      `SELECT id FROM orders WHERE business_id = ? AND idempotency_key = ? LIMIT 1`,
      [businessId, input.idempotencyKey],
    );
    if (existing[0]) {
      return loadOrder(conn, String(existing[0].id));
    }

    const [branchRows] = await conn.query<RowDataPacket[]>(
      `SELECT id, code FROM branches WHERE id = ? AND business_id = ? LIMIT 1 FOR UPDATE`,
      [input.branchId, businessId],
    );
    const branch = branchRows[0];
    if (!branch) {
      throw new AppError(404, 'BRANCH_NOT_FOUND', 'Branch was not found for this business.');
    }

    const pricedItems = [];
    for (const item of input.items) {
      const [products] = await conn.query<ProductRow[]>(
        `SELECT id, name, product_type FROM products WHERE id = ? AND business_id = ? AND is_active = 1 LIMIT 1`,
        [item.productId, businessId],
      );
      const product = products[0];
      if (!product) {
        throw new AppError(400, 'INVALID_PRODUCT', 'A selected product is not available.');
      }

      let variant: VariantRow | undefined;
      if (item.variantId) {
        const [variants] = await conn.query<VariantRow[]>(
          `SELECT id, product_id, name, price FROM product_variants
           WHERE id = ? AND product_id = ? AND business_id = ? AND is_active = 1 LIMIT 1`,
          [item.variantId, item.productId, businessId],
        );
        variant = variants[0];
        if (!variant) {
          throw new AppError(400, 'INVALID_VARIANT', 'A selected product option is not available.');
        }
      } else {
        const [variants] = await conn.query<VariantRow[]>(
          `SELECT id, product_id, name, price FROM product_variants
           WHERE product_id = ? AND business_id = ? AND is_active = 1
           ORDER BY is_default DESC LIMIT 1`,
          [item.productId, businessId],
        );
        variant = variants[0];
      }
      if (!variant) {
        throw new AppError(400, 'INVALID_VARIANT', 'This product has no sellable price.');
      }

      let extra = money(0);
      const optionSnapshots: Array<{ id: string; name: string; extraPrice: string }> = [];
      for (const optionId of item.optionIds ?? []) {
        const [options] = await conn.query<OptionRow[]>(
          `SELECT id, product_id, name, extra_price FROM product_options
           WHERE id = ? AND product_id = ? AND business_id = ? AND is_active = 1 LIMIT 1`,
          [optionId, item.productId, businessId],
        );
        const option = options[0];
        if (!option) {
          throw new AppError(400, 'INVALID_OPTION', 'A selected add-on is not available.');
        }
        extra = extra.plus(option.extra_price);
        optionSnapshots.push({ id: option.id, name: option.name, extraPrice: moneyString(option.extra_price) });
      }

      pricedItems.push({
        product,
        variant,
        quantity: item.quantity,
        extraPrice: moneyString(extra),
        discountAmount: item.discountAmount ?? '0',
        optionSnapshots,
        nameSnapshot: item.nameSnapshot ?? `${product.name}${variant.name === 'Regular' ? '' : ` (${variant.name})`}`,
      });
    }

    const totals = calculateOrderTotals({
      taxRate,
      orderDiscountAmount: input.discountAmount ?? '0',
      lines: pricedItems.map((item) => ({
        quantity: item.quantity,
        unitPrice: item.variant.price,
        extraPrice: item.extraPrice,
        discountAmount: item.discountAmount,
      })),
    });

    const paid = input.payments.reduce((sum, payment) => sum.plus(payment.amount), money(0));
    if (paid.lt(totals.total)) {
      throw new AppError(400, 'PAYMENT_INCOMPLETE', 'Payment does not cover the order total.');
    }

    const orderId = newId();
    const orderNumber = await nextOrderNumber(conn, businessId, input.branchId, String(branch.code));

    await conn.execute(
      `INSERT INTO orders
        (id, business_id, branch_id, cashier_id, order_number, idempotency_key, status, subtotal, discount_amount, tax_amount, total, notes, sync_status)
       VALUES (?, ?, ?, ?, ?, ?, 'COMPLETED', ?, ?, ?, ?, ?, 'SYNCED')`,
      [
        orderId,
        businessId,
        input.branchId,
        auth.userId,
        orderNumber,
        input.idempotencyKey,
        totals.subtotal,
        totals.discountAmount,
        totals.taxAmount,
        totals.total,
        input.notes ?? null,
      ],
    );

    for (const [index, item] of pricedItems.entries()) {
      const orderItemId = newId();
      await conn.execute(
        `INSERT INTO order_items
          (id, order_id, product_id, variant_id, name_snapshot, quantity, unit_price, discount_amount, line_total)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          orderItemId,
          orderId,
          item.product.id,
          item.variant.id,
          item.nameSnapshot,
          item.quantity,
          moneyString(item.variant.price),
          moneyString(item.discountAmount),
          totals.lineTotals[index] ?? '0.00',
        ],
      );
      for (const option of item.optionSnapshots) {
        await conn.execute(
          `INSERT INTO order_item_options (id, order_item_id, option_id, name_snapshot, extra_price)
           VALUES (?, ?, ?, ?, ?)`,
          [newId(), orderItemId, option.id, option.name, option.extraPrice],
        );
      }

      const components = await explodeRecipe(
        conn,
        businessId,
        item.product.id,
        item.variant.id,
        new Decimal(item.quantity),
      );
      for (const component of components) {
        await applyInventoryMove(conn, {
          businessId,
          branchId: input.branchId,
          ingredientId: component.ingredientId,
          delta: component.quantityBase.negated(),
          type: 'SALE',
          referenceType: 'order',
          referenceId: orderId,
          userId: auth.userId,
        });
      }
    }

    for (const payment of input.payments) {
      await conn.execute(
        `INSERT INTO payments (id, business_id, order_id, cashier_id, method, amount, reference_no, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'COMPLETED')`,
        [
          newId(),
          businessId,
          orderId,
          auth.userId,
          payment.method,
          moneyString(payment.amount),
          payment.referenceNo ?? null,
        ],
      );
    }

    return loadOrder(conn, orderId);
  });
}

async function nextOrderNumber(
  conn: PoolConnection,
  businessId: string,
  branchId: string,
  branchCode: string,
): Promise<string> {
  const day = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const prefix = `${branchCode}-${day}-`;
  const [rows] = await conn.query<RowDataPacket[]>(
    `SELECT order_number FROM orders
     WHERE business_id = ? AND branch_id = ? AND order_number LIKE ?
     ORDER BY order_number DESC
     LIMIT 1`,
    [businessId, branchId, `${prefix}%`],
  );
  const last = rows[0]?.order_number as string | undefined;
  const seq = last ? Number(last.slice(prefix.length)) + 1 : 1;
  return `${prefix}${String(Number.isFinite(seq) ? seq : 1).padStart(4, '0')}`;
}

export interface SavedOrder {
  id: string;
  order_number: string;
  items: RowDataPacket[];
  payments: RowDataPacket[];
  [key: string]: unknown;
}

export async function loadOrder(conn: PoolConnection, orderId: string): Promise<SavedOrder> {
  const [orders] = await conn.query<RowDataPacket[]>('SELECT * FROM orders WHERE id = ? LIMIT 1', [orderId]);
  const order = orders[0];
  if (!order) {
    throw new AppError(404, 'ORDER_NOT_FOUND', 'Order was not found.');
  }
  const [items] = await conn.query<RowDataPacket[]>('SELECT * FROM order_items WHERE order_id = ?', [orderId]);
  const [payments] = await conn.query<RowDataPacket[]>('SELECT * FROM payments WHERE order_id = ?', [orderId]);
  return {
    ...(order as Record<string, unknown>),
    id: String(order.id),
    order_number: String(order.order_number),
    items,
    payments,
  };
}
