#!/usr/bin/env bash
# generate.sh — Generate trail.json for any GitHub repo or local directory
#
# Usage:
#   ./generate.sh <org/repo>             # remote GitHub repo
#   ./generate.sh /path/to/local/repo   # local directory
#   ./generate.sh <source> output.json  # custom output path
#
# Requires: ANTHROPIC_API_KEY environment variable

set -euo pipefail

REPO="${1:-}"
OUTPUT="${2:-trail.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$REPO" ]]; then
  echo "Usage: $0 <org/repo|local-path> [output.json]"
  echo ""
  echo "Remote:  $0 facebook/react"
  echo "Local:   $0 /path/to/repo"
  exit 1
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Error: ANTHROPIC_API_KEY is not set."
  exit 1
fi

node "$SCRIPT_DIR/generate.js" "$REPO" "$OUTPUT"
