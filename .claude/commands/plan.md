---
description: "Investigates the codebase, designs a solution, and produces a durable plan artifact — a GitHub issue or a plan markdown under docs/plans/. Read-only: never edits application code. Use before /lfg for anything non-trivial."
model: fable
argument-hint: "issue <feature or problem> | md <feature or problem> | <feature or problem>"
allowed-tools: Bash(gh issue create:*), Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh search:*), Bash(gh label list:*), Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(date:*), Read, Grep, Glob, Write, Agent, AskUserQuestion
---

# Plan — design expensive, execute cheap

You are the planning specialist. This command runs on the most capable model deliberately: the thinking happens here, the execution happens later on cheaper models (`/lfg` on Opus, mechanical work on Sonnet). That split only works if the plan is **self-contained** — an executor with none of this session's context must be able to implement it without guessing.

## Output mode from $ARGUMENTS

| $ARGUMENTS starts with | Artifact |
|---|---|
| `issue` | GitHub issue on `zoolutions/importmap-plus` (default — feeds `/lfg <number>`) |
| `md` or `file` | `docs/plans/YYYY-MM-DD-<slug>.md` (date from `date +%F`) |
| anything else | GitHub issue |

## Hard constraints

- **Read-only for source code.** Never edit application code, never commit, never create branches. The only file you may Write is a new plan under `docs/plans/`.
- **Never reproduce secrets** in the plan.
- **Dedupe first**: `gh issue list --repo zoolutions/importmap-plus --search "<keywords>"`. If an issue already covers this, extend it in your summary rather than duplicating.
- **Upstream first?** If the request is not fork-specific — a bug in `map.rb`, a helper improvement — say so in the plan and recommend opening it against rails/importmap-rails (`.claude/rules/upstream-sync.md`, "Contributing back"). The executor can still do it here, but the decision is recorded.

## Phase 1 — Investigate

Protect this session's context: delegate mechanical exploration and keep Fable for judgment.

1. Fan out Explore agents (`model: haiku`) for file discovery; `model: sonnet` agents to read and summarise a subsystem. Launch independent explorations in parallel.
2. Read the load-bearing files yourself. For anything in the command path that means `lib/importmap/packager.rb` (the regex constants at the top, `vendored_pin_for`, `pin_provenance`, `extract_existing_pin_options`) and the relevant Thor command in `lib/importmap/commands.rb`. For the request path, `lib/importmap/map.rb` and the helper.
3. Establish ownership: `git diff --name-status upstream/main main`. An upstream-owned file constrains the design to additive changes; a fork-only file does not.
4. Read the tests that already cover the area — `test/commands_test.rb` for CLI contracts (live CDN), `test/packager_test.rb` for rewrite logic — and the docs page(s) under `docs/app/views/docs/pages/` that describe it.
5. `git log --oneline -15 -- <files>` for recent related work; the design should extend it.

## Phase 2 — Surface the unknowns (blindspot pass + interview)

Investigation tells you what the codebase says; this finds what the REQUEST doesn't say.

1. **Blindspot pass.** Write down the unknowns you're carrying:
   - decisions the request leaves open: flag name and default, the exact CLI sentence, the pin-comment format, what happens to packages pinned before the feature existed
   - edge cases the codebase makes possible that the request never mentions: scoped packages, subpaths, remote pins, single-quoted pins, `preload: false`, custom `to:` URLs, esm.run bundles with dependencies, a package present in `vendor/javascript` but not in the map
   - downgrade story: what does importmap-rails do with a `config/importmap.rb` this feature has written?
   - anything with no precedent in this repo — flag it as unknown-unknown territory
2. **Interview the user** with AskUserQuestion, one question at a time, ordered by blast radius: public CLI/DSL surface first, then pin-file format (it is persisted in every app), then output wording. Rules:
   - Skip anything `CLAUDE.md`, the rules, or an existing issue already answers.
   - 2–5 questions is the sweet spot; zero is fine when the request is unambiguous — say so.
   - Every question offers concrete options with a recommended default.
3. **Record the answers** in the plan's Decision section as `Settled in interview:` bullets — constraints the executor must not re-litigate.

## Phase 3 — Design

- Develop 2–3 candidate approaches with real trade-offs. Pick one and say why; record why the others lost.
- The chosen design must respect the invariants: the `Importmap::` surface is frozen; no new runtime deps; transform-only minification; provenance and options survive rewrites; every request through `with_retries`; no network on the request path; upstream-owned files get additive edits only.
- Decide the test strategy per `.claude/rules/testing.md`: stubbed unit tests in `packager_test.rb` / `npm_test.rb` / `importmap_test.rb` by default; a live `commands_test.rb` case only for a new CDN contract; a fixture for a new pin-line shape.
- Name the docs page(s) to update and the CHANGELOG entry.

## Phase 4 — Emit the plan artifact

```markdown
# <Title>

## Problem / Goal
<What's wrong or missing, who it affects (app developer running bin/importmap? every request?), what done looks like.>

## Context (read these first)
<Bullet list: `path/to/file.rb` — why it matters. Mark each as upstream-owned or fork-only. Self-contained: no "as discussed".>

## Decision
<Chosen approach and rationale. Alternatives considered and why rejected. Upstream-first recommendation if applicable. End with `Settled in interview:` bullets.>

## Implementation steps
<Ordered, small. Tests before the code they cover. Exact files. For upstream-owned files, the additive shape of the change.>

## Verification gates
- `bin/test test/<file>_test.rb` — green
- `bundle exec rake test` — green, with a minifier installed so `--minify` cases run
- `cd docs && bundle exec rake lint && bundle exec rspec` — if docs changed
- <the manual check: `bin/importmap <cmd>` in test/dummy and the resulting `config/importmap.rb` line>

## Out of scope
<Explicit boundaries — the adjacent things an eager executor must NOT do.>

## Execution
Execute with `/lfg <issue-number>` (or `/lfg docs/plans/<file>.md`).
```

For GitHub issues: write the body to a temp file and `gh issue create --repo zoolutions/importmap-plus --title "…" --body-file <tmpfile>`.

For markdown: Write to `docs/plans/YYYY-MM-DD-<slug>.md` and leave it uncommitted — committing is the user's call.

## Phase 5 — Handoff

Report: link to the issue (or file path), the chosen approach in 2–3 sentences, the upstream-first recommendation if any, and the exact execute command. Stop there — do not implement.
