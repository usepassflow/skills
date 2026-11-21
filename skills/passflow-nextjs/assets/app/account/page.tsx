import { Suspense } from 'react';
import { AuthLinks } from '@/components/auth-links';
import { passflow } from '@/lib/passflow';

// The page shell is public. Everything that needs a signed-in user renders under <Account>, which checks the
// session first.
export default function AccountPage() {
  return (
    <main>
      <h1>Account</h1>
      <Suspense fallback={<p>Loading…</p>}>
        <Account />
      </Suspense>
    </main>
  );
}

async function Account() {
  // Signed out, this redirects to sign-in, which returns to this page.
  const { user } = await passflow.requireSession();
  return (
    <section data-passflow-protected>
      <p>
        Signed in as <span data-passflow-email>{user.email}</span>
      </p>
      <AuthLinks />
    </section>
  );
}
