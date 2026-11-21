import { createVerifier } from '@passflow/node';

// One verifier per trust policy, built once at startup. It owns the key cache.
// PASSFLOW_ISSUER is matched exactly against the token's `iss`; it is the same URL as VITE_PASSFLOW_URL.
// PASSFLOW_AUDIENCE is the SPA app's client ID, the same value as VITE_PASSFLOW_APP_ID: the access tokens the
// SPA sends carry aud = [app ID].
// A missing value throws a TypeError when this module loads.
export const verifier = createVerifier({
  issuer: process.env.PASSFLOW_ISSUER,
  audience: process.env.PASSFLOW_AUDIENCE,
});

// The SPA's origin, the one origin the API's CORS allows. APP_BASE_URL is the SPA's URL, for example
// http://localhost:5173.
const appBaseUrl = process.env.APP_BASE_URL;
if (!appBaseUrl) {
  throw new TypeError('[passflow] APP_BASE_URL must be set to the SPA URL');
}
export const appOrigin = new URL(appBaseUrl).origin;
