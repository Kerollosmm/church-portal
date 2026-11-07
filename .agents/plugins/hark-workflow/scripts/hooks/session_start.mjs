#!/usr/bin/env node
// SessionStart: give the agent the workflow context in one system message.
// The hook runs with cwd = plugin root (docs), so this is also how the agent learns the absolute kit path (HW_KIT).
import { existsSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { KIT_DIR, currentBranch, defaults, gitRoot, loadConfig, protectedBranches } from '../lib/config.mjs';
import { emit, readPayload, workspaceDir } from './_common.mjs';

(async () => {
  try {
    const payload = await readPayload();
    const ws = workspaceDir(payload);
    const root = gitRoot(ws);
    const hw = `node "${join(KIT_DIR, 'scripts', 'hw.mjs')}"`;
    const parts = [`hark-workflow: HW_KIT=${KIT_DIR} (helper: ${hw} help)`];
    if (root) {
      const { conf, file } = loadConfig(root);
      const c = defaults(conf);
      const branch = currentBranch(root) || '?';
      parts.push(`repo ${root} on branch \`${branch}\`${protectedBranches(c).has(branch) ? ' (PROTECTED: never edit or commit here; use a worktree per PR, skill hw-worktree)' : ''}`);
      parts.push(`config .agents/workflow.env ${file ? 'found' : 'MISSING (run skill hw-bootstrap)'}`);
      const sd = join(root, c.STATUS_DIR);
      if (existsSync(sd)) {
        const open = readdirSync(sd).filter((d) => existsSync(join(sd, d, 'STATUS.md'))).slice(-5);
        if (open.length) parts.push(`open STATUS files: ${open.map((d) => relative(root, join(sd, d, 'STATUS.md'))).join(', ')} — read the newest before doing anything`);
      }
      if (c.OWNER_LANGUAGE && c.OWNER_LANGUAGE !== 'en') parts.push(`reply to the owner in ${c.OWNER_LANGUAGE}`);
    }
    parts.push('Entry point: skill hw-start (or the parent-agent custom agent).');
    emit({ injectSteps: [{ systemMessage: { systemMessage: parts.join('; ') } }] });
  } catch {
    emit({});
  }
})();
