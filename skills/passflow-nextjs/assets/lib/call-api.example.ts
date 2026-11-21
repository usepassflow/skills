import { passflow } from '@/lib/passflow';

// Server code that calls an API as the signed-in user. The access token goes from this server to the API and
// nowhere else: return the API's data, never the token. Call it from a server component, a server action or a
// route handler with a URL the app chose; never mark this file 'use server', which would let the browser pick
// the URL. The API verifies the token itself.
export async function fetchAsUser(url: string, init: RequestInit = {}): Promise<Response | null> {
  const token = await passflow.getAccessToken();
  if (token === null) {
    return null;
  }
  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${token}`);
  return fetch(url, { ...init, headers, cache: 'no-store' });
}
