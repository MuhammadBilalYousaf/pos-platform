export class AppError extends Error {
  readonly statusCode: number;
  readonly code: string;
  readonly details?: unknown;

  constructor(statusCode: number, code: string, message: string, details?: unknown) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

export function publicErrorMessage(error: unknown): { statusCode: number; code: string; message: string } {
  if (error instanceof AppError) {
    return { statusCode: error.statusCode, code: error.code, message: error.message };
  }
  return {
    statusCode: 500,
    code: 'INTERNAL_ERROR',
    message: 'Something went wrong. Please try again.',
  };
}
