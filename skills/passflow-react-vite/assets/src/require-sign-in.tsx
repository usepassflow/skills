import { PassflowEvent, type PassflowSubscriber, useAuth, usePassflow } from '@passflow/react';
import { type ReactNode, useEffect, useState } from 'react';
import { AccountButton } from './passflow';

// True when this page load is the return from the hosted sign-in: the SDK is still redeeming the code.
function isSignInReturn(): boolean {
  const params = new URLSearchParams(window.location.search);
  return params.has('code') && (params.has('state') || params.has('user_state'));
}

// Hides its children from a signed-out user. It renders nothing until the first session check ends,
// then the children when a user is signed in, else the sign-in button.
// This only hides a page. The API checks the token on every protected route; that is what protects data.
export function RequireSignIn({ children }: { children: ReactNode }) {
  const passflow = usePassflow();
  const { isSignedIn, isLoading } = useAuth();
  const [returning, setReturning] = useState(isSignInReturn);

  useEffect(() => {
    if (!returning) return;
    const subscriber: PassflowSubscriber = { onAuthChange: () => setReturning(false) };
    passflow.subscribe(subscriber, [PassflowEvent.SignIn, PassflowEvent.Error]);
    // A code that is not a Passflow sign-in return gets no event: stop waiting after a while.
    const timer = setTimeout(() => setReturning(false), 15_000);
    return () => {
      clearTimeout(timer);
      passflow.unsubscribe(subscriber);
    };
  }, [passflow, returning]);

  if (isLoading || (returning && !isSignedIn)) {
    return null;
  }
  return isSignedIn ? <>{children}</> : <AccountButton />;
}
