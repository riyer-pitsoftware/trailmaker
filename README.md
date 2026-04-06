# Trailmaker

Generate interactive, educational trails through any open-source codebase. Point it at a GitHub repo — Claude or Codex scans it, extracts insights, maps tech dependencies 3 levels deep, and produces a `trail.json`. A single-file HTML viewer renders it as an Oregon Trail-inspired experience.

## Quickstart

```bash
# Generate a trail for any GitHub repo
./generate.sh facebook/react

# View it
python3 -m http.server 8000
open http://localhost:8000
```

## How It Works

```
generate.sh <org/repo>
    └── claude --print --system-prompt generate-trail.md "Scan <repo>"
            └── produces trail.json
                    └── index.html renders it
```

**Four generation phases:**
1. **Recon** — tree, file counts, language stats, README, manifests
2. **Chapter mapping** — 8–20 logical subsystems (not just directories)
3. **Insight extraction** — magic numbers, security boundaries, clever algorithms, 5–15 per chapter, each backed by a real file path
4. **Branch generation** — tech chain traced 3 levels deep (Sourced Tech → How It Works → Core CS concept) with a puzzle gate

## Usage

```bash
# Default: writes trail.json, uses claude CLI
./generate.sh <org/repo>
./generate.sh <org/repo> <output.json>      # custom output path

# Use Codex instead of Claude
MODEL=codex ./generate.sh <org/repo>

# Full URL also works
./generate.sh https://github.com/denoland/deno
```

**Requires:** `claude` CLI ([install](https://claude.ai/code)) or `codex` CLI if using `MODEL=codex`.

## Viewer Features

- Trail map with dots, segments, chapter markers, and wagon position
- Card-based insight display with source file links (GitHub or local)
- Branch trail overlay — 3-level tech deep-dive with mini map
- Puzzle gate to return from branch to main trail
- Chapter interstitials, search overlay (`/`), chapter nav sidebar (`C`)
- Keyboard: arrows, `h/j/k/l`, `G` jump, `[` `]` chapter skip, `b` branch
- Touch swipe support
- localStorage progress (namespaced per repo, survives refresh)
- CRT scanline theme, Google Fonts (Press Start 2P + VT323)
- No build step — hosts on GitHub Pages as-is

## Multiple Trails

The viewer supports a `?trail=` query param, so you can host one viewer for many trails:

```
http://localhost:8000?trail=react.json
http://localhost:8000?trail=deno.json
```

## Validate a Trail

```bash
node validate.js trail.json
# ✓ Valid trail.json
#   12 chapters · 87 insights · 24 branches
```

## File Structure

```
generate.sh          ← run this to generate a trail
generate-trail.md    ← system prompt for the model
index.html           ← viewer (self-contained, no dependencies)
trail.json           ← generated output (one per project)
validate.js          ← validates trail.json against the schema
schema/
  trail.schema.json  ← JSON Schema for trail.json
```

## trail.json Format

```json
{
  "meta": { "title": "The React Trail", "subtitle": "...", "stats": "...", "repo": "https://github.com/...", "icon": "⚛️" },
  "chapters": [{ "id": "reconciler", "title": "Reconciler", "desc": "..." }],
  "insights": [{ "ch": 0, "t": "Title", "d": "Finding", "f": "packages/react/src/...", "l": "<strong>Why it matters:</strong> ..." }],
  "branches": {
    "3": {
      "trail": [
        { "title": "React Fiber", "level": "Sourced Tech", "desc": "...", "core": "..." },
        { "title": "Incremental Rendering", "level": "How It Works", "desc": "...", "core": "..." },
        { "title": "Cooperative Scheduling", "level": "Core Tech", "desc": "...", "core": "..." }
      ],
      "puzzle": { "q": "Question?", "opts": ["A", "B", "C", "D"], "ans": 2 }
    }
  }
}
```
