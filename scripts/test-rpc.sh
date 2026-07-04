#!/usr/bin/env bash
# Manual JSON-RPC smoke tests for the notes-summarizer Executa plugin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT/executas/notes-summarizer"
FIXTURE="$ROOT/fixtures/sampling-mock.jsonl"

cd "$PLUGIN_DIR"

echo "== describe =="
anna-app executa dev --describe

echo
echo "== invoke with mock sampling =="
anna-app executa dev \
  --mock-sampling "$FIXTURE" \
  --invoke summarize_notes \
  --args '{"notes":[{"order":1,"content":"明天跟客户 follow up"},{"order":2,"content":"修复登录 bug"}]}'

echo
echo "Done. Check stderr for 'sampling/createMessage' evidence in verbose logs."
