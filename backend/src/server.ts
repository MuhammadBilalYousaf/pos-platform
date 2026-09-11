import { env } from './config/env';
import { initFirebase } from './config/firebase';
import { logger } from './config/logger';
import { createApp } from './app';

initFirebase();

const app = createApp();

app.listen(env.PORT, () => {
  logger.info({ port: env.PORT, prefix: env.API_PREFIX }, 'POS API listening');
});
