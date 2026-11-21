import { exposeChallengeHeader } from '@passflow/node/express';
import cors from 'cors';
import type { RequestHandler } from 'express';
import { appOrigin } from './passflow.js';

// For an API that already depends on cors and mounts no CORS middleware yet: `app.use(passflowCors)` before
// every route, so a preflight never reaches authentication and a 401 still carries the CORS headers. Only the
// SPA's origin is allowed; exposeChallengeHeader adds WWW-Authenticate to the exposed headers.
export const passflowCors: RequestHandler = cors(exposeChallengeHeader({ origin: appOrigin }));
