import { createVerifier } from '@passflow/node';

// One verifier per trust policy, built once at startup. It owns the key cache.
// PASSFLOW_ISSUER is matched exactly against the token's `iss`.
// PASSFLOW_AUDIENCE is the client ID of the Passflow app whose access tokens this API accepts.
// A missing value throws a TypeError when this module loads.
export const verifier = createVerifier({
  issuer: process.env.PASSFLOW_ISSUER,
  audience: process.env.PASSFLOW_AUDIENCE,
});
