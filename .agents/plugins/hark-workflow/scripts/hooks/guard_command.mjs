#!/usr/bin/env node
// PreToolUse guard for run_command (hark-workflow safety rules).
//
// deny:      any force push (--force, -f in a short-flag group, --force-with-lease, --force-if-includes, +refspec),
//            --all / --mirror, a push to a protected branch (PROTECTED_BRANCHES + DEFAULT_BRANCH; also a bare
//            `git push` while on one), deleting a protected branch, destructive data commands (built-ins +
//            DESTRUCTIVE_PATTERNS from .agents/workflow.env), rm -rf on / ~ $HOME.
// force_ask: git reset --hard, git clean -f, discarding the whole tree, firebase deploy, gh pr merge --admin,
//            DELETE through gh api, any git rebase (pushed history must not be rewritten).
// allow:     everything else (normal Antigravity permissions still apply).
// Bootstrap of a brand-new empty repo only: ALLOW_PROTECTED_PUSH_ONCE=1 in .agents/workflow.env (force stays denied).
import { basename } from 'node:path';
import { currentBranch, protectedBranches } from '../lib/config.mjs';
import { allow, configFor, deny, forceAsk, guard, readPayload, toolArgs, words } from './_common.mjs';

const BUILTIN_DESTRUCTIVE = [
  /seed[_-]?firestore(\.js)?\b.*--force/i,
  /\bseed\b.*\s--force\b/i,
  /firebase\s+firestore:delete/i,
  /firebase\s+database:remove/i,
  /gh\s+workflow\s+run\s+\S*seed\S*.*force\s*=\s*true/i,
  /\bdrop\s+(database|table)\b/i,
];
const ASK = [
  [/\bgit\s+reset\s+--hard\b/, 'git reset --hard discards work'],
  [/\bgit\s+clean\s+-[a-zA-Z]*f/, 'git clean -f deletes untracked files'],
  [/\bgit\s+(checkout\s+--|restore)\s+\.(\s|$)/, 'this discards every uncommitted change'],
  [/\bgit\s+rebase\b/, 'rebasing rewrites history; the workflow merges instead (git merge --no-ff origin/<base>)'],
  [/\bfirebase\s+deploy\b/, 'live deploys go through the Deploy workflow on main, not from the agent'],
  [/\bgh\s+pr\s+merge\b.*--admin/, 'merging with --admin bypasses branch protection'],
  [/\bgh\s+api\b.*(-X|--method)\s*DELETE/, 'DELETE through the GitHub API'],
];

function gitSub(toks) {
  for (let i = 0; i < toks.length; i++) {
    if (basename(toks[i]).replace(/\.exe$/i, '') !== 'git') continue;
    let j = i + 1;
    while (j < toks.length) {
      const t = toks[j];
      if (['-C', '-c', '--git-dir', '--work-tree', '--namespace'].includes(t)) { j += 2; continue; }
      if (t.startsWith('-')) { j += 1; continue; }
      return [j, t];
    }
    return [-1, null];
  }
  return [-1, null];
}

function checkPush(toks, idx, cwd, prot, conf) {
  const args = toks.slice(idx + 1);
  for (const a of args) {
    if (['-f', '--force', '--force-with-lease', '--force-if-includes'].includes(a) || a.startsWith('--force-with-lease=') ||
      (a.startsWith('-') && !a.startsWith('--') && a.slice(1).includes('f'))) {
      deny('Force pushes are never allowed. Push a new commit instead (merge the base into the branch; never rebase pushed work).');
    }
    if (a === '--all' || a === '--mirror') deny(`\`git push ${a}\` can overwrite protected branches. Push one feature branch by name.`);
  }
  const positional = args.filter((a) => !a.startsWith('-'));
  let del = args.includes('--delete') || args.includes('-d');
  const specs = positional.slice(1);
  const boot = conf.ALLOW_PROTECTED_PUSH_ONCE === '1';
  const hint = boot ? '' : ' (Brand-new empty repo only: the owner may set ALLOW_PROTECTED_PUSH_ONCE=1 in .agents/workflow.env for the first push, then remove it.)';
  for (const spec of specs) {
    if (spec.startsWith('+')) deny('A `+refspec` is a force push. Not allowed.');
    if (spec.startsWith(':')) del = true;
    let dst = spec.includes(':') ? spec.split(':').slice(1).join(':') : spec;
    dst = dst.replace(/^refs\/heads\//, '');
    if (dst === 'HEAD') dst = currentBranch(cwd) || dst;
    if (prot.has(dst)) {
      if (del) deny(`Deleting the protected branch \`${dst}\` is not allowed.`);
      if (!boot) deny(`Never push to \`${dst}\`. Push your feature branch (feat/…, fix/…, docs/…) and open a draft PR.${hint}`);
    }
  }
  if (!specs.length) {
    const b = currentBranch(cwd);
    if (prot.has(b) && !boot) deny(`You are on \`${b}\`: a bare \`git push\` would push it. Create a branch first: git switch -c feat/<topic>.${hint}`);
  }
}

guard(async () => {
  const payload = await readPayload();
  const [name, args] = toolArgs(payload);
  if (name && name !== 'run_command') allow();
  const cmd = String(args.CommandLine || '');
  if (!cmd.trim()) allow();
  const { conf } = configFor(payload, args);
  const cwd = args.Cwd || (payload.workspacePaths || [])[0] || process.cwd();
  const prot = protectedBranches(conf);
  const extra = [];
  if ((conf.DESTRUCTIVE_PATTERNS || '').trim()) { try { extra.push(new RegExp(conf.DESTRUCTIVE_PATTERNS, 'i')); } catch { /* bad pattern: ignore */ } }
  for (const re of [...BUILTIN_DESTRUCTIVE, ...extra]) {
    if (re.test(cmd)) deny("Destructive data command blocked (it overwrites or deletes live data). It needs the owner's explicit OK and the owner runs it, not the agent.");
  }
  if (/\brm\s+-[a-zA-Z]*r[a-zA-Z]*f?[a-zA-Z]*\s+(\/|~|\$HOME)(\s|\/?$)/.test(cmd)) deny('rm -rf on the filesystem root or home directory.');
  for (const seg of cmd.split(/&&|\|\||;|\||\n/)) {
    const toks = words(seg.trim());
    if (!toks.length) continue;
    const [idx, sub] = gitSub(toks);
    if (sub === 'push') checkPush(toks, idx, cwd, prot, conf);
    else if (sub === 'branch') {
      const rest = toks.slice(idx + 1);
      if (rest.some((a) => ['-D', '-d', '--delete'].includes(a)) && rest.some((a) => prot.has(a))) deny('Deleting a protected branch is not allowed.');
    }
  }
  for (const [re, why] of ASK) if (re.test(cmd)) forceAsk(`Needs your confirmation: ${why}.`);
  allow();
});
