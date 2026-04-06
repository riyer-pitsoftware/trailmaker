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
  echo "Remote:  $0 facebook/react"
  echo "Local:   $0 /path/to/repo"
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
  if [[ ! -d "$REPO" ]]; then
    echo "Error: '$REPO' is not a directory."
    exit 1
  fi
  IS_LOCAL=true
  LOCAL_PATH="$(cd "$REPO" && pwd)"
  DISPLAY_SOURCE="$LOCAL_PATH (local)"
else
  [[ "$REPO" =~ ^https?:// ]] && REPO_URL="$REPO" || REPO_URL="https://github.com/$REPO"
  DISPLAY_SOURCE="$REPO_URL"
fi

# ── Temp files ─────────────────────────────────────────────────────────────
TMP=$(mktemp /tmp/trail-raw-XXXXXX.txt)
TMP2=$(mktemp /tmp/trail-fmt-XXXXXX.txt)
trap 'rm -f "$TMP" "$TMP2"' EXIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TRAILMAKER GENERATOR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Source : $DISPLAY_SOURCE"
echo "  Output : $OUTPUT"
echo "  Model  : $MODEL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Build prompts ──────────────────────────────────────────────────────────
if $IS_LOCAL; then
  PASS1_PROMPT="Scan the local repository at: $LOCAL_PATH"
else
  PASS1_PROMPT="Scan $REPO_URL"
fi

# ── Claude runner ──────────────────────────────────────────────────────────
run_claude() {
  local system_prompt="$1"
  local user_prompt="$2"
  local out_file="$3"

  if ! command -v claude &>/dev/null; then
    echo "Error: 'claude' CLI not found. Install: https://claude.ai/code"
    exit 1
  fi

  claude --print \
    --system-prompt "$system_prompt" \
    "$user_prompt" \
    | tee "$out_file"
}

# ── JSON extractor ─────────────────────────────────────────────────────────
extract_json() {
  local in_file="$1"
  local out_file="$2"
  node - "$in_file" "$out_file" <<'NODE'
const fs = require('fs');
const raw = fs.readFileSync(process.argv[2], 'utf8');
const outPath = process.argv[3];

// 1. ```json fence
const m1 = raw.match(/```json\s*([\s\S]*?)```/);
if (m1) { try { JSON.parse(m1[1].trim()); fs.writeFileSync(outPath, m1[1].trim() + '\n'); process.exit(0); } catch(_){} }

// 2. bare ``` fence
const m2 = raw.match(/```\s*(\{[\s\S]*?\})\s*```/);
if (m2) { try { JSON.parse(m2[1].trim()); fs.writeFileSync(outPath, m2[1].trim() + '\n'); process.exit(0); } catch(_){} }

// 3. largest { ... } span
const s = raw.indexOf('{'), e = raw.lastIndexOf('}');
if (s >= 0 && e > s) {
  const c = raw.slice(s, e + 1).trim();
  try { JSON.parse(c); fs.writeFileSync(outPath, c + '\n'); process.exit(0); } catch(_) {}
}

process.exit(1); // signal: no JSON found
NODE
}

# ── Pass 1: analysis ───────────────────────────────────────────────────────
echo "[ PASS 1 — Scanning repository ]"
echo ""

if $IS_LOCAL; then
  (cd "$LOCAL_PATH" && run_claude "$SYSTEM_PROMPT" "$PASS1_PROMPT" "$TMP")
else
  run_claude "$SYSTEM_PROMPT" "$PASS1_PROMPT" "$TMP"
fi

echo ""
echo "→ Extracting JSON..."

if extract_json "$TMP" "$OUTPUT"; then
  echo "→ JSON extracted from pass 1."
else
  # ── Pass 2: formatting ─────────────────────────────────────────────────
  echo "→ Pass 1 produced analysis text. Running formatting pass..."
  echo ""
  echo "[ PASS 2 — Formatting as trail.json ]"
  echo ""

  SCHEMA=$(cat "$SCRIPT_DIR/schema/trail.schema.json")
  ANALYSIS=$(cat "$TMP")

  PASS2_SYSTEM="You are a JSON formatter. Convert codebase analysis into a trail.json object.
Output ONLY a raw JSON object — no markdown, no code fences, no explanation. Start with { and end with }.

The JSON must conform to this schema:
$SCHEMA

Rules:
- insights[].ch is the 0-based index into chapters[]
- branches keys are stringified insight indices (\"0\", \"3\", etc.)
- branch trail arrays must have exactly 3 items with levels in order: \"Sourced Tech\", \"How It Works\", \"Core Tech\"
- puzzle opts must have exactly 4 strings, ans is 0-3
- insights[].f must be a real path relative to the repo root (no leading slash)"

  PASS2_PROMPT="Convert this codebase analysis into a trail.json object:

$ANALYSIS"

  run_claude "$PASS2_SYSTEM" "$PASS2_PROMPT" "$TMP2"

  echo ""
  echo "→ Extracting JSON from pass 2..."

  if ! extract_json "$TMP2" "$OUTPUT"; then
    echo ""
    echo "Error: Could not extract JSON from either pass."
    echo "Raw pass 1 saved to: $TMP"
    echo "Raw pass 2 saved to: $TMP2"
    # prevent trap from deleting them
    TMP=/dev/null; TMP2=/dev/null
    exit 1
  fi
fi

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
