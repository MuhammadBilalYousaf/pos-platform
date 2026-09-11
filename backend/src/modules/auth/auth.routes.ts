import { Router } from 'express';
import { authenticate, requireAuth } from '../../middleware/authenticate';
import { query } from '../../database/pool';
import { ok } from '../../utils/apiResponse';

export const authRouter = Router();

authRouter.get('/session', authenticate, async (req, res, next) => {
  try {
    const auth = requireAuth(req);
    const business = auth.businessId
      ? (
          await query(
            `SELECT id, name, slug, logo_url, primary_color, secondary_color, currency_code, tax_rate,
                    address, phone, receipt_header, receipt_footer, status
             FROM businesses WHERE id = ? LIMIT 1`,
            [auth.businessId],
          )
        )[0]
      : null;
    const branch = auth.branchId
      ? (
          await query(
            `SELECT id, business_id, name, code, address, phone, timezone, status
             FROM branches WHERE id = ? LIMIT 1`,
            [auth.branchId],
          )
        )[0]
      : null;
    const branches = auth.businessId
      ? await query(
          `SELECT id, business_id, name, code, address, phone, timezone, status
           FROM branches WHERE business_id = ? AND status = 'ACTIVE' ORDER BY name`,
          [auth.businessId],
        )
      : [];

    ok(res, {
      user: {
        id: auth.userId,
        name: auth.name,
        email: auth.email,
        role: auth.roleSlug,
        permissions: auth.permissions,
      },
      business,
      branch,
      branches,
    });
  } catch (error) {
    next(error);
  }
});
