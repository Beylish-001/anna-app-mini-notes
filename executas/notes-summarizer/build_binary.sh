#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TOOL_ID="tool-test-notes-summarizer-12345678"
VERSION="1.0.0"
SDK_PATH="$SCRIPT_DIR/../../sdk/python"
RUN_TEST=false
PACKAGE=false

for arg in "$@"; do
  case "$arg" in
    --test) RUN_TEST=true ;;
    --package) PACKAGE=true ;;
  esac
done

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="arm64" ;;
  esac
  if [[ "$os" == "darwin" ]]; then
    echo "darwin-${arch}"
  elif [[ "$os" == "linux" ]]; then
    if [[ "$arch" == "arm64" ]]; then echo "linux-aarch64"; else echo "linux-x86_64"; fi
  else
    echo "windows-x86_64"
  fi
}

echo "Building Notes Summarizer binary..."
rm -rf dist build
mkdir -p dist

PYTHONPATH="$SDK_PATH" pyinstaller \
  --onefile \
  --name "$TOOL_ID" \
  --clean \
  --noupx \
  --hidden-import executa_sdk \
  --hidden-import executa_sdk.sampling \
  --paths "$SDK_PATH" \
  notes_summarizer.py

PLATFORM="$(detect_platform)"
if [[ "$PLATFORM" == windows-* ]]; then
  BINARY="dist/${TOOL_ID}.exe"
else
  BINARY="dist/${TOOL_ID}"
fi

if [[ ! -f "$BINARY" ]]; then
  echo "Build failed: $BINARY not found" >&2
  exit 1
fi

echo "Built $BINARY ($PLATFORM)"

if [[ "$RUN_TEST" == "true" ]]; then
  echo '{"jsonrpc":"2.0","method":"describe","id":1}' | "$BINARY" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); assert d['result']['name']=='$TOOL_ID'; print('describe smoke test passed')"
fi

if [[ "$PACKAGE" == "true" ]]; then
  mkdir -p dist/packages
  STAGE="dist/stage-$PLATFORM"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp "$BINARY" "$STAGE/$(basename "$BINARY")"
  cat > "$STAGE/manifest.json" <<EOF
{
  "name": "$TOOL_ID",
  "version": "$VERSION",
  "runtime": {
    "binary": {
      "entrypoint": {
        "default": "$(basename "$BINARY")",
        "windows-x86_64": "${TOOL_ID}.exe"
      },
      "permissions": {
        "$(basename "$BINARY")": "0o755"
      }
    }
  }
}
EOF
  ARCHIVE="dist/packages/${TOOL_ID}-${PLATFORM}"
  if [[ "$PLATFORM" == windows-* ]]; then
    (cd "$STAGE" && zip -r "../packages/${TOOL_ID}-${PLATFORM}.zip" .)
  else
    tar -czf "${ARCHIVE}.tar.gz" -C "$STAGE" .
  fi
  echo "Package written to dist/packages/"
fi

echo "Done."
