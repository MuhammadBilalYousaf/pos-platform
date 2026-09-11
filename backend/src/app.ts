import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import pinoHttp from 'pino-http';
import { env } from './config/env';
import { logger } from './config/logger';
import { pingDatabase } from './database/pool';
import { ok } from './utils/apiResponse';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';
import { authRouter } from './modules/auth/auth.routes';
import { orgRouter } from './modules/org/org.routes';
import { catalogRouter } from './modules/catalog/catalog.routes';
import { inventoryRouter } from './modules/inventory/inventory.routes';
import { recipesRouter } from './modules/recipes/recipes.routes';
import { ordersRouter } from './modules/orders/orders.routes';
import { reportsRouter } from './modules/reports/reports.routes';
import { syncRouter } from './modules/sync/sync.routes';
import { settingsRouter } from './modules/settings/settings.routes';

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.use(helmet());
  app.use(
    cors({
      origin: env.CORS_ORIGIN === '*' ? true : env.CORS_ORIGIN.split(',').map((value) => value.trim()),
      credentials: true,
    }),
  );
  app.use(express.json({ limit: '1mb' }));
  app.use(
    pinoHttp({
      logger,
      autoLogging: {
        ignore: (req) => req.url === `${env.API_PREFIX}/health`,
      },
    }),
  );

  const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 60,
    standardHeaders: true,
    legacyHeaders: false,
  });

  app.get(`${env.API_PREFIX}/health`, async (_req, res, next) => {
    try {
      await pingDatabase();
      ok(res, { status: 'ok', database: 'up' });
    } catch (error) {
      next(error);
    }
  });

  app.use(`${env.API_PREFIX}/auth`, authLimiter, authRouter);
  app.use(env.API_PREFIX, orgRouter);
  app.use(env.API_PREFIX, catalogRouter);
  app.use(env.API_PREFIX, inventoryRouter);
  app.use(env.API_PREFIX, recipesRouter);
  app.use(env.API_PREFIX, ordersRouter);
  app.use(env.API_PREFIX, reportsRouter);
  app.use(env.API_PREFIX, syncRouter);
  app.use(env.API_PREFIX, settingsRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
