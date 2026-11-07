# STATUS — {{TOPIC}}

> The single source of truth for this work. Every agent reads it FIRST and updates it AFTER EVERY STEP.
> Never trust memory: if it is not written here, it did not happen.
> Update a row: `node "{{KIT}}/scripts/hw.mjs" status set {{TOPIC}} <key> "<value>"`
> Add a log line: `node "{{KIT}}/scripts/hw.mjs" status log {{TOPIC}} "<what happened + evidence line>"`

## State

| Key | Value |
|---|---|
| goal | {{GOAL}} |
| stage | 01-intake |
| next_action | read the request, write questions for the owner |
| owner_language | {{LANG}} |
| kit | {{KIT}} |
| repo | {{REPO}} |
| plan_doc | - |
| chain | - |
| branch | - |
| worktree | - |
| base | - |
| pr | - |
| head_sha | - |
| gate | - |
| size | - |
| ci | - |
| review_round | 0 |
| review_open_threads | - |
| dev_test | - |
| owner_approval | - |
| merge_sha | - |
| deploy | - |
| psi | - |
| docs | - |
| retries_this_stage | 0 |
| blocked | no |

## PRs (one row per PR; the parent-agent keeps it; single PR = one row)

| # | PR | branch | base | worktree | agent now | stage | head | gate | ci | reviews | owner |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A | - | - | - | - | - | - | - | - | - | 0/2 | - |

## Acceptance criteria (copied from the plan; tick with evidence)

- [ ] (fill in at stage 02-plan)

## Owner decisions (quote the owner + time)

- {{NOW}} — (none yet)

## Log (newest last; every line ends with the evidence: a command verdict line, a SHA, a URL)

- {{NOW}} — STATUS created
