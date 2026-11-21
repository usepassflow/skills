import cors, { type FastifyCorsOptions } from '@fastify/cors';
import { exposeChallengeHeader } from '@passflow/node/fastify';
import type { FastifyInstance } from 'fastify';

// For an app that already depends on @fastify/cors and is called by a browser page on another origin.
// Register it before passflowPlugin, so a preflight never reaches authentication and a 401 still carries
// the CORS headers. Pass the options the API already uses; exposeChallengeHeader adds WWW-Authenticate to
// the exposed headers and keeps the rest.
export async function passflowCors(app: FastifyInstance, options: FastifyCorsOptions): Promise<void> {
  await app.register(cors, exposeChallengeHeader(options));
}
