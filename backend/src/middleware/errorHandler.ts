import type { NextFunction, Request, Response } from 'express';
import { logger } from '../config/logger';
import { isProduction } from '../config/env';
import { AppError, publicErrorMessage } from '../utils/appError';

export function errorHandler(error: unknown, req: Request, res: Response, _next: NextFunction): void {
  const mapped = publicErrorMessage(error);
  const logPayload = {
    err: error,
    path: req.path,
    method: req.method,
    userId: req.auth?.userId,
    businessId: req.auth?.businessId,
  };

  if (mapped.statusCode >= 500) {
    logger.error(logPayload, 'Unhandled API error');
  } else if (!(error instanceof AppError) || error.code === 'INVALID_TOKEN') {
    logger.warn(logPayload, 'Request rejected');
  }

  res.status(mapped.statusCode).json({
    success: false,
    error: {
      code: mapped.code,
      message: mapped.message,
      ...(error instanceof AppError && error.details && !isProduction() ? { details: error.details } : {}),
    },
  });
}

export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({
    success: false,
    error: { code: 'NOT_FOUND', message: `No API route for ${req.method} ${req.path}` },
  });
}
