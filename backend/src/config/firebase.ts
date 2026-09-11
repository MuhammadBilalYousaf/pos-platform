import { existsSync, readFileSync } from 'node:fs';
import admin from 'firebase-admin';
import { env } from './env';
import { logger } from './logger';

let initialized = false;

export function firebaseEnabled(): boolean {
  return Boolean(
    env.FIREBASE_SERVICE_ACCOUNT_PATH ||
      (env.FIREBASE_PROJECT_ID && env.FIREBASE_CLIENT_EMAIL && env.FIREBASE_PRIVATE_KEY),
  );
}

export function initFirebase(): void {
  if (initialized || admin.apps.length > 0) {
    initialized = true;
    return;
  }
  if (!firebaseEnabled()) {
    logger.warn('Firebase Admin is not configured. Authentication will reject tokens until it is.');
    return;
  }

  if (env.FIREBASE_SERVICE_ACCOUNT_PATH) {
    if (!existsSync(env.FIREBASE_SERVICE_ACCOUNT_PATH)) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT_PATH does not exist');
    }
    const raw = JSON.parse(readFileSync(env.FIREBASE_SERVICE_ACCOUNT_PATH, 'utf8')) as admin.ServiceAccount;
    admin.initializeApp({ credential: admin.credential.cert(raw) });
  } else {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: env.FIREBASE_PROJECT_ID,
        clientEmail: env.FIREBASE_CLIENT_EMAIL,
        privateKey: env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
      }),
    });
  }
  initialized = true;
  logger.info('Firebase Admin initialized');
}

export async function verifyFirebaseToken(idToken: string): Promise<{ uid: string; email?: string }> {
  if (!firebaseEnabled()) {
    throw new Error('FIREBASE_NOT_CONFIGURED');
  }
  const decoded = await admin.auth().verifyIdToken(idToken);
  return { uid: decoded.uid, email: decoded.email };
}
