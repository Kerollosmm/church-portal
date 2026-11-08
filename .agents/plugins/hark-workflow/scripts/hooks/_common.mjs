// Shared helpers for the hark-workflow hooks (Node, cross-platform).
// Contract (https://antigravity.google/docs/hooks): JSON on stdin, one JSON object on stdout, exit 0.
// A crash must never block the agent: every hook catches everything and answers "allow" / {}.
import { existsSync, writeSync } from 'node:fs';
import { loadConfig } from '../lib/config.mjs';

export async function readPayload() {
  const chunks = [];
  try {
    for await (const ch of process.stdin) chunks.push(ch);
    const raw = Buffer.concat(chunks).toString('utf8');
    return raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

export function emit(obj) {
  writeSync(1, JSON.stringify(obj)); // synchronous: process.exit must not cut a piped write
  process.exit(0);
}

export const allow = () => emit({ decision: 'allow' });
export const deny = (reason) => emit({ decision: 'deny', reason: `[hark-workflow] ${reason}` });
export const forceAsk = (reason) => emit({ decision: 'force_ask', reason: `[hark-workflow] ${reason}` });

export function toolArgs(payload) {
  const call = payload.toolCall || {};
  return [call.name || '', call.args || {}];
}

export function workspaceDir(payload, args) {
  const cands = [];
  if (args && args.Cwd) cands.push(args.Cwd);
  cands.push(...(payload.workspacePaths || []));
  for (const c of cands) if (c && existsSync(c)) return c;
  return process.cwd();
}

export function configFor(payload, args) {
  return loadConfig(workspaceDir(payload, args));
}

/** POSIX-ish word splitting (quotes and backslashes), good enough for git command lines. */
export function words(s) {
  const out = []; let cur = ''; let q = null; let any = false;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (q) {
      if (ch === q) { q = null; continue; }
      if (ch === '\\' && q === '"' && i + 1 < s.length) { cur += s[++i]; continue; }
      cur += ch; continue;
    }
    if (ch === '"' || ch === "'") { q = ch; any = true; continue; }
    if (ch === '\\' && i + 1 < s.length) { cur += s[++i]; any = true; continue; }
    if (/\s/.test(ch)) { if (cur || any) { out.push(cur); cur = ''; any = false; } continue; }
    cur += ch;
  }
  if (cur || any) out.push(cur);
  return out;
}

export function guard(main) {
  main().catch(() => allow());
}
