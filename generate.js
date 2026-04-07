#!/usr/bin/env node
/**
 * generate.js — Generate trail.json by calling the Anthropic API directly.
 *
 * Usage:
 *   node generate.js <local-path> [output.json]
 *   node generate.js <org/repo>   [output.json]   (remote GitHub)
 *
 * Requires: ANTHROPIC_API_KEY environment variable
 */

'use strict';

const fs   = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');

// ── Args ────────────────────────────────────────────────────────────────────
const source = process.argv[2];
const output = process.argv[3] || 'trail.json';
const scriptDir = __dirname;

if (!source) {
  console.error('Usage: node generate.js <local-path|org/repo> [output.json]');
  process.exit(1);
}

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  console.error('Error: ANTHROPIC_API_KEY environment variable is not set.');
  process.exit(1);
}

// ── Detect local vs remote ──────────────────────────────────────────────────
const isLocal = fs.existsSync(source) && fs.statSync(source).isDirectory()
  || source.startsWith('/')
  || source.startsWith('./')
  || source.startsWith('../');

let localPath = '';
let repoUrl   = '';

if (isLocal) {
  if (!fs.existsSync(source) || !fs.statSync(source).isDirectory()) {
    console.error(`Error: '${source}' is not a directory.`);
    process.exit(1);
  }
  localPath = path.resolve(source);
} else {
  repoUrl = source.startsWith('http') ? source : `https://github.com/${source}`;
}

// ── Load system prompt ──────────────────────────────────────────────────────
const systemPromptPath = path.join(scriptDir, 'generate-trail.md');
if (!fs.existsSync(systemPromptPath)) {
  console.error('Error: generate-trail.md not found.');
  process.exit(1);
}
const systemPrompt = fs.readFileSync(systemPromptPath, 'utf8');

// ── Build context for local repos ───────────────────────────────────────────
function buildLocalContext(repoPath) {
  const lines = [];

  // File tree
  lines.push('## File Tree\n```');
  try {
    const tree = execSync(
      `find . -not -path './.git/*' -not -path './.beads/*' -not -path './__pycache__/*' -not -path './node_modules/*' -not -name '*.pyc' | sort`,
      { cwd: repoPath, encoding: 'utf8', maxBuffer: 1024 * 1024 }
    );
    lines.push(tree.trim());
  } catch (e) {
    lines.push('(could not list files)');
  }
  lines.push('```\n');

  // File count by extension
  lines.push('## File Counts by Extension\n```');
  try {
    const counts = execSync(
      `find . -type f -not -path './.git/*' -not -path './.beads/*' -not -path './node_modules/*' | sed 's/.*\\.//' | sort | uniq -c | sort -rn | head -20`,
      { cwd: repoPath, encoding: 'utf8', maxBuffer: 512 * 1024 }
    );
    lines.push(counts.trim());
  } catch (e) {}
  lines.push('```\n');

  // Line count
  try {
    const loc = execSync(
      `find . -type f \\( -name '*.ts' -o -name '*.js' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.rb' -o -name '*.cpp' -o -name '*.c' \\) -not -path './node_modules/*' | xargs wc -l 2>/dev/null | tail -1`,
      { cwd: repoPath, encoding: 'utf8', maxBuffer: 512 * 1024 }
    ).trim();
    if (loc) lines.push(`## Total Lines of Code\n${loc}\n`);
  } catch (e) {}

  // Git remote (for meta.repo)
  try {
    const remote = execSync('git remote get-url origin 2>/dev/null || true', {
      cwd: repoPath, encoding: 'utf8'
    }).trim();
    if (remote) lines.push(`## Git Remote\n${remote}\n`);
  } catch (e) {}

  // Key files — read and include
  const keyFiles = [
    'README.md', 'README', 'readme.md',
    'package.json', 'Cargo.toml', 'go.mod', 'pyproject.toml', 'setup.py',
    'tsconfig.json', 'Makefile', '.env.example',
  ];
  for (const f of keyFiles) {
    const p = path.join(repoPath, f);
    if (fs.existsSync(p)) {
      const content = fs.readFileSync(p, 'utf8').slice(0, 4000);
      lines.push(`## ${f}\n\`\`\`\n${content}\n\`\`\`\n`);
    }
  }

  // Source files — find and include up to 10, 300 lines each
  const sourceExts = ['.py', '.ts', '.js', '.go', '.rs', '.rb', '.java'];
  const excludeDirs = ['node_modules', '.git', '.beads', '__pycache__', 'dist', 'build', '.next'];
  let sourceFiles = [];
  try {
    const found = execSync(
      `find . -type f \\( ${sourceExts.map(e => `-name '*${e}'`).join(' -o ')} \\) ${excludeDirs.map(d => `-not -path './${d}/*'`).join(' ')} | sort`,
      { cwd: repoPath, encoding: 'utf8', maxBuffer: 1024 * 1024 }
    ).trim().split('\n').filter(Boolean);
    // Prioritise non-test, non-config files
    sourceFiles = found
      .filter(f => !f.includes('test') && !f.includes('spec') && !f.includes('__init__'))
      .slice(0, 8)
      .concat(found.filter(f => f.includes('test')).slice(0, 2));
  } catch (e) {}

  for (const relPath of sourceFiles.slice(0, 12)) {
    const absPath = path.join(repoPath, relPath);
    try {
      const content = fs.readFileSync(absPath, 'utf8')
        .split('\n').slice(0, 300).join('\n');
      lines.push(`## ${relPath}\n\`\`\`\n${content}\n\`\`\`\n`);
    } catch (e) {}
  }

  return lines.join('\n');
}

// ── Anthropic API call ──────────────────────────────────────────────────────
function callAnthropic(system, userMessage) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: 'claude-opus-4-6',
      max_tokens: 8096,
      system,
      messages: [{ role: 'user', content: userMessage }],
    });

    const req = https.request({
      hostname: 'api.anthropic.com',
      path: '/v1/messages',
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
      },
    }, res => {
      let raw = '';
      res.on('data', chunk => {
        raw += chunk;
        process.stderr.write('.'); // progress indicator
      });
      res.on('end', () => {
        process.stderr.write('\n');
        try {
          const parsed = JSON.parse(raw);
          if (parsed.error) {
            reject(new Error(`API error: ${parsed.error.message}`));
          } else {
            resolve(parsed.content?.[0]?.text || '');
          }
        } catch (e) {
          reject(new Error(`Failed to parse API response: ${e.message}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ── Extract JSON from response ──────────────────────────────────────────────
function extractJson(text) {
  // ```json fence
  const m1 = text.match(/```json\s*([\s\S]*?)```/);
  if (m1) { try { JSON.parse(m1[1].trim()); return m1[1].trim(); } catch(_) {} }
  // bare ``` fence
  const m2 = text.match(/```\s*(\{[\s\S]*?\})\s*```/);
  if (m2) { try { JSON.parse(m2[1].trim()); return m2[1].trim(); } catch(_) {} }
  // bare JSON
  const s = text.indexOf('{'), e = text.lastIndexOf('}');
  if (s >= 0 && e > s) {
    const c = text.slice(s, e + 1).trim();
    try { JSON.parse(c); return c; } catch(_) {}
  }
  return null;
}

// ── Main ────────────────────────────────────────────────────────────────────
(async () => {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  TRAILMAKER GENERATOR');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`  Source : ${isLocal ? localPath + ' (local)' : repoUrl}`);
  console.log(`  Output : ${output}`);
  console.log(`  Model  : claude-opus-4-6`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('');

  let userMessage;

  if (isLocal) {
    console.log('→ Building repository context...');
    const context = buildLocalContext(localPath);
    userMessage = `Scan the local repository at: ${localPath}\n\nHere is the full repository context:\n\n${context}`;
    console.log(`→ Context built (${Math.round(userMessage.length / 1000)}K chars). Calling API...`);
  } else {
    userMessage = `Scan ${repoUrl}`;
    console.log('→ Calling API...');
  }

  process.stderr.write('→ Streaming response ');
  let responseText;
  try {
    responseText = await callAnthropic(systemPrompt, userMessage);
  } catch (e) {
    console.error(`\nError calling Anthropic API: ${e.message}`);
    process.exit(1);
  }

  console.log('→ Extracting JSON...');
  const json = extractJson(responseText);

  if (!json) {
    const debugPath = path.join(require('os').tmpdir(), 'trail-debug.txt');
    fs.writeFileSync(debugPath, responseText);
    console.error(`Error: No valid JSON found in response.`);
    console.error(`Raw response saved to: ${debugPath}`);
    process.exit(1);
  }

  fs.writeFileSync(output, json + '\n');
  console.log(`→ JSON written to ${output}`);

  // Validate
  console.log('');
  const { execFileSync } = require('child_process');
  try {
    const result = execFileSync('node', [path.join(scriptDir, 'validate.js'), output], { encoding: 'utf8' });
    process.stdout.write(result);
  } catch (e) {
    console.error(e.stdout || e.message);
    process.exit(1);
  }

  console.log('');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`  Trail written to: ${output}`);
  console.log('');
  console.log('  View it:');
  console.log('    python3 -m http.server 8000');
  console.log('    open http://localhost:8000');
  if (output !== 'trail.json') {
    console.log(`    open "http://localhost:8000?trail=${output}"`);
  }
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
})();
