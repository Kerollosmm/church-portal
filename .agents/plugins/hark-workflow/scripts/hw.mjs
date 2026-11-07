#!/usr/bin/env node
// hw.mjs — the hark-workflow helper CLI. One file, zero dependencies, Node >= 18, Windows / macOS / Linux.
//
// Run `node <KIT>/scripts/hw.mjs help` for the command list. Every command prints a last line that starts with an
// UPPER-CASE verdict (GATE: PASS, CI: GREEN, ...) so an agent can copy it into STATUS.md as evidence.
import { execFileSync, spawnSync } from 'node:child_process';
import {
  appendFileSync, copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { homedir, platform } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { gzipSync } from 'node:zlib';
import { KIT_DIR, currentBranch, defaults, git, gitRoot, loadConfig, mainRoot } from './lib/config.mjs';
import { botWait, pickChannelUrl } from './lib/pure.mjs';

// Behind an HTTP(S) proxy, Node's fetch needs NODE_USE_ENV_PROXY=1 (Node >= 22.18 / 24). Re-exec once with it.
if ((process.env.HTTPS_PROXY || process.env.https_proxy) && !process.env.NODE_USE_ENV_PROXY && !process.env.HW_NO_REEXEC) {
  const r = spawnSync(process.execPath, ['--no-warnings', ...process.argv.slice(1)], {
    stdio: 'inherit', env: { ...process.env, NODE_USE_ENV_PROXY: '1', HW_NO_REEXEC: '1',
      NODE_EXTRA_CA_CERTS: process.env.NODE_EXTRA_CA_CERTS || process.env.SSL_CERT_FILE || '' },
  });
  process.exit(r.status ?? 1);
}

const IS_WIN = platform() === 'win32';
process.stdout.on('error', (e) => { if (e.code === 'EPIPE') process.exit(0); });
const argv = process.argv.slice(2);
const CMD = argv[0] || 'help';

// ---------- small utils ----------
const out = (s = '') => process.stdout.write(s + '\n');
const err = (s = '') => process.stderr.write(s + '\n');
function die(msg, code = 1) { err(`ERROR: ${msg}`); process.exit(code); }
function opts(list, spec = {}) {
  // spec: { name: 'string'|'bool'|'list' }
  const o = { _: [] };
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a.startsWith('--')) {
      const [k, inline] = a.slice(2).split(/=(.*)/s);
      const t = spec[k];
      if (!t) die(`unknown option --${k} (see: hw.mjs help ${CMD})`);
      if (t === 'bool') o[k] = true;
      else {
        const v = inline !== undefined ? inline : list[++i];
        if (v === undefined) die(`--${k} needs a value`);
        if (t === 'list') (o[k] ||= []).push(v); else o[k] = v;
      }
    } else o._.push(a);
  }
  return o;
}
function sh(cmd, cwd, env) { // run through the platform shell, capture output
  const r = spawnSync(cmd, { cwd, shell: true, encoding: 'utf8', env: { ...process.env, ...env }, maxBuffer: 1 << 28 });
  return { code: r.status ?? 1, out: (r.stdout || '') + (r.stderr || '') };
}
function have(bin) {
  const r = spawnSync(IS_WIN ? 'where' : 'which', [bin], { encoding: 'utf8' });
  return r.status === 0 ? (r.stdout || '').split(/\r?\n/)[0].trim() : null;
}
function pythonCmd() {
  for (const c of ['python3', 'python', 'py']) {
    const r = spawnSync(c, c === 'py' ? ['-3', '--version'] : ['--version'], { encoding: 'utf8' });
    if (r.status === 0 && /Python 3/.test((r.stdout || '') + (r.stderr || ''))) return c === 'py' ? 'py -3' : c;
  }
  return null;
}
function ctx() {
  const { conf, root, file } = loadConfig(process.cwd());
  return { c: defaults(conf), root, file, main: mainRoot(root) || root };
}
function nowStamp(tz) { return stamp(new Date(), tz); }
function stamp(d, tz) {
  try {
    const zone = tz || Intl.DateTimeFormat().resolvedOptions().timeZone;
    const s = d.toLocaleString('sv-SE', { timeZone: zone, hour12: false }).slice(0, 16);
    return `${s} ${zone}`;
  } catch { return d.toISOString().slice(0, 16).replace('T', ' ') + ' UTC'; }
}
function readText(p) { return readFileSync(p, 'utf8'); }
function bodyArg(o) {
  if (o['body-file']) return readText(o['body-file']);
  if (o.body !== undefined) return o.body;
  die('give --body-file <file> (preferred) or --body "<text>"');
}
const kb = (n) => `${n.toLocaleString('en-US')} B`;
const signed = (n) => (n >= 0 ? '+' : '') + n.toLocaleString('en-US');

// ---------- GitHub ----------
let TOKEN;
function token() {
  if (TOKEN !== undefined) return TOKEN;
  TOKEN = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '';
  if (!TOKEN && have('gh')) {
    try { TOKEN = execFileSync('gh', ['auth', 'token'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { TOKEN = ''; }
  }
  if (!TOKEN && !process.env.HW_ALLOW_NO_TOKEN) err('WARN: no GitHub token (set GITHUB_TOKEN or run `gh auth login`); trying without one');
  return TOKEN;
}
function repoSlug(c, root) {
  if (c.GITHUB_REPO) return c.GITHUB_REPO;
  const url = (git(['remote', 'get-url', 'origin'], root) || '').replace(/\.git$/, '');
  const m = url.match(/github\.com[:/]+([^/]+\/[^/]+)$/);
  if (!m) throw new Error('cannot tell the GitHub repo: set GITHUB_REPO="owner/repo" in .agents/workflow.env');
  return m[1];
}
async function gh(method, path, body, { raw = false, accept } = {}) {
  const api = (process.env.HW_GITHUB_API || 'https://api.github.com').replace(/\/$/, ''); // override: GitHub Enterprise or a test stub
  const url = path.startsWith('http') ? path : `${api}/${path.replace(/^\//, '')}`;
  const headers = { Accept: accept || 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'hark-workflow' };
  const t = token(); if (t) headers.Authorization = `Bearer ${t}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  let res;
  for (let attempt = 0; attempt < 3; attempt++) {
    res = await fetch(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), redirect: 'follow' });
    if (res.status >= 500 && attempt < 2) { await sleep(3000 * (attempt + 1)); continue; }
    break;
  }
  if (res.status === 429 || (res.status === 403 && res.headers.get('x-ratelimit-remaining') === '0')) {
    const reset = res.headers.get('x-ratelimit-reset');
    throw Object.assign(new Error(`GitHub rate limit. Stop and retry after ${reset ? new Date(reset * 1000).toISOString() : 'one minute'}. Do not loop.`), { exitCode: 4 });
  }
  const text = await res.text();
  if (!res.ok) throw new Error(`GitHub ${method} ${path} -> HTTP ${res.status}: ${text.slice(0, 400)}`);
  if (raw) return text;
  return text ? JSON.parse(text) : {};
}
async function graphql(query, variables) {
  const r = await gh('POST', process.env.HW_GITHUB_GRAPHQL || 'graphql', { query, variables });
  if (r.errors?.length) throw new Error(`GraphQL: ${r.errors.map((e) => e.message).join('; ')}`);
  return r.data;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function headSha(slug, target) {
  if (/^\d{1,6}$/.test(target)) return (await gh('GET', `repos/${slug}/pulls/${target}`)).head.sha;
  return (await gh('GET', `repos/${slug}/commits/${target}`)).sha;
}
const PASS_CONCL = new Set(['success', 'skipped', 'neutral']);
async function ciState(slug, sha, ignoreRe) {
  const runs = (await gh('GET', `repos/${slug}/commits/${sha}/check-runs?per_page=100`)).check_runs.filter((r) => !ignoreRe || !ignoreRe.test(r.name));
  const st = await gh('GET', `repos/${slug}/commits/${sha}/status`);
  const items = [
    ...runs.map((r) => ({ kind: 'check', name: r.name, state: r.status !== 'completed' ? 'pending' : (PASS_CONCL.has(r.conclusion) ? 'ok' : 'fail'), detail: r.conclusion || r.status, url: r.html_url, id: r.id })),
    ...st.statuses.map((s) => ({ kind: 'status', name: s.context, state: s.state === 'pending' ? 'pending' : (s.state === 'success' ? 'ok' : 'fail'), detail: s.state, url: s.target_url || '' })),
  ];
  return items;
}

// ---------- commands ----------
const HELP = {
  help: 'help [command]                      this text',
  kit: 'kit                                 print the absolute kit folder (write it into STATUS.md as KIT)',
  doctor: 'doctor                              check git, node, gh login, flutter, java, npm, python, chrome, repo, config',
  config: 'config                              print the effective .agents/workflow.env values',
  status: 'status init|log|set|show <topic> …  STATUS.md: init <topic> --goal "…"; log <topic> "msg"; set <topic> <key> "<value>"; show <topic>',
  gate: 'gate [--quick] [--no-build] [--keep-going] [--only a,b] [--status <topic>]   the local gate with evidence; --only runs just the named steps (setup, analyze, tests, seed, rules, build, post-build, extra-N)',
  size: 'size [--file F] [--baseline-raw B] [--baseline-gz B] [--budget-gz B] [--status <topic>]   raw + gzip-9 size of SIZE_FILE vs baseline; the flags override SIZE_BASELINE_RAW / SIZE_BASELINE_GZ / SIZE_BUDGET_GZ (exit 1 over budget)',
  'adr-next': 'adr-next                            next free ADR number (tree + origin/<default> + open PRs + remote branches)',
  'adr-new': 'adr-new "<title>" [--pr N] [--id ADR-NNN]   insert an ADR block from the template',
  'pr-create': 'pr-create --base B --head H --title T --body-file F   open a DRAFT pull request',
  'pr-edit': 'pr-edit <n> [--body-file F] [--title T] [--base B]   update a PR (body / title / base)',
  'pr-status': 'pr-status <n> [--json]              state, head, checks + statuses, reviews, unresolved threads, bot comments',
  'wait-ci': 'wait-ci <pr|sha> [--timeout 2700] [--interval 30]   wait for every check run + commit status (exit 0 green, 1 red, 2 timeout, 3 none)',
  'ci-logs': 'ci-logs <pr|sha> [--lines 80]       failed jobs: save logs to .work/_logs and print the error lines',
  'ci-rerun': 'ci-rerun <run-id>                   re-run the FAILED jobs of a finished run, once (refused when the run was already re-run)',
  dispatch: 'dispatch <workflow> [--ref B] [--input k=v]…   start a workflow_dispatch run (workflow = file name, id or name) and print its run id',
  'wait-run': 'wait-run <run-id> | wait-run latest --workflow W [--branch B]  [--timeout 1800] [--interval 30] [--status <topic>]   wait for one Actions run (exit 0 success, 1 failed, 2 timeout)',
  'pr-ready': 'pr-ready <n> --approval "<owner words + time>"   mark a draft PR ready for review (only with the owner\'s OK)',
  'pr-checkout': 'pr-checkout <n> [--dir D]           read-only detached worktree of a PR head (forks too) under WORKTREE_ROOT/review-pr-<n>',
  bots: 'bots [--prs 15]                     which review bots are active on this repo (seen on recent PRs)',
  'bots-wait': 'bots-wait <n> [--bot coderabbitai]   read the bot\'s newest rate-limit comment: retry time (exit 0 ready / no limit, 2 wait)',
  'review-request': 'review-request <n> [--bots "coderabbitai sentry"]   post "@<bot> review" (one comment per bot)',
  threads: 'threads <n> [--all]                 review threads with ids (thread id, comment id, file:line, author)',
  reply: 'reply <n> <commentId> --body-file F  reply inside a review thread',
  resolve: 'resolve <threadId>                  mark a review thread resolved',
  comment: 'comment <n> --body-file F           PR conversation comment',
  merge: 'merge <n> --sha <headSha> --approval "<owner words + time>"   squash-merge with a head-SHA guard',
  'deploy-verify': 'deploy-verify [--sha S] [--expect STR]… [--absent STR]… [--path P]… [--url U] [--workflow name|file.yml]   deploy run jobs + live 200 + bundle strings',
  'sentry-issues': 'sentry-issues --since <ISO time | 90m | 2h> [--env E] [--org O] [--project P] [--status <topic>]   new Sentry issues first seen since then (SENTRY_TOKEN; exit 0 none, 1 new, 3 not checked)',
  'dev-channel-url': 'dev-channel-url [--run <id>] [--workflow W]   channel URL printed by the latest successful dev deploy run vs DEV_URL (exit 0 same, 1 changed, 3 not found)',
  psi: 'psi [<url>] [--strategy mobile|desktop|both] [--runs 3] [--status <topic>]   PageSpeed median vs PSI_BASELINE_*',
  screenshot: 'screenshot <url> [--width 390] [--height 844] [--out file.png]   headless Chrome screenshot',
  worktree: 'worktree <new-branch> --base <base-branch> | worktree <branch> --existing | worktree list   one worktree per PR under WORKTREE_ROOT (never on main); --existing checks out a branch already on origin',
  install: 'install workspace <project> | global | profile <name> <project> [--force] | skills <dir>   put the kit where Antigravity reads it; profile copies examples/<name>/agents-dir/ into <project>/.agents/',
  api: 'api <GET|POST|PATCH|PUT|DELETE> <path> [--body-file F]   raw GitHub REST call (escape hatch)',
};

const commands = {
  async help() {
    const which = argv[1];
    if (which && HELP[which]) { out(`node hw.mjs ${HELP[which]}`); return; }
    out('hark-workflow helper — node <KIT>/scripts/hw.mjs <command>\n');
    for (const v of Object.values(HELP)) out('  ' + v);
    out('\nConfig: <repo>/.agents/workflow.env. GitHub auth: GITHUB_TOKEN / GH_TOKEN or `gh auth login`.');
  },

  async kit() { out(KIT_DIR); },

  async config() {
    const { c, root, file } = ctx();
    out(`repo: ${root}\nconfig: ${file || 'MISSING (.agents/workflow.env)'}`);
    for (const [k, v] of Object.entries(c).sort()) out(`${k}=${JSON.stringify(v)}`);
  },

  async doctor() {
    const { c, root, file } = ctx();
    const rows = [];
    const add = (ok, name, detail) => rows.push([ok, name, detail]);
    const ver = (bin, args = ['--version']) => {
      const r = spawnSync(bin, args, { encoding: 'utf8', shell: IS_WIN });
      return r.status === 0 ? ((r.stdout || r.stderr || '').split(/\r?\n/).find((l) => l.trim()) || '').trim() : null;
    };
    const nodeMajor = Number(process.versions.node.split('.')[0]);
    add(nodeMajor >= 18 ? 'ok' : 'fail', 'node', `v${process.versions.node}${nodeMajor < 18 ? ' (need >= 18)' : ''}`);
    const g = ver('git'); add(g ? 'ok' : 'fail', 'git', g || 'not found');
    const ghv = ver('gh');
    if (ghv) {
      const a = spawnSync('gh', ['auth', 'status'], { encoding: 'utf8', shell: IS_WIN });
      add(a.status === 0 ? 'ok' : 'warn', 'gh', a.status === 0 ? 'signed in' : 'installed, NOT signed in: run `gh auth login`');
    } else add(process.env.GITHUB_TOKEN || process.env.GH_TOKEN ? 'ok' : 'warn', 'gh', process.env.GITHUB_TOKEN || process.env.GH_TOKEN ? 'not installed; GITHUB_TOKEN set' : 'not installed and no GITHUB_TOKEN: GitHub commands will fail (https://cli.github.com)');
    const stack = c.STACK && c.STACK !== 'auto' ? c.STACK : detectStack(root);
    const envFile = c.GATE_ENV_SCRIPT && !IS_WIN ? resolve(root || '.', c.GATE_ENV_SCRIPT) : '';
    if (stack.startsWith('flutter')) {
      let f = ver('flutter');
      if (!f && envFile && existsSync(envFile)) { const r = sh(`. "${envFile}" >/dev/null 2>&1 && flutter --version`, root); if (r.code === 0) f = `${(r.out.split(/\r?\n/).find((l) => l.trim()) || '').trim()} (via GATE_ENV_SCRIPT)`; }
      add(f ? 'ok' : 'fail', 'flutter', f || 'not on PATH');
    }
    if (stack === 'flutter-firebase' || stack === 'node' || existsSync(join(root, 'package.json'))) {
      const n = ver('npm'); add(n ? 'ok' : 'warn', 'npm', n || 'not found');
    }
    if (stack === 'flutter-firebase') { const j = ver('java', ['-version']); add(j ? 'ok' : 'warn', 'java', j || 'not found (Firestore rules emulator tests need Java 11+)'); }
    const py = pythonCmd(); add(py ? 'ok' : 'warn', 'python', py ? `${py}` : 'not found (needed for tool/*.py in some repos)');
    const ch = findChrome(); add(ch ? 'ok' : 'warn', 'chrome', ch || 'not found (screenshots: ask the owner to run /browser)');
    add(root && gitRoot(root) ? 'ok' : 'fail', 'repo', root ? `${root} on branch ${currentBranch(root) || '?'}` : 'not a git repo');
    if (c.SENTRY_ORG || c.SENTRY_PROJECT) add(process.env.SENTRY_TOKEN || process.env.SENTRY_AUTH_TOKEN ? 'ok' : 'warn', 'sentry', process.env.SENTRY_TOKEN || process.env.SENTRY_AUTH_TOKEN ? `token set (${c.SENTRY_ORG}/${c.SENTRY_PROJECT})` : 'SENTRY_ORG/PROJECT set but no SENTRY_TOKEN: sentry-issues says NOT CHECKED');
    add(file ? 'ok' : 'warn', 'config', file ? relative(root, file) : '.agents/workflow.env MISSING (skill hw-bootstrap)');
    add('ok', 'kit', KIT_DIR);
    for (const [ok, name, detail] of rows) out(`${ok === 'ok' ? 'OK  ' : ok === 'warn' ? 'WARN' : 'FAIL'}  ${name.padEnd(8)} ${detail}`);
    const bad = rows.filter((r) => r[0] === 'fail').length;
    out(`DOCTOR: ${bad ? `FAIL (${bad})` : 'OK'}`);
    process.exitCode = bad ? 1 : 0;
  },

  async status() {
    const [sub, topic, ...rest] = argv.slice(1);
    if (!sub || !topic) die('usage: status init|log|set|show <topic> …');
    const { c, main: root } = ctx();
    const dir = join(root, c.STATUS_DIR, topic);
    const file = join(dir, 'STATUS.md');
    if (sub === 'init') {
      const o = opts(rest, { goal: 'string', force: 'bool' });
      if (existsSync(file) && !o.force) { out(`exists: ${file}`); out('STATUS: EXISTS (read it and continue from "Next action")'); return; }
      mkdirSync(dir, { recursive: true });
      const tpl = readText(join(KIT_DIR, 'resources', 'templates', 'STATUS.md'));
      const filled = tpl.replaceAll('{{TOPIC}}', topic).replaceAll('{{GOAL}}', o.goal || '(fill in)')
        .replaceAll('{{KIT}}', KIT_DIR).replaceAll('{{REPO}}', root).replaceAll('{{NOW}}', nowStamp(c.TIMEZONE))
        .replaceAll('{{LANG}}', c.OWNER_LANGUAGE || 'en');
      writeFileSync(file, filled);
      ensureIgnored(root, c.STATUS_DIR);
      out(file); out('STATUS: CREATED');
    } else if (sub === 'log') {
      if (!existsSync(file)) die(`no ${file}: run status init ${topic} first`);
      const msg = rest.join(' ').trim(); if (!msg) die('give a message');
      appendFileSync(file, `- ${nowStamp(c.TIMEZONE)} — ${msg.replace(/\r?\n/g, ' ')}\n`);
      out('STATUS: LOGGED');
    } else if (sub === 'set') {
      if (!existsSync(file)) die(`no ${file}: run status init ${topic} first`);
      const [key, ...val] = rest; if (!key) die('usage: status set <topic> <key> "<value>"');
      const value = val.join(' ').replace(/\|/g, '/');
      const txt = readText(file);
      const re = new RegExp(`^\\| ${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} \\|.*\\|$`, 'm');
      const row = `| ${key} | ${value} |`;
      writeFileSync(file, re.test(txt) ? txt.replace(re, row) : txt.replace(/(\| Key \| Value \|\n\|---\|---\|\n)/, `$1${row}\n`));
      out(`STATUS: SET ${key}`);
    } else if (sub === 'show') {
      if (!existsSync(file)) die(`no ${file}`);
      out(readText(file));
    } else die(`unknown status subcommand ${sub}`);
  },

  async gate() {
    const o = opts(argv.slice(1), { quick: 'bool', 'no-build': 'bool', 'keep-going': 'bool', status: 'string', only: 'string' });
    const { c, root } = ctx();
    const stack = c.STACK && c.STACK !== 'auto' ? c.STACK : detectStack(root);
    const steps = gateSteps(c, root, stack, o);
    if (!steps.length) die(`nothing to run for stack "${stack}": set GATE_* commands in .agents/workflow.env`);
    const logDir = join(root, c.STATUS_DIR, '_logs'); mkdirSync(logDir, { recursive: true }); ensureIgnored(root, c.STATUS_DIR);
    const env = { NO_PROXY: [process.env.NO_PROXY, '127.0.0.1,localhost'].filter(Boolean).join(','), no_proxy: [process.env.no_proxy, '127.0.0.1,localhost'].filter(Boolean).join(',') };
    const results = []; let tests = ''; let failed = 0;
    out(`gate: stack ${stack}, ${o.quick ? 'quick' : 'full'}, repo ${root}`);
    if (c.GATE_ENV_SCRIPT) { // e.g. a toolchain env file (PATH to Flutter, PUB_CACHE) sourced before every step
      const envFile = resolve(root, c.GATE_ENV_SCRIPT);
      if (!existsSync(envFile)) out(`env:  ${c.GATE_ENV_SCRIPT} not found — skipped (tools come from PATH)`);
      else if (IS_WIN) out(`env:  ${c.GATE_ENV_SCRIPT} skipped on Windows (POSIX shell file)`);
      else { out(`env:  sourcing ${envFile} before each step`); for (const s2 of steps) if (s2.cmd) s2.cmd = `. "${envFile}" >/dev/null 2>&1 && ${s2.cmd}`; }
    }
    for (const s of steps) {
      if (s.skip) { results.push(['SKIP', s.name, s.skip]); out(`SKIP  ${s.name}: ${s.skip}`); continue; }
      out(`RUN   ${s.name}: ${s.cmd}`);
      const t0 = Date.now();
      const r = sh(s.cmd, root, env);
      const secs = Math.round((Date.now() - t0) / 1000);
      const logf = join(logDir, `gate-${s.name.replace(/[^a-z0-9]+/gi, '_')}.log`);
      writeFileSync(logf, r.out);
      if (s.name === 'tests') tests = testCount(r.out) || tests;
      if (r.code === 0) { results.push(['PASS', s.name, `${secs}s`]); out(`PASS  ${s.name} (${secs}s)`); }
      else {
        failed++; results.push(['FAIL', s.name, `${secs}s, log ${relative(root, logf)}`]);
        out(`FAIL  ${s.name} (${secs}s) — last lines:`); out(r.out.trim().split(/\r?\n/).slice(-40).join('\n'));
        if (!o['keep-going']) break;
      }
    }
    let sizeLine = '';
    const builtNow = results.some((r) => r[0] === 'PASS' && r[1] === 'build');
    if (!failed && !o.quick && !o['no-build'] && c.SIZE_FILE && (builtNow || (!o.only && existsSync(join(root, c.SIZE_FILE))))) sizeLine = sizeReport(c, root).line;
    out('\n== gate summary ==');
    for (const [v, n, d] of results) out(`${v.padEnd(5)} ${n} (${d})`);
    if (tests) out(`tests: ${tests}`);
    if (sizeLine) out(sizeLine);
    const verdict = `GATE: ${failed ? 'FAIL' : 'PASS'} — ${results.filter((r) => r[0] === 'PASS').map((r) => r[1]).join(', ')}${tests ? ` — tests ${tests}` : ''}${failed ? ` — failed: ${results.filter((r) => r[0] === 'FAIL').map((r) => r[1]).join(', ')}` : ''}`;
    out(verdict);
    writeFileSync(join(logDir, 'gate-summary.txt'), verdict + '\n' + (sizeLine ? sizeLine + '\n' : ''));
    if (o.status) statusAppend(c, root, o.status, verdict + (sizeLine ? ` · ${sizeLine}` : ''));
    process.exitCode = failed ? 1 : 0;
  },

  async size() {
    const o = opts(argv.slice(1), { file: 'string', status: 'string', 'baseline-raw': 'string', 'baseline-gz': 'string', 'budget-gz': 'string' });
    const { c, root } = ctx();
    if (o.file) c.SIZE_FILE = o.file;
    if (o['baseline-raw']) c.SIZE_BASELINE_RAW = o['baseline-raw'];
    if (o['baseline-gz']) c.SIZE_BASELINE_GZ = o['baseline-gz'];
    if (o['budget-gz']) c.SIZE_BUDGET_GZ = o['budget-gz'];
    if (!c.SIZE_FILE) die('set SIZE_FILE in .agents/workflow.env or pass --file');
    const r = sizeReport(c, root);
    out(r.line);
    if (o.status) statusAppend(c, root, o.status, r.line);
    process.exitCode = r.over ? 1 : 0;
  },

  async 'adr-next'() {
    const { c, root } = ctx();
    const file = c.ADR_FILE || join(c.MEMORY_BANK_DIR, '10-decisions-and-history.md');
    const nums = (t) => [...String(t || '').matchAll(/ADR-(\d{3,4})/g)].map((m) => Number(m[1]));
    const local = existsSync(join(root, file)) ? nums(readText(join(root, file))) : (c.ADR_DIR && existsSync(join(root, c.ADR_DIR)) ? nums(readdirSync(join(root, c.ADR_DIR)).join(' ')) : []);
    git(['fetch', '-q', 'origin'], root);
    const base = nums(git(['show', `origin/${c.DEFAULT_BRANCH}:${file}`], root));
    let claims = [];
    try {
      const slug = repoSlug(c, root);
      const prs = await gh('GET', `repos/${slug}/pulls?state=open&per_page=100`);
      claims = prs.flatMap((p) => [...new Set(nums(`${p.title} ${p.body || ''}`))].map((n) => ({ n, where: `PR #${p.number} (${p.head.ref})` })));
    } catch { /* offline: tree + base only */ }
    const branchClaims = [];
    const refs = (git(['for-each-ref', '--format=%(refname:short)', 'refs/remotes/origin'], root) || '').split('\n').filter((r) => r && !r.endsWith('/HEAD'));
    for (const ref of refs.slice(0, 200)) {
      for (const n of new Set(nums(git(['show', `${ref}:${file}`], root)))) branchClaims.push({ n, where: ref });
    }
    const all = [...local, ...base, ...claims.map((x) => x.n), ...branchClaims.map((x) => x.n)];
    const highest = all.length ? Math.max(...all) : 0;
    const next = highest + 1;
    out(`highest in working tree: ${local.length ? Math.max(...local) : 'none'} · on origin/${c.DEFAULT_BRANCH}: ${base.length ? Math.max(...base) : 'none'}`);
    const top = [...claims, ...branchClaims].filter((x) => x.n > (base.length ? Math.max(...base) : 0)).sort((a, b) => a.n - b.n);
    const byNum = new Map();
    for (const x of top) { if (!byNum.has(x.n)) byNum.set(x.n, new Set()); byNum.get(x.n).add(x.where); }
    for (const [n, w] of byNum) out(`claimed: ADR-${String(n).padStart(3, '0')} by ${[...w].slice(0, 4).join(', ')}${w.size > 4 ? ` +${w.size - 4} more` : ''}`);
    out(`ADR-NEXT: ADR-${String(next).padStart(3, '0')}`);
  },

  async 'adr-new'() {
    const o = opts(argv.slice(1), { pr: 'string', id: 'string', supersedes: 'string' });
    const title = o._[0]; if (!title) die('usage: adr-new "<title>" [--pr N] [--id ADR-NNN]');
    const { c, root } = ctx();
    const tpl = readText(join(KIT_DIR, 'resources', 'templates', 'adr.md'));
    const file = join(root, c.ADR_FILE || join(c.MEMORY_BANK_DIR, '10-decisions-and-history.md'));
    if (!existsSync(file)) die(`${file} not found (set ADR_FILE)`);
    const txt = readText(file);
    let id = o.id;
    if (!id) { const ns = [...txt.matchAll(/ADR-(\d{3,4})/g)].map((m) => Number(m[1])); id = `ADR-${String((ns.length ? Math.max(...ns) : 0) + 1).padStart(3, '0')}`; }
    if (new RegExp(`##\\s+${id}\\b`).test(txt)) die(`${id} already exists in ${file}`);
    const block = tpl.replaceAll('{{ID}}', id).replaceAll('{{TITLE}}', title).replaceAll('{{PR}}', o.pr ? ` (PR #${o.pr})` : '')
      .replaceAll('{{DATE}}', nowStamp(c.TIMEZONE).slice(0, 10)).replaceAll('{{SUPERSEDES}}', o.supersedes || 'none');
    const idx = txt.search(/^## Timeline/m);
    writeFileSync(file, idx === -1 ? `${txt.replace(/\s*$/, '\n')}\n${block}` : `${txt.slice(0, idx)}${block}\n${txt.slice(idx)}`);
    out(`ADR: ${id} -> ${relative(root, file)} (fill Context / Decision / Consequences / Cost now)`);
  },

  async 'pr-create'() {
    const o = opts(argv.slice(1), { base: 'string', head: 'string', title: 'string', 'body-file': 'string', body: 'string' });
    if (!o.base || !o.head || !o.title) die('usage: pr-create --base B --head H --title T --body-file F');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const pr = await gh('POST', `repos/${slug}/pulls`, { base: o.base, head: o.head, title: o.title, body: bodyArg(o), draft: true });
    out(`${pr.html_url}`); out(`PR: #${pr.number} DRAFT head ${pr.head.sha.slice(0, 7)} ${pr.head.ref} -> ${pr.base.ref}`);
  },

  async 'pr-edit'() {
    const o = opts(argv.slice(1), { 'body-file': 'string', title: 'string', base: 'string' });
    const n = o._[0]; if (!n) die('usage: pr-edit <n> [--body-file F] [--title T] [--base B]');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const patch = {};
    if (o['body-file']) patch.body = readText(o['body-file']);
    if (o.title) patch.title = o.title;
    if (o.base) patch.base = o.base;
    if (!Object.keys(patch).length) die('nothing to change');
    const pr = await gh('PATCH', `repos/${slug}/pulls/${n}`, patch);
    out(`PR: #${pr.number} UPDATED (${Object.keys(patch).join(', ')}) base ${pr.base.ref}`);
  },

  async 'pr-status'() {
    const o = opts(argv.slice(1), { json: 'bool' });
    const n = o._[0]; if (!n) die('usage: pr-status <n> [--json]');
    const { c, root } = ctx(); const slug = repoSlug(c, root); const [owner, name] = slug.split('/');
    const pr = await gh('GET', `repos/${slug}/pulls/${n}`);
    const items = await ciState(slug, pr.head.sha, c.CI_IGNORE_CHECKS ? new RegExp(c.CI_IGNORE_CHECKS) : null);
    const reviews = await gh('GET', `repos/${slug}/pulls/${n}/reviews?per_page=100`);
    const comments = await gh('GET', `repos/${slug}/issues/${n}/comments?per_page=100`);
    const threads = await reviewThreads(owner, name, Number(n));
    const bots = new RegExp(String(c.REVIEW_BOTS).split(/\s+/).filter(Boolean).join('|') || '$^', 'i');
    const botComments = Object.values(comments.filter((x) => bots.test(x.user.login)).reduce((a, x) => { a[x.user.login] = x; return a; }, {}));
    const open = threads.filter((t) => !t.isResolved);
    const summary = {
      number: pr.number, title: pr.title, url: pr.html_url, state: pr.state, draft: pr.draft, merged: pr.merged,
      mergeable: pr.mergeable, mergeable_state: pr.mergeable_state, head: pr.head.ref, head_sha: pr.head.sha, base: pr.base.ref,
      merge_commit_sha: pr.merge_commit_sha, checks: items, reviews: reviews.map((r) => ({ user: r.user.login, state: r.state, at: r.submitted_at })),
      unresolved_threads: open.map(threadView),
      bot_comments: botComments.map((x) => ({ user: x.user.login, at: x.created_at, url: x.html_url, rate_limited: /rate.?limit/i.test(x.body), excerpt: clean(x.body) })),
    };
    if (o.json) { out(JSON.stringify(summary, null, 2)); return; }
    out(`PR #${pr.number} ${pr.title}\n${pr.html_url}`);
    out(`state: ${pr.state}  draft: ${pr.draft}  merged: ${pr.merged}  mergeable: ${pr.mergeable} (${pr.mergeable_state})`);
    out(`head: ${pr.head.ref} @ ${pr.head.sha.slice(0, 7)} -> ${pr.base.ref}${pr.merged ? `  merge commit ${String(pr.merge_commit_sha).slice(0, 7)}` : ''}`);
    out(`\nchecks + statuses (${items.length}):`); for (const i of items) out(`  ${i.state.toUpperCase().padEnd(7)} ${i.name} [${i.detail}]`);
    out(`\nreviews:`); for (const r of summary.reviews) out(`  ${r.state.padEnd(17)} ${r.user} ${r.at}`);
    out(`\nunresolved threads: ${open.length}`); for (const t of summary.unresolved_threads) out(`  ${t.path}:${t.line ?? '-'} ${t.author}: ${t.excerpt}\n    thread ${t.thread_id} · comment ${t.comment_id} · ${t.url}`);
    out(`\nlatest bot comments:`); for (const b of summary.bot_comments) out(`  ${b.user} ${b.at}${b.rate_limited ? ' RATE-LIMITED' : ''}: ${b.excerpt}`);
    const pending = items.filter((i) => i.state === 'pending').length; const fail = items.filter((i) => i.state === 'fail').length;
    out(`PR-STATUS: #${pr.number} ${pr.merged ? 'MERGED' : pr.state.toUpperCase()}${pr.draft ? ' DRAFT' : ''} head ${pr.head.sha.slice(0, 7)} · CI ${fail ? `RED (${fail} failed)` : pending ? `RUNNING (${pending})` : items.length ? 'GREEN' : 'NONE'} · open threads ${open.length}`);
  },

  async 'wait-ci'() {
    const o = opts(argv.slice(1), { timeout: 'string', interval: 'string', status: 'string' });
    const target = o._[0]; if (!target) die('usage: wait-ci <pr|sha> [--timeout S] [--interval S]');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const timeout = Number(o.timeout || 2700) * 1000; const interval = Number(o.interval || 30) * 1000;
    const ignore = c.CI_IGNORE_CHECKS ? new RegExp(c.CI_IGNORE_CHECKS) : null;
    const sha = await headSha(slug, target);
    const t0 = Date.now();
    for (;;) {
      const items = await ciState(slug, sha, ignore);
      const pending = items.filter((i) => i.state === 'pending');
      const fails = items.filter((i) => i.state === 'fail');
      const el = Math.round((Date.now() - t0) / 1000);
      if (!items.length && el >= 180) { out(`CI: NONE — no checks or statuses on ${sha.slice(0, 7)} after 180s`); process.exitCode = 3; return; }
      if (items.length && !pending.length) {
        for (const i of items) out(`  ${i.state.toUpperCase().padEnd(7)} ${i.name} [${i.detail}]`);
        const line = fails.length ? `CI: RED on ${sha.slice(0, 7)} — failed: ${fails.map((f) => f.name).join(', ')}` : `CI: GREEN on ${sha.slice(0, 7)} (${items.length} checks/statuses)`;
        for (const f of fails) out(`  FAILED ${f.name}: ${f.url}`);
        out(line); if (o.status) statusAppend(c, root, o.status, line);
        process.exitCode = fails.length ? 1 : 0; return;
      }
      if (Date.now() - t0 >= timeout) { out(`CI: TIMEOUT after ${el}s — still running: ${pending.map((p) => p.name).join(', ')}`); process.exitCode = 2; return; }
      err(`... ${pending.length}/${items.length} running (${el}s)`);
      await sleep(interval);
    }
  },

  async 'ci-logs'() {
    const o = opts(argv.slice(1), { lines: 'string' });
    const target = o._[0]; if (!target) die('usage: ci-logs <pr|sha>');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const sha = await headSha(slug, target);
    const runs = (await gh('GET', `repos/${slug}/actions/runs?head_sha=${sha}&per_page=50`)).workflow_runs;
    const logDir = join(root, c.STATUS_DIR, '_logs'); mkdirSync(logDir, { recursive: true }); ensureIgnored(root, c.STATUS_DIR);
    let n = 0;
    for (const run of runs) {
      const jobs = (await gh('GET', `repos/${slug}/actions/runs/${run.id}/jobs?per_page=100`)).jobs;
      for (const j of jobs.filter((x) => x.conclusion && !PASS_CONCL.has(x.conclusion))) {
        n++;
        const text = await gh('GET', `repos/${slug}/actions/jobs/${j.id}/logs`, undefined, { raw: true });
        const f = join(logDir, `ci-${j.id}.log`); writeFileSync(f, text);
        const lines = text.split(/\r?\n/).map((l) => l.replace(/^\d{4}-\d\d-\d\dT[\d:.]+Z\s?/, ''));
        const failedStep = (j.steps || []).find((s) => s.conclusion === 'failure');
        out(`\n=== ${run.name} / ${j.name} (${j.conclusion}) step: ${failedStep ? failedStep.name : '?'} — ${j.html_url}`);
        out(`log saved: ${relative(root, f)}`);
        const hits = lines.filter((l) => /(error|failed|exception|FAIL|✗|Some tests failed|Expected:|Actual:)/.test(l)).slice(0, 40);
        if (hits.length) { out('-- error lines --'); out(hits.join('\n')); }
        out(`-- last ${o.lines || 80} lines --`); out(lines.slice(-Number(o.lines || 80)).join('\n'));
      }
    }
    out(n ? `CI-LOGS: ${n} failed job(s) saved in ${relative(root, logDir)}` : `CI-LOGS: no failed jobs on ${sha.slice(0, 7)}`);
  },

  async bots() {
    const o = opts(argv.slice(1), { prs: 'string' });
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const prs = await gh('GET', `repos/${slug}/pulls?state=all&per_page=${Number(o.prs || 15)}`);
    const seen = {};
    for (const p of prs) {
      const cm = await gh('GET', `repos/${slug}/issues/${p.number}/comments?per_page=100`);
      const rv = await gh('GET', `repos/${slug}/pulls/${p.number}/reviews?per_page=100`);
      for (const x of [...cm, ...rv]) if (x.user?.type === 'Bot' || /\[bot\]$/.test(x.user?.login || '')) seen[x.user.login] = (seen[x.user.login] || 0) + 1;
    }
    const wanted = String(c.REVIEW_BOTS).split(/\s+/).filter(Boolean);
    for (const [k, v] of Object.entries(seen)) out(`seen: ${k} (${v} comments/reviews on the last ${prs.length} PRs)`);
    const active = wanted.filter((b) => Object.keys(seen).some((k) => k.toLowerCase().startsWith(b.toLowerCase())));
    out(`BOTS: active ${active.length ? active.join(' ') : 'none'}${prs.length ? '' : ' (no PRs yet: unknown)'} · configured ${wanted.join(' ')}`);
  },

  async 'review-request'() {
    const o = opts(argv.slice(1), { bots: 'string' });
    const n = o._[0]; if (!n) die('usage: review-request <n> [--bots "coderabbitai sentry"]');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const bots = String(o.bots || c.REVIEW_BOTS).split(/\s+/).filter(Boolean);
    const ids = [];
    for (const b of bots) { const r = await gh('POST', `repos/${slug}/issues/${n}/comments`, { body: `@${b} review` }); ids.push(`${b}:${r.id}`); out(`posted @${b} review -> ${r.html_url}`); }
    out(`REVIEW-REQUEST: #${n} ${ids.join(' ')} at ${nowStamp(c.TIMEZONE)}`);
  },

  async threads() {
    const o = opts(argv.slice(1), { all: 'bool' });
    const n = o._[0]; if (!n) die('usage: threads <n> [--all]');
    const { c, root } = ctx(); const [owner, name] = repoSlug(c, root).split('/');
    const ts = (await reviewThreads(owner, name, Number(n))).filter((t) => o.all || !t.isResolved);
    for (const t of ts.map(threadView)) out(`${t.resolved ? 'RESOLVED' : 'OPEN    '} ${t.path}:${t.line ?? '-'} ${t.author}${t.outdated ? ' (outdated)' : ''}\n  thread ${t.thread_id} · comment ${t.comment_id} · replies ${t.replies}\n  ${t.excerpt}\n  ${t.url}`);
    out(`THREADS: ${ts.filter((t) => !t.isResolved).length} open${o.all ? `, ${ts.filter((t) => t.isResolved).length} resolved` : ''}`);
  },

  async reply() {
    const o = opts(argv.slice(1), { 'body-file': 'string', body: 'string' });
    const [n, cid] = o._; if (!n || !cid) die('usage: reply <n> <commentId> --body-file F');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const r = await gh('POST', `repos/${slug}/pulls/${n}/comments/${cid}/replies`, { body: bodyArg(o) });
    out(`REPLY: ${r.id} ${r.html_url}`);
  },

  async resolve() {
    const id = argv[1]; if (!id) die('usage: resolve <threadId>');
    const d = await graphql('mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{id isResolved}}}', { id });
    out(`RESOLVE: ${id} ${d.resolveReviewThread.thread.isResolved ? 'RESOLVED' : 'NOT RESOLVED'}`);
  },

  async comment() {
    const o = opts(argv.slice(1), { 'body-file': 'string', body: 'string' });
    const n = o._[0]; if (!n) die('usage: comment <n> --body-file F');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const r = await gh('POST', `repos/${slug}/issues/${n}/comments`, { body: bodyArg(o) });
    out(`COMMENT: ${r.id} ${r.html_url}`);
  },

  async merge() {
    const o = opts(argv.slice(1), { sha: 'string', approval: 'string', title: 'string' });
    const n = o._[0];
    if (!n || !o.sha || !o.approval) die('usage: merge <n> --sha <headSha> --approval "<owner\'s words + time>" (the owner must have said merge in this conversation)');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const pr = await gh('GET', `repos/${slug}/pulls/${n}`);
    if (!pr.head.sha.startsWith(o.sha)) die(`head moved: PR head is ${pr.head.sha.slice(0, 7)}, you approved ${o.sha}. Re-check CI and reviews on the new head.`);
    if (pr.draft) die('PR is still a draft: mark it ready only with the owner\'s OK (gh pr ready <n>), then merge.');
    const items = await ciState(slug, pr.head.sha, c.CI_IGNORE_CHECKS ? new RegExp(c.CI_IGNORE_CHECKS) : null);
    const bad = items.filter((i) => i.state !== 'ok');
    if (bad.length) die(`CI not green on ${pr.head.sha.slice(0, 7)}: ${bad.map((b) => `${b.name}=${b.detail}`).join(', ')}`);
    const r = await gh('PUT', `repos/${slug}/pulls/${n}/merge`, { merge_method: 'squash', sha: pr.head.sha, commit_title: o.title || `${pr.title} (#${n})` });
    out(`MERGE: #${n} squashed as ${String(r.sha).slice(0, 7)} (${r.sha}) — approval: ${o.approval}`);
  },

  async 'deploy-verify'() {
    const o = opts(argv.slice(1), { sha: 'string', workflow: 'string', url: 'string', path: 'list', bundle: 'string', expect: 'list', absent: 'list', timeout: 'string', status: 'string' });
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const wf = o.workflow || c.DEPLOY_WORKFLOW; const url = (o.url || c.LIVE_URL || '').replace(/\/$/, '');
    const paths = o.path || String(c.LIVE_PATHS || '/').split(/\s+/).filter(Boolean);
    const bundle = o.bundle || c.BUNDLE_PATH || '';
    const timeout = Number(o.timeout || 2700) * 1000;
    if (!wf && !url) die('set DEPLOY_WORKFLOW and/or LIVE_URL');
    const sha = (await gh('GET', `repos/${slug}/commits/${o.sha || c.DEFAULT_BRANCH}`)).sha;
    let failed = 0; const notes = [];
    out(`commit ${sha.slice(0, 7)} (${o.sha ? `--sha ${o.sha}` : c.DEFAULT_BRANCH})`);
    if (wf) {
      const t0 = Date.now(); let run;
      for (;;) {
        const runs = (await gh('GET', `repos/${slug}/actions/runs?head_sha=${sha}&event=push&per_page=50`)).workflow_runs;
        run = runs.filter((r) => r.name === wf || String(r.path || '').split('/').pop() === wf).sort((a, b) => a.created_at.localeCompare(b.created_at)).pop();
        if (run && run.status === 'completed') { for (const r of runs.filter((x) => x.id !== run.id)) out(`other run ${r.id} ${r.name}: ${r.conclusion || r.status}`); break; }
        if (Date.now() - t0 > timeout) die(`deploy run for ${sha.slice(0, 7)} not finished after ${timeout / 1000}s`, 2);
        err(run ? `... run ${run.id} ${run.status}` : `... waiting for a "${wf}" push run on ${sha.slice(0, 7)}`);
        await sleep(30000);
      }
      out(`deploy run ${run.id} (${wf}): ${run.conclusion} ${run.html_url}`);
      const jobs = (await gh('GET', `repos/${slug}/actions/runs/${run.id}/jobs?per_page=100`)).jobs;
      for (const j of jobs) out(`  ${(j.conclusion || j.status).padEnd(9)} ${j.name}`);
      notes.push(`run ${run.id} ${run.conclusion}`);
      if (run.conclusion !== 'success') { failed++; out('FAIL deploy workflow did not succeed'); }
    }
    if (url) {
      for (const p of paths) {
        let code = 0; try { code = (await fetch(url + p, { redirect: 'follow' })).status; } catch { code = 0; }
        out(`${code === 200 ? 'OK  ' : 'FAIL'} GET ${url}${p} -> ${code}`); if (code !== 200) failed++;
      }
      notes.push(`${paths.length} paths`);
      const exp = o.expect || []; const abs = o.absent || [];
      if (bundle && (exp.length || abs.length)) {
        const blobs = [];
        for (const b of bundle.split(/\s+/).filter(Boolean)) {
          const res = await fetch(`${url}/${b.replace(/^\//, '')}?v=${Date.now()}`);
          if (!res.ok) { out(`FAIL cannot download ${b} (${res.status})`); failed++; continue; }
          const txt = await res.text(); blobs.push(txt);
          if (b.endsWith('main.dart.js')) {
            const prefix = b.replace(/^\//, '').replace(/main\.dart\.js$/, '');
            for (const part of new Set(txt.match(/main\.dart\.js_\d+\.part\.js/g) || [])) {
              const pr = await fetch(`${url}/${prefix}${part}?v=${Date.now()}`); if (pr.ok) blobs.push(await pr.text());
            }
          }
        }
        out(`searched ${blobs.length} bundle file(s)`);
        const count = (s) => { const forms = new Set([s, jsEscape(s, false), jsEscape(s, true)]); let n = 0; for (const t of blobs) for (const f of forms) n += t.split(f).length - 1; return n; };
        for (const s of exp) { const n = count(s); out(`${n >= 1 ? 'OK  ' : 'FAIL'} bundle has «${s}» (${n})`); if (n < 1) failed++; }
        for (const s of abs) { const n = count(s); out(`${n === 0 ? 'OK  ' : 'FAIL'} bundle free of «${s}» (${n})`); if (n !== 0) failed++; }
      }
    }
    const line = `DEPLOY: ${failed ? 'NOT VERIFIED' : 'VERIFIED'} ${sha.slice(0, 7)} — ${notes.join(', ')}`;
    out(line); if (o.status) statusAppend(c, root, o.status, line);
    process.exitCode = failed ? 1 : 0;
  },

  async psi() {
    const o = opts(argv.slice(1), { strategy: 'string', runs: 'string', status: 'string' });
    const { c, root } = ctx();
    const url = o._[0] || c.LIVE_URL; if (!url) die('usage: psi <url> (or set LIVE_URL)');
    const strategies = (o.strategy || 'both') === 'both' ? ['mobile', 'desktop'] : [o.strategy];
    const runs = Number(o.runs || 3); const cats = ['performance', 'accessibility', 'best-practices', 'seo'];
    let below = 0; const parts = [];
    for (const s of strategies) {
      const scores = { performance: [], accessibility: [], 'best-practices': [], seo: [] };
      for (let i = 0; i < runs; i++) {
        const q = new URLSearchParams({ url, strategy: s }); for (const k of cats) q.append('category', k);
        if (process.env.PSI_API_KEY) q.set('key', process.env.PSI_API_KEY);
        const res = await fetch(`https://www.googleapis.com/pagespeedonline/v5/runPagespeed?${q}`);
        const j = await res.json().catch(() => ({}));
        if (!res.ok) die(`PSI HTTP ${res.status}: ${(j.error && j.error.message) || ''} (quota? set PSI_API_KEY, or run it on pagespeed.web.dev)`);
        for (const k of cats) scores[k].push(Math.round(100 * (j.lighthouseResult?.categories?.[k]?.score ?? 0)));
        out(`${s} run ${i + 1}: ${cats.map((k) => scores[k][i]).join('/')}`);
      }
      const med = cats.map((k) => { const a = [...scores[k]].sort((x, y) => x - y); return a[Math.floor(a.length / 2)]; });
      const base = String(c[`PSI_BASELINE_${s.toUpperCase()}`] || '').split('/').map(Number);
      const cmp = base.length === 4 ? med.map((v, i) => (v < base[i] ? `${v}<${base[i]}` : `${v}`)).join('/') : med.join('/');
      if (base.length === 4 && med.some((v, i) => v < base[i])) below++;
      parts.push(`${s} ${med.join('/')}${base.length === 4 ? ` (baseline ${base.join('/')}${cmp.includes('<') ? `, BELOW: ${cmp}` : ''})` : ''}`);
    }
    const line = `PSI: ${below ? 'BELOW BASELINE' : 'OK'} — ${parts.join(' · ')} — median of ${runs}, ${url}, ${nowStamp(c.TIMEZONE)}`;
    out(line); if (o.status) statusAppend(c, root, o.status, line);
    process.exitCode = below ? 1 : 0;
  },

  async screenshot() {
    const o = opts(argv.slice(1), { width: 'string', height: 'string', out: 'string', wait: 'string' });
    const url = o._[0]; if (!url) die('usage: screenshot <url> [--width 390] [--height 844] [--out file.png]');
    const w = Number(o.width || 390); const h = Number(o.height || 844);
    const { c, root } = ctx();
    const file = resolve(o.out || join(root, c.STATUS_DIR, 'png', `shot-${w}-${Date.now()}.png`)); mkdirSync(dirname(file), { recursive: true });
    const chrome = findChrome();
    if (!chrome) {
      out(`SCREENSHOT: NO-CHROME — ask the owner to paste this in Antigravity:\n/browser Open ${url}, set the viewport to ${w}x${h}, wait until the page has finished loading, and save a screenshot as an artifact. Report what is visible.`);
      process.exitCode = 3; return;
    }
    const r = spawnSync(chrome, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', `--window-size=${w},${h}`,
      `--virtual-time-budget=${Number(o.wait || 20000)}`, `--screenshot=${file}`, url], { encoding: 'utf8', timeout: 120000 });
    if (r.status !== 0 || !existsSync(file)) die(`chrome failed: ${(r.stderr || '').slice(-400)}`);
    out(`SCREENSHOT: ${file} (${w}x${h}, ${statSync(file).size} B)`);
  },

  async worktree() {
    const o = opts(argv.slice(1), { base: 'string', existing: 'bool' });
    const { c, main } = ctx();
    if (o._[0] === 'list') { out(git(['worktree', 'list'], main) || ''); out('WORKTREE: LISTED'); return; }
    const branch = o._[0]; if (!branch || (!o.base && !o.existing)) die('usage: worktree <new-branch> --base <base-branch>   (or --existing for a branch that is already on origin)');
    if ([...String(c.PROTECTED_BRANCHES).split(/\s+/), c.DEFAULT_BRANCH].includes(branch)) die(`refusing: ${branch} is protected`);
    const dir = resolve(main, c.WORKTREE_ROOT, branch.replace(/[^A-Za-z0-9._-]+/g, '-'));
    if (existsSync(dir)) { out(dir); out(`WORKTREE: EXISTS ${dir} (branch ${currentBranch(dir)})`); return; }
    if (git(['fetch', 'origin'], main) === null) die('git fetch origin failed (network? sign-in?)');
    mkdirSync(dirname(dir), { recursive: true });
    ensureIgnored(main, c.STATUS_DIR);
    const exists = git(['rev-parse', '--verify', '-q', `refs/remotes/origin/${branch}`], main);
    const args = exists ? ['worktree', 'add', dir, branch] : ['worktree', 'add', '-b', branch, dir, `origin/${o.base}`];
    const r = spawnSync('git', args, { cwd: main, encoding: 'utf8' });
    if (r.status !== 0) die(`git ${args.join(' ')} failed: ${(r.stderr || '').trim()}`);
    const sha = git(['rev-parse', '--short', 'HEAD'], dir);
    out(dir); out(`WORKTREE: CREATED ${dir} branch ${branch} at ${sha}${exists ? ' (existing remote branch)' : ` from origin/${o.base}`}`);
  },

  async 'ci-rerun'() {
    const id = argv[1]; if (!id || !/^\d+$/.test(id)) die('usage: ci-rerun <run-id>   (the number in …/actions/runs/<run-id>/job/…)');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const run = await gh('GET', `repos/${slug}/actions/runs/${id}`);
    if (run.status !== 'completed') die(`run ${id} is still ${run.status}: wait for it first (wait-run ${id})`);
    if (PASS_CONCL.has(run.conclusion)) { out(`CI-RERUN: NOT NEEDED — run ${id} (${run.name}) is ${run.conclusion}`); return; }
    if ((run.run_attempt || 1) > 1) {
      out(`CI-RERUN: REFUSED — run ${id} (${run.name}) is already attempt ${run.run_attempt}. One re-run only: treat the failure as real (ci-logs ${run.head_sha.slice(0, 7)}).`);
      process.exitCode = 1; return;
    }
    await gh('POST', `repos/${slug}/actions/runs/${id}/rerun-failed-jobs`);
    out(run.html_url);
    out(`CI-RERUN: STARTED run ${id} (${run.name}) attempt 2, failed jobs only, on ${run.head_sha.slice(0, 7)} — next: wait-run ${id}`);
  },

  async dispatch() {
    const o = opts(argv.slice(1), { ref: 'string', input: 'list', status: 'string' });
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const wfArg = o._[0] || c.DEV_WORKFLOW; if (!wfArg) die('usage: dispatch <workflow file|id|name> [--ref B] [--input k=v]   (or set DEV_WORKFLOW)');
    const wf = await resolveWorkflow(slug, wfArg);
    const ref = o.ref || c.DEV_BRANCH || c.DEFAULT_BRANCH;
    if (c.DEPLOY_WORKFLOW && wf.name === c.DEPLOY_WORKFLOW) die(`refusing: "${wf.name}" is the production deploy (DEPLOY_WORKFLOW); it runs on a push to ${c.DEFAULT_BRANCH} only`);
    if (/seed/i.test(`${wf.name} ${wf.path}`)) die(`refusing: "${wf.name}" looks like a data seed workflow — only the owner runs it`);
    const inputs = {};
    for (const kv of o.input || []) { const i = kv.indexOf('='); if (i < 1) die(`--input needs key=value, got "${kv}"`); inputs[kv.slice(0, i)] = kv.slice(i + 1); }
    const before = (await gh('GET', `repos/${slug}/actions/workflows/${wf.id}/runs?per_page=1`)).workflow_runs;
    const prevId = before.length ? before[0].id : 0;
    await gh('POST', `repos/${slug}/actions/workflows/${wf.id}/dispatches`, { ref, ...(Object.keys(inputs).length ? { inputs } : {}) });
    out(`dispatched "${wf.name}" (${wf.path}) on ${ref}${Object.keys(inputs).length ? ` inputs ${JSON.stringify(inputs)}` : ''}`);
    for (let i = 0; i < 18; i++) {
      await sleep(i ? 5000 : 3000);
      const runs = (await gh('GET', `repos/${slug}/actions/workflows/${wf.id}/runs?event=workflow_dispatch&per_page=5`)).workflow_runs;
      const r = runs.filter((x) => x.id > prevId && x.head_branch === ref).sort((a, b) => a.id - b.id)[0];
      if (r) {
        out(r.html_url);
        const line = `DISPATCH: "${wf.name}" on ${ref} -> run ${r.id} (${r.status}) — next: wait-run ${r.id}`;
        out(line); if (o.status) statusAppend(c, root, o.status, line); return;
      }
    }
    out(`DISPATCH: SENT "${wf.name}" on ${ref} but no run visible after 90s — find it: wait-run latest --workflow "${wf.path.split('/').pop()}" --branch ${ref}`);
    process.exitCode = 2;
  },

  async 'wait-run'() {
    const o = opts(argv.slice(1), { workflow: 'string', branch: 'string', timeout: 'string', interval: 'string', status: 'string' });
    const target = o._[0]; if (!target) die('usage: wait-run <run-id> | wait-run latest --workflow W [--branch B]');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    let id = target;
    if (target === 'latest') {
      const wfArg = o.workflow || c.DEV_WORKFLOW; if (!wfArg) die('wait-run latest needs --workflow W (or DEV_WORKFLOW)');
      const wf = await resolveWorkflow(slug, wfArg);
      const q = new URLSearchParams({ per_page: '1' }); if (o.branch) q.set('branch', o.branch);
      const runs = (await gh('GET', `repos/${slug}/actions/workflows/${wf.id}/runs?${q}`)).workflow_runs;
      if (!runs.length) { out(`RUN: NONE — no run of "${wf.name}"${o.branch ? ` on ${o.branch}` : ''}`); process.exitCode = 3; return; }
      id = String(runs[0].id);
    } else if (!/^\d+$/.test(target)) die('run id must be a number (or "latest")');
    const timeout = Number(o.timeout || 1800) * 1000; const interval = Number(o.interval || 30) * 1000; const t0 = Date.now();
    for (;;) {
      const run = await gh('GET', `repos/${slug}/actions/runs/${id}`);
      const el = Math.round((Date.now() - t0) / 1000);
      if (run.status === 'completed') {
        const jobs = (await gh('GET', `repos/${slug}/actions/runs/${id}/jobs?per_page=100`)).jobs;
        for (const j of jobs) out(`  ${String(j.conclusion || j.status).padEnd(9)} ${j.name}`);
        out(run.html_url);
        const ok = run.conclusion === 'success';
        const line = `RUN: ${id} "${run.name}" ${String(run.conclusion).toUpperCase()} on ${run.head_branch}@${run.head_sha.slice(0, 7)} (attempt ${run.run_attempt || 1}, ${run.event})`;
        out(line); if (o.status) statusAppend(c, root, o.status, line);
        process.exitCode = ok ? 0 : 1; return;
      }
      if (Date.now() - t0 >= timeout) { out(`RUN: TIMEOUT ${id} "${run.name}" still ${run.status} after ${el}s — ${run.html_url}`); process.exitCode = 2; return; }
      err(`... run ${id} ${run.status} (${el}s)`);
      await sleep(interval);
    }
  },

  async 'pr-ready'() {
    const o = opts(argv.slice(1), { approval: 'string' });
    const n = o._[0];
    if (!n || !o.approval) die('usage: pr-ready <n> --approval "<owner\'s words + time>" (the owner must have said it in this conversation)');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const pr = await gh('GET', `repos/${slug}/pulls/${n}`);
    if (pr.state !== 'open') die(`PR #${n} is ${pr.merged ? 'merged' : pr.state}`);
    if (!pr.draft) { out(`PR-READY: #${n} ALREADY READY (not a draft) head ${pr.head.sha.slice(0, 7)}`); return; }
    const d = await graphql('mutation($id:ID!){markPullRequestReadyForReview(input:{pullRequestId:$id}){pullRequest{number isDraft}}}', { id: pr.node_id });
    const still = d.markPullRequestReadyForReview.pullRequest.isDraft;
    out(`PR-READY: #${n} ${still ? 'STILL DRAFT' : 'READY FOR REVIEW'} head ${pr.head.sha.slice(0, 7)} — approval: ${o.approval}`);
    process.exitCode = still ? 1 : 0;
  },

  async 'pr-checkout'() {
    const o = opts(argv.slice(1), { dir: 'string' });
    const n = o._[0]; if (!n || !/^\d+$/.test(n)) die('usage: pr-checkout <n> [--dir D]');
    const { c, main } = ctx();
    let headSha = null;
    try { headSha = (await gh('GET', `repos/${repoSlug(c, main)}/pulls/${n}`)).head.sha; } catch (e) { err(`WARN: cannot read PR #${n} from the API (${e.message.slice(0, 120)}); checking out what git fetch gives`); }
    const ref = `refs/remotes/origin/pr/${n}`;
    const f = spawnSync('git', ['fetch', 'origin', `+refs/pull/${n}/head:${ref}`], { cwd: main, encoding: 'utf8' });
    if (f.status !== 0) die(`git fetch of pull/${n}/head failed: ${(f.stderr || '').trim()}`);
    const sha = git(['rev-parse', ref], main);
    const dir = resolve(main, o.dir || join(c.WORKTREE_ROOT, `review-pr-${n}`));
    ensureIgnored(main, c.STATUS_DIR);
    if (existsSync(dir)) {
      const dirty = git(['status', '--porcelain'], dir);
      if (dirty) die(`${dir} has local changes; a review checkout must stay clean (look at them, then remove the worktree)`);
      const r = spawnSync('git', ['checkout', '-q', '--detach', ref], { cwd: dir, encoding: 'utf8' });
      if (r.status !== 0) die(`git checkout in ${dir} failed: ${(r.stderr || '').trim()}`);
    } else {
      mkdirSync(dirname(dir), { recursive: true });
      const r = spawnSync('git', ['worktree', 'add', '--detach', dir, ref], { cwd: main, encoding: 'utf8' });
      if (r.status !== 0) die(`git worktree add failed: ${(r.stderr || '').trim()}`);
    }
    const note = headSha ? (headSha === sha ? ' = PR head' : ` — PR head on GitHub is ${headSha.slice(0, 7)} (it moved; run again)`) : '';
    out(dir); out(`PR-CHECKOUT: #${n} ${sha.slice(0, 7)} -> ${dir} (detached, read-only review${note})`);
    if (headSha && headSha !== sha) process.exitCode = 1;
  },

  async 'bots-wait'() {
    const o = opts(argv.slice(1), { bot: 'string' });
    const n = o._[0]; if (!n) die('usage: bots-wait <n> [--bot coderabbitai]');
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    const bot = String(o.bot || 'coderabbitai').toLowerCase();
    const comments = [];
    for (let page = 1; page <= 5; page++) {
      const part = await gh('GET', `repos/${slug}/issues/${n}/comments?per_page=100&page=${page}`);
      comments.push(...part); if (part.length < 100) break;
    }
    for (let page = 1; page <= 5; page++) { // limit notices also arrive as replies inside review threads
      const part = await gh('GET', `repos/${slug}/pulls/${n}/comments?per_page=100&page=${page}`);
      comments.push(...part); if (part.length < 100) break;
    }
    const reviews = await gh('GET', `repos/${slug}/pulls/${n}/reviews?per_page=100`);
    const r = botWait({ comments, reviews, bot, now: Date.now() });
    const tz = c.TIMEZONE;
    if (r.state === 'none') { out(`BOTS-WAIT: NONE — ${r.reason}`); return; }
    out(`rate-limit messages from ${bot} on #${n}: ${r.count} · newest (${r.kind} limit) ${r.url}`);
    if (r.kind === 'chat') out('chat limit: thread replies that mention the bot count against it; write plain replies without @mentions');
    out(`wait text: "${r.snippet}"${r.assumed ? ' (no time stated: assuming 60 min)' : ''}`);
    if (r.state === 'ready') {
      out(`BOTS-WAIT: READY — ${bot} limit set ${stamp(new Date(r.at), tz)} ended ${stamp(new Date(r.ready), tz)}; request ONCE: review-request ${n} --bots ${bot}`);
      return;
    }
    out(`BOTS-WAIT: WAIT until ${stamp(new Date(r.ready), tz)} (${Math.ceil((r.ready - Date.now()) / 60000)} min) — ${bot} rate-limited at ${stamp(new Date(r.at), tz)}; post nothing that mentions @${bot} before then`);
    process.exitCode = 2;
  },

  async 'sentry-issues'() {
    const o = opts(argv.slice(1), { since: 'string', env: 'string', org: 'string', project: 'string', host: 'string', status: 'string' });
    const { c, root } = ctx();
    if (!o.since) die('usage: sentry-issues --since <ISO time with zone | 90m | 2h | 1d> [--env production]');
    const since = parseSince(o.since);
    const org = o.org || c.SENTRY_ORG; const project = o.project || c.SENTRY_PROJECT;
    const env = o.env !== undefined ? o.env : (c.SENTRY_ENVIRONMENT || '');
    const host = String(o.host || c.SENTRY_HOST || 'https://sentry.io').replace(/\/$/, '');
    const tok = process.env.SENTRY_TOKEN || process.env.SENTRY_AUTH_TOKEN || '';
    const tz = c.TIMEZONE;
    const notChecked = (why) => { const line = `SENTRY: NOT CHECKED — ${why}`; out(line); if (o.status) statusAppend(c, root, o.status, line); process.exitCode = 3; };
    if (!org || !project) return notChecked('set SENTRY_ORG and SENTRY_PROJECT in .agents/workflow.env (or --org / --project)');
    if (!tok) return notChecked('no SENTRY_TOKEN in the environment (a Sentry auth token with event:read / project:read; never commit it)');
    const q = new URLSearchParams({ query: `is:unresolved firstSeen:>${since.toISOString().slice(0, 19)}`, sort: 'new', limit: '100' });
    if (env) q.set('environment', env);
    let url = `${host}/api/0/projects/${encodeURIComponent(org)}/${encodeURIComponent(project)}/issues/?${q}`;
    const issues = [];
    for (let page = 0; url && page < 5; page++) {
      let res;
      try { res = await fetch(url, { headers: { Authorization: `Bearer ${tok}`, 'User-Agent': 'hark-workflow' } }); } catch (e) { return notChecked(`cannot reach ${host} (${e.message})`); }
      if (res.status === 401 || res.status === 403) return notChecked(`token refused (HTTP ${res.status}) by ${host}`);
      if (res.status === 404) return notChecked(`project ${org}/${project} not found on ${host}`);
      if (res.status === 429) return notChecked(`Sentry rate limit (HTTP 429); try again in a few minutes`);
      if (!res.ok) return notChecked(`HTTP ${res.status} from ${host}: ${(await res.text()).slice(0, 200)}`);
      issues.push(...(await res.json()));
      const next = String(res.headers.get('link') || '').split(',').find((p) => /rel="next"/.test(p) && /results="true"/.test(p));
      url = next ? (next.match(/<([^>]+)>/) || [])[1] : null;
    }
    const fresh = issues.filter((i) => Date.parse(i.firstSeen) >= since.getTime());
    for (const i of fresh) out(`NEW  ${i.shortId} [${i.level || '?'}] ${clean(i.title, 120)} — first seen ${stamp(new Date(i.firstSeen), tz)} · ${i.count} events · ${i.userCount ?? '?'} users · ${i.permalink || ''}`);
    const line = `SENTRY: ${fresh.length ? `${fresh.length} NEW ISSUE(S)` : '0 new issues'} since ${stamp(since, tz)}${env ? ` (env ${env})` : ''} — ${org}/${project}`;
    out(line); if (o.status) statusAppend(c, root, o.status, line);
    process.exitCode = fresh.length ? 1 : 0;
  },

  async 'dev-channel-url'() {
    const o = opts(argv.slice(1), { run: 'string', workflow: 'string', branch: 'string', status: 'string' });
    const { c, root } = ctx(); const slug = repoSlug(c, root);
    let run;
    if (o.run) run = await gh('GET', `repos/${slug}/actions/runs/${o.run}`);
    else {
      const wfArg = o.workflow || c.DEV_WORKFLOW; if (!wfArg) die('set DEV_WORKFLOW (e.g. deploy-dev.yml) in .agents/workflow.env, or pass --workflow / --run');
      const wf = await resolveWorkflow(slug, wfArg);
      const q = new URLSearchParams({ status: 'success', per_page: '1' }); const br = o.branch || c.DEV_BRANCH; if (br) q.set('branch', br);
      run = (await gh('GET', `repos/${slug}/actions/workflows/${wf.id}/runs?${q}`)).workflow_runs[0];
      if (!run) { out(`DEV-URL: NOT FOUND — no successful run of "${wf.name}"${br ? ` on ${br}` : ''}`); process.exitCode = 3; return; }
    }
    const jobs = (await gh('GET', `repos/${slug}/actions/runs/${run.id}/jobs?per_page=100`)).jobs;
    const texts = [];
    for (const j of jobs) { // ::notice:: lines become check-run annotations (job id = check run id): cheap, no log download
      try { for (const a of await gh('GET', `repos/${slug}/check-runs/${j.id}/annotations?per_page=50`)) texts.push(`${a.title || ''} ${a.message || ''}`); } catch { /* none */ }
    }
    let found = pickChannelUrl(texts.join('\n'), c.HOSTING_CHANNEL);
    if (!found.url) {
      for (const j of jobs.filter((x) => /deploy|channel|hosting/i.test(x.name)).concat(jobs.filter((x) => !/deploy|channel|hosting/i.test(x.name)))) {
        try { found = pickChannelUrl(await gh('GET', `repos/${slug}/actions/jobs/${j.id}/logs`, undefined, { raw: true }), c.HOSTING_CHANNEL); } catch { /* no log */ }
        if (found.url) break;
      }
    }
    const when = `run ${run.id} (${run.head_branch}@${run.head_sha.slice(0, 7)}, ${stamp(new Date(run.updated_at), c.TIMEZONE)})`;
    if (!found.url) { out(`DEV-URL: NOT FOUND — no *--*.web.app URL in the annotations or logs of ${when}`); process.exitCode = 3; return; }
    const norm = (u) => String(u || '').trim().replace(/\/+$/, '');
    const same = norm(found.url) === norm(c.DEV_URL);
    const line = same
      ? `DEV-URL: SAME ${norm(found.url)}${found.expires ? ` (expires ${found.expires})` : ''} — ${when}`
      : `DEV-URL: CHANGED ${norm(found.url)} (DEV_URL is ${norm(c.DEV_URL) || 'empty'})${found.expires ? ` expires ${found.expires}` : ''} — ${when} — the owner adds the host to Firebase Auth authorized domains + the reCAPTCHA key`;
    out(line); if (o.status) statusAppend(c, root, o.status, line);
    process.exitCode = same ? 0 : 1;
  },

  async install() {
    const [mode, a, b] = argv.slice(1);
    const copyKit = (target) => {
      rmSync(target, { recursive: true, force: true }); mkdirSync(target, { recursive: true });
      for (const e of ['plugin.json', 'README.md', 'CHANGELOG.md', 'LICENSE', 'hooks.json', 'assets', 'agents', 'rules', 'skills', 'scripts', 'resources']) {
        const src = join(KIT_DIR, e); if (existsSync(src)) cpSync(src, join(target, e), { recursive: true });
      }
      out(`copied kit -> ${target}`);
    };
    const writeEnv = (proj) => {
      const f = join(proj, '.agents', 'workflow.env'); mkdirSync(dirname(f), { recursive: true });
      if (existsSync(f)) out(`kept existing ${f}`); else { copyFileSync(join(KIT_DIR, 'resources', 'templates', 'workflow.env.example'), f); out(`wrote ${f} (edit it)`); }
    };
    if (mode === 'workspace') {
      if (!a) die('usage: install workspace <project-dir>');
      copyKit(join(resolve(a), '.agents', 'plugins', 'hark-workflow')); writeEnv(resolve(a));
      out('INSTALL: OK workspace — reopen the project (CLI: /skills reload) and check Settings → Customizations');
    } else if (mode === 'global') {
      copyKit(join(homedir(), '.gemini', 'config', 'plugins', 'hark-workflow'));
      out('INSTALL: OK global (~/.gemini/config/plugins/hark-workflow) — or use: agy plugin install <repo-url>');
    } else if (mode === 'profile') {
      const force = argv.includes('--force');
      if (!a || !b) die('usage: install profile <name> <project-dir> [--force]   (profiles: ' + readdirSync(join(KIT_DIR, 'examples')).join(', ') + ')');
      const src = join(KIT_DIR, 'examples', a, 'agents-dir');
      if (!existsSync(src)) die(`no profile ${a} (expected examples/${a}/agents-dir/)`);
      if (!gitRoot(resolve(b))) die(`${resolve(b)} is not a git repository`);
      const dest = join(resolve(b), '.agents');
      const files = []; const walk = (d) => { for (const e of readdirSync(d, { withFileTypes: true })) { const p = join(d, e.name); if (e.isDirectory()) walk(p); else files.push(p); } }; walk(src);
      let wrote = 0; let kept = 0;
      for (const f of files) {
        const to = join(dest, relative(src, f)); mkdirSync(dirname(to), { recursive: true });
        if (existsSync(to) && !force) { out(`kept    ${relative(resolve(b), to)} (exists; --force overwrites)`); kept++; continue; }
        copyFileSync(f, to); out(`wrote   ${relative(resolve(b), to)}`); wrote++;
      }
      out(`INSTALL: OK profile ${a} -> ${dest} (${wrote} written, ${kept} kept) — commit the files on a docs/chore branch, never on ${'main'}`);
    } else if (mode === 'skills') {
      if (!a) die('usage: install skills <skills-dir>   (e.g. <repo>/.claude/skills for other agents)');
      for (const s of readdirSync(join(KIT_DIR, 'skills'))) cpSync(join(KIT_DIR, 'skills', s), join(resolve(a), s), { recursive: true });
      out(`INSTALL: OK skills -> ${resolve(a)} (scripts stay in ${KIT_DIR})`);
    } else die('usage: install workspace <project> | global | profile <name> <project> [--force] | skills <dir>');
  },

  async api() {
    const o = opts(argv.slice(1), { 'body-file': 'string' });
    const [method, path] = o._; if (!method || !path) die('usage: api <METHOD> <path> [--body-file F]');
    const { c, root } = ctx();
    const p = path.replace('{repo}', repoSlug(c, root));
    const r = await gh(method.toUpperCase(), p, o['body-file'] ? JSON.parse(readText(o['body-file'])) : undefined);
    out(JSON.stringify(r, null, 2));
  },
};

// ---------- helpers used by several commands ----------
function detectStack(root) {
  if (existsSync(join(root, 'pubspec.yaml'))) return existsSync(join(root, 'firebase.json')) ? 'flutter-firebase' : 'flutter';
  if (existsSync(join(root, 'package.json'))) return 'node';
  if (['pyproject.toml', 'requirements.txt', 'setup.py'].some((f) => existsSync(join(root, f)))) return 'python';
  return 'unknown';
}
function gateSteps(c, root, stack, o) {
  const py = pythonCmd() || 'python3';
  const sub = (s) => String(s || '').replaceAll('{python}', py);
  const pick = (key, legacy, def) => sub(c[key] ?? c[legacy] ?? def);
  const steps = [];
  const add = (name, cmd, quick = false) => { if (cmd && cmd !== 'off' && (!o.quick || quick)) steps.push({ name, cmd }); };
  if (stack.startsWith('flutter')) {
    add('setup', pick('GATE_SETUP', '', 'flutter pub get'), true);
    add('analyze', pick('GATE_ANALYZE', 'ANALYZE_CMD', 'flutter analyze'), true);
    add('tests', pick('GATE_TEST', 'TEST_CMD', 'flutter test'));
    add('seed', pick('GATE_SEED', 'SEED_CHECK_CMD', existsSync(join(root, 'tool', 'gen_seed.py')) ? '{python} tool/gen_seed.py && git diff --exit-code -- assets/seed tool/known_seed_ids.json tool/retired_seed_ids.json' : ''));
    if (stack === 'flutter-firebase') {
      const dir = c.RULES_TEST_DIR || 'tool/rules_test';
      const def = existsSync(join(root, dir, 'package.json')) ? `cd ${dir} && npm ci --no-audit --no-fund && npm test` : '';
      add('rules', pick('GATE_RULES', '', def));
    }
    if (!o['no-build']) {
      add('build', pick('GATE_BUILD', 'BUILD_CMD', existsSync(join(root, 'web')) ? 'flutter build web --release' : 'flutter build apk --release'));
      add('post-build', pick('GATE_POST_BUILD', 'FINGERPRINT_CMD', existsSync(join(root, 'tool', 'fingerprint_icon_fonts.py')) ? '{python} tool/fingerprint_icon_fonts.py build/web' : ''));
    }
  } else if (stack === 'node') {
    let scripts = {}; try { scripts = JSON.parse(readText(join(root, 'package.json'))).scripts || {}; } catch { /* none */ }
    add('setup', pick('GATE_SETUP', '', existsSync(join(root, 'package-lock.json')) ? 'npm ci --no-audit --no-fund' : 'npm install --no-audit --no-fund'), true);
    add('analyze', pick('GATE_ANALYZE', 'ANALYZE_CMD', scripts.lint ? 'npm run lint' : ''), true);
    add('typecheck', scripts.typecheck ? 'npm run typecheck' : '', true);
    add('tests', pick('GATE_TEST', 'TEST_CMD', scripts.test ? 'npm test' : ''));
    if (!o['no-build']) add('build', pick('GATE_BUILD', 'BUILD_CMD', scripts.build ? 'npm run build' : ''));
  } else if (stack === 'python') {
    add('analyze', pick('GATE_ANALYZE', 'ANALYZE_CMD', have('ruff') ? 'ruff check .' : ''), true);
    add('tests', pick('GATE_TEST', 'TEST_CMD', `${py} -m pytest -q`));
    if (!o['no-build']) add('build', pick('GATE_BUILD', 'BUILD_CMD', ''));
  } else {
    add('analyze', sub(c.GATE_ANALYZE), true); add('tests', sub(c.GATE_TEST)); if (!o['no-build']) add('build', sub(c.GATE_BUILD));
  }
  for (const [i, x] of String(c.GATE_EXTRA || '').split(';;').map((s) => s.trim()).filter(Boolean).entries()) add(`extra-${i + 1}`, sub(x));
  if (o.only) return steps.filter((s) => o.only.split(',').includes(s.name));
  return steps;
}
function testCount(text) {
  const m = [...text.matchAll(/\+(\d+)(?: ~(\d+))?(?: -(\d+))?: (All tests passed!|Some tests failed)/g)].pop();
  if (m) return `${m[1]} passed${m[3] ? `, ${m[3]} failed` : ''}${m[2] ? `, ${m[2]} skipped` : ''}`;
  const jest = text.match(/Tests:\s+(.*total)/); if (jest) return jest[1];
  const mocha = text.match(/(\d+) passing/); if (mocha) return `${mocha[1]} passed${(text.match(/(\d+) failing/) || [])[1] ? `, ${text.match(/(\d+) failing/)[1]} failed` : ''}`;
  const pyt = [...text.matchAll(/(\d+) passed/g)].pop(); if (pyt) return `${pyt[1]} passed`;
  const node = text.match(/# pass (\d+)/); if (node) return `${node[1]} passed`;
  return '';
}
function sizeReport(c, root) {
  const f = join(root, c.SIZE_FILE);
  if (!existsSync(f)) return { line: `SIZE: MISSING ${c.SIZE_FILE} (build first)`, over: true };
  const buf = readFileSync(f); const raw = buf.length; const gz = gzipSync(buf, { level: 9 }).length;
  const bRaw = Number(c.SIZE_BASELINE_RAW || 0); const bGz = Number(c.SIZE_BASELINE_GZ || 0); const budget = Number(c.SIZE_BUDGET_GZ || 0);
  const dGz = bGz ? gz - bGz : 0;
  const over = Boolean(budget && bGz && dGz > budget);
  const line = `SIZE: ${over ? 'OVER BUDGET' : 'OK'} — ${c.SIZE_FILE} raw ${kb(raw)}${bRaw ? ` (${signed(raw - bRaw)})` : ''} · gzip-9 ${kb(gz)}${bGz ? ` (${signed(dGz)})` : ''}${budget ? ` · budget +${budget.toLocaleString('en-US')} B gz` : ''}${c.SIZE_BASELINE_REF ? ` · baseline ${c.SIZE_BASELINE_REF}` : ''}`;
  return { line, over };
}
function clean(t, n = 160) { return String(t || '').replace(/<!--[\s\S]*?-->/g, ' ').replace(/<[^>]+>/g, ' ').replace(/!\[[^\]]*\]\([^)]*\)/g, ' ').replace(/\s+/g, ' ').trim().slice(0, n); }
function jsEscape(s, upper) { return [...s].map((ch) => { const cp = ch.codePointAt(0); if (cp <= 127) return ch; const h = cp.toString(16).padStart(4, '0'); return `\\u${upper ? h.toUpperCase() : h}`; }).join(''); }
function statusAppend(c, _root, topic, msg) {
  const f = join(mainRoot(_root) || _root, c.STATUS_DIR, topic, 'STATUS.md');
  if (existsSync(f)) appendFileSync(f, `- ${nowStamp(c.TIMEZONE)} — ${msg}\n`); else err(`WARN: ${f} missing; evidence not logged`);
}
function ensureIgnored(root, dir) {
  const gi = join(root, '.gitignore'); const line = `/${dir.replace(/^\/|\/$/g, '')}/`;
  const txt = existsSync(gi) ? readText(gi) : '';
  if (!txt.split(/\r?\n/).some((l) => [line, `${dir}/`, dir, `/${dir}`].includes(l.trim()))) {
    if (git(['check-ignore', '-q', join(dir, 'x')], root) === null) err(`WARN: ${dir}/ is not in .gitignore — add the line "${line}" in your next docs/chore commit`);
  }
}
async function reviewThreads(owner, name, number) {
  const q = 'query($o:String!,$n:String!,$p:Int!,$c:String){repository(owner:$o,name:$n){pullRequest(number:$p){reviewThreads(first:100,after:$c){pageInfo{hasNextPage endCursor} nodes{id isResolved isOutdated path line comments(first:50){totalCount nodes{databaseId author{login} body url}}}}}}}';
  let cursor = null; const all = [];
  for (;;) {
    const d = await graphql(q, { o: owner, n: name, p: number, c: cursor });
    const rt = d.repository.pullRequest.reviewThreads; all.push(...rt.nodes);
    if (!rt.pageInfo.hasNextPage) break; cursor = rt.pageInfo.endCursor;
  }
  return all;
}
function threadView(t) {
  const first = t.comments.nodes[0] || {};
  return { thread_id: t.id, comment_id: first.databaseId, path: t.path, line: t.line, author: first.author?.login, resolved: t.isResolved,
    outdated: t.isOutdated, replies: t.comments.totalCount - 1, url: first.url, excerpt: clean(first.body) };
}
async function resolveWorkflow(slug, wf) {
  const w = String(wf).replace(/^\.github\/workflows\//, '');
  if (/^\d+$/.test(w) || /\.ya?ml$/.test(w)) return gh('GET', `repos/${slug}/actions/workflows/${encodeURIComponent(w)}`);
  const list = (await gh('GET', `repos/${slug}/actions/workflows?per_page=100`)).workflows;
  const hit = list.find((x) => x.name.toLowerCase() === w.toLowerCase());
  if (!hit) throw new Error(`no workflow named "${wf}" (have: ${list.map((x) => `${x.name} [${x.path.split('/').pop()}]`).join(', ')})`);
  return hit;
}
/** "2026-11-07T18:00+02:00" | "90m" | "2h" | "1d" -> Date */
function parseSince(s) {
  const m = String(s).trim().match(/^(\d+)\s*([mhd])$/i);
  if (m) return new Date(Date.now() - Number(m[1]) * { m: 60e3, h: 3600e3, d: 86400e3 }[m[2].toLowerCase()]);
  const t = Date.parse(s);
  if (Number.isNaN(t)) die(`cannot read --since "${s}": use an ISO time with its zone (2026-11-07T18:00+02:00) or 90m / 2h / 1d`);
  if (!/(Z|[+-]\d\d:?\d\d)$/i.test(String(s).trim()) && /T\d/.test(s)) err('WARN: --since has no zone; read as this machine\'s local time');
  return new Date(t);
}
function findChrome() {
  if (process.env.CHROME_PATH && existsSync(process.env.CHROME_PATH)) return process.env.CHROME_PATH;
  const cands = IS_WIN
    ? [join(process.env.PROGRAMFILES || 'C:\\Program Files', 'Google\\Chrome\\Application\\chrome.exe'), join(process.env['PROGRAMFILES(X86)'] || 'C:\\Program Files (x86)', 'Google\\Chrome\\Application\\chrome.exe'), join(process.env.LOCALAPPDATA || '', 'Google\\Chrome\\Application\\chrome.exe'), join(process.env.PROGRAMFILES || 'C:\\Program Files', 'Microsoft\\Edge\\Application\\msedge.exe')]
    : platform() === 'darwin' ? ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/Applications/Chromium.app/Contents/MacOS/Chromium'] : [];
  for (const p of cands) if (p && existsSync(p)) return p;
  for (const b of ['google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser', 'chrome']) { const p = have(b); if (p) return p; }
  return null;
}

// ---------- main ----------
const fn = commands[CMD];
if (!fn) die(`unknown command "${CMD}". Run: node hw.mjs help`);
await fn().catch((e) => die(e && e.exitCode ? e.message : (e && e.message && !process.env.HW_DEBUG ? e.message : String(e && e.stack)), (e && e.exitCode) || 1));
