import { Router } from 'express';
import { z } from 'zod';
import { authenticate, requireAuth, requirePermission, resolveBusinessId } from '../../middleware/authenticate';
import { PERMISSIONS, ROLE_SLUGS } from '../auth/auth.types';
import { validate } from '../../middleware/validate';
import { auditAction } from '../../middleware/audit';
import { query, execute } from '../../database/pool';
import { ok, created } from '../../utils/apiResponse';
import { AppError } from '../../utils/appError';
import { newId } from '../../utils/ids';

export const orgRouter = Router();
orgRouter.use(authenticate);

const branchBody = z.object({
  name: z.string().min(1).max(191),
  code: z.string().min(1).max(32),
  address: z.string().max(255).optional(),
  phone: z.string().max(32).optional(),
  timezone: z.string().max(64).optional(),
});

orgRouter.get('/businesses', requirePermission(PERMISSIONS.PLATFORM_MANAGE, PERMISSIONS.BUSINESS_MANAGE), async (req, res, next) => {
  try {
    const auth = requireAuth(req);
    const rows =
      auth.roleSlug === ROLE_SLUGS.PLATFORM_SUPER_ADMIN
        ? await query('SELECT * FROM businesses ORDER BY name')
        : await query('SELECT * FROM businesses WHERE id = ?', [auth.businessId]);
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

orgRouter.get('/businesses/current', async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const rows = await query('SELECT * FROM businesses WHERE id = ? LIMIT 1', [businessId]);
    if (!rows[0]) {
      throw new AppError(404, 'BUSINESS_NOT_FOUND', 'Business was not found.');
    }
    ok(res, rows[0]);
  } catch (error) {
    next(error);
  }
});

const brandingBody = z.object({
  name: z.string().min(1).max(191).optional(),
  logoUrl: z.string().max(512).optional(),
  primaryColor: z.string().max(16).optional(),
  secondaryColor: z.string().max(16).optional(),
  address: z.string().max(255).optional(),
  phone: z.string().max(32).optional(),
  currencyCode: z.string().length(3).optional(),
  taxRate: z.string().regex(/^\d+(\.\d{1,4})?$/).optional(),
  receiptHeader: z.string().max(255).optional(),
  receiptFooter: z.string().max(255).optional(),
});

orgRouter.patch(
  '/businesses/current',
  requirePermission(PERMISSIONS.BUSINESS_MANAGE, PERMISSIONS.SETTINGS_MANAGE),
  validate(brandingBody),
  auditAction('business.update', 'business'),
  async (req, res, next) => {
    try {
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof brandingBody>;
      await execute(
        `UPDATE businesses
         SET name = COALESCE(?, name),
             logo_url = COALESCE(?, logo_url),
             primary_color = COALESCE(?, primary_color),
             secondary_color = COALESCE(?, secondary_color),
             address = COALESCE(?, address),
             phone = COALESCE(?, phone),
             currency_code = COALESCE(?, currency_code),
             tax_rate = COALESCE(?, tax_rate),
             receipt_header = COALESCE(?, receipt_header),
             receipt_footer = COALESCE(?, receipt_footer)
         WHERE id = ?`,
        [
          body.name ?? null,
          body.logoUrl ?? null,
          body.primaryColor ?? null,
          body.secondaryColor ?? null,
          body.address ?? null,
          body.phone ?? null,
          body.currencyCode ?? null,
          body.taxRate ?? null,
          body.receiptHeader ?? null,
          body.receiptFooter ?? null,
          businessId,
        ],
      );
      const rows = await query('SELECT * FROM businesses WHERE id = ?', [businessId]);
      ok(res, rows[0]);
    } catch (error) {
      next(error);
    }
  },
);

orgRouter.get('/branches', requirePermission(PERMISSIONS.CATALOG_READ, PERMISSIONS.ORDERS_CREATE, PERMISSIONS.BRANCH_MANAGE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const rows = await query(
      'SELECT * FROM branches WHERE business_id = ? ORDER BY name',
      [businessId],
    );
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});

orgRouter.post(
  '/branches',
  requirePermission(PERMISSIONS.BRANCH_MANAGE),
  validate(branchBody),
  auditAction('branch.create', 'branch'),
  async (req, res, next) => {
    try {
      const businessId = resolveBusinessId(req);
      const body = req.body as z.infer<typeof branchBody>;
      const id = newId();
      await execute(
        `INSERT INTO branches (id, business_id, name, code, address, phone, timezone)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [id, businessId, body.name, body.code.toUpperCase(), body.address ?? null, body.phone ?? null, body.timezone ?? 'Asia/Karachi'],
      );
      const rows = await query('SELECT * FROM branches WHERE id = ?', [id]);
      created(res, rows[0]);
    } catch (error) {
      next(error);
    }
  },
);

orgRouter.get('/users', requirePermission(PERMISSIONS.USERS_MANAGE, PERMISSIONS.BUSINESS_MANAGE), async (req, res, next) => {
  try {
    const businessId = resolveBusinessId(req);
    const rows = await query(
      `SELECT u.id, u.name, u.email, u.phone, u.status, u.branch_id, r.slug AS role, b.name AS branch_name
       FROM users u
       INNER JOIN roles r ON r.id = u.role_id
       LEFT JOIN branches b ON b.id = u.branch_id
       WHERE u.business_id = ?
       ORDER BY u.name`,
      [businessId],
    );
    ok(res, rows);
  } catch (error) {
    next(error);
  }
});
