---
description: "Use when CI checks are failing on a PR — fetches failure logs, diagnoses root causes, implements fixes, and pushes until CI is green."
model: sonnet
argument-hint: "PR number (e.g., 5 or #5)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh run view:*), Bash(git log:*), Bash(git diff:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(bundle exec:*), Bash(bundle install:*), Bash(bin/test:*), Bash(BUNDLE_GEMFILE=*), Bash(cd:*), Read, Write, Edit, Glob, Grep, Agent
---

# Fix GitHub CI Failures: $ARGUMENTS

Repo: `zoolutions/importmap-plus`. Diagnose and fix CI failures systematically: identify, read logs, root-cause, fix locally, verify, push.

## Phase 0: Determine the PR number

Parse `$ARGUMENTS` flexibly (`PR5`, `#5`, `5`); empty → auto-detect from the current branch:

```bash
gh pr list --author=@me --head="$(git branch --show-current)" --state=open --json number,title
```

Confirm:

```bash
gh pr view <PR> --json title,state,url,mergeable,baseRefName
```

**Pre-flight: conflicts (detection only).** `mergeable: CONFLICTING` → STOP. Don't diagnose CI on a conflicted branch; hand off to `/github-review-pr`, whose Phase A0 owns resolution. `UNKNOWN` → note it and proceed.

---

## Phase 1: Identify failing checks

```bash
gh pr checks <PR>
```

Two workflows produce checks here:

| Workflow | Check name | What it runs | Notes |
|---|---|---|---|
| `CI` (`ci.yml`) | `Tests (Ruby 3.x, Rails 7.x, sprockets\|propshaft)` — one per matrix cell | `bundle exec rake` = the whole Minitest suite, with bun installed, `BUNDLE_GEMFILE=gemfiles/rails_<v>_<pipeline>.gemfile`, `ASSETS_PIPELINE` set | Live CDN tests run in every cell |
| `Docs site` (`docs-ci.yml`) | `Build & test` | inside `docs/`: `bundle install` (frozen), icon sync, `bun run build:css`, `rake lint`, `rspec` | Only runs when `docs/**` changed |

Read the matrix before reading logs:

- **Every cell red, same test** → deterministic regression in this branch (or a CDN outage — check the error text).
- **One Rails version red** → a compatibility break for that version (Rails 6.1 needs `logger`/`mutex_m`/`drb` explicitly; `main` moves).
- **One Ruby version red** → language floor (3.1) or a Ruby 4.0 change.
- **`sprockets` cells only** → the `ASSETS_PIPELINE` branch in `importmap_test.rb`, or an asset-path assumption.
- **One random cell red** with a `429`, `ECONNRESET`, or `Net::ReadTimeout` on a live test → likely a CDN flake; see Phase 3.

Run and job IDs come from the check URLs: `https://github.com/zoolutions/importmap-plus/actions/runs/<RUN_ID>/job/<JOB_ID>`.

All passing or pending → report and stop.

---

## Phase 2: Fetch failure logs

```bash
gh run view <RUN_ID> --job=<JOB_ID> --log-failed
gh run view <RUN_ID> --job=<JOB_ID> --log 2>&1 | grep -n -B5 -A30 'Failure:\|Error:' | head -200   # when --log-failed is too thin
```

Extract for each failure: test name and file, error class and message, the Minitest seed (`--seed N`), the matrix cell.

---

## Phase 3: Diagnose each failure

### Test failures (Minitest, not RSpec)

- `NoMethodError` / `NameError` → an API used that a Rails or Ruby version in the matrix doesn't have; check the cell
- `expected … got …` on a CLI output line → the sentence `bin/importmap` prints changed; decide whether the test or the code is right (the docs quote these sentences — check `docs/`)
- `flunk "bin/importmap … failed"` in `commands_test.rb` → the CLI's own output is in the message; read it. A CDN error (`429`, `503`, `Unexpected transport error`) is Phase 3's flake question; a Ruby exception is a bug
- A `skip` count higher than expected → the runner has no minifier; CI installs bun, so a skip in CI means the setup step changed
- `Importmap::Map::InvalidFile` → a fixture or a rewrite produced a line `config/importmap.rb` can't `instance_eval`

### Is a live-test failure a flake?

Only if ALL of these hold: it is in `commands_test.rb` or an `*_integration_test.rb`; the error is transport-shaped (`429`, `5xx`, reset, timeout) after `HttpRetries` already retried; it failed in one cell while the same test passed in the others on the same commit. Then note it as a probable CDN flake, don't "fix" it, and run `/debug-flaky` if it recurs. Never add a `retry`, `sleep` or `skip`.

### Docs site failures

- `bundle install` frozen failure mentioning `importmap-plus` → the `docs/Gemfile.lock` pin drifted from `Importmap::VERSION` (`cd docs && bundle install`, commit the lock)
- RuboCop offenses → `cd docs && bundle exec rake lint:fix`, then read what it changed
- A request spec failing on a page → the page's `#content` raised; `cd docs && bundle exec rspec spec/requests/docs_spec.rb`
- CSS build → a class the scan couldn't find, or `bun.lock` out of date

### Build / bundle failures

- Gemspec `files` glob missing something new under `app/` or `lib/`
- A gemfile under `gemfiles/` out of date with `Appraisals` → `bundle exec appraisal generate`

---

## Phase 4: Fix locally

1. **Read the failing code and test** before changing anything
2. **Make the fix** — root cause, in the right layer, additive in upstream-owned files
3. **Verify locally**, in the failing cell's configuration when the failure is cell-specific:

```bash
bin/test test/<failing>_test.rb -n /<test name>/
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7.1_sprockets.gemfile ASSETS_PIPELINE=sprockets bin/test test/<failing>_test.rb
bundle exec rake test                                     # before pushing
cd docs && bundle exec rake lint && bundle exec rspec     # docs failures
```

### Fix priority

1. Deterministic test failures across all cells
2. Cell-specific compatibility failures
3. Docs site failures
4. Probable flakes — note, don't fix

---

## Phase 5: Commit and push

```bash
git add <specific files>
git commit -m "$(cat <<'EOF'
fix(ci): <what was fixed>

- <failure 1: cause → fix>
- <failure 2>
EOF
)"
git push
```

One commit for the whole pass — each push runs the full matrix against live CDNs.

---

## Phase 6: Verify

```bash
gh pr checks <PR>
```

Report which checks are re-running and what was fixed. Do NOT poll in a loop. Flag any failure you expect to persist (a CDN outage, a pre-existing failure on `main`).

---

## Important notes

- **Read before fixing.**
- **Root cause, not suppression** — no `skip`, no loosened assertion, no `rescue`.
- **Don't fix unrelated failures** — already red on `main`? Note it, leave it.
- **One push per pass.**
- **Docs CI is separate** — a `docs/**` change gets both workflows; a change outside `docs/` gets only `CI`.
