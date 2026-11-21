import { authenticateRequest } from '@passflow/node';
import { verifier } from './passflow.js';

// For a handler that receives a web Request and returns a Response (in Hono, `(c) => handleMe(c.req.raw)`).
// A rejection is a complete Response: 401 with WWW-Authenticate, or 503 when the key set is unavailable,
// each with Cache-Control: no-store. Return it unchanged.
export async function handleMe(request: Request): Promise<Response> {
  const result = await authenticateRequest(verifier, request);
  if ('response' in result) {
    return result.response;
  }
  return Response.json({ sub: result.claims.sub }, { headers: { 'Cache-Control': 'no-store' } });
}
