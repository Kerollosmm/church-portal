#!/usr/bin/env node
// validate.mjs — static checks for the hark-workflow kit (v2 layout). Zero dependencies, Node >= 18, any OS.
//
//   node scripts/validate.mjs [--no-tests]
//
// * every *.json parses; plugin.json follows the v1 schema (known fields, kebab name, <= 3 prompts, logo exists)
// * skills/<dir>/SKILL.md: frontmatter name == <dir> (kebab, <= 64), description 1..1024 chars
// * agents/*.md: frontmatter name == file, description, model, commandExecutionPolicy, booleans, tools only from the
//   documented Antigravity list (a misspelled tool can hang a subagent); body has Role / Checklist / Never /
//   Single-agent sections (weak-model contract + IDE fallback)
// * rules/*.md: valid trigger frontmatter (rules/AGENTS.md has none); every rule file <= 24,000 bytes
// * hooks.json: documented events, matcher + hooks for tool events, commands are `node ./scripts/...` files that exist
// * README.md / AGENTS.md: no removed v1 script or skill names; hw-* skills, hw.mjs commands and relative links exist
// * cross references: every hw-* skill named anywhere exists; every agent in the hw-start routing table exists;
//   every `hw.mjs <command>` used in skills / agents / templates / rules exists; help lists every command;
//   every resources/templates/<file> named exists; every c.KEY read by hw.mjs is in workflow.env.example
// * examples/<name>/agents-dir/: workflow.env keys known, rules frontmatter valid (the install-profile layout)
// * node --check on every .mjs; hook tests (scripts/test_hooks.mjs) and hw.mjs offline tests (scripts/test_hw.mjs)
// * `agy plugin validate --strict .` when the Antigravity CLI is installed
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseEnv } from './lib/config.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const NO_TESTS = process.argv.includes('--no-tests');
const bad = [];
const err = (m) => bad.push(m);
const ok = (m) => console.log(`OK   ${m}`);
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const exists = (p) => existsSync(join(ROOT, p));

function walk(dir, acc = []) {
  for (const e of readdirSync(join(ROOT, dir), { withFileTypes: true })) {
    if (['.git', 'node_modules', '.work'].includes(e.name)) continue;
    const p = dir ? `${dir}/${e.name}` : e.name;
    if (e.isDirectory()) walk(p, acc); else acc.push(p);
  }
  return acc;
}
const FILES = walk('');

/** Tiny YAML subset for frontmatter: `k: v`, quoted values, booleans, `k: >-` / `k: |` blocks, `k:` + `- item` lists. */
function frontmatter(path) {
  const txt = read(path).replace(/\r\n/g, '\n');
  const m = txt.match(/^---\n([\s\S]*?)\n---\n/);
  if (!m) return null;
  const fm = {}; const lines = m[1].split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const kv = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
    if (!kv) { err(`${path}: frontmatter line not understood: "${line}"`); continue; }
    const [, key, rawVal] = kv; let val = rawVal.trim();
    if (val === '>-' || val === '>' || val === '|' || val === '|-') {
      const block = []; while (i + 1 < lines.length && (/^\s+/.test(lines[i + 1]) || !lines[i + 1].trim())) block.push(lines[++i].trim());
      fm[key] = val.startsWith('>') ? block.join(' ').replace(/\s+/g, ' ').trim() : block.join('\n');
    } else if (val === '') {
      const list = []; while (i + 1 < lines.length && /^\s*-\s+/.test(lines[i + 1])) list.push(lines[++i].replace(/^\s*-\s+/, '').trim().replace(/^["']|["']$/g, ''));
      fm[key] = list;
    } else if (/^".*"$/.test(val) || /^'.*'$/.test(val)) fm[key] = val.slice(1, -1);
    else if (val === 'true' || val === 'false') fm[key] = val === 'true';
    else fm[key] = val;
  }
  return fm;
}
const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/;

// ---------- JSON + plugin.json ----------
for (const f of FILES.filter((p) => p.endsWith('.json'))) { try { JSON.parse(read(f)); } catch (e) { err(`${f}: invalid JSON: ${e.message}`); } }
const pj = JSON.parse(read('plugin.json'));
const PJ_FIELDS = new Set(['$schema', 'name', 'displayName', 'description', 'version', 'disabled', 'logo', 'suggestedPrompts', 'skills', 'author', 'homepage', 'repository', 'license', 'keywords', 'extensions']);
for (const k of Object.keys(pj)) if (!PJ_FIELDS.has(k)) err(`plugin.json: field ${k} is not in the v1 schema (additionalProperties: false)`);
if (!KEBAB.test(pj.name || '')) err('plugin.json: name missing or not kebab-case');
if ((pj.suggestedPrompts || []).length > 3) err('plugin.json: more than 3 suggestedPrompts');
if (pj.logo && !exists(pj.logo)) err(`plugin.json: logo ${pj.logo} missing`);
if (pj.version && !/^\d+\.\d+\.\d+([-+].+)?$/.test(pj.version)) err('plugin.json: version is not semver');
ok('JSON files + plugin.json');

// ---------- skills ----------
const skillNames = new Set();
for (const d of readdirSync(join(ROOT, 'skills')).sort()) {
  const p = `skills/${d}/SKILL.md`;
  if (!statSync(join(ROOT, 'skills', d)).isDirectory()) continue;
  if (!exists(p)) { err(`skills/${d}: missing SKILL.md`); continue; }
  const fm = frontmatter(p); if (!fm) { err(`${p}: no frontmatter`); continue; }
  if (fm.name !== d) err(`${p}: name "${fm.name}" != folder "${d}"`);
  if (!KEBAB.test(d) || d.length > 64) err(`${p}: bad skill name`);
  const desc = String(fm.description || '');
  if (!desc || desc.length > 1024) err(`${p}: description missing or > 1024 chars (${desc.length})`);
  if (!/Definition of done/i.test(read(p))) err(`${p}: no "Definition of done" section`);
  skillNames.add(d);
}
ok(`${skillNames.size} skills`);

// ---------- agents ----------
const TOOLS = new Set(['view_file', 'write_to_file', 'replace_file_content', 'multi_replace_file_content', 'list_dir', 'find_by_name',
  'grep_search', 'search_web', 'read_url_content', 'run_command', 'manage_task', 'schedule', 'list_permissions', 'ask_permission',
  'invoke_subagent', 'define_subagent', 'send_message', 'manage_subagents', 'ask_question', 'generate_image']);
const agentNames = new Set();
for (const f of readdirSync(join(ROOT, 'agents')).filter((x) => x.endsWith('.md')).sort()) {
  const p = `agents/${f}`; const fm = frontmatter(p);
  if (!fm) { err(`${p}: no frontmatter`); continue; }
  const name = basename(f, '.md'); agentNames.add(name);
  if (fm.name !== name) err(`${p}: name "${fm.name}" != file name`);
  if (!fm.description) err(`${p}: description missing`);
  if (!['inherit', 'flash_lite', 'flash', 'pro', undefined].includes(fm.model)) err(`${p}: bad model ${fm.model}`);
  if (!['off', 'auto', 'eager', 'sandbox', undefined].includes(fm.commandExecutionPolicy)) err(`${p}: bad commandExecutionPolicy`);
  for (const b of ['mainAgent', 'subagent', 'inheritMcp', 'inheritCustomizations']) if (fm[b] !== undefined && typeof fm[b] !== 'boolean') err(`${p}: ${b} must be true/false`);
  if (fm.tools !== undefined && !Array.isArray(fm.tools)) err(`${p}: tools must be a list`);
  for (const t of fm.tools || []) if (!TOOLS.has(t)) err(`${p}: unknown tool "${t}" (a misspelled tool can hang the subagent)`);
  for (const s of fm.skills || []) if (!skillNames.has(s) && !exists(join(s, 'SKILL.md'))) err(`${p}: skill ${s} not found`);
  const body = read(p);
  for (const sec of ['## Role', '## Never', 'Single-agent mode']) if (!body.includes(sec)) err(`${p}: missing section "${sec}"`);
  if (!/## Checklist/.test(body)) err(`${p}: missing a "## Checklist" section`);
  if (fm.commandExecutionPolicy === 'sandbox' && /git push|hw\.mjs" (pr-|wait-ci|merge)/.test(body)) err(`${p}: needs the network (push / GitHub) but runs in the sandbox (no network): use auto`);
  if (fm.subagent !== false && !(fm.tools || []).includes('send_message')) err(`${p}: a sub-agent needs send_message to report back`);
}
ok(`${agentNames.size} agents`);

// ---------- rules ----------
for (const f of readdirSync(join(ROOT, 'rules')).filter((x) => x.endsWith('.md'))) {
  const p = `rules/${f}`;
  if (Buffer.byteLength(read(p)) > 24000) err(`${p}: over 24,000 bytes (Antigravity rule limit)`);
  if (['AGENTS.md', 'GEMINI.md'].includes(f)) { if (/^---\n/.test(read(p))) err(`${p}: must not have frontmatter`); continue; }
  const fm = frontmatter(p); if (!fm) { err(`${p}: no frontmatter (the rule would be dropped silently)`); continue; }
  if (!['always_on', 'model_decision', 'glob', 'manual'].includes(fm.trigger)) err(`${p}: bad trigger ${fm.trigger}`);
  if (fm.trigger === 'model_decision' && !fm.description) err(`${p}: model_decision needs a description`);
  if (fm.trigger === 'glob' && typeof (fm.globs ?? fm.glob) !== 'string') err(`${p}: globs must be a comma-separated string`);
}
ok('rules');

// ---------- hooks ----------
const EVENTS = new Set(['SessionStart', 'PreToolUse', 'PostToolUse', 'PreInvocation', 'PostInvocation', 'Stop']);
const hooks = JSON.parse(read('hooks.json'));
for (const [name, h] of Object.entries(hooks)) {
  for (const [ev, v] of Object.entries(h)) {
    if (ev === 'enabled') continue;
    if (!EVENTS.has(ev)) { err(`hooks.json:${name}: unknown event ${ev}`); continue; }
    for (const entry of v) {
      const handlers = ['PreToolUse', 'PostToolUse'].includes(ev) ? (entry.matcher && entry.hooks?.length ? entry.hooks : (err(`hooks.json:${name}:${ev}: needs matcher + hooks`), [])) : [entry];
      if (entry.matcher) try { new RegExp(entry.matcher); } catch { err(`hooks.json:${name}: matcher is not a valid regex`); }
      for (const hd of handlers) {
        const cmd = String(hd.command || '');
        if (!cmd) err(`hooks.json:${name}:${ev}: handler without command`);
        if (cmd.includes('${PLUGIN_ROOT}')) err(`hooks.json:${name}: use ./relative paths (cwd = plugin root), not \${PLUGIN_ROOT}`);
        if (!/^node \.\//.test(cmd)) err(`hooks.json:${name}: run hooks with "node ./scripts/…" (python / bash are missing on stock Windows)`);
        for (const tok of cmd.split(/\s+/)) if (tok.startsWith('./') && !exists(tok.slice(2))) err(`hooks.json:${name}: ${tok} missing`);
      }
    }
  }
}
ok('hooks.json');

// ---------- cross references ----------
const DOCS = FILES.filter((p) => /^(skills|agents|rules|resources\/templates|examples)\/.*\.(md|tmpl|env|example)$/.test(p) || /^(AGENTS|README)\.md$/.test(p));
const hwSrc = read('scripts/hw.mjs');
const helpKeys = new Set([...hwSrc.slice(hwSrc.indexOf('const HELP = {'), hwSrc.indexOf('const commands = {')).matchAll(/^\s+'?([a-z][a-z-]*)'?:\s*'/gm)].map((m) => m[1]));
const cmdKeys = new Set([...hwSrc.slice(hwSrc.indexOf('const commands = {')).matchAll(/^\s{2}async\s+'?([a-z][a-z-]*)'?\(\)/gm)].map((m) => m[1]));
for (const k of cmdKeys) if (!helpKeys.has(k)) err(`hw.mjs: command ${k} has no HELP line`);
for (const k of helpKeys) if (!cmdKeys.has(k)) err(`hw.mjs: HELP lists ${k} but there is no such command`);
const V1_SCRIPTS = ['validate_kit.sh', 'new_adr.sh', 'verify.sh', 'pr_status.sh', 'wait_ci.sh', 'verify_deploy.sh', 'install.sh', 'common.sh',
  'guard_command.py', 'guard_secrets.py', 'commit_gate.py', 'session_start.py', '_common.py', 'test_hooks.py'];
const V1_SKILLS = ['ship-change', 'pr-review-loop', 'verify-release', 'project-bootstrap'];
for (const p of DOCS) {
  const t = read(p);
  if (/^(skills|agents|rules|resources|examples)\//.test(p)) {
    for (const m of t.matchAll(/\bhw-[a-z]+(?:-[a-z]+)*\b/g)) if (t[m.index - 1] !== '<' && !skillNames.has(m[0])) err(`${p}: names skill ${m[0]}, which does not exist`);
    for (const m of t.matchAll(/hw\.mjs"\s+([a-z][a-z-]+)|`hw\.mjs ([a-z][a-z-]+)/g)) if (!cmdKeys.has(m[1] || m[2])) err(`${p}: uses \`hw.mjs ${m[1] || m[2]}\`, which does not exist`);
    for (const m of t.matchAll(/resources\/templates\/([\w.-]+(?:\/[\w.-]+)?)/g)) if (!exists(`resources/templates/${m[1].replace(/[.,)]+$/, '')}`)) err(`${p}: template ${m[1]} not found`);
    for (const m of t.matchAll(/<KIT>\/agents\/([a-z-]+)\.md/g)) if (!agentNames.has(m[1])) err(`${p}: agent ${m[1]} not found`);
  }
  // removed v1 scripts: never referenced anywhere (README / AGENTS included); CHANGELOG.md is history and not checked
  for (const v1 of V1_SCRIPTS) if (new RegExp(`(^|[^\\w.-])${v1.replace(/[.]/g, '\\.')}\\b`).test(t)) err(`${p}: refers to the removed v1 script ${v1}`);
  if (/^(README|AGENTS)\.md$/.test(p)) {
    for (const s of V1_SKILLS) if (new RegExp(`(^|[^\\w-])${s}(?![\\w-])`).test(t) && !skillNames.has(s)) err(`${p}: names the removed v1 skill ${s} (v2 skills are hw-*)`);
    for (const m of t.matchAll(/\bhw-[a-z]+(?:-[a-z]+)*\b/g)) if (!skillNames.has(m[0])) err(`${p}: names skill ${m[0]}, which does not exist`);
    for (const m of t.matchAll(/hw\.mjs"\s+([a-z][a-z-]+)|`hw\.mjs ([a-z][a-z-]+)|scripts\/hw\.mjs ([a-z][a-z-]+)/g)) if (!cmdKeys.has(m[1] || m[2] || m[3])) err(`${p}: uses \`hw.mjs ${m[1] || m[2] || m[3]}\`, which does not exist`);
    for (const m of t.matchAll(/\]\((?!https?:|#)([^)\s]+)\)/g)) if (!exists(m[1])) err(`${p}: link target ${m[1]} does not exist`);
  }
}
const start = read('skills/hw-start/SKILL.md');
const routing = start.slice(start.indexOf('### 3b'), start.indexOf('## Step 4'));
for (const m of routing.matchAll(/\|\s*([a-z][a-z-]+)\s*\|\s*$/gm)) if (m[1] !== 'parent' && !agentNames.has(m[1])) err(`hw-start routing table: agent ${m[1]} has no agents/${m[1]}.md`);
if (!agentNames.has('parent-agent')) err('agents/parent-agent.md missing (hw-start delegates through it)');
const exampleText = read('resources/templates/workflow.env.example');
const example = parseEnv(exampleText);
for (const m of exampleText.matchAll(/^#\s*([A-Z][A-Z0-9_]+)=/gm)) example[m[1]] ??= ''; // documented but commented out
const LEGACY = new Set(['ANALYZE_CMD', 'TEST_CMD', 'SEED_CHECK_CMD', 'BUILD_CMD', 'FINGERPRINT_CMD']); // still read for v1 configs
for (const m of new Set([...hwSrc.matchAll(/\bc\.([A-Z][A-Z0-9_]+)/g)].map((x) => x[1]))) {
  if (!(m in example) && !LEGACY.has(m)) err(`hw.mjs reads ${m}, which workflow.env.example does not document`);
}
ok(`cross references (${cmdKeys.size} hw.mjs commands)`);

// ---------- examples (install-profile layout) ----------
for (const name of readdirSync(join(ROOT, 'examples'))) {
  const dir = `examples/${name}/agents-dir`;
  if (!exists(dir)) { err(`examples/${name}: no agents-dir/ (hw.mjs install profile copies it into <project>/.agents/)`); continue; }
  if (exists(`${dir}/workflow.env`)) {
    const env = parseEnv(read(`${dir}/workflow.env`));
    for (const k of Object.keys(env)) if (!(k in example) && !LEGACY.has(k)) err(`${dir}/workflow.env: key ${k} is not in workflow.env.example`);
  }
  if (exists(`${dir}/rules`)) {
    for (const f of readdirSync(join(ROOT, dir, 'rules'))) {
      const fm = frontmatter(`${dir}/rules/${f}`);
      if (!fm || !['always_on', 'model_decision', 'glob', 'manual'].includes(fm.trigger)) err(`${dir}/rules/${f}: needs frontmatter with a valid trigger`);
    }
  }
  for (const f of FILES.filter((p) => p.startsWith(`${dir}/`) && p.endsWith('.md'))) if (Buffer.byteLength(read(f)) > 24000) err(`${f}: over 24,000 bytes`);
}
ok('examples');

// ---------- syntax + tests ----------
for (const f of FILES.filter((p) => p.endsWith('.mjs'))) {
  const r = spawnSync(process.execPath, ['--check', join(ROOT, f)], { encoding: 'utf8' });
  if (r.status !== 0) err(`${f}: node --check failed: ${(r.stderr || '').split('\n').slice(0, 4).join(' ')}`);
}
ok('node --check');
let testsFailed = false;
if (!NO_TESTS) {
  for (const t of ['scripts/test_hooks.mjs', 'scripts/test_hw.mjs']) {
    const r = spawnSync(process.execPath, [join(ROOT, t)], { encoding: 'utf8', timeout: 300000 });
    process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
    if (r.status !== 0) { testsFailed = true; err(`${t} failed`); }
  }
} else console.log('SKIP tests (--no-tests)');
const agy = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['agy'], { encoding: 'utf8' });
if (agy.status === 0) {
  const r = spawnSync('agy', ['plugin', 'validate', '--strict', ROOT], { encoding: 'utf8', shell: process.platform === 'win32' });
  process.stdout.write(r.stdout || ''); if (r.status !== 0) err(`agy plugin validate --strict failed: ${(r.stderr || '').slice(0, 300)}`);
} else console.log('SKIP agy plugin validate (Antigravity CLI not installed)');

for (const b of bad) console.log(`FAIL ${b}`);
console.log(`VALIDATE: ${bad.length ? `FAIL (${bad.length})` : 'PASS'}${testsFailed ? ' — tests failed' : ''}`);
process.exitCode = bad.length ? 1 : 0;

