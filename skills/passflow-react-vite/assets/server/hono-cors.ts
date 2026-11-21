import { exposeChallengeHeader } from '@passflow/node/hono';
import { cors } from 'hono/cors';
import { appOrigin } from './passflow.js';

// For an API that mounts no CORS middleware yet (hono/cors ships with hono): `app.use(passflowCors)` before
// every route, so a preflight never reaches authentication and a 401 still carries the CORS headers. Only the
// SPA's origin is allowed; exposeChallengeHeader adds WWW-Authenticate to the exposed headers.
export const passflowCors = cors(exposeChallengeHeader({ origin: appOrigin }));
