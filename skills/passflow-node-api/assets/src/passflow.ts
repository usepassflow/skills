import { createVerifier } from '@passflow/node';

// One verifier per trust policy, built once at startup. It owns the key cache.
// PASSFLOW_ISSUER is matched exactly against the token's `iss`.
// PASSFLOW_AUDIENCE is one client ID, or several joined with commas: each is the client ID of a Passflow app
// whose access tokens this API accepts.
// A missing value throws a TypeError when this module loads.
export const verifier = createVerifier({
  issuer: process.env.PASSFLOW_ISSUER,
  audience: clientIds(process.env.PASSFLOW_AUDIENCE),
});

// Splits a comma-separated list of client IDs, trims each and drops empty entries. Nothing left counts as
// missing.
function clientIds(value: string | undefined): string[] | undefined {
  const ids = (value ?? '')
    .split(',')
    .map((id) => id.trim())
    .filter((id) => id !== '');
  return ids.length > 0 ? ids : undefined;
}
