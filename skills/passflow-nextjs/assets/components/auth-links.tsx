import { passflow } from '@/lib/passflow';

// Plain <a href>, never <Link>: a prefetching link would run sign-in or sign-out before anyone clicks.
// It reads the session, so render it inside <Suspense>.
export async function AuthLinks({ returnTo = '/' }: { returnTo?: string }) {
  const session = await passflow.getSession();
  if (session === null) {
    return <a href={`/auth/login?returnTo=${encodeURIComponent(returnTo)}`}>Sign in</a>;
  }
  return <a href="/auth/logout">Sign out</a>;
}
