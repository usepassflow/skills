import { createVerifier } from '@passflow/node';

// One verifier per trust policy, built once at startup. It owns the key cache.
// PASSFLOW_ISSUER is matched exactly against the token's `iss`; it is the same URL as VITE_PASSFLOW_URL.
// PASSFLOW_AUDIENCE is the SPA app's client ID, the same value as VITE_PASSFLOW_APP_ID: the access tokens the
// SPA sends carry aud = [app ID]. When the API also accepts the tokens of other Passflow apps, it is a
// comma-separated list of client IDs that includes the SPA's.
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

// The SPA's origin, the one origin the API's CORS allows. APP_BASE_URL is the SPA's URL, for example
// http://localhost:5173.
const appBaseUrl = process.env.APP_BASE_URL;
if (!appBaseUrl) {
  throw new TypeError('[passflow] APP_BASE_URL must be set to the SPA URL');
}
export const appOrigin = new URL(appBaseUrl).origin;
