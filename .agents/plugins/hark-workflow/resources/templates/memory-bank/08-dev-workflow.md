# 08 — Dev workflow

## Commands
```bash
# install / analyze / test / build / rules tests / seed dry-run
```

## Branch and PR rules
- Branch per change (`feat/`, `fix/`, `docs/`); never push to `{{DEFAULT_BRANCH}}`; never force-push.
- PR: tests + memory bank + documentation/ in the same PR; request AI reviews; CI green on head; squash-merge.
- Never run destructive data scripts (seed `--force`, deletes) without the owner's explicit OK.

## CI/CD
| Workflow | Trigger | Jobs |
|---|---|---|
| {{CI_WORKFLOW}} | PR, push | |
| {{DEPLOY_WORKFLOW}} | push to {{DEFAULT_BRANCH}}, PR preview | |

## Checklists
### Add a feature / section
1. Domain logic + tests
2. Model + admin schema + rules + seed
3. Switch hides it everywhere when off
4. Strings in both languages
5. Memory bank + documentation/ + ADR
