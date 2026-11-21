import cors from '@fastify/cors';
import { exposeChallengeHeader } from '@passflow/node/fastify';
import type { FastifyInstance } from 'fastify';
import { appOrigin } from './passflow.js';

// For an API that already depends on @fastify/cors and registers no CORS yet: `await passflowCors(app)` before
// passflowPlugin, so a preflight never reaches authentication and a 401 still carries the CORS headers. Only
// the SPA's origin is allowed; exposeChallengeHeader adds WWW-Authenticate to the exposed headers.
export async function passflowCors(app: FastifyInstance): Promise<void> {
  await app.register(cors, exposeChallengeHeader({ origin: appOrigin }));
}
