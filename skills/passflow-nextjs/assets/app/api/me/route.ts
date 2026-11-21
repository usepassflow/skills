import { passflow } from '@/lib/passflow';

// A route handler answers 401 when signed out, never a redirect.
export async function GET() {
  const session = await passflow.getSession();
  if (session === null) {
    return passflow.unauthorized();
  }
  return Response.json({ user: session.user }, { headers: { 'Cache-Control': 'no-store' } });
}

// A handler that changes data also refuses requests from other sites.
export async function POST(request: Request) {
  if (!passflow.isSameOrigin(request)) {
    return new Response(null, { status: 403 });
  }
  const session = await passflow.getSession();
  if (session === null) {
    return passflow.unauthorized();
  }
  return new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store' } });
}
