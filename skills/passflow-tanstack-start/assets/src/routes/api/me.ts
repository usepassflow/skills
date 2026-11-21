import { createFileRoute } from '@tanstack/react-router';
import { passflow } from '../../lib/passflow';

export const Route = createFileRoute('/api/me')({
  server: {
    handlers: {
      // A server route answers 401 when signed out, never a redirect.
      GET: async () => {
        const session = await passflow.getSession();
        if (session === null) {
          return passflow.unauthorized();
        }
        return Response.json({ user: session.user }, { headers: { 'Cache-Control': 'no-store' } });
      },
      // A request from another site that carries a cookie never gets here: the middleware answers 403.
      POST: async () => {
        const session = await passflow.getSession();
        if (session === null) {
          return passflow.unauthorized();
        }
        return new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store' } });
      },
    },
  },
});
