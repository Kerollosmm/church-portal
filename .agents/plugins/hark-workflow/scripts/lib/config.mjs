// Shared helpers for hw.mjs and the hooks: find the kit, the repo, and read .agents/workflow.env.
// Zero dependencies. Works on Windows, macOS and Linux (Node >= 18).
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const KIT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
export const CONFIG_REL = join('.agents', 'workflow.env');

/** Run git and return trimmed stdout, or null on any error. */
export function git(args, cwd) {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 15000 }).trim();
  } catch {
    return null;
  }
}

export function gitRoot(path) {
  return git(['rev-parse', '--show-toplevel'], path);
}

/** The main checkout of a repo (worktrees share it): STATUS files and the fallback config live there. */
export function mainRoot(path) {
  const common = git(['rev-parse', '--path-format=absolute', '--git-common-dir'], path);
  if (common && /[\\/]\.git$/.test(common)) return dirname(common);
  return gitRoot(path);
}

export function currentBranch(path) {
  return git(['symbolic-ref', '--short', '-q', 'HEAD'], path) || git(['rev-parse', '--abbrev-ref', 'HEAD'], path);
}

/** Parse KEY="value" lines (shell-like, never executed). */
export function parseEnv(text) {
  const conf = {};
  for (let raw of text.split(/\r?\n/)) {
    let line = raw.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    if (line.startsWith('export ')) line = line.slice(7).trim();
    const eq = line.indexOf('=');
    const key = line.slice(0, eq).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let rest = line.slice(eq + 1).trim();
    let value = '';
    if (rest.startsWith('"')) {
      let i = 1;
      while (i < rest.length) {
        const ch = rest[i];
        if (ch === '\\' && i + 1 < rest.length) { value += rest[i + 1]; i += 2; continue; }
        if (ch === '"') break;
        value += ch; i += 1;
      }
    } else if (rest.startsWith("'")) {
      const end = rest.indexOf("'", 1);
      value = end === -1 ? rest.slice(1) : rest.slice(1, end);
    } else {
      const hash = rest.search(/\s#/);
      value = (hash === -1 ? rest : rest.slice(0, hash)).trim();
    }
    conf[key] = value;
  }
  return conf;
}

/** Config of the repository that contains `path`: walks up to the git root looking for .agents/workflow.env. */
export function loadConfig(path = process.cwd()) {
  const start = resolve(path);
  const root = gitRoot(start) || start;
  let probe = start;
  for (;;) {
    const cand = join(probe, CONFIG_REL);
    if (existsSync(cand)) {
      try {
        return { conf: parseEnv(readFileSync(cand, 'utf8')), root, file: cand };
      } catch {
        return { conf: {}, root, file: null };
      }
    }
    if (resolve(probe) === resolve(root) || dirname(probe) === probe) break;
    probe = dirname(probe);
  }
  // A worktree of a branch that does not carry .agents/workflow.env yet: use the main checkout's copy.
  const main = mainRoot(start);
  if (main && resolve(main) !== resolve(root) && existsSync(join(main, CONFIG_REL))) {
    try { return { conf: parseEnv(readFileSync(join(main, CONFIG_REL), 'utf8')), root, file: join(main, CONFIG_REL) }; } catch { /* fall through */ }
  }
  return { conf: {}, root, file: null };
}

export function defaults(conf) {
  return {
    DEFAULT_BRANCH: 'main',
    PROTECTED_BRANCHES: 'main master',
    REVIEW_BOTS: 'coderabbitai sentry',
    REVIEW_MAX_ROUNDS: '2',
    REVIEW_STALL_MINUTES: '10',
    MEMORY_BANK_DIR: 'docs/memory-bank',
    DOCS_DIR: 'documentation',
    STATUS_DIR: '.work',
    WORKTREE_ROOT: '.work/wt',
    TIMEZONE: '',
    OWNER_LANGUAGE: 'en',
    ...conf,
  };
}

export function protectedBranches(conf) {
  const names = new Set(String(conf.PROTECTED_BRANCHES || 'main master').replace(/,/g, ' ').split(/\s+/).filter(Boolean));
  if (conf.DEFAULT_BRANCH) names.add(conf.DEFAULT_BRANCH);
  return names;
}
