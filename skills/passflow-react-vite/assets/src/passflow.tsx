import '@passflow/react/dist/style.css';
import { LoginButton, PassflowProvider } from '@passflow/react';
import type { ReactNode } from 'react';

// Both values are public: Vite puts every VITE_ variable into the browser bundle. Nothing secret goes in VITE_.
const passflowUrl: string | undefined = import.meta.env.VITE_PASSFLOW_URL;
const passflowAppId: string | undefined = import.meta.env.VITE_PASSFLOW_APP_ID;
if (!passflowUrl || !passflowAppId) {
  throw new Error('VITE_PASSFLOW_URL and VITE_PASSFLOW_APP_ID must be set in .env.local');
}

// One Passflow client for the whole app. Wrap the root component in it, in src/main.tsx.
// `offline` is the scope that gets a refresh token, so a reload keeps the user signed in.
// `email` puts the user's email in the tokens, which is what the signed-in button shows.
export function PassflowRoot({ children }: { children: ReactNode }) {
  return (
    <PassflowProvider url={passflowUrl} appId={passflowAppId} scopes={['id', 'offline', 'openid', 'email']}>
      {children}
    </PassflowProvider>
  );
}

// Signed out it reads "Sign in" and opens the hosted sign-in; signed in it shows the user and signs out.
// Sign-in and sign-out return to the app's root URL, which is a registered redirect URL of the app.
// The button's default is the current page's URL, which is registered only when it is the root.
export function AccountButton() {
  const appRoot = new URL(import.meta.env.BASE_URL, window.location.origin).href;
  return <LoginButton authRedirectOptions={{ redirectUrl: appRoot }} postLogoutRedirectUri={appRoot} />;
}
