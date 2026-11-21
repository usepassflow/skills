import { exposeChallengeHeader } from '@passflow/node/hono';
import type { MiddlewareHandler } from 'hono';
import { cors } from 'hono/cors';

// For an app called by a browser page on another origin; hono/cors ships with hono. Mount it before every
// route, so a preflight never reaches authentication and a 401 still carries the CORS headers. Pass the
// options the API already uses; exposeChallengeHeader adds WWW-Authenticate to the exposed headers and
// keeps the rest.
export function passflowCors(options: NonNullable<Parameters<typeof cors>[0]>): MiddlewareHandler {
  return cors(exposeChallengeHeader(options));
}
