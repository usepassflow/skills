import { createFileRoute } from '@tanstack/react-router';
import { AuthLinks } from '../components/auth-links';
import { requireUser } from '../lib/passflow';

export const Route = createFileRoute('/account')({
  // The guard runs on the server for a page load and in the browser for a link click, so it calls a server
  // function. Signed out, it redirects to sign-in, which returns to this page.
  beforeLoad: async ({ location }) => ({ user: await requireUser({ data: { returnTo: location.href } }) }),
  component: Account,
});

function Account() {
  const { user } = Route.useRouteContext();
  return (
    <main>
      <h1>Account</h1>
      <section data-passflow-protected>
        <p>
          Signed in as <span data-passflow-email>{user.email}</span>
        </p>
        <AuthLinks user={user} />
      </section>
    </main>
  );
}
