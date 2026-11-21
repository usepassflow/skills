import { AAL2 } from '@passflow/node';
import { getAuth } from '@passflow/node/express';
import type { Express } from 'express';
import { passflow } from './passflow-express.js';

// How the app's own routes take each check. Copy the line that fits a route into the app's route file.
export function protectRoutes(app: Express): void {
  // Any valid access token. Signed out or invalid: 401 with WWW-Authenticate: Bearer.
  app.get('/api/orders', passflow.authenticate, (req, res) => {
    res.set('Cache-Control', 'no-store').json({ owner: getAuth(req).sub });
  });

  // A second factor in this sign-in. Without one: 401 with acr_values="2".
  app.post('/api/payouts', passflow.requireACR(AAL2), (_req, res) => {
    res.status(204).end();
  });

  // A sign-in within the last 300 seconds. Older: 401 with max_age=300.
  app.delete('/api/account', passflow.requireFresh(300), (_req, res) => {
    res.status(204).end();
  });
}
