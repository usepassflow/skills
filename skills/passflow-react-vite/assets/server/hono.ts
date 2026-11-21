import { getAuth, type PassflowVariables, passflowHono } from '@passflow/node/hono';
import { Hono } from 'hono';
import { verifier } from './passflow.js';

export type PassflowEnv = { Variables: PassflowVariables };

// authenticate: a verified access token. requireACR(AAL2): a second factor. requireFresh(300): a recent sign-in.
export const passflow = passflowHono(verifier);

// A protected route: `app.route('/', passflowRoutes)`, after CORS. Every route that returns or changes private
// data gets passflow.authenticate.
export const passflowRoutes = new Hono<PassflowEnv>();

passflowRoutes.get('/api/me', passflow.authenticate, (c) => {
  c.header('Cache-Control', 'no-store');
  return c.json({ sub: getAuth(c).sub });
});
