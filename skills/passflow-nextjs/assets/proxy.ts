import type { NextRequest } from 'next/server';
import { passflow } from './lib/passflow';

// Serves /auth/login, /auth/callback and /auth/logout, and refreshes the session. It protects nothing by itself:
// every page and route handler checks the session in its own server code.
export function proxy(request: NextRequest) {
  return passflow.proxy(request);
}

export const config = { matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'] };
