import { Router } from 'express';
import { authenticate, requirePermission } from '../../middleware/authenticate';
import { PERMISSIONS } from '../auth/auth.types';
import { auditAction } from '../../middleware/audit';
import { ok } from '../../utils/apiResponse';
import { syncOrders } from './sync.service';

export const syncRouter = Router();
syncRouter.use(authenticate);

syncRouter.post(
  '/sync/orders',
  requirePermission(PERMISSIONS.SYNC_APPLY, PERMISSIONS.ORDERS_CREATE),
  auditAction('sync.orders', 'order'),
  async (req, res, next) => {
    try {
      const result = await syncOrders(req, req.body);
      ok(res, result);
    } catch (error) {
      next(error);
    }
  },
);
