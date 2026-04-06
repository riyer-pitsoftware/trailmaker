#!/usr/bin/env bash
# generate.sh — Generate trail.json for any GitHub repo using Claude or Codex
#
# Usage:
#   ./generate.sh <org/repo>                    # writes trail.json
#   ./generate.sh <org/repo> react.json         # custom output path
#   ./generate.sh https://github.com/org/repo   # full URL also works
#
# Model: defaults to claude. Override with MODEL env var:
#   MODEL=codex ./generate.sh org/repo
#
# Examples:
#   ./generate.sh facebook/react
#   ./generate.sh denoland/deno deno.json
#   MODEL=codex ./generate.sh golang/go

set -euo pipefail

REPO="${1:-}"
OUTPUT="${2:-trail.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_PROMPT="$SCRIPT_DIR/generate-trail.md"
MODEL="${MODEL:-claude}"

# ── Validate args ──────────────────────────────────────────────────────────
if [[ -z "$REPO" ]]; then
  echo "Usage: $0 <org/repo> [output.json]"
  echo ""
  echo "Examples:"
  echo "  $0 facebook/react"
  echo "  $0 denoland/deno deno.json"
  echo "  MODEL=codex $0 golang/go"
  exit 1
fi

if [[ ! -f "$SYSTEM_PROMPT" ]]; then
  echo "Error: generate-trail.md not found at $SYSTEM_PROMPT"
  exit 1
fi

# Normalize to full GitHub URL
if [[ "$REPO" =~ ^https?:// ]]; then
  REPO_URL="$REPO"
else
  REPO_URL="https://github.com/$REPO"
fi

# ── Temp file for raw model output ────────────────────────────────────────
TMP=$(mktemp /tmp/trail-raw-XXXXXX.txt)
trap 'rm -f "$TMP"' EXIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TRAILMAKER GENERATOR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Repo   : $REPO_URL"
echo "  Output : $OUTPUT"
echo "  Model  : $MODEL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Run model ─────────────────────────────────────────────────────────────
PROMPT="Scan $REPO_URL"

if [[ "$MODEL" == "codex" ]]; then
  # OpenAI Codex / codex CLI
  if ! command -v codex &>/dev/null; then
    echo "Error: 'codex' CLI not found. Install it or use MODEL=claude."
    exit 1
  fi
  codex --full-auto -q "$PROMPT" \
    --system-prompt "$(cat "$SYSTEM_PROMPT")" \
    > "$TMP"

else
  # Claude CLI (default)
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
echo "  View it:"
echo "    python3 -m http.server 8000"
echo "    open http://localhost:8000"
echo ""
echo "  Or with a custom trail path:"
echo "    open http://localhost:8000?trail=$OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
