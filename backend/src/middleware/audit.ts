import type { NextFunction, Request, Response } from 'express';
import { newId } from '../utils/ids';
import { execute } from '../database/pool';
import { logger } from '../config/logger';

export function auditAction(action: string, entityType: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    res.on('finish', () => {
      if (res.statusCode >= 400 || !req.auth) {
        return;
      }
      const entityId =
        typeof req.params['id'] === 'string'
          ? req.params['id']
          : typeof req.body?.id === 'string'
            ? req.body.id
            : null;
      execute(
        `INSERT INTO audit_logs (id, business_id, user_id, action, entity_type, entity_id, metadata, ip_address)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          newId(),
          req.auth.businessId,
          req.auth.userId,
          action,
          entityType,
          entityId,
          JSON.stringify({ method: req.method, path: req.originalUrl }),
          req.ip ?? null,
        ],
      ).catch((error: unknown) => {
        logger.error({ err: error }, 'Failed to write audit log');
      });
    });
    next();
  };
}
