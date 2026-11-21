import { createPassflow } from '@passflow/tanstack-react-start';
import { createServerFn } from '@tanstack/react-start';

// Reads PASSFLOW_ISSUER, PASSFLOW_CLIENT_ID, PASSFLOW_CLIENT_SECRET, PASSFLOW_SECRET and APP_BASE_URL on first use.
export const passflow = createPassflow();

// The signed-in user, or null. For a page that shows the user when there is one.
export const getUser = createServerFn().handler(async () => (await passflow.getSession())?.user ?? null);

// The signed-in user. Signed out, it redirects to sign-in, which returns to `returnTo`. For a route guard: pass the
// router's location.href, because inside a server function the request is the server function's own.
export const requireUser = createServerFn()
  .validator((data: { returnTo: string }) => data)
  .handler(async ({ data }) => (await passflow.requireSession({ returnTo: data.returnTo })).user);
