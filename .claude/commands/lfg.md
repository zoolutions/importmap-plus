---
description: "Executes the full autonomous engineering workflow with verification. Use when implementing a complete feature, tackling a GitHub issue, or running an end-to-end development cycle on importmap-plus."
model: opus
argument-hint: "GitHub issue number/URL, a docs/plans/*.md path, or a feature description"
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(bundle exec:*), Bash(bundle install:*), Bash(BUNDLE_GEMFILE=*), Bash(git:*), Bash(cd:*), Read, Write, Edit, Glob, Grep, Agent
---

# LFG — Full Autonomous Workflow

Execute a complete engineering workflow with verification at each phase. Read `CLAUDE.md` first: the never-do list there (constant surface, no new deps, transform-only minify, provenance survives rewrites, retries on every request) is the set of constraints every phase below assumes.

## Phase 0: Branch setup

**BEFORE any other work:**

```bash
git fetch origin main
git switch -c <type>/<slug> origin/main      # feat/, fix/, chore/, docs/ — see .claude/rules/git-workflow.md
```

Never branch from an existing feature branch unless the work is deliberately stacked on an open PR — say so in the PR body if it is.

---

## Phase 1: Understand

### Step 1: Gather requirements

- A GitHub issue number or URL: `gh issue view <number> --json title,body,labels,comments`
- A `docs/plans/*.md` path: read it — it is a `/plan` artifact and its Decision and Out-of-scope sections are binding
- A description: use it directly

### Step 2: Acceptance criteria

**MANDATORY.** Write them as GIVEN / WHEN / THEN before anything else. For a CLI change, THEN is the exact sentence `bin/importmap` prints and the exact `config/importmap.rb` line it leaves behind — that is the contract `commands_test.rb` asserts.

### Step 3: Comprehension gate

You must be able to state, before proceeding:

1. The problem or feature in one sentence
2. WHY it is needed — what an app developer runs into today
3. What changes from the user's perspective: a new flag, a new pin comment, a new output line, a new docs page
4. Edge cases not mentioned: scoped packages (`@scope/name`), subpaths (`pkg/core`), remote pins (`to: "https://…"`), single-quoted pins, `preload: false`, a package pinned to a custom URL, a package already locked
5. The code path: request path (engine → Map → helpers) or command path (Commands → Packager/Npm → CDN)? Which upstream-owned files does it touch, and can the change be additive there?

If you cannot complete all five, investigate further.

### Step 4: Task list

Create a task list with the concrete implementation steps.

---

## Phase 2: Explore

1. Find related code (Explore agent with `model: haiku` for the sweep; read the load-bearing files yourself)
2. For a CLI change: `lib/importmap/commands.rb` (the Thor command and `pin_package`), `lib/importmap/packager.rb` (regexes, `vendored_pin_for`, `pin_provenance`, `provenance_for`), and the `commands_test.rb` cases for the same command
3. For a Map/helper change: `lib/importmap/map.rb`, `app/helpers/importmap/importmap_tags_helper.rb`, `test/importmap_test.rb` (note the `ASSETS_PIPELINE` branches)
4. For a registry change: `lib/importmap/npm.rb` and `test/npm_test.rb`
5. Check `git diff --name-status upstream/main main` — is the file you're about to edit upstream-owned? Then the change must be additive (`.claude/rules/upstream-sync.md`)
6. Find the docs page(s) that describe the behaviour: `grep -rl "<command or option>" docs/app/views/docs/pages/`
7. Check what `CHANGELOG.md`'s next version heading already lists

---

## Phase 3: Plan

1. Files to modify, with the specific additive change in each
2. New files to create (a new collaborator beats a bigger `packager.rb`)
3. Tests first: which existing test file gets a case, whether a new fixture under `test/fixtures/files/` is needed, whether a live `commands_test.rb` case is justified
4. The docs page and the CHANGELOG entry
5. Backwards compatibility: does a `config/importmap.rb` written by this change still parse under importmap-rails? Does an existing pin without the new metadata still behave as before?

---

## Phase 4: Implement (TDD)

### The deviation log (keep it from the first edit)

The plan is the map; the codebase is the territory. The moment reality forces a choice the plan or issue didn't settle, log it in `implementation-notes.md` at the repo root — one line, at the moment it happens:

- **Deviations** — the plan said X, you did Y, because Z
- **Discoveries** — facts about the codebase the plan didn't know
- **Judgment calls** — choices the user might have made differently (defaults, wording of a CLI message, scope cuts)

Pick the conservative option and keep going. Never commit the file: its contents move into the PR body (Phase 7), then the file is deleted.

For each logical unit:

### 4.1: Write the failing test first

```bash
bundle exec ruby -Itest test/packager_test.rb -n /provenance/
```

Watch it fail for the right reason. A test that fails with `NoMethodError` on the thing you're about to write is fine; one that fails because the fixture is wrong is not.

### 4.2: Implement the minimum

| Never do | Always do |
|---|---|
| A bare `Net::HTTP.get_response` in Packager or Npm | Go through `with_retries` |
| Rewrite a pin line with string surgery | Match with `Importmap::Map.pin_line_regexp_for` and re-emit via `vendored_pin_for` / `pin_for` |
| Drop `preload:` / `integrity:` / the provenance comment on rewrite | Read them with `extract_existing_pin_options` and carry them through |
| Join `vendor_path` with a package name by hand | `vendored_package_path(package)` |
| `system("tool #{args}")` | `Open3.capture3(executable, *argv)` |
| Restructure an upstream method | Add a line that calls a fork-only collaborator |
| Reach the network from `Map` or a helper | Keep network code in the command path |

### 4.3: Refactor

Once green, tidy — within the fork-cost rule (`.claude/rules/striving-for-excellence.md`).

### 4.4: Validate

```bash
bundle exec ruby -Itest test/<touched>_test.rb
```

### 4.5: Repeat

Next unit. Mark task items complete.

---

## Phase 5: Deep root cause analysis (bug fixes only)

### Trace the data

For the pin, package or import-map entry that misbehaves:

- Where did the line in `config/importmap.rb` come from — `pin`, `update`, `pristine`, hand-written? What did the CDN return and what did `vendored_pin_for` emit?
- Which regex matched (or didn't)? Run it against the exact line in a console.
- What did the code ASSUME at the failure point — a version comment present, a double-quoted pin, a jspm URL shape?
- Which assumption was violated, and why does that input exist?

### Use git history

```bash
git log --oneline -20 -- lib/importmap/packager.rb
git blame lib/importmap/packager.rb -L <start>,<end>
```

Was the code upstream's or the fork's? Did an upstream sync change a regex the fork depended on?

### Map all callers

`pin_package` is called from `pin`, `update` and the esm.run dependency pinning; `extract_existing_pin_options` from several places. Does the bug occur in one context only? Why?

### Five whys

Keep asking until you reach the fix point. The best fix is usually not where the error surfaces:

- A nil URL in `pin_vendored_package` → fix the resolver that returned nil, or the check that let a missing package through
- A vendored file with an unresolvable import → fix the esm.run rewrite, not the app's import map
- A `preload: false` lost on update → fix the option carry-through, not the assertion

### Unacceptable superficial fixes

- `rescue nil` around a CDN call
- `&.` to silence a nil that means "the CDN said no"
- `return if …` that silently skips a package
- Loosening a regex until the bad input matches
- A `retry`/`sleep` in a test

These hide bugs. The root cause keeps producing wrong import maps elsewhere.

---

## Phase 6: Verify

**All of these must pass before committing:**

```bash
bundle exec rake test                                   # includes the live CDN tests
cd docs && bundle exec rake lint && bundle exec rspec   # if docs/ changed
```

If the change touched the engine, `Map` or a helper, also run the nearest CI matrix cell:

```bash
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bundle exec rake test
```

Confirm the `--minify` tests **ran** (not skipped) — install bun if they didn't.

### Solution verification

- "If I were the app developer who asked, is this fully resolved?"
- "Root cause, not symptom?"
- "Do the tests prove the fix — would they fail on `main`?"
- "Does a `config/importmap.rb` written by this change still work under importmap-rails?"
- "Is the upstream-owned diff additive?"

---

## Phase 7: Commit & PR

### Commit

```bash
git add <specific files>       # never -A: docs/ may hold untracked build output
git commit -m "$(cat <<'EOF'
feat(cli): brief description

Why this exists, from the app developer's side. What invariant shaped the design.

## Test coverage
- test/packager_test.rb: <what it proves>
- test/commands_test.rb: <the live contract it pins>

Refs #<issue>
EOF
)"
```

### Push & PR

```bash
git push -u origin $(git branch --show-current)

cat > /tmp/pr-body.md <<'EOF'
## Summary
- Key change touching `lib/importmap/packager.rb`
- Docs page updated: `docs/app/views/docs/pages/<page>.rb`
- CHANGELOG entry under <next version>

Closes #<issue>

## Test plan
- [ ] `bundle exec rake test` green with bun installed
- [ ] <the manual check an app developer would do: `bin/importmap pin … && cat config/importmap.rb`>

## Deviations & judgment calls
<contents of implementation-notes.md, or "None — the plan held.">
EOF
gh pr create --title "feat(cli): brief description" --body-file /tmp/pr-body.md
rm /tmp/pr-body.md implementation-notes.md
```

With a single-quoted heredoc, backticks and `$` pass through verbatim — never escape them. `--body-file` sidesteps the shell entirely and is the default here because PR bodies for this gem quote pin lines and commands.

The PR body MUST end with a `## Deviations & judgment calls` section. It is read first in review — the audit trail for every decision the plan didn't make.

---

## Phase 8: Comprehension close-out

The tests prove the code; this keeps the user's mental model right. End your final message with:

1. **The decisions, not the diff** — the 3–5 non-obvious choices someone must understand to maintain this. Lead with the deviation log; the user has not seen it.
2. **Three merge-gate questions** the user should be able to answer before merging. If any answer isn't obvious to them, offer a walkthrough.

---

## Verification checklist

- [ ] All acceptance criteria met
- [ ] Tests written BEFORE implementation and seen red
- [ ] `bundle exec rake test` green, `--minify` tests ran
- [ ] Nearest matrix cell green if engine/Map/helpers changed
- [ ] Docs page and CHANGELOG updated for user-visible changes
- [ ] Upstream-owned file diffs are additive and in upstream's style
- [ ] `config/importmap.rb` output still parses under importmap-rails
- [ ] PR created; body ends with Deviations & judgment calls
- [ ] Comprehension close-out delivered

Now execute this workflow for: $ARGUMENTS
