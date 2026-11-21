import { AAL2 } from '@passflow/node';
import { createFastifyHooks, getAuth } from '@passflow/node/fastify';
import type { FastifyInstance } from 'fastify';
import { verifier } from './passflow.js';

// How the app's own routes take each check, after passflowPlugin(app) has run. Copy the preHandler that
// fits a route into the app's route file.
export async function protectRoutes(app: FastifyInstance): Promise<void> {
  // Any valid access token. Signed out or invalid: 401 with WWW-Authenticate: Bearer.
  app.get('/api/orders', { preHandler: app.passflow.authenticate }, async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    return { owner: getAuth(request).sub };
  });

  // A second factor in this sign-in. Without one: 401 with acr_values="2".
  app.post('/api/payouts', { preHandler: app.passflow.requireACR(AAL2) }, async (_request, reply) => {
    return reply.code(204).send();
  });

  // A sign-in within the last 300 seconds. Older: 401 with max_age=300.
  app.delete('/api/account', { preHandler: app.passflow.requireFresh(300) }, async (_request, reply) => {
    return reply.code(204).send();
  });
}

// The same hooks without decorating the instance: for a plugin scope where passflowPlugin is not
// registered. passflowPlugin itself can be registered only once per instance.
export const passflowHooks = createFastifyHooks(verifier);
