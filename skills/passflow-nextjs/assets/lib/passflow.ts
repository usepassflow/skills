import { createPassflow } from '@passflow/nextjs';

// Reads PASSFLOW_ISSUER, PASSFLOW_CLIENT_ID, PASSFLOW_CLIENT_SECRET, PASSFLOW_SECRET and APP_BASE_URL on first use.
export const passflow = createPassflow();
