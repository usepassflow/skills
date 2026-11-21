'use server';

import { passflow } from '@/lib/passflow';

// Every server action that reads or changes private data starts with requireSession().
// Signed out, the rest of the action never runs and the browser goes to sign-in.
export async function saveNote(formData: FormData): Promise<void> {
  const { user } = await passflow.requireSession();

  const note = formData.get('note');
  if (typeof note !== 'string' || note.length === 0) {
    return;
  }
  await storeNote(user.sub, note);
}

// The app's own data layer goes here.
async function storeNote(userId: string, note: string): Promise<void> {
  void userId;
  void note;
}
