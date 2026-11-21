import { extractBearer, isPassflowAuthError } from '@passflow/node';
import { verifier } from './passflow.js';

// Why a token is refused, for debugging only. Logs the error's code and reason, never the token or the
// header. Call it from a temporary debug route or a script, and remove it afterwards.
export async function explainRejection(authorization: string | undefined): Promise<void> {
  const token = extractBearer(authorization);
  if (token === undefined) {
    console.log('passflow: no bearer token');
    return;
  }
  try {
    await verifier.verify(token);
    console.log('passflow: token accepted');
  } catch (error) {
    if (isPassflowAuthError(error)) {
      console.log('passflow:', error.code, error.reason ?? '');
      return;
    }
    throw error;
  }
}
