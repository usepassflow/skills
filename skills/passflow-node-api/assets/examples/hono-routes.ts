import { AAL2 } from '@passflow/node';
import { getAuth } from '@passflow/node/hono';
import type { Hono } from 'hono';
import { type PassflowEnv, passflow } from './passflow-hono.js';

// How the app's own routes take each check. Copy the line that fits a route into the app's route file.
export function protectRoutes(app: Hono<PassflowEnv>): void {
  // Any valid access token. Signed out or invalid: 401 with WWW-Authenticate: Bearer.
  app.get('/api/orders', passflow.authenticate, (c) => {
    c.header('Cache-Control', 'no-store');
    return c.json({ owner: getAuth(c).sub });
  });

  // A second factor in this sign-in. Without one: 401 with acr_values="2".
  app.post('/api/payouts', passflow.requireACR(AAL2), (c) => c.body(null, 204));

  // A sign-in within the last 300 seconds. Older: 401 with max_age=300.
  app.delete('/api/account', passflow.requireFresh(300), (c) => c.body(null, 204));
}
