import { passflow } from './passflow';

// Server code that calls an API as the signed-in user. The access token goes from this server to the API and
// nowhere else: return the API's data, never the token. Call it only inside a server function's handler or a
// server route, with a URL the app chose; never pass a URL from the browser. The API verifies the token itself.
export async function fetchAsUser(url: string, init: RequestInit = {}): Promise<Response | null> {
  const token = await passflow.getAccessToken();
  if (token === null) {
    return null;
  }
  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${token}`);
  return fetch(url, { ...init, headers });
}
