import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import mysql from 'mysql2/promise';
import { env } from '../config/env';
import { logger } from '../config/logger';

async function ensureDatabase(): Promise<void> {
  const conn = await mysql.createConnection({
    host: env.MYSQL_HOST,
    port: env.MYSQL_PORT,
    user: env.MYSQL_USER,
    password: env.MYSQL_PASSWORD,
    multipleStatements: true,
  });
  try {
    await conn.query(
      `CREATE DATABASE IF NOT EXISTS \`${env.MYSQL_DATABASE}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`,
    );
  } finally {
    await conn.end();
  }
}

export async function runMigrations(): Promise<void> {
  await ensureDatabase();
  const conn = await mysql.createConnection({
    host: env.MYSQL_HOST,
    port: env.MYSQL_PORT,
    user: env.MYSQL_USER,
    password: env.MYSQL_PASSWORD,
    database: env.MYSQL_DATABASE,
    multipleStatements: true,
  });
  try {
    const dir = join(dirname(__filename), 'migrations');
    const files = readdirSync(dir)
      .filter((file) => file.endsWith('.sql'))
      .sort();
    for (const file of files) {
      const sql = readFileSync(join(dir, file), 'utf8');
      logger.info({ file }, 'Running migration');
      await conn.query(sql);
    }
    logger.info('Migrations complete');
  } finally {
    await conn.end();
  }
}

if (require.main === module) {
  runMigrations()
    .then(() => process.exit(0))
    .catch((error: unknown) => {
      logger.error({ err: error }, 'Migration failed');
      process.exit(1);
    });
}
