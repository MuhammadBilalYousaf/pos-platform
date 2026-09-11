import { Router } from 'express';
import { z } from 'zod';
import { authenticate, requirePermission, resolveBranchId, resolveBusinessId } from '../../middleware/authenticate';
import { PERMISSIONS } from '../auth/auth.types';
import { validate } from '../../middleware/validate';
import { execute, query } from '../../database/pool';
import { ok, created } from '../../utils/apiResponse';
import { newId } from '../../utils/ids';
import { assertBranchOfBusiness } from '../org/tenant';

export const settingsRouter = Router();
settingsRouter.use(authenticate);

settingsRouter.get('/printers', requirePermission(PERMISSIONS.SETTINGS_MANAGE, PERMISSIONS.ORDERS_CREATE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const branchId = resolveBranchId(req, typeof req.query.branchId === 'string' ? req.query.branchId : undefined);
    await assertBranchOfBusiness(businessId, branchId);
    ok(
      res,
      await query('SELECT * FROM printers WHERE business_id = ? AND branch_id = ? ORDER BY is_default DESC, name', [
        businessId,
        branchId,
      ]),
    );
  } catch (error) {
    next(error);
  }
});

const printerBody = z.object({
  branchId: z.string().uuid().optional(),
  name: z.string().min(1).max(128),
  paperWidthMm: z.union([z.literal(58), z.literal(80)]),
  connectionType: z.enum(['NETWORK', 'USB', 'FILE']).default('NETWORK'),
  connectionTarget: z.string().max(191).optional(),
  isDefault: z.boolean().optional(),
});

settingsRouter.post(
  '/printers',
  requirePermission(PERMISSIONS.SETTINGS_MANAGE),
  validate(printerBody),
  async (req, res, next) => {
    try {
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof printerBody>;
      const branchId = resolveBranchId(req, body.branchId);
      await assertBranchOfBusiness(businessId, branchId);
      const id = newId();
      if (body.isDefault) {
        await execute('UPDATE printers SET is_default = 0 WHERE business_id = ? AND branch_id = ?', [businessId, branchId]);
      }
      await execute(
        `INSERT INTO printers (id, business_id, branch_id, name, printer_type, paper_width_mm, connection_type, connection_target, is_default)
         VALUES (?, ?, ?, ?, 'ESC_POS', ?, ?, ?, ?)`,
        [id, businessId, branchId, body.name, body.paperWidthMm, body.connectionType, body.connectionTarget ?? null, body.isDefault ? 1 : 0],
      );
      created(res, { id });
    } catch (error) {
      next(error);
    }
  },
);

settingsRouter.get('/settings', requirePermission(PERMISSIONS.SETTINGS_MANAGE, PERMISSIONS.ORDERS_CREATE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const rows = await query('SELECT setting_key, setting_value, branch_id FROM settings WHERE business_id = ?', [businessId]);
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});
