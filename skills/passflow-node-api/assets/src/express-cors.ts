import { exposeChallengeHeader } from '@passflow/node/express';
import cors, { type CorsOptions } from 'cors';
import type { RequestHandler } from 'express';

// For an app that already depends on cors and is called by a browser page on another origin. Mount it
// before every route, so a preflight never reaches authentication and a 401 still carries the CORS
// headers. Pass the options the API already uses; exposeChallengeHeader adds WWW-Authenticate to the
// exposed headers and keeps the rest.
export function passflowCors(options: CorsOptions): RequestHandler {
  return cors(exposeChallengeHeader(options));
}
