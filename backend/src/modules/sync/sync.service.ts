import { z } from 'zod';
import type { Request } from 'express';
import { requireAuth, resolveBranchId, resolveBusinessId } from '../../middleware/authenticate';
import { completeOrder } from '../orders/orders.service';
import { assertBranchOfBusiness } from '../org/tenant';
import { toValidationError } from '../../middleware/validate';

const syncOrderBody = z.object({
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

const syncPayload = z.object({
  orders: z.array(syncOrderBody).min(1).max(50),
});

export const completeBodySync = syncOrderBody;

export async function syncOrders(req: Request, rawBody: unknown) {
  const parsed = syncPayload.safeParse(rawBody);
  if (!parsed.success) {
    throw toValidationError(parsed.error);
  }
  const auth = requireAuth(req);
  const businessId = resolveBusinessId(req);
  const results: Array<{ idempotencyKey: string; status: 'SYNCED' | 'SYNC_FAILED'; orderId?: string; message?: string }> = [];

  for (const order of parsed.data.orders) {
    try {
      const branchId = resolveBranchId(req, order.branchId);
      await assertBranchOfBusiness(businessId, branchId);
      const saved = await completeOrder(auth, businessId, { ...order, branchId });
      results.push({
        idempotencyKey: order.idempotencyKey,
        status: 'SYNCED',
        orderId: String(saved.id),
      });
    } catch (error) {
      results.push({
        idempotencyKey: order.idempotencyKey,
        status: 'SYNC_FAILED',
        message: error instanceof Error ? error.message : 'Unable to complete order. Please try again.',
      });
    }
  }

  return { results };
}
