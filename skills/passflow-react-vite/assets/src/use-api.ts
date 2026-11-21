import { type FetchLike, usePassflow } from '@passflow/react';
import { useMemo } from 'react';

// The API's origin as the browser calls it, for example http://localhost:8086 or https://api.example.com.
const apiBase: string | undefined = import.meta.env.VITE_API_URL;
if (!apiBase) {
  throw new Error('VITE_API_URL must be set in .env.local');
}
const apiRoot = apiBase.replace(/\/+$/, '');
const apiOrigin = new URL(apiRoot).origin;

// The full URL of an API path: apiUrl('/api/me').
export function apiUrl(path: string): string {
  return `${apiRoot}${path}`;
}

// A fetch for the API. It adds `Authorization: Bearer <access token>` to requests for VITE_API_URL's origin
// (and the page's own origin) only, and refreshes an expired token first. Requests to any other origin, and
// requests made while signed out, go out without a token. Never add the header by hand.
export function useApi(): FetchLike {
  const passflow = usePassflow();
  return useMemo(() => passflow.withAuth(fetch, { origins: [apiOrigin] }), [passflow]);
}
