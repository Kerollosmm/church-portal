#!/usr/bin/env node
// PreToolUse guard for file writes: never let a secret land in the tree.
// Blocks write_to_file / replace_file_content / multi_replace_file_content when the new content contains a private key,
// a Google service-account key or a well-known token format. Public identifiers (Firebase web apiKey, Sentry DSN,
// reCAPTCHA site key) are NOT secrets and are allowed. Extra: SECRET_PATTERNS (one regular expression) in workflow.env.
import { basename } from 'node:path';
import { allow, configFor, deny, guard, readPayload, toolArgs } from './_common.mjs';

const PATTERNS = [
  [/-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/, 'a private key'],
  [/"type"\s*:\s*"service_account"[\s\S]{0,4000}"private_key"/, 'a Google service-account key'],
  [/\bgh[pousr]_[A-Za-z0-9]{36,}\b/, 'a GitHub token'],
  [/\bgithub_pat_[A-Za-z0-9_]{40,}\b/, 'a GitHub fine-grained token'],
  [/\bsk-(proj-|ant-)?[A-Za-z0-9_-]{32,}\b/, 'an API secret key'],
  [/\bxox[baprs]-[A-Za-z0-9-]{20,}\b/, 'a Slack token'],
  [/\bsntrys_[A-Za-z0-9_=-]{40,}\b/, 'a Sentry auth token'],
  [/\bAKIA[0-9A-Z]{16}\b/, 'an AWS access key id'],
];

function* contents(name, args) {
  if (name === 'write_to_file') yield String(args.CodeContent || '');
  else if (name === 'replace_file_content') yield String(args.ReplacementContent || '');
  else if (name === 'multi_replace_file_content') for (const ch of args.ReplacementChunks || []) if (ch && typeof ch === 'object') yield String(ch.ReplacementContent || '');
}

guard(async () => {
  const payload = await readPayload();
  const [name, args] = toolArgs(payload);
  const { conf } = configFor(payload, args);
  const pats = [...PATTERNS];
  if ((conf.SECRET_PATTERNS || '').trim()) { try { pats.push([new RegExp(conf.SECRET_PATTERNS), 'a project-defined secret']); } catch { /* ignore */ } }
  for (const text of contents(name, args)) {
    for (const [re, what] of pats) {
      if (re.test(text)) deny(`The new content of ${basename(String(args.TargetFile || '')) || 'the file'} looks like ${what}. Secrets never go in code, config, docs or chat: use the CI secret store / environment variables and reference them by name.`);
    }
  }
  allow();
});
