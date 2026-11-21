import { getAuth, passflowFastify } from '@passflow/node/fastify';
import type { FastifyInstance } from 'fastify';
import { verifier } from './passflow.js';

// `await passflowPlugin(app)`, after CORS. Decorates the instance with app.passflow: authenticate,
// requireACR(level) and requireFresh(seconds). It registers no hook, so each route that returns or changes
// private data opts in with a preHandler. Register it once per instance.
export async function passflowPlugin(app: FastifyInstance): Promise<void> {
  await app.register(passflowFastify, { verifier });

  app.get('/api/me', { preHandler: app.passflow.authenticate }, async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    return { sub: getAuth(request).sub };
  });
}
