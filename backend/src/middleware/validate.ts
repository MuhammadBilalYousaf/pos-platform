import type { NextFunction, Request, Response } from 'express';
import { ZodError, type ZodType } from 'zod';
import { AppError } from '../utils/appError';

export function validate(schema: ZodType, source: 'body' | 'query' | 'params' = 'body') {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const parsed = schema.safeParse(req[source]);
    if (!parsed.success) {
      next(toValidationError(parsed.error));
      return;
    }
    req[source] = parsed.data;
    next();
  };
}

export function toValidationError(error: ZodError): AppError {
  return new AppError(400, 'VALIDATION_ERROR', 'Please check the submitted information.', {
    issues: error.issues.map((issue) => ({ path: issue.path.join('.'), message: issue.message })),
  });
}
