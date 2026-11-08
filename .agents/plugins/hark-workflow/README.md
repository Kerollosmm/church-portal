# hark-workflow v2 — an engineering ship loop for Google Antigravity agents

**English** · [بالعربي](#بالعربي)

`hark-workflow` is a Google Antigravity **plugin** (the repo root is the plugin) that turns an owner's request into a
live, verified, documented change, the way [`Kerollosmm/church-portal`](https://github.com/Kerollosmm/church-portal)
is built:

intake → plan + owner gate G0 → one git worktree per PR → test-first code → docs in the same PR → local gate with size
budget → draft PR → green CI → AI reviews (CodeRabbit, Sentry) triaged and answered → optional dev-channel test →
owner approval with phone screenshots → squash-merge with a head-SHA guard → deploy + live check → final docs and a
short report in the owner's language.

Everything is plain Markdown plus one zero-dependency Node helper (`scripts/hw.mjs`), so it runs the same on Linux,
macOS and Windows, and a weak model can follow it step by step.

| Part | What you get |
|---|---|
| **Skills** (`skills/`, 18) | `hw-start` (entry point and router) + one skill per stage, see the [stage map](#stage-map) |
| **Custom agents** (`agents/`, 9) | `parent-agent` (main agent, delegates and re-checks) + 8 sub-agents, each a checklist with a single-agent fallback |
| **Rules** (`rules/`) | `AGENTS.md` always-on safety rules · `quality-bar.md` · `reporting.md` |
| **Hooks** (`hooks.json`) | git safety (no force-push, no push to `main`, no destructive data commands), secret guard on file writes, session context |
| **Helper** (`scripts/hw.mjs`) | 35 commands: doctor, STATUS.md, local gate, size, ADR numbers, PRs, CI, reviews, merge guard, deploy check, PSI, Sentry, install |
| **Templates** (`resources/templates/`) | STATUS, plan, sub-agent brief, PR body, ADR, owner report, PR-review report, QA phase report, memory bank 00–12, AGENTS.md, project rules, `workflow.env.example` |
| **Profiles** (`examples/<name>/agents-dir/`) | ready project settings; `church-portal` is the reference profile |

Formats follow the Antigravity docs as of Nov 2026: [plugins](https://antigravity.google/docs/plugins),
[build plugins](https://antigravity.google/docs/build-plugins), [skills](https://antigravity.google/docs/skills),
[custom subagents](https://antigravity.google/docs/subagents), [rules](https://antigravity.google/docs/rules),
[hooks](https://antigravity.google/docs/hooks), [customization discovery](https://antigravity.google/docs/customization-discovery).

## Requirements

- **Node.js 18+** (hooks and `hw.mjs`; no npm packages) and **git**.
- GitHub access: the `gh` CLI signed in (`gh auth login`) **or** `GITHUB_TOKEN` / `GH_TOKEN` in the environment.
- Your stack's tools for the local gate (church-portal: Flutter stable, Node 22, Java 21 for the Firestore emulator,
  Python 3 for the seed scripts). Optional: Chrome (screenshots), `SENTRY_TOKEN` (Sentry check).
- `node scripts/hw.mjs doctor` checks all of it and says what is missing.

## Install

Pick one. Plugin skills and agents are namespaced `hark-workflow:<name>`.

```bash
# A) Antigravity CLI — every workspace on this machine (also shows in the App's Installed tab)
agy plugin install Kerollosmm/agent-workflow-kit
#   or: agy plugin install https://github.com/Kerollosmm/agent-workflow-kit
agy plugin list                         # hark-workflow (enabled, 2.0.0)

# B) One project only — committed with the repo, so every teammate and agent gets the same kit
git clone https://github.com/Kerollosmm/agent-workflow-kit /tmp/hark-workflow
node /tmp/hark-workflow/scripts/hw.mjs install workspace /path/to/your-repo
#   -> /path/to/your-repo/.agents/plugins/hark-workflow/  (+ .agents/workflow.env from the template if missing)

# C) Global without the CLI — every project on this machine
node /tmp/hark-workflow/scripts/hw.mjs install global
#   -> ~/.gemini/config/plugins/hark-workflow/

# Other agents (Claude Code, Codex, Cursor …): copy only the skills
node /tmp/hark-workflow/scripts/hw.mjs install skills /path/to/your-repo/.claude/skills
```

| Location | Path | Use when |
|---|---|---|
| Project | `<repo>/.agents/plugins/hark-workflow/` | the kit version should travel with the repo (reviewable in PRs) |
| Global | `~/.gemini/config/plugins/hark-workflow/` (or `agy plugin install`) | you work on many repos with the same kit |

The repository is private: `agy plugin install` and `git clone` need a GitHub login on that machine that can read it.

Check it loaded: App → **Settings → Projects → <project> → Customizations** (skills, rules, plugins, custom agents),
or in the CLI `/skills`, `/agents`, `/plugin`. The session-start message `hark-workflow: HW_KIT=…` proves the hooks
run.

## First run

1. Open the project (a git repo) in Antigravity and check the machine:

   ```bash
   node "<KIT>/scripts/hw.mjs" doctor          # <KIT> = the folder with plugin.json; `hw.mjs kit` prints it
   ```

2. **No project settings yet** (`config … MISSING`): run the skill **`hw-bootstrap`** (say "set up the hark
   workflow for this repo"). It detects the stack, writes `.agents/workflow.env`, the project `AGENTS.md`, the memory
   bank, the owner's rules in `.agents/rules/`, `.gitignore` entries and size / PageSpeed baselines, runs a first
   gate, and delivers it all as one draft PR.
3. **A profile exists for the repo** (church-portal): install it instead, on a branch, never on `main`:

   ```bash
   node "<KIT>/scripts/hw.mjs" install profile church-portal /path/to/church-portal          # keeps existing files
   node "<KIT>/scripts/hw.mjs" install profile church-portal /path/to/church-portal --force  # overwrites them
   node "<KIT>/scripts/hw.mjs" config                                                        # effective values
   ```

   It copies `examples/church-portal/agents-dir/` into `<repo>/.agents/`: `workflow.env`, `AGENTS.md` (owner and
   process rules) and `rules/church-portal.md` (code and content rules). Commit them with explicit paths and open a
   draft PR.
4. Add `.work/` to `.gitignore` (STATUS files, logs, worktrees live there).

## How to use it

### Antigravity App or CLI — parent-agent with sub-agents

Select the custom agent **`parent-agent`** as the main agent (App: agent picker; CLI: `/agents`) and give it the
request or the plan. It loads `hw-start`, keeps `.work/<topic>/STATUS.md`, and for each stage:

1. fills `resources/templates/subagent-brief.md`;
2. calls `invoke_subagent` with the stage's agent (`implementer`, `reviewer-fixer` …; if the type is unknown it
   retries once with `hark-workflow:implementer`);
3. **re-checks every claim itself** — re-runs the gate, reads CI, counts open threads — before the next stage;
4. stops only at the owner gates: G0 plan, G1 visual check (if asked), G2 chain ready, G3 merge approval, any live-data
   write, money or outside message, and `blocked: yes`.

Say "continue" (or «كمّل») in a new session: the session hook lists open STATUS files and the agent resumes there.

### Antigravity IDE — single-agent fallback

The IDE has no sub-agents. Use the normal agent and start with the skill **`hw-start`** (or ask for `parent-agent`).
It runs every stage itself, one at a time, in **persona mode**: before each stage it reads that agent's Role,
Checklist and Never sections from `agents/<agent>.md`, logs `persona: <agent>` and `mode: single-agent` in STATUS.md,
and still runs the "verify every claim" commands. The same happens in the App / CLI when delegation fails twice.

### Start prompt for Gemini in Antigravity

English:

```text
Use the hark-workflow plugin. Start with the skill hw-start (you are the parent-agent; if invoke_subagent is not
available, work in single-agent persona mode). First run `node "<KIT>/scripts/hw.mjs" doctor`; if the config is
MISSING, run hw-bootstrap. Create or read .work/<topic>/STATUS.md and keep it current after every step.
My request: <describe the change, bug, plan file, or "review PR #n">.
Rules: plan first and wait for my G0 approval before any code; one worktree and one draft PR per topic; never push
to main, never force-push, never merge without my written "merge"; no live data writes without my OK for that one
item; docs in the same PR; every claim with evidence (GATE / CI / SHA / URL). Ask me at most 3 numbered questions,
each with your recommendation.
```

بالعربي:

```text
استخدم إضافة hark-workflow. ابدأ بمهارة hw-start (أنت parent-agent، ولو أداة invoke_subagent مش متاحة اشتغل
بنفسك مرحلة مرحلة في وضع single-agent). أول حاجة شغّل `node "<KIT>/scripts/hw.mjs" doctor`، ولو الإعدادات
MISSING شغّل hw-bootstrap. اعمل أو اقرأ ‎.work/<topic>/STATUS.md وحدّثه بعد كل خطوة.
طلبي: <اوصف التعديل أو المشكلة أو ملف الخطة أو «راجع PR رقم n»>.
القواعد: الخطة الأول واستنى موافقتي G0 قبل أي كود؛ worktree واحد و PR مسودة واحد لكل موضوع؛ ممنوع push على main
وممنوع force-push وممنوع merge من غير ما أكتب «ادمج»؛ ممنوع أي كتابة على البيانات الحية من غير موافقتي على كل بند
لوحده؛ التوثيق في نفس الـ PR؛ كل نتيجة بدليل (GATE / CI / SHA / رابط). كلمني بالعربي، وبحد أقصى ٣ أسئلة مرقّمة
ومع كل سؤال اقتراحك.
```

## Stage map

### The 18 skills

| Stage | Skill | Does | Agent |
|---|---|---|---|
| — | `hw-start` | entry point: STATUS.md, picks the stage, delegates or runs it | parent-agent |
| 00 | `hw-bootstrap` | workflow.env, AGENTS.md, memory bank, rules, baselines, first gate — one draft PR | orchestrator |
| 01 | `hw-intake` | goal, acceptance criteria, scope, owner questions | planner |
| 02 | `hw-plan` | plan doc, PR chain, ADR numbers, size / cost budgets, owner gate G0 | planner |
| 03 | `hw-worktree` | one worktree per PR, chain sync by merge (never rebase) | orchestrator |
| 04 | `hw-implement` | code + tests for one PR, explicit pathspecs | implementer |
| 04 | `hw-fix-bug` | root cause + regression test that fails before the fix | implementer |
| 04b / 13 | `hw-docs-sync` | mode A in the PR (memory bank, ADR, user docs, open tasks); mode B after merge | docs-keeper |
| 05 | `hw-local-gate` | full gate + size budget before every push | implementer |
| 06 | `hw-open-pr` | push + draft PR with the full body | implementer |
| 07 | `hw-review-loop` | CodeRabbit + Sentry, triage, fix with tests, reply on every thread, max 2 rounds | reviewer-fixer |
| 08 | `hw-ci-watch` | green CI on the head; red → logs, reproduce, fix (one infra re-run max) | release-verifier |
| 09 | `hw-dev-test` | merge into dev, dev channel deploy, test on the dev URL (optional) | release-verifier |
| 10 | `hw-owner-approval` | 390 px / 1280 px screenshots, approval recorded word for word with the head SHA | parent-agent |
| 11 | `hw-merge` | squash-merge with head-SHA guard; chains bottom-up | release-verifier |
| 12 | `hw-deploy-verify` | CI + deploy on main, live 200, bundle strings, PSI, Sentry | release-verifier |
| side | `hw-pr-review` | review someone else's PR read-only, verdict report | pr-reviewer |
| side | `hw-qa-sim` | QA phase on the emulator only, PASS / PARTIAL / FAIL / N/A report | qa-tester |

Normal order for one PR: 03 → 04 → 04b → 05 → 06 → 08 → 07 → 08 → (09) → 10 → 11 → 12 → 13. Every fix goes back
through 05 and 08.

### The 9 agents

| Agent | Model | Stages |
|---|---|---|
| `parent-agent` | pro (main agent) | all: routes, delegates, verifies, owner contact (10) |
| `planner` | pro | 01, 02 |
| `orchestrator` | flash | 00, 03 |
| `implementer` | pro | 04, 05, 06, code fixes from 07 / 08 |
| `docs-keeper` | flash | 04b, 13 |
| `reviewer-fixer` | pro | 07 |
| `release-verifier` | flash | 08, 09, 11, 12 (never edits code) |
| `pr-reviewer` | pro | side: review a PR |
| `qa-tester` | flash | side: QA simulation (never fixes code) |

## hw.mjs command reference

Run `node "<KIT>/scripts/hw.mjs" help [command]`. Exit codes are documented per command; every command prints one
verdict line (`GATE: PASS`, `CI: GREEN on <sha7>`, `DEPLOY: VERIFIED <sha7>` …) that the agents quote as evidence.

| Group | Commands |
|---|---|
| Setup | `help`, `kit`, `doctor`, `config`, `install workspace <project> \| global \| profile <name> <project> [--force] \| skills <dir>` |
| State | `status init\|log\|set\|show <topic>` |
| Local checks | `gate [--quick] [--no-build] [--keep-going] [--only a,b] [--status <topic>]`, `size`, `adr-next`, `adr-new "<title>"` |
| Worktrees | `worktree <new-branch> --base <base>`, `worktree <branch> --existing`, `worktree list`, `pr-checkout <n>` |
| Pull requests | `pr-create` (always draft), `pr-edit`, `pr-status`, `pr-ready <n> --approval "…"`, `merge <n> --sha <head> --approval "…"` |
| CI / Actions | `wait-ci <pr\|sha>`, `ci-logs`, `ci-rerun <run-id>` (once), `dispatch <workflow>`, `wait-run` |
| Reviews | `bots`, `bots-wait`, `review-request`, `threads`, `reply`, `resolve`, `comment` |
| Release | `deploy-verify`, `dev-channel-url`, `psi`, `screenshot`, `sentry-issues --since …` |
| Escape hatch | `api <METHOD> <path>` |

Settings live in `<repo>/.agents/workflow.env` (documented key by key in `resources/templates/workflow.env.example`).

## Safety guarantees

Enforced by hooks (Antigravity runs them before the tool call):

- **No force-push** in any form (`--force`, `-f`, `--force-with-lease`, `+refspec`), no `--all` / `--mirror`.
- **No push to `main`** or any `PROTECTED_BRANCHES` (also a bare `git push` while on one); no deleting them.
- **No destructive data commands**: built-ins (forced seeds, `firestore:delete`, `database:remove`, `drop table`) plus
  the project's `DESTRUCTIVE_PATTERNS` (church-portal: real seed runs, Seed / Deploy / commemoration workflows by hand,
  `publish_hosting_file.js`, `hosting:channel:deploy`, `firebase firestore:*`).
- **Ask first**: `git reset --hard`, `git clean -f`, discarding the tree, `firebase deploy`, `gh pr merge --admin`,
  API `DELETE`, any `git rebase`.
- **No secrets in files**: private keys, service-account JSON, GitHub / Slack / Sentry / AWS / API tokens are blocked
  in file writes (public web keys like the Firebase apiKey or a Sentry DSN are allowed).

Enforced by `hw.mjs`: PRs are opened as drafts; `pr-ready` and `merge` need the owner's approval text; `merge`
refuses when the head SHA moved or CI is not green; `ci-rerun` re-runs only failed jobs and only once.

Enforced by rules (on the agent): never merge without the owner's "merge" / «ادمج» for that PR, no live-data writes
without approval per item, explicit pathspecs (never `git add -A`), no invented facts, stop after the same failure
twice, reply in the owner's language.

## Known limits and unverified items

- **Not verified in a real Antigravity session yet**: that Antigravity loads `.agents/AGENTS.md` (installed by a
  profile) as always-on context. If it does not, the project rules still apply through `.agents/rules/*.md`
  (`trigger: always_on`) and the repo's own `AGENTS.md` pointer.
- **Not verified**: whether `invoke_subagent` needs the plugin prefix (`hark-workflow:implementer`) for plugin
  agents. The kit tries the bare name first and retries once with the prefix.
- **Windows**: hooks and `hw.mjs` are plain Node and the offline tests pass on Linux, but the hook shell on Windows
  (how Antigravity launches `node ./scripts/...` there) is untested.
- `agy plugin validate --strict` runs in `scripts/validate.mjs` only when the Antigravity CLI is installed; CI does not
  have it.
- The church-portal profile's `GATE_ENV_SCRIPT` points at a Hark sandbox path; on any other machine the gate reports
  it as skipped and takes Flutter / Node / Java from `PATH`.

## Changing this kit

Layout and conventions: [`AGENTS.md`](AGENTS.md). Gate: `node scripts/validate.mjs` (manifest, skills, agents, rules,
hooks, cross references, examples, `node --check`, hook tests, `hw.mjs` offline tests). History:
[`CHANGELOG.md`](CHANGELOG.md).

---

<div dir="rtl">

## بالعربي

**`hark-workflow`** إضافة (plugin) لـ Google Antigravity — جذر المستودع هو الإضافة نفسها. بتحوّل طلب صاحب المشروع
لتعديل شغّال على الموقع الحي، متأكَّد منه وموثَّق، بنفس الطريقة اللي اتبنى بيها مشروع
[`Kerollosmm/church-portal`](https://github.com/Kerollosmm/church-portal):

استلام الطلب ← خطة وموافقة صاحب المشروع (G0) ← worktree منفصل لكل PR ← اختبارات قبل الكود ← التوثيق في نفس الـ PR ←
فحص محلي كامل مع ميزانية الحجم ← PR مسودة ← CI أخضر ← مراجعات الذكاء الاصطناعي (CodeRabbit و Sentry) والرد على كل
تعليق ← تجربة على قناة dev (اختياري) ← موافقة صاحب المشروع بصور من الموبايل ← دمج squash مع حماية الـ SHA ← التأكد من
النشر والموقع الحي ← تحديث التوثيق النهائي وتقرير قصير بلغة صاحب المشروع.

كل حاجة ملفات Markdown عادية ومعاها أداة Node واحدة من غير أي مكتبات (`scripts/hw.mjs`)، فبتشتغل زي بعض على Linux و
macOS و Windows، وأي موديل حتى لو ضعيف يقدر يمشي عليها خطوة خطوة.

| الجزء | فيه إيه |
|---|---|
| **المهارات** (`skills/`، ١٨) | `hw-start` (نقطة البداية والموزّع) + مهارة لكل مرحلة — شوف خريطة المراحل تحت |
| **الوكلاء** (`agents/`، ٩) | `parent-agent` (الوكيل الرئيسي: بيوزّع الشغل ويراجعه بنفسه) + ٨ وكلاء فرعيين، كل واحد قائمة مهام ومعاه وضع الوكيل الواحد |
| **القواعد** (`rules/`) | `AGENTS.md` قواعد أمان شغّالة دايمًا · `quality-bar.md` · `reporting.md` |
| **الـ Hooks** (`hooks.json`) | حماية git (لا force-push ولا push على `main` ولا أوامر تمسح بيانات)، منع الأسرار في الملفات، معلومات أول الجلسة |
| **الأداة** (`scripts/hw.mjs`) | ٣٥ أمر: الفحص، STATUS.md، الفحص المحلي، الحجم، أرقام ADR، الـ PRs، الـ CI، المراجعات، الدمج الآمن، التأكد من النشر، PSI، Sentry، التثبيت |
| **القوالب** (`resources/templates/`) | STATUS، الخطة، تكليف الوكيل الفرعي، وصف الـ PR، ADR، تقرير صاحب المشروع، تقرير مراجعة PR، تقرير مرحلة QA، بنك الذاكرة ٠٠–١٢، AGENTS.md، قواعد المشروع، `workflow.env.example` |
| **الملفات الجاهزة** (`examples/<name>/agents-dir/`) | إعدادات مشروع جاهزة؛ `church-portal` هو المثال المرجعي |

### المتطلبات

- **Node.js 18 أو أحدث** و **git**.
- صلاحية GitHub: أداة `gh` متسجّل فيها (`gh auth login`) **أو** `GITHUB_TOKEN` / `GH_TOKEN` في البيئة.
- أدوات المشروع نفسه للفحص المحلي (church-portal: Flutter stable و Node 22 و Java 21 للمحاكي و Python 3).
  اختياري: Chrome للصور، و `SENTRY_TOKEN` لفحص Sentry.
- الأمر `node scripts/hw.mjs doctor` بيفحص ده كله وبيقول الناقص إيه.

### التثبيت

اختار طريقة واحدة. المهارات والوكلاء بيظهروا باسم `hark-workflow:<name>`.

```bash
# أ) من Antigravity CLI — لكل المشاريع على الجهاز (وبتظهر كمان في تبويب Installed في التطبيق)
agy plugin install Kerollosmm/agent-workflow-kit
#   أو: agy plugin install https://github.com/Kerollosmm/agent-workflow-kit

# ب) لمشروع واحد بس — بتتحفظ مع المستودع وكل الفريق والوكلاء ياخدوا نفس النسخة
git clone https://github.com/Kerollosmm/agent-workflow-kit /tmp/hark-workflow
node /tmp/hark-workflow/scripts/hw.mjs install workspace /path/to/your-repo
#   -> .agents/plugins/hark-workflow/ جوه المشروع

# ج) لكل المشاريع من غير الـ CLI
node /tmp/hark-workflow/scripts/hw.mjs install global
#   -> ~/.gemini/config/plugins/hark-workflow/
```

| المكان | المسار | امتى |
|---|---|---|
| المشروع | `<repo>/.agents/plugins/hark-workflow/` | عايز نسخة الأداة تمشي مع المستودع وتتراجع في الـ PRs |
| عام | `~/.gemini/config/plugins/hark-workflow/` (أو `agy plugin install`) | بتشتغل على مستودعات كتير بنفس الأداة |

المستودع خاص (private)، فلازم الجهاز يكون عليه حساب GitHub يقدر يقرأه.

للتأكد إنها اتحمّلت: في التطبيق **Settings ← Projects ← المشروع ← Customizations**، أو في الـ CLI ‏`/skills` و
`/agents` و `/plugin`. ورسالة أول الجلسة `hark-workflow: HW_KIT=…` معناها إن الـ hooks شغّالة.

### أول تشغيل

١. افتح المشروع في Antigravity وافحص الجهاز: `node "<KIT>/scripts/hw.mjs" doctor` (‏`<KIT>` هو الفولدر اللي فيه
   `plugin.json`، والأمر `hw.mjs kit` بيطبعه).

٢. **لو مفيش إعدادات للمشروع** (`config … MISSING`): شغّل مهارة **`hw-bootstrap`** (قول «جهّز hark workflow
   للمستودع ده»). هتكتشف نوع المشروع وتكتب `.agents/workflow.env` و `AGENTS.md` وبنك الذاكرة وقواعدك في
   `.agents/rules/` وقيم الحجم و PageSpeed الأساسية، وتعمل أول فحص، وتسلّم كل ده في PR مسودة واحد.

٣. **لو فيه ملف جاهز للمشروع** (church-portal): ثبّته على فرع جديد، مش على `main`:

```bash
node "<KIT>/scripts/hw.mjs" install profile church-portal /path/to/church-portal          # بيسيب الملفات الموجودة
node "<KIT>/scripts/hw.mjs" install profile church-portal /path/to/church-portal --force  # بيكتب فوقها
node "<KIT>/scripts/hw.mjs" config                                                        # القيم الفعلية
```

   بينسخ `examples/church-portal/agents-dir/` جوه `<repo>/.agents/`: ‏`workflow.env` و `AGENTS.md` (قواعد صاحب
   المشروع وطريقة الشغل) و `rules/church-portal.md` (قواعد الكود والمحتوى). اعمل لهم commit بمسارات صريحة وافتح PR
   مسودة.

٤. ضيف `.work/` لملف `.gitignore` (ملفات STATUS والسجلات والـ worktrees بتبقى هناك).

### طريقة الاستخدام

**في تطبيق Antigravity أو الـ CLI (وكيل رئيسي + وكلاء فرعيين):** اختار الوكيل **`parent-agent`** كوكيل رئيسي
وادّيله الطلب أو الخطة. هيحمّل `hw-start` ويمسك ملف `.work/<topic>/STATUS.md`، وفي كل مرحلة: يملا قالب التكليف،
ويستدعي الوكيل الفرعي المناسب بـ `invoke_subagent` (ولو الاسم مش معروف يجرب مرة واحدة بـ
`hark-workflow:implementer`)، و**يراجع بنفسه كل نتيجة** (يعيد الفحص المحلي ويقرأ الـ CI ويعدّ التعليقات المفتوحة)
قبل المرحلة اللي بعدها. مش بيوقف ويسألك غير عند: موافقة الخطة G0، المراجعة بالصور G1 (لو طلبتها)، جاهزية السلسلة
G2، موافقة الدمج G3، أي كتابة على البيانات الحية أو فلوس أو رسالة برّه المستودع، أو لما يبقى `blocked: yes`.
في جلسة جديدة قول «كمّل» وهو هيكمّل من ملف STATUS المفتوح.

**في Antigravity IDE (وكيل واحد):** الـ IDE مفيهوش وكلاء فرعيين. ابدأ بمهارة **`hw-start`**، وهي هتشغّل كل مرحلة
بنفسها واحدة ورا التانية في **وضع الشخصية**: قبل كل مرحلة تقرأ أقسام Role و Checklist و Never من
`agents/<agent>.md` وتكتب `persona: <agent>` و `mode: single-agent` في STATUS.md، وبرضه بتشغّل أوامر التحقق. نفس
الكلام بيحصل في التطبيق لو التفويض فشل مرتين.

**جملة البداية لـ Gemini:** موجودة فوق بالإنجليزي وبالعربي في قسم «Start prompt for Gemini in Antigravity» — انسخها
والصقها وغيّر الطلب.

### خريطة المراحل

| المرحلة | المهارة | بتعمل إيه | الوكيل |
|---|---|---|---|
| — | `hw-start` | البداية: STATUS.md واختيار المرحلة وتوزيعها | parent-agent |
| ٠٠ | `hw-bootstrap` | تجهيز المستودع كله في PR مسودة واحد | orchestrator |
| ٠١ | `hw-intake` | الهدف ومعايير القبول والنطاق وأسئلة صاحب المشروع | planner |
| ٠٢ | `hw-plan` | ملف الخطة وسلسلة الـ PRs وأرقام ADR والميزانيات وموافقة G0 | planner |
| ٠٣ | `hw-worktree` | worktree لكل PR ومزامنة السلسلة بالـ merge (من غير rebase) | orchestrator |
| ٠٤ | `hw-implement` | الكود والاختبارات لـ PR واحد | implementer |
| ٠٤ | `hw-fix-bug` | السبب الحقيقي واختبار بيفشل قبل الإصلاح | implementer |
| ٠٤ب / ١٣ | `hw-docs-sync` | التوثيق جوه الـ PR، وبعد الدمج التأكد إنه وصل `main` | docs-keeper |
| ٠٥ | `hw-local-gate` | الفحص المحلي الكامل والحجم قبل كل push | implementer |
| ٠٦ | `hw-open-pr` | push و PR مسودة بالوصف الكامل | implementer |
| ٠٧ | `hw-review-loop` | مراجعات CodeRabbit و Sentry والرد على كل تعليق، بحد أقصى جولتين | reviewer-fixer |
| ٠٨ | `hw-ci-watch` | CI أخضر على آخر commit؛ لو أحمر: السجل وإعادة الخطأ محليًا والإصلاح | release-verifier |
| ٠٩ | `hw-dev-test` | دمج في dev والتجربة على رابط dev (اختياري) | release-verifier |
| ١٠ | `hw-owner-approval` | صور ٣٩٠ و ١٢٨٠ بكسل وتسجيل الموافقة بالنص والوقت والـ SHA | parent-agent |
| ١١ | `hw-merge` | دمج squash مع حماية الـ SHA؛ السلسلة من تحت لفوق | release-verifier |
| ١٢ | `hw-deploy-verify` | الـ CI والنشر على main والموقع الحي و PSI و Sentry | release-verifier |
| جانبي | `hw-pr-review` | مراجعة PR حد تاني قراءة بس وتقرير بالحكم | pr-reviewer |
| جانبي | `hw-qa-sim` | مرحلة QA على المحاكي بس، تقرير PASS / PARTIAL / FAIL / N/A | qa-tester |

الوكلاء التسعة: `parent-agent` و `planner` و `orchestrator` و `implementer` و `docs-keeper` و `reviewer-fixer` و
`release-verifier` و `pr-reviewer` و `qa-tester` — تفاصيل كل واحد في جدول «The 9 agents» فوق.

### أوامر hw.mjs

`node "<KIT>/scripts/hw.mjs" help [command]` بيعرض كل الأوامر. أهمها: `doctor` و `config` و `install` (إعداد)،
`status` (ملف الحالة)، `gate` و `size` و `adr-next` و `adr-new` (فحص محلي)، `worktree` و `pr-checkout`،
`pr-create` (دايمًا مسودة) و `pr-status` و `pr-ready` و `merge` (بموافقتك وبحماية الـ SHA)، `wait-ci` و `ci-logs` و
`ci-rerun` (مرة واحدة بس)، `threads` و `reply` و `resolve` (المراجعات)، `deploy-verify` و `psi` و `sentry-issues`
(بعد النشر). كل أمر بيطبع سطر نتيجة واحد (زي `GATE: PASS`) والوكلاء بيستخدموه كدليل.

### ضمانات الأمان

- **بالـ hooks (Antigravity بيشغّلها قبل الأمر):** ممنوع force-push بأي شكل، ممنوع push أو مسح لـ `main` أو أي فرع
  محمي، ممنوع أوامر مسح البيانات (والأوامر الخاصة بالمشروع في `DESTRUCTIVE_PATTERNS`، زي تشغيل الـ seed الحقيقي أو
  workflows النشر باليد)، وبيسأل قبل `git reset --hard` و `git clean -f` و `firebase deploy` و أي `git rebase`.
  وممنوع كتابة أي سر (مفتاح خاص، service account، توكن) في ملف.
- **بالأداة `hw.mjs`:** الـ PR بيتفتح مسودة دايمًا؛ `pr-ready` و `merge` محتاجين نص موافقتك؛ `merge` بيرفض لو
  الـ SHA اتغيّر أو الـ CI مش أخضر؛ `ci-rerun` مرة واحدة بس وللوظائف اللي فشلت.
- **بالقواعد:** مفيش دمج من غير «ادمج» منك للـ PR ده، مفيش كتابة على البيانات الحية من غير موافقة لكل بند لوحده،
  الـ commit بمسارات صريحة، مفيش معلومات متألّفة، ولو نفس الخطوة فشلت مرتين يوقف ويبلّغك، والرد بلغتك.

### حدود معروفة وحاجات لسه متأكدناش منها

- **لسه ما اتجرّبش في جلسة Antigravity حقيقية:** إن Antigravity بيقرأ `.agents/AGENTS.md` اللي بيتثبّت من الملف
  الجاهز كقواعد دايمة. لو مش بيقرأه، القواعد برضه شغّالة من `.agents/rules/*.md` (‏`trigger: always_on`) ومن الإشارة
  في `AGENTS.md` بتاع المستودع.
- **مش متأكدين:** هل `invoke_subagent` محتاج البادئة `hark-workflow:` لوكلاء الإضافة. الأداة بتجرب الاسم من غيرها
  الأول وبعدين مرة واحدة بالبادئة.
- **Windows:** الـ hooks والأداة Node عادي والاختبارات ناجحة على Linux، لكن طريقة تشغيل الـ hooks على Windows لسه
  ما اتجرّبتش.
- `agy plugin validate --strict` بيشتغل بس لو الـ CLI متثبّت على الجهاز؛ الـ CI مفيهوش.
- قيمة `GATE_ENV_SCRIPT` في ملف church-portal مسار في بيئة Hark؛ على أي جهاز تاني الفحص بيتخطاه وياخد Flutter و
  Node و Java من الـ `PATH`.

</div>
