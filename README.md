# Trailmaker

Generate interactive, educational trails through any codebase. Point it at a GitHub repo or a local directory — Claude or Codex scans it, extracts insights, maps tech dependencies 3 levels deep, and produces a `trail.json`. A single-file HTML viewer renders it as an Oregon Trail-inspired experience.

## Quickstart

```bash
./generate.sh facebook/react
python3 -m http.server 8000
open http://localhost:8000
```

## generate.sh

```
./generate.sh <source> [output]
```

| Param | Required | Description |
|---|---|---|
| `source` | yes | What to scan. A GitHub `org/repo`, a full `https://` URL, or a local directory path. |
| `output` | no | Where to write the trail file. Defaults to `trail.json` in the current directory. Useful when generating trails for multiple projects — give each one a distinct name. |

```bash
# GitHub repo (shorthand)
./generate.sh facebook/react

# GitHub repo (full URL)
./generate.sh https://github.com/denoland/deno

# Local directory — for private or offline repos
./generate.sh /path/to/cloned/repo

# Custom output file — keeps trail.json from being overwritten
./generate.sh golang/go go.json
./generate.sh /path/to/my-project my-project.json

# Use Codex instead of Claude
MODEL=codex ./generate.sh facebook/react
```

**Requires:** `claude` CLI ([install](https://claude.ai/code)) or `codex` CLI if `MODEL=codex`.

For repos that aren't publicly accessible, clone them locally first:

```bash
git clone <url> /tmp/my-repo
./generate.sh /tmp/my-repo my-repo.json
```

## Viewing Trails

```bash
# Serve from the trailmaker directory
python3 -m http.server 8000

# Default — loads trail.json
open http://localhost:8000

# Custom output file
open "http://localhost:8000?trail=go.json"
```

## How It Works

```
generate.sh <source> [output]
    └── claude --print --system-prompt generate-trail.md "Scan <source>"
            └── produces <output> (trail.json by default)
                    └── index.html renders it in the browser
```

The model runs four phases:

1. **Recon** — directory tree, file counts, language stats, README, manifests
2. **Chapter mapping** — 8–20 logical subsystems (not just directories)
3. **Insight extraction** — magic numbers, security boundaries, clever algorithms; 5–15 per chapter, each backed by a real file path
4. **Branch generation** — tech chain traced 3 levels deep (Sourced Tech → How It Works → Core CS concept) with a puzzle gate

## Viewer Features

- Trail map with dots, segments, chapter markers, wagon position indicator
- Card-based insight display with source file links (GitHub or local)
- Branch trail overlay — 3-level tech deep-dive with mini map
- Puzzle gate to return from a branch to the main trail
- Chapter interstitials, search overlay, chapter nav sidebar
- Keyboard: arrows, `h/j/k/l`, `G` jump, `[` `]` chapter skip, `b` branch, `/` search, `C` chapters
- Touch swipe support
- Progress saved to localStorage per repo (survives refresh)
- CRT scanline theme — no build step, hosts on GitHub Pages as-is

## Validate a Trail

```bash
node validate.js trail.json
# ✓ Valid trail.json
#   12 chapters · 87 insights · 24 branches
```

## File Structure

```
generate.sh           ← entry point: scan a repo, produce a trail file
generate-trail.md     ← system prompt that drives the model scan
index.html            ← viewer (single self-contained file, no dependencies)
validate.js           ← validates any trail file against the schema
schema/
  trail.schema.json   ← JSON Schema defining the trail.json format
trail.json            ← example/default trail file (generated, not checked in)
```

## trail.json Format

```json
{
  "meta": { "title": "The React Trail", "subtitle": "...", "stats": "~300K lines · JavaScript", "repo": "https://github.com/...", "icon": "⚛️" },
  "chapters": [{ "id": "reconciler", "title": "Reconciler", "desc": "..." }],
  "insights": [{ "ch": 0, "t": "Title", "d": "Specific finding with real numbers", "f": "packages/react/src/ReactFiber.js", "l": "<strong>Why it matters:</strong> ..." }],
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
