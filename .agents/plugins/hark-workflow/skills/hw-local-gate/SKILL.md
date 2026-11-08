---
name: hw-local-gate
description: >-
  Stage 05 of the hark-workflow loop: run the full local gate (setup, analyze, tests, seed drift, security-rules
  emulator tests, release build, bundle size vs budget) before EVERY push, and check that nothing unwanted is staged.
  Use after implementing and documenting a PR, after every review or CI fix, and before any git push.
---

# hw-local-gate — prove it locally before you push (stage 05)

## Before you start (every time)

1. Find `<KIT>` (two folders above this file; also STATUS.md row `kit`). Replace `<KIT>` in commands. Keep quotes.
2. Read `.work/<TOPIC>/STATUS.md`. Run every command from the `worktree` folder.
3. Check: `git branch --show-current` prints the STATUS `branch`. IF it prints `main` → STOP, run `hw-worktree`.
4. One action per step, in order.

## Rules

- The gate runs before EVERY push. A push without a `GATE: PASS` line for the same commit is a broken rule.
- Never push with a red gate "because CI will check it". CI minutes are slower than your machine.
- Never skip a step by editing `.agents/workflow.env`. Only the owner changes the gate.
- Never commit what the build or a tool produced: `build/`, `node_modules/`, `*-debug.log`
  (`firestore-debug.log`, `firebase-debug.log`, `ui-debug.log`), `.dart_tool/`, coverage, screenshots of a run.

## Step 1 — Clean tree check

1. Run: `git status --short`
2. Read every line. Use this table:

| Line looks like | Do |
|---|---|
| ` M lib/…` / `?? test/…` that belongs to this PR | keep it; it gets staged in Step 4 |
| `?? node_modules/` or `?? tool/rules_test/node_modules/` | do NOT stage. Check `.gitignore` has `node_modules/`. Missing → add it in this PR. |
| `?? firestore-debug.log`, `?? *-debug.log`, `?? ui-debug.log` | do NOT stage. Delete the file. Add `*-debug.log` to `.gitignore` if missing. |
| `?? build/`, `?? .dart_tool/`, `?? coverage/` | do NOT stage. They must be ignored. |
| a file you did not touch | do NOT stage. Ask yourself why it changed (a generator?). Unsure → write it in STATUS.md. |

## Step 2 — Run the gate

1. Run: `node "<KIT>/scripts/hw.mjs" gate --status <TOPIC>`
   (it runs: setup → analyze → tests → seed → rules → build → post-build → size, and logs the verdict in STATUS.md)
2. Wait for the last line. It starts with `GATE:`. Copy it.
3. Decide:

| Last line | Do |
|---|---|
| `GATE: PASS — …` | go to Step 3 |
| `GATE: FAIL — … failed: analyze` | read the printed lines; fix every issue (also "info" lints the project treats as errors); run the gate again |
| `GATE: FAIL — … failed: tests` | open `.work/_logs/gate-tests.log`; find the first `FAILED` / `Expected:`; fix the cause (skill `hw-fix-bug`); run again |
| `GATE: FAIL — … failed: seed` | the generator output differs from the committed file. Run the generator, look at the diff, commit the regenerated file IF the change is yours; ELSE fix the generator input |
| `GATE: FAIL — … failed: rules` | open `.work/_logs/gate-rules.log`; see the rules table below |
| `GATE: FAIL — … failed: build` | read the error; a deferred-import or tree-shaking error is common (see the size table) |
| `ERROR: …` (tool missing) | run `node "<KIT>/scripts/hw.mjs" doctor`; install the FAIL tool; run again |

4. The SAME step fails twice with the SAME error after your fixes → STOP. `status set <TOPIC> blocked yes`, report
   with the blocked template (rule `reporting`).

### Security-rules failures (Firestore)

| Error text | Cause | Fix |
|---|---|---|
| `Evaluation error` / `exceeded maximum expressions` / the write is denied only for BIG documents | Firestore rules stop at **1000 expressions per evaluation**. A huge `validFeatures()` with every key checked every time hits it. | Split into functions. Short-circuit legacy keys first (`request.resource.data.diff(resource.data).affectedKeys().hasOnly([...legacy])`). Check new keys only when a new key changed. Keep a test with the worst-case (largest) real document. |
| an OLD client write is now denied | you tightened or renamed a legacy key | rules must stay backward compatible: never tighten an existing key; add new keys in a new gated function |
| `ECONNREFUSED 127.0.0.1:8080` | emulator not started / port busy | the test script starts it; kill the old Java process; run again |
| `java: not found` | no Java | install Java 11+ (doctor row `java`) |

## Step 3 — Size budget (only when `SIZE_FILE` is set)

1. Find the `SIZE:` line in the gate output (or run `node "<KIT>/scripts/hw.mjs" size --status <TOPIC>`).
2. Decide:

| Line | Do |
|---|---|
| `SIZE: OK — …` | copy it into STATUS.md row `size`: `node "<KIT>/scripts/hw.mjs" status set <TOPIC> size "<line>"` |
| `SIZE: OVER BUDGET — …` | make code lazy. Flutter web: move big, rarely used screens / sheets / helpers behind `import '…' deferred as x;` and `await x.loadLibrary()` before first use. Rebuild. Run size again. |
| `SIZE: MISSING …` | the build did not run. Run the gate without `--no-build`. |

3. Deferred import traps (real bugs from church-portal):
   - A tear-off like `onPressed: guide.showSteps` is evaluated BEFORE `loadLibrary()` → `_DeferredNotLoadedError`.
     Write a closure: `onPressed: () async { await guide.loadLibrary(); guide.showSteps(context); }`.
   - Constants and types from a deferred library cannot be used in `const` expressions or type annotations.
   - Add a widget test that taps the button that loads the deferred library.
4. IF still over budget after deferring → STOP. Ask the owner: "accept +N KB gz (why) or cut <feature>?"
   Recommended answer included.

## Step 4 — Stage and commit what is left (only if Steps 1–3 changed files)

1. `git add <explicit paths>` — never `git add -A`, never `git add .`.
2. `git status --short` — check that only your files are staged (first column `M`/`A`).
3. `git commit -m "<area>: <what>"`

## Step 5 — Record

1. `node "<KIT>/scripts/hw.mjs" status set <TOPIC> gate "<GATE: line> @ <sha7>"` (sha7 = `git rev-parse --short HEAD`)
2. Set `stage`: first time for this PR → `06-open-pr`. Coming back from review or CI → the stage you came from
   (`07-review-loop` or `08-ci-watch`); the push happens there.
3. Set `next_action` (e.g. `push and open the draft PR`).

## Definition of done

- [ ] `GATE: PASS — …` line in STATUS.md for the current HEAD sha7 (print `git rev-parse --short HEAD` next to it).
- [ ] `SIZE: OK` line (or the owner's quoted OK for the overage) when `SIZE_FILE` is set.
- [ ] `git status --short` prints nothing (or only ignored-by-design files you listed in STATUS.md).
- [ ] No `node_modules/`, `*-debug.log`, `build/` in `git show --stat HEAD`.
