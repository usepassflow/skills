import { createCsrfMiddleware, createStart } from '@tanstack/react-start';
import { passflow } from './lib/passflow';

export const startInstance = createStart(() => ({
  requestMiddleware: [
    // Start's own check that a server function call comes from this site. It is off once requestMiddleware is
    // set, so it is listed here again.
    createCsrfMiddleware({ filter: (ctx) => ctx.handlerType === 'serverFn' }),
    // Serves /auth/login, /auth/callback and /auth/logout, refreshes the session, and refuses a request from
    // another site that changes data and carries a cookie. It protects no page by itself: every route guard,
    // server function and server route checks the session.
    passflow.middleware(),
  ],
}));
