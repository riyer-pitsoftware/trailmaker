#!/usr/bin/env node
/**
 * validate.js — Validate a trail.json against schema/trail.schema.json
 * Usage: node validate.js path/to/trail.json
 */

const fs = require('fs');
const path = require('path');

const trailPath = process.argv[2];
if (!trailPath) {
  console.error('Usage: node validate.js path/to/trail.json');
  process.exit(1);
}

// Load trail.json
let trail;
try {
  trail = JSON.parse(fs.readFileSync(trailPath, 'utf8'));
} catch (e) {
  console.error(`Error reading ${trailPath}: ${e.message}`);
  process.exit(1);
}

// Load schema
const schemaPath = path.join(__dirname, 'schema', 'trail.schema.json');
let schema;
try {
  schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
} catch (e) {
  console.error(`Error reading schema: ${e.message}`);
  process.exit(1);
}

const errors = [];

function err(msg) {
  errors.push(msg);
}

// --- Validate meta ---
if (!trail.meta || typeof trail.meta !== 'object') {
  err('meta: missing or not an object');
} else {
  for (const field of ['title', 'subtitle', 'stats', 'repo', 'icon']) {
    if (typeof trail.meta[field] !== 'string' || trail.meta[field].length === 0) {
      err(`meta.${field}: must be a non-empty string`);
    }
  }
}

// --- Validate chapters ---
if (!Array.isArray(trail.chapters) || trail.chapters.length === 0) {
  err('chapters: must be a non-empty array');
} else {
  trail.chapters.forEach((ch, i) => {
    if (typeof ch.id !== 'string' || !/^[a-z0-9-]+$/.test(ch.id)) {
      err(`chapters[${i}].id: must be a lowercase slug (got ${JSON.stringify(ch.id)})`);
    }
    if (typeof ch.title !== 'string' || ch.title.length === 0) {
      err(`chapters[${i}].title: must be a non-empty string`);
    }
    if (typeof ch.desc !== 'string' || ch.desc.length === 0) {
      err(`chapters[${i}].desc: must be a non-empty string`);
    }
  });
}

const chapterCount = Array.isArray(trail.chapters) ? trail.chapters.length : 0;

// --- Validate insights ---
if (!Array.isArray(trail.insights) || trail.insights.length === 0) {
  err('insights: must be a non-empty array');
} else {
  trail.insights.forEach((ins, i) => {
    if (!Number.isInteger(ins.ch) || ins.ch < 0) {
      err(`insights[${i}].ch: must be a non-negative integer (got ${JSON.stringify(ins.ch)})`);
    } else if (ins.ch >= chapterCount) {
      err(`insights[${i}].ch: ${ins.ch} is out of range (only ${chapterCount} chapters)`);
    }
    for (const field of ['t', 'd', 'f', 'l']) {
      if (typeof ins[field] !== 'string' || ins[field].length === 0) {
        err(`insights[${i}].${field}: must be a non-empty string`);
      }
    }
    if ('v' in ins && typeof ins.v !== 'string') {
      err(`insights[${i}].v: must be a string if present`);
    }
  });
}

const insightCount = Array.isArray(trail.insights) ? trail.insights.length : 0;

// --- Validate branches ---
const LEVELS = ['Sourced Tech', 'How It Works', 'Core Tech'];

if (!trail.branches || typeof trail.branches !== 'object' || Array.isArray(trail.branches)) {
  err('branches: must be an object');
} else {
  for (const [key, branch] of Object.entries(trail.branches)) {
    if (!/^[0-9]+$/.test(key)) {
      err(`branches: key "${key}" must be a stringified integer`);
    } else {
      const idx = parseInt(key, 10);
      if (idx >= insightCount) {
        err(`branches["${key}"]: index ${idx} is out of range (only ${insightCount} insights)`);
      }
    }

    // trail array
    if (!Array.isArray(branch.trail) || branch.trail.length !== 3) {
      err(`branches["${key}"].trail: must be an array of exactly 3 items`);
    } else {
      branch.trail.forEach((step, i) => {
        if (step.level !== LEVELS[i]) {
          err(`branches["${key}"].trail[${i}].level: expected "${LEVELS[i]}", got "${step.level}"`);
        }
        for (const field of ['title', 'desc', 'core']) {
          if (typeof step[field] !== 'string' || step[field].length === 0) {
            err(`branches["${key}"].trail[${i}].${field}: must be a non-empty string`);
          }
        }
      });
    }

    // puzzle
    const p = branch.puzzle;
    if (!p || typeof p !== 'object') {
      err(`branches["${key}"].puzzle: missing or not an object`);
    } else {
      if (typeof p.q !== 'string' || p.q.length === 0) {
        err(`branches["${key}"].puzzle.q: must be a non-empty string`);
      }
      if (!Array.isArray(p.opts) || p.opts.length !== 4) {
        err(`branches["${key}"].puzzle.opts: must be an array of exactly 4 strings`);
      } else {
        p.opts.forEach((opt, i) => {
          if (typeof opt !== 'string' || opt.length === 0) {
            err(`branches["${key}"].puzzle.opts[${i}]: must be a non-empty string`);
          }
        });
      }
      if (!Number.isInteger(p.ans) || p.ans < 0 || p.ans > 3) {
        err(`branches["${key}"].puzzle.ans: must be an integer 0–3 (got ${JSON.stringify(p.ans)})`);
      }
    }
  }
}

// --- Report ---
if (errors.length === 0) {
  const branchCount = trail.branches ? Object.keys(trail.branches).length : 0;
  console.log(`✓ Valid trail.json`);
  console.log(`  ${chapterCount} chapters · ${insightCount} insights · ${branchCount} branches`);
  process.exit(0);
} else {
  console.error(`✗ Invalid trail.json — ${errors.length} error(s):\n`);
  errors.forEach(e => console.error(`  • ${e}`));
  process.exit(1);
}
