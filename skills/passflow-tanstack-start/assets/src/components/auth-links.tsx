import type { PassflowUser } from '@passflow/tanstack-react-start';

// Plain <a href>, never <Link>: a preloading link would run sign-in or sign-out before anyone clicks, and the
// router doesn't know these routes. Sign-in returns to `returnTo`, a path on this app.
export function AuthLinks({ user, returnTo = '/' }: { user: PassflowUser | null; returnTo?: string }) {
  if (user === null) {
    return <a href={`/auth/login?returnTo=${encodeURIComponent(returnTo)}`}>Sign in</a>;
  }
  return <a href="/auth/logout">Sign out</a>;
}
