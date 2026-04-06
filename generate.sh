#!/usr/bin/env bash
# generate.sh — Generate trail.json for any GitHub repo or local directory
#
# Usage:
#   ./generate.sh <org/repo>                    # remote GitHub repo
#   ./generate.sh https://github.com/org/repo   # full URL also works
#   ./generate.sh /path/to/local/repo           # local directory
#   ./generate.sh ./my-project output.json      # custom output path
#
# Model: defaults to claude. Override with MODEL env var:
#   MODEL=codex ./generate.sh org/repo
#
# Examples:
#   ./generate.sh facebook/react
#   ./generate.sh /Users/me/code/my-project
#   ./generate.sh ../some-repo some-repo.json
#   MODEL=codex ./generate.sh golang/go

set -euo pipefail

REPO="${1:-}"
OUTPUT="${2:-trail.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_PROMPT="$SCRIPT_DIR/generate-trail.md"
MODEL="${MODEL:-claude}"

# ── Validate args ──────────────────────────────────────────────────────────
if [[ -z "$REPO" ]]; then
  echo "Usage: $0 <org/repo|local-path> [output.json]"
  echo ""
  echo "Remote:"
  echo "  $0 facebook/react"
  echo "  $0 denoland/deno deno.json"
  echo "  MODEL=codex $0 golang/go"
  echo ""
  echo "Local:"
  echo "  $0 /path/to/repo"
  echo "  $0 ../my-project my-project.json"
  exit 1
fi

if [[ ! -f "$SYSTEM_PROMPT" ]]; then
  echo "Error: generate-trail.md not found at $SYSTEM_PROMPT"
  exit 1
fi

# ── Detect local vs remote ─────────────────────────────────────────────────
IS_LOCAL=false
LOCAL_PATH=""
REPO_URL=""
DISPLAY_SOURCE=""

if [[ "$REPO" = /* ]] || [[ "$REPO" = ./* ]] || [[ "$REPO" = ../* ]] || [[ -d "$REPO" ]]; then
  # Local path
  if [[ ! -d "$REPO" ]]; then
    echo "Error: '$REPO' is not a directory."
    exit 1
  fi
  IS_LOCAL=true
  LOCAL_PATH="$(cd "$REPO" && pwd)"
  DISPLAY_SOURCE="$LOCAL_PATH (local)"
else
  # Remote GitHub
  if [[ "$REPO" =~ ^https?:// ]]; then
    REPO_URL="$REPO"
  else
    REPO_URL="https://github.com/$REPO"
  fi
  DISPLAY_SOURCE="$REPO_URL"
fi

# ── Temp file for raw model output ────────────────────────────────────────
TMP=$(mktemp /tmp/trail-raw-XXXXXX.txt)
trap 'rm -f "$TMP"' EXIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TRAILMAKER GENERATOR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Source : $DISPLAY_SOURCE"
echo "  Output : $OUTPUT"
echo "  Model  : $MODEL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Build prompt ───────────────────────────────────────────────────────────
if $IS_LOCAL; then
  PROMPT="Scan the local repository at: $LOCAL_PATH"
else
  PROMPT="Scan $REPO_URL"
fi

# ── Run model ─────────────────────────────────────────────────────────────
run_model() {
  if [[ "$MODEL" == "codex" ]]; then
    if ! command -v codex &>/dev/null; then
      echo "Error: 'codex' CLI not found. Install it or use MODEL=claude."
      exit 1
    fi
    codex --full-auto -q "$PROMPT" \
      --system-prompt "$(cat "$SYSTEM_PROMPT")" \
      > "$TMP"
  else
    if ! command -v claude &>/dev/null; then
      echo "Error: 'claude' CLI not found."
      echo "Install: https://claude.ai/code"
      exit 1
    fi
    claude --print \
      --system-prompt "$SYSTEM_PROMPT" \
      "$PROMPT" \
      > "$TMP"
  fi
}

if $IS_LOCAL; then
  # Run from within the repo so relative file paths resolve correctly
  (cd "$LOCAL_PATH" && run_model)
else
  run_model
fi

echo ""
echo "→ Model finished. Extracting JSON..."

# ── Extract JSON from model output ────────────────────────────────────────
node - "$TMP" "$OUTPUT" <<'NODE'
const fs = require('fs');
const raw = fs.readFileSync(process.argv[2], 'utf8');
const outPath = process.argv[3];

// 1. Try ```json ... ``` fence
const fenceMatch = raw.match(/```json\s*([\s\S]*?)```/);
if (fenceMatch) {
  const candidate = fenceMatch[1].trim();
  try {
    JSON.parse(candidate);
    fs.writeFileSync(outPath, candidate + '\n');
    console.log('→ Extracted from JSON code block.');
    process.exit(0);
  } catch (_) {}
}

// 2. Try bare ``` ... ``` fence containing JSON
const bareFence = raw.match(/```\s*(\{[\s\S]*?\})\s*```/);
if (bareFence) {
  const candidate = bareFence[1].trim();
  try {
    JSON.parse(candidate);
    fs.writeFileSync(outPath, candidate + '\n');
    console.log('→ Extracted from code block.');
    process.exit(0);
  } catch (_) {}
}

// 3. Try largest { ... } span in the output
const start = raw.indexOf('{');
const end   = raw.lastIndexOf('}');
if (start >= 0 && end > start) {
  const candidate = raw.slice(start, end + 1).trim();
  try {
    JSON.parse(candidate);
    fs.writeFileSync(outPath, candidate + '\n');
    console.log('→ Extracted bare JSON object.');
    process.exit(0);
  } catch (e) {
    console.error('Error: Found JSON-like content but it does not parse:');
    console.error('  ' + e.message);
    console.error('Raw output saved to: ' + process.argv[2]);
    process.exit(1);
  }
}

console.error('Error: No JSON object found in model output.');
console.error('Raw output saved to: ' + process.argv[2]);
process.exit(1);
NODE

# ── Validate ───────────────────────────────────────────────────────────────
echo ""
node "$SCRIPT_DIR/validate.js" "$OUTPUT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Trail written to: $OUTPUT"
echo ""
echo "  View it (from the trailmaker directory):"
echo "    python3 -m http.server 8000"
echo "    open http://localhost:8000"
if [[ "$OUTPUT" != "trail.json" ]]; then
  echo ""
  echo "  Custom trail path:"
  echo "    open \"http://localhost:8000?trail=$OUTPUT\""
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
