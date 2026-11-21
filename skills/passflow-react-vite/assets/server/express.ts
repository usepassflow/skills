import { getAuth, passflowExpress } from '@passflow/node/express';
import { Router } from 'express';
import { verifier } from './passflow.js';

// authenticate: a verified access token. requireACR(AAL2): a second factor. requireFresh(300): a recent sign-in.
export const passflow = passflowExpress(verifier);

// A protected route: `app.use(passflowRoutes)`, after CORS. Every route that returns or changes private data
// gets passflow.authenticate.
export const passflowRoutes = Router();

passflowRoutes.get('/api/me', passflow.authenticate, (req, res) => {
  res.set('Cache-Control', 'no-store').json({ sub: getAuth(req).sub });
});
