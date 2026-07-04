import { STORAGE_KEY } from "./constants.js";

/** @typedef {{ id: string, content: string, order: number, createdAt: string }} Note */

/**
 * @param {import('/static/anna-apps/_sdk/latest/index.js').AnnaAppRuntime | null} anna
 */
export async function loadNotes(anna) {
  if (!anna) return [];
  const { value } = await anna.storage.get({ key: STORAGE_KEY });
  if (!Array.isArray(value)) return [];
  return value.slice().sort((a, b) => a.order - b.order);
}

/**
 * @param {import('/static/anna-apps/_sdk/latest/index.js').AnnaAppRuntime | null} anna
 * @param {Note[]} notes
 */
export async function saveNotes(anna, notes) {
  if (!anna) throw new Error("Anna runtime not connected");
  await anna.storage.set({ key: STORAGE_KEY, value: notes });
}

/**
 * @param {import('/static/anna-apps/_sdk/latest/index.js').AnnaAppRuntime | null} anna
 * @param {string} content
 * @param {Note[]} current
 */
export async function addNote(anna, content, current) {
  const trimmed = content.trim();
  if (!trimmed) return current;

  const nextOrder =
    current.length === 0 ? 1 : Math.max(...current.map((n) => n.order)) + 1;

  const note = {
    id: crypto.randomUUID(),
    content: trimmed,
    order: nextOrder,
    createdAt: new Date().toISOString(),
  };

  const updated = [...current, note];
  await saveNotes(anna, updated);
  return updated;
}

/**
 * @param {import('/static/anna-apps/_sdk/latest/index.js').AnnaAppRuntime | null} anna
 * @param {string} id
 * @param {Note[]} current
 */
export async function deleteNote(anna, id, current) {
  const updated = current.filter((n) => n.id !== id);
  await saveNotes(anna, updated);
  return updated;
}
