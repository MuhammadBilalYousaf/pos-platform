import type { NextFunction, Request, Response } from 'express';
import { firebaseEnabled, verifyFirebaseToken } from '../config/firebase';
import { query } from '../database/pool';
import { AppError } from '../utils/appError';
import type { AuthContext } from '../modules/auth/auth.types';
import { ROLE_SLUGS } from '../modules/auth/auth.types';

interface UserRow {
  id: string;
  firebase_uid: string;
  business_id: string | null;
  branch_id: string | null;
  role_id: string;
  name: string;
  email: string;
  status: string;
  role_slug: string;
}

export async function authenticate(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new AppError(401, 'UNAUTHENTICATED', 'Sign in is required.');
    }
    if (!firebaseEnabled()) {
      throw new AppError(503, 'AUTH_UNAVAILABLE', 'Authentication is not configured on the server.');
    }

    const token = header.slice(7);
    let uid: string;
    try {
      const decoded = await verifyFirebaseToken(token);
      uid = decoded.uid;
    } catch (error) {
      if (error instanceof Error && error.message === 'FIREBASE_NOT_CONFIGURED') {
        throw new AppError(503, 'AUTH_UNAVAILABLE', 'Authentication is not configured on the server.');
      }
      throw new AppError(401, 'INVALID_TOKEN', 'Your session is not valid. Please sign in again.');
    }

    const users = await query<UserRow>(
      `SELECT u.id, u.firebase_uid, u.business_id, u.branch_id, u.role_id, u.name, u.email, u.status, r.slug AS role_slug
       FROM users u
       INNER JOIN roles r ON r.id = u.role_id
       WHERE u.firebase_uid = ?
       LIMIT 1`,
      [uid],
    );
    const user = users[0];
    if (!user) {
      throw new AppError(403, 'USER_NOT_PROVISIONED', 'This account is not set up in the POS.');
    }
    if (user.status !== 'ACTIVE') {
      throw new AppError(403, 'USER_DISABLED', 'This account is disabled.');
    }

    const permissionRows = await query<{ code: string }>(
      `SELECT p.code
       FROM role_permissions rp
       INNER JOIN permissions p ON p.id = rp.permission_id
       WHERE rp.role_id = ?`,
      [user.role_id],
    );

    const auth: AuthContext = {
      firebaseUid: user.firebase_uid,
      userId: user.id,
      businessId: user.business_id,
      branchId: user.branch_id,
      roleId: user.role_id,
      roleSlug: user.role_slug,
      permissions: permissionRows.map((row) => row.code),
      name: user.name,
      email: user.email,
    };
    req.auth = auth;
    next();
  } catch (error) {
    next(error);
  }
}

export function requireAuth(req: Request): AuthContext {
  if (!req.auth) {
    throw new AppError(401, 'UNAUTHENTICATED', 'Sign in is required.');
  }
  return req.auth;
}

export function requirePermission(...codes: string[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    try {
      const auth = requireAuth(req);
      const allowed = codes.some((code) => auth.permissions.includes(code));
      if (!allowed) {
        throw new AppError(403, 'FORBIDDEN', 'You do not have permission to perform this action.');
      }
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireBusiness(auth: AuthContext): string {
  if (auth.roleSlug === ROLE_SLUGS.PLATFORM_SUPER_ADMIN) {
    throw new AppError(400, 'BUSINESS_CONTEXT_REQUIRED', 'Select a business first.');
  }
  if (!auth.businessId) {
    throw new AppError(400, 'BUSINESS_CONTEXT_REQUIRED', 'This account is not assigned to a business.');
  }
  return auth.businessId;
}

export function resolveBusinessId(req: Request): string {
  const auth = requireAuth(req);
  if (auth.roleSlug === ROLE_SLUGS.PLATFORM_SUPER_ADMIN) {
    const header = req.header('x-business-id');
    if (!header) {
      throw new AppError(400, 'BUSINESS_CONTEXT_REQUIRED', 'Select a business first.');
    }
    return header;
  }
  return requireBusiness(auth);
}

export function resolveBranchId(req: Request, requested?: string): string {
  const auth = requireAuth(req);
  const businessId = resolveBusinessId(req);

  if (auth.roleSlug === ROLE_SLUGS.CASHIER || auth.roleSlug === ROLE_SLUGS.BRANCH_MANAGER) {
    if (!auth.branchId) {
      throw new AppError(400, 'BRANCH_CONTEXT_REQUIRED', 'This account is not assigned to a branch.');
    }
    if (requested && requested !== auth.branchId) {
      throw new AppError(403, 'FORBIDDEN', 'You do not have permission to perform this action.');
    }
    return auth.branchId;
  }

  const branchId = requested ?? auth.branchId ?? undefined;
  if (!branchId) {
    throw new AppError(400, 'BRANCH_CONTEXT_REQUIRED', 'Select a branch first.');
  }
  void businessId;
  return branchId;
}
