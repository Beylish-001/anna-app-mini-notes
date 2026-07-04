import { AnnaAppRuntime } from "/static/anna-apps/_sdk/latest/index.js";
import { TOOL_ID, TOOL_METHOD } from "./constants.js";
import { addNote, deleteNote, loadNotes } from "./notes.js";

const $ = (sel) => document.querySelector(sel);

const els = {
  input: $("#note-input"),
  saveBtn: $("#save-btn"),
  summarizeBtn: $("#summarize-btn"),
  summaryOutput: $("#summary-output"),
  summaryError: $("#summary-error"),
  notesList: $("#notes-list"),
  emptyState: $("#empty-state"),
  connStatus: $("#conn-status"),
};

/** @type {import('/static/anna-apps/_sdk/latest/index.js').AnnaAppRuntime | null} */
let anna = null;
/** @type {import('./notes.js').Note[] | null} */
let notes = [];

function setConn(connected) {
  els.connStatus.textContent = connected ? "Anna connected" : "standalone preview";
  els.connStatus.classList.toggle("connected", connected);
}

function renderNotes() {
  els.notesList.innerHTML = "";
  const list = notes ?? [];

  if (list.length === 0) {
    els.emptyState.hidden = false;
    return;
  }

  els.emptyState.hidden = true;

  for (const note of list) {
    const li = document.createElement("li");
    li.className = "note-item";

    const meta = document.createElement("div");
    meta.className = "note-meta";
    meta.textContent = `#${note.order} · ${new Date(note.createdAt).toLocaleString()}`;

    const body = document.createElement("p");
    body.className = "note-content";
    body.textContent = note.content;

    const delBtn = document.createElement("button");
    delBtn.type = "button";
    delBtn.className = "delete-btn";
    delBtn.textContent = "删除";
    delBtn.addEventListener("click", () => onDelete(note.id));

    li.append(meta, body, delBtn);
    els.notesList.appendChild(li);
  }
}

function clearSummary() {
  els.summaryOutput.hidden = true;
  els.summaryOutput.textContent = "";
  els.summaryError.hidden = true;
  els.summaryError.textContent = "";
}

function showSummary(text) {
  els.summaryOutput.textContent = text;
  els.summaryOutput.hidden = false;
  els.summaryError.hidden = true;
}

function showSummaryError(message) {
  els.summaryError.textContent = message;
  els.summaryError.hidden = false;
}

async function refreshNotes() {
  if (!anna) return;
  notes = await loadNotes(anna);
  renderNotes();
}

async function onSave() {
  if (!anna) return;
  const text = els.input.value;
  if (!text.trim()) return;

  try {
    notes = await addNote(anna, text, notes ?? []);
    els.input.value = "";
    renderNotes();
    clearSummary();
  } catch (err) {
    showSummaryError(err?.message || String(err));
  }
}

async function onDelete(id) {
  if (!anna) return;
  try {
    notes = await deleteNote(anna, id, notes ?? []);
    renderNotes();
    clearSummary();
  } catch (err) {
    showSummaryError(err?.message || String(err));
  }
}

async function onSummarize() {
  if (!anna) return;
  clearSummary();

  const payload = (notes ?? []).map(({ order, content }) => ({ order, content }));
  if (payload.length === 0) {
    showSummaryError("没有可总结的笔记。");
    return;
  }

  els.summarizeBtn.disabled = true;
  try {
    const result = await anna.tools.invoke({
      tool_id: TOOL_ID,
      method: TOOL_METHOD,
      args: { notes: payload },
    });

    const summary = result?.data?.summary ?? result?.summary;
    if (typeof summary === "string" && summary.trim()) {
      showSummary(summary);
    } else {
      showSummaryError("Tool 返回了空 summary。");
    }
  } catch (err) {
    showSummaryError(err?.message || String(err));
  } finally {
    els.summarizeBtn.disabled = false;
  }
}

function bindUi() {
  els.saveBtn.addEventListener("click", onSave);
  els.summarizeBtn.addEventListener("click", onSummarize);
  els.input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) onSave();
  });
}

async function init() {
  bindUi();
  renderNotes();

  try {
    anna = await AnnaAppRuntime.connect();
    setConn(true);
    await anna.window.set_title({ title: "Mini Notes" });
    await refreshNotes();
  } catch (err) {
    setConn(false);
    console.warn("[mini-notes] standalone preview:", err?.message || err);
  }
}

init();
