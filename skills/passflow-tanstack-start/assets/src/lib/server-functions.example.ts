import { createServerFn } from '@tanstack/react-start';
import { passflow } from './passflow';

// Every server function that reads or changes private data checks the session itself: a route guard
// protects navigation, not data. Signed out, the rest of the function never runs.
export const saveNote = createServerFn({ method: 'POST' })
  .validator((data: { note: string }) => data)
  .handler(async ({ data }) => {
    const { user } = await passflow.requireSession();

    if (data.note.length === 0) return { saved: false };
    await storeNote(user.sub, data.note);
    return { saved: true };
  });

// The app's own data layer goes here.
async function storeNote(userId: string, note: string): Promise<void> {
  void userId;
  void note;
}
